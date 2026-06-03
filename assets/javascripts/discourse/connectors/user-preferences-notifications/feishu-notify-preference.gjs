import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";

export default class FeishuNotifyPreference extends Component {
  @tracked loading = true;
  @tracked saving = false;
  @tracked bound = false;

  @tracked savedNotifyEnabled = true;
  @tracked draftNotifyEnabled = true;

  @tracked saved = false;
  @tracked error = null;

  constructor() {
    super(...arguments);
    this.load();
  }

  get dirty() {
    return this.savedNotifyEnabled !== this.draftNotifyEnabled;
  }

  get saveDisabled() {
    return this.saving || !this.dirty;
  }

  async load() {
    this.loading = true;
    this.error = null;

    try {
      const result = await ajax("/feishu/notification-preference");

      this.bound = !!result.bound;
      this.savedNotifyEnabled = !!result.notify_enabled;
      this.draftNotifyEnabled = !!result.notify_enabled;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
      this.error = "飞书通知设置加载失败";
    } finally {
      this.loading = false;
    }
  }

  @action
  changeDraft(event) {
    this.draftNotifyEnabled = event.target.checked;
    this.saved = false;
    this.error = null;
  }

  @action
  async save() {
    if (!this.dirty || this.saving) {
      return;
    }

    this.saving = true;
    this.saved = false;
    this.error = null;

    try {
      const result = await ajax("/feishu/notification-preference", {
        type: "PUT",
        data: {
          notify_enabled: this.draftNotifyEnabled,
        },
      });

      this.savedNotifyEnabled = !!result.notify_enabled;
      this.draftNotifyEnabled = !!result.notify_enabled;
      this.saved = true;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
      this.error = "飞书通知设置保存失败";
    } finally {
      this.saving = false;
    }
  }

  @action
  reset() {
    this.draftNotifyEnabled = this.savedNotifyEnabled;
    this.saved = false;
    this.error = null;
  }

  <template>
    <section class="control-group feishu-notify-preference">
      <label class="control-label">
        飞书通知
      </label>

      {{#if this.loading}}
        <p class="instructions">
          正在加载飞书通知设置……
        </p>
      {{else if this.bound}}
        <label class="checkbox-label">
          <input
            type="checkbox"
            checked={{this.draftNotifyEnabled}}
            disabled={{this.saving}}
            {{on "change" this.changeDraft}}
          />

          通过飞书私聊接收论坛通知
        </label>

        <p class="instructions">
          关闭后，论坛站内通知仍然正常显示，只是不再通过飞书私聊提醒。（此设置需要单独保存，不受页面底部保存按钮影响）
        </p>

        <button
          type="button"
          class="btn btn-primary"
          disabled={{this.saveDisabled}}
          {{on "click" this.save}}
        >
          {{#if this.saving}}
            保存中……
          {{else}}
            保存飞书通知设置
          {{/if}}
        </button>

        {{#if this.dirty}}
          <button
            type="button"
            class="btn btn-default"
            disabled={{this.saving}}
            {{on "click" this.reset}}
          >
            撤销
          </button>
        {{/if}}

        {{#if this.saved}}
          <p class="success">
            已保存
          </p>
        {{/if}}

        {{#if this.error}}
          <p class="error">
            {{this.error}}
          </p>
        {{/if}}
      {{else}}
        <p class="instructions">
          当前账号没有有效的飞书绑定，因此无法开启飞书私聊通知。
        </p>
      {{/if}}
    </section>
  </template>
}