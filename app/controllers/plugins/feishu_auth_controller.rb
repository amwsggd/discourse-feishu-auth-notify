class Plugins::FeishuAuthController < ::ApplicationController
  skip_before_action :redirect_to_login_if_required
  skip_before_action :block_if_requires_login
  skip_before_action :check_xhr
  skip_before_action :preload_json
  skip_before_action :verify_authenticity_token

  require 'net/http'
  require 'json'

  FEISHU_OAUTH_AUTHORIZE_URL = "https://accounts.feishu.cn/open-apis/authen/v1/authorize"
  FEISHU_OAUTH_TOKEN_URL     = "https://open.feishu.cn/open-apis/authen/v2/oauth/token"
  FEISHU_USER_INFO_URL       = "https://open.feishu.cn/open-apis/authen/v1/user_info"

  def auth
    state = SecureRandom.hex(24)
    session[:feishu_oauth_state] = state

    query = {
        client_id: SiteSetting.feishu_login_app_id,
        redirect_uri: callback_url,
        response_type: "code",
        scope: "contact:user.base:readonly",
        state: state
    }.to_query

    redirect_to "#{FEISHU_OAUTH_AUTHORIZE_URL}?#{query}", allow_other_host: true
  end

  def callback
    code = params[:code]
    if code.blank?
      render plain: "Missing code", status: 400
      return
    end

    # 1. 获取 user_access_token
    token_resp = Net::HTTP.post(
      URI(FEISHU_OAUTH_TOKEN_URL),
      {
        grant_type: "authorization_code",
        code: code,
        client_id: SiteSetting.feishu_login_app_id,
        client_secret: SiteSetting.feishu_login_app_secret,
        redirect_uri: callback_url
      }.to_json,
      "Content-Type" => "application/json"
    )

    token_data = JSON.parse(token_resp.body)["data"]
    user_access_token = token_data["access_token"]

    # 2. 获取用户信息
    uri = URI(FEISHU_USER_INFO_URL)
    req = Net::HTTP::Get.new(uri)
    req["Authorization"] = "Bearer #{user_access_token}"
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    user_data = JSON.parse(res.body)["data"]

    tenant_key = user_data["tenant_key"]
    union_id   = user_data["union_id"]
    open_id    = user_data["open_id"]
    name       = user_data["name"]
    avatar_url = user_data["avatar_url"]

    # 3. 校验 tenant_key
    allowed = SiteSetting.feishu_allowed_tenant_keys.split("|")
    unless allowed.include?(tenant_key)
      render plain: "Tenant not allowed", status: 403
      return
    end

    # 4. 查绑定表或创建 Discourse 用户
    binding = FeishuUserBinding.find_by(tenant_key: tenant_key, union_id: union_id)
    if binding
      user = User.find(binding.discourse_user_id)
      binding.update!(open_id: open_id, name: name, avatar_url: avatar_url, last_login_at: Time.zone.now, active: true)
    else
      # 占位邮箱
      generated_email = "feishu-#{tenant_key}-#{union_id}@feishu.local.invalid"

      user = User.create!(
        username: union_id,
        name: name,
        email: generated_email,
        active: true,
        trust_level: TrustLevel[3],
        password: SecureRandom.hex(32)
      )

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

    # 5. 登录用户
    sign_in(user)
    redirect_to "/"
  end

  private

  def callback_url
    "#{Discourse.base_url}/feishu/callback"
  end
end