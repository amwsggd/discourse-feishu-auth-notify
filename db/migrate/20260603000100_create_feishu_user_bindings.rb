# frozen_string_literal: true

class CreateFeishuUserBindings < ActiveRecord::Migration[7.0]
  def change
    create_table :feishu_user_bindings do |t|
      t.integer :discourse_user_id, null: false

      t.string :tenant_key, null: false
      t.string :union_id, null: false
      t.string :open_id, null: false

      t.string :feishu_user_id
      t.string :login_app_id
      t.string :notify_app_id

      t.string :name
      t.text :avatar_url

      # 未来部门限制用。先存 JSON 字符串或数组都可以，这里用 jsonb。
      t.jsonb :department_ids, null: false, default: []
      t.jsonb :department_names, null: false, default: []

      # 未来同步飞书成员状态用。
      t.string :employee_status

      t.boolean :active, null: false, default: true

      t.datetime :last_login_at
      t.datetime :last_checked_at

      t.timestamps null: false
    end

    add_index :feishu_user_bindings,
              [:tenant_key, :union_id],
              unique: true,
              name: "idx_feishu_bindings_on_tenant_union"

    add_index :feishu_user_bindings,
              [:discourse_user_id, :tenant_key],
              unique: true,
              name: "idx_feishu_bindings_on_user_tenant"

    add_index :feishu_user_bindings,
              :open_id,
              name: "idx_feishu_bindings_on_open_id"

    add_index :feishu_user_bindings,
              :active,
              name: "idx_feishu_bindings_on_active"

    add_index :feishu_user_bindings,
              :last_checked_at,
              name: "idx_feishu_bindings_on_last_checked_at"
  end
end