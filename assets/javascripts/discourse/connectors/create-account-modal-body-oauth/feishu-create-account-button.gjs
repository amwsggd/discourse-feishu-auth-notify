import Component from "@glimmer/component";

export default class FeishuCreateAccountButton extends Component {
  <template>
    <div class="oauth-login-button-wrapper">
      <a href="/feishu/login" class="btn btn-oauth btn-feishu">
        <span class="btn-icon">
          <img src="/plugins/discourse-feishu-auth-notify/assets/images/feishu-icon.png" alt="飞书"/>
        </span>
        <span class="btn-text">使用飞书注册 / 登录</span>
      </a>
    </div>
  </template>
}