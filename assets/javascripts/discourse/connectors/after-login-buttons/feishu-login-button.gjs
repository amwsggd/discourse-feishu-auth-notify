import Component from "@glimmer/component";
import { action } from "@ember/object";
import { on } from "@ember/modifier";

export default class FeishuLoginButton extends Component {
  @action
  login(event) {
    event.preventDefault();
    window.location.href = "/feishu/login";
  }

  <template>
    <div class="feishu-login-button-wrapper">
      <button
        type="button"
        class="btn btn-social btn-feishu"
        {{on "click" this.login}}
      >
        使用飞书登录
      </button>
    </div>
  </template>
}