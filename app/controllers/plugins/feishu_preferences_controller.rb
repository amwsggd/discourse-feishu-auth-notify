# frozen_string_literal: true

class Plugins::FeishuPreferencesController < ::ApplicationController
  requires_login

    # show
    def show
    binding = current_binding

    render json: {
        bound: binding.present?,
        notify_enabled: binding ? binding.notify_enabled : false
    }
    rescue => e
    render json: { error: e.message }, status: 500
    end

    # update
    def update
    binding = current_binding

    if binding.blank?
        render json: { error: "当前账号没有有效的飞书绑定" }, status: 404
        return
    end

    enabled = ActiveModel::Type::Boolean.new.cast(params[:notify_enabled])

    binding.update!(notify_enabled: enabled)

    render json: {
        success: true,
        bound: true,
        notify_enabled: binding.notify_enabled
    }
    rescue => e
    render json: { error: e.message }, status: 500
    end

  private

  def current_binding
    FeishuUserBinding.find_by(
      discourse_user_id: current_user.id,
      active: true
    )
  end
end