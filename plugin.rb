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
  # 监听 OAuth2 Basic 登录事件
  on(:oauth2_basic_authenticated) do |auth, user|
    # auth.extra_data = 飞书返回的 data
    tenant_key = auth.extra_data["tenant_key"]
    union_id   = auth.extra_data["union_id"]
    open_id    = auth.extra_data["open_id"]
    name       = auth.extra_data["name"]
    avatar_url = auth.extra_data["avatar_url"]

    # 校验 tenant_key
    allowed_tenants = SiteSetting.feishu_allowed_tenant_keys.split("|")
    unless allowed_tenants.include?(tenant_key)
      raise Discourse::InvalidAccess.new("Tenant not allowed")
    end

    # 查绑定
    binding = FeishuUserBinding.find_by(tenant_key: tenant_key, union_id: union_id)
    if binding
      # 已有绑定，更新 open_id 和 last_login
      binding.update!(
        open_id: open_id,
        name: name,
        avatar_url: avatar_url,
        last_login_at: Time.zone.now,
        active: true
      )
      user = User.find(binding.discourse_user_id)
    else
      # 新用户，创建 Discourse 用户
      generated_email = "feishu-#{tenant_key}-#{union_id}@feishu.local.invalid"

      user ||= User.create!(
        username: union_id,
        name: name,
        email: generated_email,
        active: true,
        password: SecureRandom.hex(32)
      )

      # 写入绑定表
      FeishuUserBinding.create!(
        discourse_user_id: user.id,
        tenant_key: tenant_key,
        union_id: union_id,
        open_id: open_id,
        name: name,
        avatar_url: avatar_url,
        login_app_id: SiteSetting.feishu_login_app_id,
        notify_app_id: SiteSetting.feishu_notify_app_id,
        last_login_at: Time.zone.now,
        active: true
      )
    end

    # 完成登录
    user
  end
end