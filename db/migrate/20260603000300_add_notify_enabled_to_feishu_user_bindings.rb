# frozen_string_literal: true

class AddNotifyEnabledToFeishuUserBindings < ActiveRecord::Migration[7.0]
  def up
    unless column_exists?(:feishu_user_bindings, :notify_enabled)
      add_column :feishu_user_bindings,
                 :notify_enabled,
                 :boolean,
                 null: false,
                 default: true
    end

    unless index_exists?(:feishu_user_bindings, [:discourse_user_id, :active, :notify_enabled],
                         name: "idx_feishu_bindings_on_user_active_notify")
      add_index :feishu_user_bindings,
                [:discourse_user_id, :active, :notify_enabled],
                name: "idx_feishu_bindings_on_user_active_notify"
    end
  end

  def down
    if index_exists?(:feishu_user_bindings, name: "idx_feishu_bindings_on_user_active_notify")
      remove_index :feishu_user_bindings, name: "idx_feishu_bindings_on_user_active_notify"
    end

    if column_exists?(:feishu_user_bindings, :notify_enabled)
      remove_column :feishu_user_bindings, :notify_enabled
    end
  end
end