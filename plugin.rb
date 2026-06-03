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
  # 注册回调路由
  Discourse::Application.routes.append do
    get '/auth/feishu' => 'plugins/feishu_auth#auth'
    get '/auth/feishu/callback' => 'plugins/feishu_auth#callback'
  end
end