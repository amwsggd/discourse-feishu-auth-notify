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
  end
end