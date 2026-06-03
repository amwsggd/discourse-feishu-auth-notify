# frozen_string_literal: true

class FeishuUserBinding < ActiveRecord::Base
  self.table_name = "feishu_user_bindings"

  belongs_to :user, foreign_key: :discourse_user_id, optional: true

  validates :discourse_user_id, presence: true
  validates :tenant_key, presence: true
  validates :union_id, presence: true
  validates :open_id, presence: true

  scope :active, -> { where(active: true) }
end
