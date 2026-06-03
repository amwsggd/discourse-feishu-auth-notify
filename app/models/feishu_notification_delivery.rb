# frozen_string_literal: true

class FeishuNotificationDelivery < ActiveRecord::Base
  self.table_name = "feishu_notification_deliveries"

  belongs_to :user, foreign_key: :discourse_user_id, optional: true
  belongs_to :feishu_user_binding, optional: true

  STATUSES = %w[
    pending
    sending
    sent
    retrying
    failed
    skipped
  ].freeze

  validates :notification_id, presence: true
  validates :discourse_user_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending_or_retrying, -> {
    where(status: ["pending", "retrying"])
      .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.zone.now)
  }
end