class Plugins::FeishuAuthController < ::ApplicationController
  skip_before_action :redirect_to_login_if_required
  skip_before_action :block_if_requires_login
  skip_before_action :check_xhr
  skip_before_action :preload_json
  skip_before_action :verify_authenticity_token

  require 'net/http'
  require 'json'
  require "digest"

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

    token_data = JSON.parse(token_resp.body)
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
    binding = FeishuUserBinding.find_by(tenant_key: tenant_key, union_id: union_id, active: true)
    if binding
      user = User.find(binding.discourse_user_id)
      binding.update!(open_id: open_id, name: name, avatar_url: avatar_url, last_login_at: Time.zone.now, active: true)
    else
        user = nil

        ActiveRecord::Base.transaction(requires_new: true) do
            acquire_feishu_identity_lock!(tenant_key, union_id)

            # 关键：拿到锁后必须重新查一次
            binding = FeishuUserBinding.find_by(
            tenant_key: tenant_key,
            union_id: union_id
            )

            if binding
            user = User.find_by!(id: binding.discourse_user_id)

            binding.update!(
                open_id: open_id,
                name: name,
                avatar_url: avatar_url,
                login_app_id: SiteSetting.feishu_login_app_id,
                notify_app_id: SiteSetting.feishu_notify_app_id.presence || SiteSetting.feishu_login_app_id,
                last_login_at: Time.zone.now,
                active: true
            )
            else
            user = create_feishu_user!(
                tenant_key: tenant_key,
                union_id: union_id,
                name: name
            )

            FeishuUserBinding.create!(
                discourse_user_id: user.id,
                tenant_key: tenant_key,
                union_id: union_id,
                open_id: open_id,
                name: name,
                avatar_url: avatar_url,
                login_app_id: SiteSetting.feishu_login_app_id,
                notify_app_id: SiteSetting.feishu_notify_app_id.presence || SiteSetting.feishu_login_app_id,
                last_login_at: Time.zone.now,
                active: true
            )
            end
        end
    end

    # 5. 登录用户
    log_on_user(user)
    redirect_to "/"
  end

  private

    def acquire_feishu_identity_lock!(tenant_key, union_id)
        digest = Digest::SHA256.hexdigest("#{tenant_key}:#{union_id}")

        key = digest[0, 16].to_i(16)
        key = key - (1 << 63) if key >= (1 << 63)

        ActiveRecord::Base.connection.exec_query(
            "SELECT pg_advisory_xact_lock(#{key})"
        )
    end

  def feishu_identity_digest(tenant_key, union_id)
    Digest::SHA256.hexdigest("#{tenant_key}:#{union_id}")
  end

  def feishu_placeholder_email(tenant_key, union_id)
    # digest = feishu_identity_digest(tenant_key, union_id)[0, 32]
    "feishu-#{tenant_key}-#{union_id}@feishu.local.invalid"
  end

  def build_unique_feishu_username(tenant_key, union_id, name = nil)
    max_length = SiteSetting.max_username_length || 20
    min_length = SiteSetting.min_username_length || 3

    digest = feishu_identity_digest(tenant_key, union_id)

    readable =
        name.to_s
        .downcase
        .gsub(/[^a-z0-9_]/, "_")
        .gsub(/_+/, "_")
        .gsub(/\A_+|_+\z/, "")

    readable = "fs" if readable.blank?
    readable = readable[0, 6]

    candidates = [
        "#{readable}_#{digest[0, 8]}",
        "fs_#{digest[0, 12]}",
        "f_#{digest[0, 14]}"
    ]

    candidates.each do |candidate|
        candidate = candidate[0, max_length]
        candidate = candidate.ljust(min_length, "0")

        return candidate unless User.exists?(username_lower: candidate.downcase)
    end

    loop do
        random_part = SecureRandom.alphanumeric(12).downcase
        candidate = "fs_#{random_part}"[0, max_length]
        candidate = candidate.ljust(min_length, "0")

        return candidate unless User.exists?(username_lower: candidate.downcase)
    end
    end
    
    def create_feishu_user!(tenant_key:, union_id:, name:)
        generated_email = feishu_placeholder_email(tenant_key, union_id)

        5.times do
            username = build_unique_feishu_username(tenant_key, union_id, name)

            begin
            return User.create!(
                username: username,
                name: name.presence || username,
                email: generated_email,
                active: true,
                password: SecureRandom.hex(32)
            )
            rescue ActiveRecord::RecordInvalid => e
            username_related =
                e.record.errors[:username].present? ||
                e.record.errors[:username_lower].present?

            raise unless username_related
            rescue ActiveRecord::RecordNotUnique
            # 并发下可能撞唯一索引，重试
            end
        end

        raise "Failed to create unique username for Feishu user"
    end
  def callback_url
    "#{SiteSetting.feishu_auth_callback_url}/feishu/callback"
  end
end