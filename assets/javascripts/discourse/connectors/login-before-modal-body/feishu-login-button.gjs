import Component from "@glimmer/component";

export default class FeishuLoginButton extends Component {
  <template>
    <div class="feishu-login-panel">
      <a href="/feishu/login" class="btn btn-primary feishu-login-button">
        使用飞书登录
      </a>

      <p class="feishu-login-help">
        使用组织飞书账号登录或注册论坛。
      </p>
    </div>
  </template>
}