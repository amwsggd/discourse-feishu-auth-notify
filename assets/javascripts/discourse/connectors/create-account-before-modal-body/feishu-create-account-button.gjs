import Component from "@glimmer/component";

export default class FeishuCreateAccountButton extends Component {
  <template>
    <div class="feishu-login-panel">
      <a href="/feishu/login" class="btn btn-primary feishu-login-button">
        使用飞书注册 / 登录
      </a>

      <p class="feishu-login-help">
        论坛账号会根据你的组织飞书身份自动创建。
      </p>
    </div>
  </template>
}