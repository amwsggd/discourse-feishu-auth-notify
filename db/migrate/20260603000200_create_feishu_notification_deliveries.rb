# frozen_string_literal: true

class CreateFeishuNotificationDeliveries < ActiveRecord::Migration[7.0]
  def change
    create_table :feishu_notification_deliveries do |t|
      t.integer :notification_id, null: false
      t.integer :discourse_user_id, null: false
      t.integer :feishu_user_binding_id

      t.string :tenant_key
      t.string :union_id
      t.string :open_id

      t.string :status, null: false, default: "pending"

      t.integer :attempt_count, null: false, default: 0
      t.datetime :next_retry_at

      t.string :last_error_code
      t.text :last_error_message

      t.string :feishu_message_id

      t.datetime :sent_at
      t.datetime :failed_at

      t.timestamps null: false
    end

    add_index :feishu_notification_deliveries,
              [:notification_id, :discourse_user_id, :feishu_user_binding_id],
              unique: true,
              name: "idx_feishu_deliveries_unique_notification"

    add_index :feishu_notification_deliveries,
              :status,
              name: "idx_feishu_deliveries_on_status"

    add_index :feishu_notification_deliveries,
              :next_retry_at,
              name: "idx_feishu_deliveries_on_next_retry_at"

    add_index :feishu_notification_deliveries,
              :created_at,
              name: "idx_feishu_deliveries_on_created_at"

    add_index :feishu_notification_deliveries,
              :notification_id,
              name: "idx_feishu_deliveries_on_notification_id"

    add_index :feishu_notification_deliveries,
              :discourse_user_id,
              name: "idx_feishu_deliveries_on_discourse_user_id"
  end
end