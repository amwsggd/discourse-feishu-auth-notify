# frozen_string_literal: true

# name: discourse-feishu-auth-notify
# about: Feishu OAuth login and Discourse notification delivery
# version: 0.0.1
# authors: local
# required_version: 2.7.0

enabled_site_setting :feishu_integration_enabled

module ::MyPluginModule
  PLUGIN_NAME = "discourse-feishu-auth-notify"
end

require_relative "lib/my_plugin_module/engine"

after_initialize do
  require_dependency "plugins/feishu_auth_controller"
  require_dependency "plugins/feishu_preferences_controller"


  on(:user_destroyed) do |user|
    ActiveRecord::Base.transaction do
      # 删除飞书绑定
      FeishuUserBinding.where(discourse_user_id: user.id).delete_all
      # 如果你还有其他相关清理，也可以放这里
    end
  end
  Discourse::Application.routes.append do
    get "/feishu/login" => "plugins/feishu_auth#auth"
    get "/feishu/callback" => "plugins/feishu_auth#callback"

    get "/feishu/notification-preference" => "plugins/feishu_preferences#show"
    put "/feishu/notification-preference" => "plugins/feishu_preferences#update"
  end



  class ::Jobs::FeishuPrepareNotificationDelivery < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.feishu_integration_enabled
      return unless SiteSetting.feishu_notify_enabled

      notification_id = args[:notification_id]
      notification = Notification.find_by(id: notification_id)
      return if notification.blank?

      binding = FeishuUserBinding.find_by(
        discourse_user_id: notification.user_id,
        active: true,
        notify_enabled: true
      )

      return if binding.blank?
      return if binding.open_id.blank?

      delivery = nil

      begin
        delivery = FeishuNotificationDelivery.find_or_create_by!(
          notification_id: notification.id,
          discourse_user_id: notification.user_id,
          feishu_user_binding_id: binding.id
        ) do |d|
          d.tenant_key = binding.tenant_key
          d.union_id = binding.union_id
          d.open_id = binding.open_id
          d.status = "pending"
          d.attempt_count = 0
          d.next_retry_at = Time.zone.now
        end
      rescue ActiveRecord::RecordNotUnique
        delivery = FeishuNotificationDelivery.find_by(
          notification_id: notification.id,
          discourse_user_id: notification.user_id,
          feishu_user_binding_id: binding.id
        )
      end

      return if delivery.blank?
      return if delivery.status == "sent"

      # 如果之前失败过，现在重新发现有有效绑定，可以重新进入 retrying。
      if delivery.status == "failed"
        delivery.update!(
          status: "retrying",
          next_retry_at: Time.zone.now,
          last_error_code: nil,
          last_error_message: nil,
          failed_at: nil
        )
      end

      Jobs.enqueue(:feishu_send_delivery, delivery_id: delivery.id)
    end
  end

  class ::Jobs::FeishuSendDelivery < ::Jobs::Base
    MAX_ATTEMPTS = 6

    RETRY_DELAYS = [
      1.minute,
      2.minutes,
      5.minutes,
      10.minutes,
      15.minutes,
      20.minutes
    ].freeze

    def execute(args)
      return unless SiteSetting.feishu_integration_enabled
      return unless SiteSetting.feishu_notify_enabled

      delivery = FeishuNotificationDelivery.find_by(id: args[:delivery_id])
      return if delivery.blank?
      return if delivery.status == "sent"
      return if delivery.status == "skipped"

      if delivery.next_retry_at.present? && delivery.next_retry_at > Time.zone.now
        return
      end

      delivery.with_lock do
        delivery.reload

        return if delivery.status == "sent"
        return if delivery.status == "skipped"

        delivery.update!(
          status: "sending",
          attempt_count: delivery.attempt_count + 1
        )
      end

      notification = Notification.find_by(id: delivery.notification_id)

      if notification.blank?
        mark_skipped!(delivery, "notification_missing", "Notification no longer exists")
        return
      end

      binding = FeishuUserBinding.find_by(
        id: delivery.feishu_user_binding_id,
        active: true,
        notify_enabled: true
      )

      if binding.blank?
        mark_skipped!(delivery, "binding_disabled", "Feishu binding is missing, inactive, or notification disabled")
        return
      end

      if binding.open_id.blank?
        mark_skipped!(delivery, "open_id_blank", "Feishu open_id is blank")
        return
      end

      text = render_notification_text(notification)

      uuid = delivery_uuid(delivery)

      result = ::DiscourseFeishuAuthNotify::FeishuApi.send_text_to_open_id!(
        open_id: binding.open_id,
        text: text,
        uuid: uuid
      )

      message_id =
        result.dig("data", "message_id") ||
        result.dig("data", "message", "message_id") ||
        result["message_id"]

      delivery.update!(
        status: "sent",
        sent_at: Time.zone.now,
        failed_at: nil,
        next_retry_at: nil,
        last_error_code: nil,
        last_error_message: nil,
        feishu_message_id: message_id
      )
    rescue => e
      handle_failure(delivery, e) if delivery.present?
      raise e if Rails.env.development?
    end

    private

    def mark_skipped!(delivery, code, message)
      delivery.update!(
        status: "skipped",
        failed_at: nil,
        next_retry_at: nil,
        last_error_code: code,
        last_error_message: message
      )
    end

    def handle_failure(delivery, error)
      delivery.reload

      code =
        if error.respond_to?(:code)
          error.code
        else
          error.class.name
        end

      message = error.message.to_s

      if error.respond_to?(:response_body) && error.response_body.present?
        message = "#{message}; response=#{error.response_body.inspect}"
      end

      if delivery.attempt_count >= MAX_ATTEMPTS
        delivery.update!(
          status: "failed",
          failed_at: Time.zone.now,
          next_retry_at: nil,
          last_error_code: code.to_s,
          last_error_message: message[0, 2000]
        )

        Jobs.enqueue(:feishu_admin_alert, delivery_id: delivery.id)
      else
        delay = RETRY_DELAYS[[delivery.attempt_count - 1, 0].max] || 30.minutes

        delivery.update!(
          status: "retrying",
          next_retry_at: Time.zone.now + delay,
          last_error_code: code.to_s,
          last_error_message: message[0, 2000]
        )
      end
    end

    def delivery_uuid(delivery)
      "dc-n-#{delivery.notification_id}-u-#{delivery.discourse_user_id}"
    end

    def render_notification_text(notification)
      data = JSON.parse(notification.data.to_s) rescue {}

      type =
        begin
          Notification.types.invert[notification.notification_type]&.to_s
        rescue
          nil
        end

      type ||= notification.notification_type.to_s

      actor =
        data["display_username"] ||
        data["username"] ||
        data["original_username"] ||
        "有人"

      topic =
        if notification.respond_to?(:topic)
          notification.topic
        else
          Topic.find_by(id: notification.topic_id)
        end

      topic_title =
        data["topic_title"] ||
        topic&.title ||
        "论坛通知"

      title =
        case type
        when "mentioned"
          "#{actor} 在「#{topic_title}」中提到了你"
        when "group_mentioned"
          "#{actor} 在「#{topic_title}」中提到了你所在的群组"
        when "replied"
          "#{actor} 回复了你在「#{topic_title}」中的内容"
        when "quoted"
          "#{actor} 引用了你在「#{topic_title}」中的内容"
        when "liked"
          "#{actor} 点赞了你在「#{topic_title}」中的内容"
        when "private_message"
          "你收到一条新的论坛私信：「#{topic_title}」"
        when "invited_to_private_message"
          "你被邀请加入一条论坛私信：「#{topic_title}」"
        when "bookmark_reminder"
          "你有一个书签提醒：「#{topic_title}」"
        else
          "你在论坛有一条新通知：「#{topic_title}」"
        end

      link = notification_link(notification, topic)

      <<~TEXT.strip
        #{title}

        打开查看：
        #{link}
      TEXT
    end

    def notification_link(notification, topic)
      if topic.present?
        post_number =
          notification.respond_to?(:post_number) && notification.post_number.present? ?
            notification.post_number :
            1

        "#{Discourse.base_url}#{topic.relative_url}/#{post_number}"
      else
        user = User.find_by(id: notification.user_id)

        if user
          "#{Discourse.base_url}/u/#{user.username}/notifications"
        else
          Discourse.base_url
        end
      end
    end
  end

  class ::Jobs::FeishuRetryDeliveries < ::Jobs::Scheduled
    every 1.minute

    def execute(_args)
      return unless SiteSetting.feishu_integration_enabled
      return unless SiteSetting.feishu_notify_enabled

      FeishuNotificationDelivery
        .where(status: ["pending", "retrying"])
        .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.zone.now)
        .order(:created_at)
        .limit(50)
        .pluck(:id)
        .each do |delivery_id|
          Jobs.enqueue(:feishu_send_delivery, delivery_id: delivery_id)
        end
    end
  end

  class ::Jobs::FeishuBackfillNotificationDeliveries < ::Jobs::Scheduled
    every 5.minutes

    def execute(_args)
      return unless SiteSetting.feishu_integration_enabled
      return unless SiteSetting.feishu_notify_enabled

      Notification
        .where("created_at >= ?", 30.minutes.ago)
        .order(:created_at)
        .find_each do |notification|
          exists =
            FeishuNotificationDelivery.exists?(
              notification_id: notification.id,
              discourse_user_id: notification.user_id
            )

          next if exists

          Jobs.enqueue(
            :feishu_prepare_notification_delivery,
            notification_id: notification.id
          )
        end
    end
  end

  class ::Jobs::FeishuAdminAlert < ::Jobs::Base
    def execute(args)
      return unless SiteSetting.feishu_admin_alert_chat_id.present?

      delivery = FeishuNotificationDelivery.find_by(id: args[:delivery_id])
      return if delivery.blank?

      text = <<~TEXT.strip
        Discourse 飞书通知投递失败

        delivery_id: #{delivery.id}
        notification_id: #{delivery.notification_id}
        user_id: #{delivery.discourse_user_id}
        attempts: #{delivery.attempt_count}
        error_code: #{delivery.last_error_code}
        error_message: #{delivery.last_error_message}
      TEXT

      ::DiscourseFeishuAuthNotify::FeishuApi.send_text_to_chat_id!(
        chat_id: SiteSetting.feishu_admin_alert_chat_id,
        text: text,
        uuid: "dc-feishu-alert-#{delivery.id}"
      )
    rescue => e
      Rails.logger.warn(
        "[discourse-feishu-auth-notify] failed to send admin alert: #{e.class}: #{e.message}"
      )
    end
  end

  on(:notification_created) do |notification|
    next unless SiteSetting.feishu_integration_enabled
    next unless SiteSetting.feishu_notify_enabled

    Jobs.enqueue(
      :feishu_prepare_notification_delivery,
      notification_id: notification.id
    )
  end
end