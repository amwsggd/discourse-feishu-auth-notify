# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module ::DiscourseFeishuAuthNotify
  PLUGIN_NAME = "discourse-feishu-auth-notify"

  FEISHU_TOKEN_URL = "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal"
  FEISHU_MESSAGE_URL = "https://open.feishu.cn/open-apis/im/v1/messages"

  class FeishuApiError < StandardError
    attr_reader :code, :response_body

    def initialize(message, code: nil, response_body: nil)
      super(message)
      @code = code
      @response_body = response_body
    end
  end

  class FeishuApi
    def self.notify_app_id
      SiteSetting.feishu_notify_app_id.presence || SiteSetting.feishu_login_app_id
    end

    def self.notify_app_secret
      SiteSetting.feishu_notify_app_secret.presence || SiteSetting.feishu_login_app_secret
    end

    def self.token_cache_key
      "feishu_notify:tenant_access_token:#{notify_app_id}"
    end

    def self.tenant_access_token(force_refresh: false)
      raise FeishuApiError.new("feishu notify app_id is blank") if notify_app_id.blank?
      raise FeishuApiError.new("feishu notify app_secret is blank") if notify_app_secret.blank?

      Discourse.cache.delete(token_cache_key) if force_refresh

      # 飞书 token 有效期一般是 2 小时，这里缓存 100 分钟，提前刷新。
      Discourse.cache.fetch(token_cache_key, expires_in: 100.minutes) do
        request_tenant_access_token!
      end
    end

    def self.request_tenant_access_token!
      uri = URI(FEISHU_TOKEN_URL)

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json; charset=utf-8"
      req.body = {
        app_id: notify_app_id,
        app_secret: notify_app_secret
      }.to_json

      res = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 10
      ) { |http| http.request(req) }

      body = JSON.parse(res.body) rescue {}

      unless res.code.to_i.between?(200, 299) && body["code"] == 0 && body["tenant_access_token"].present?
        raise FeishuApiError.new(
          "failed to get feishu tenant_access_token",
          code: body["code"],
          response_body: body
        )
      end

      body["tenant_access_token"]
    end

    def self.send_text_to_open_id!(open_id:, text:, uuid:)
      send_text!(
        receive_id_type: "open_id",
        receive_id: open_id,
        text: text,
        uuid: uuid
      )
    end

    def self.send_text_to_chat_id!(chat_id:, text:, uuid:)
      send_text!(
        receive_id_type: "chat_id",
        receive_id: chat_id,
        text: text,
        uuid: uuid
      )
    end

    def self.send_text!(receive_id_type:, receive_id:, text:, uuid:)
      raise FeishuApiError.new("receive_id is blank") if receive_id.blank?
      raise FeishuApiError.new("message text is blank") if text.blank?

      token = tenant_access_token

      uri = URI("#{FEISHU_MESSAGE_URL}?receive_id_type=#{receive_id_type}")

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{token}"
      req["Content-Type"] = "application/json; charset=utf-8"

      req.body = {
        receive_id: receive_id,
        msg_type: "text",
        uuid: uuid.to_s[0, 64],
        content: {
          text: text
        }.to_json
      }.to_json

      res = Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true,
        open_timeout: 5,
        read_timeout: 10
      ) { |http| http.request(req) }

      body = JSON.parse(res.body) rescue {}

      # 如果 token 失效，强制刷新一次并重试。
      if body["code"].to_s == "99991663"
        token = tenant_access_token(force_refresh: true)

        req["Authorization"] = "Bearer #{token}"

        res = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: true,
          open_timeout: 5,
          read_timeout: 10
        ) { |http| http.request(req) }

        body = JSON.parse(res.body) rescue {}
      end

      unless res.code.to_i.between?(200, 299) && body["code"] == 0
        raise FeishuApiError.new(
          "failed to send feishu message",
          code: body["code"],
          response_body: body
        )
      end

      body
    end
  end
end