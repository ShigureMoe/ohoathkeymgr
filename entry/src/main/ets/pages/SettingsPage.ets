/**
 * 设置页（M5-6 / S10/S12）：
 *  - 暗黑模式三选一（跟随系统/深色/亮色，持久化）
 *  - 重置安全卡片（输入 RESETTHEKEY 确认）
 *  - 已保存的会话密码（session-password-persist：Navigation 跳转管理页，仅展示/删除）
 *  - 关于应用（作者/项目地址/问题反馈/License/兼容性测试，前四项外链跳转）
 */
import { common, OpenLinkOptions } from '@kit.AbilityKit';
import { AppContextHolder } from '../common/AppContextHolder';
import { AppPreferences } from '../storage/AppPreferences';
import { ThemeManager } from '../service/ThemeManager';
import { LanguageManager } from '../service/LanguageManager';
import { ResUtil } from '../common/ResUtil';
import { OathSessionManager } from '../service/OathSessionManager';

// 关于应用外链（用户指定，取值逐字一致，禁止改写）
const ABOUT_URL_AUTHOR: string = 'https://github.com/ShigureMoe';
const ABOUT_URL_REPO: string = 'https://github.com/ShigureMoe/ohoathkeymgr';
const ABOUT_URL_ISSUES: string = 'https://github.com/ShigureMoe/ohoathkeymgr/issues';
const ABOUT_URL_LICENSE: string = 'https://raw.githubusercontent.com/ShigureMoe/ohoathkeymgr/refs/heads/master/COPYING';

// 语言偏好内部值（与 Select 选项下标一一对应；内部值不翻译，仅展示层资源化）
const LANGUAGE_VALUES: string[] = [LanguageManager.FOLLOW_SYSTEM, LanguageManager.ZH_HANS, LanguageManager.EN_US];

@Component
export struct SettingsPage {
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('connMode') connMode: string = 'none';
  // Navigation 路由栈（与 Index 的 @Provide('navPathStack') 配对）：跳转已保存会话密码管理页
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State themeValue: string = 'system';
  @State langValue: string = LanguageManager.FOLLOW_SYSTEM;
  @State resetDialogVisible: boolean = false;
  @State resetInput: string = '';
  @State resetBusy: boolean = false;
  @State aboutVisible: boolean = false;

  aboutToAppear(): void {
    this.themeValue = AppPreferences.getString('ui_theme', ThemeManager.THEME_SYSTEM);
    this.langValue = LanguageManager.getPersisted();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 12 }) {
          Text($r('app.string.tab_settings'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .alignSelf(ItemAlign.Start)
            .margin({ left: 20 })

          Column({ space: 0 }) {
            Row() {
              Text($r('app.string.settings_dark_mode'))
                .fontSize(15)
              Blank()
            }
            .width('100%')
            .padding(16)
            Column({ space: 12 }) {
              this.themeRow($r('app.string.settings_theme_system'), ThemeManager.THEME_SYSTEM)
              this.themeRow($r('app.string.settings_theme_dark'), ThemeManager.THEME_DARK)
              this.themeRow($r('app.string.settings_theme_light'), ThemeManager.THEME_LIGHT)
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 14 })
          }
          .width('92%')
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)

          // 语言设置组（app-i18n US1）：下拉框三选项，选择即时生效并持久化
          Column({ space: 0 }) {
            Row() {
              Text($r('app.string.settings_language'))
                .fontSize(15)
              Blank()
            }
            .width('100%')
            .padding(16)
            Select(this.languageOptions())
              .selected(this.languageIndex())
              .value(this.languageLabelRes())
              .onSelect((index: number) => {
                this.onLanguageSelect(index);
              })
              .width('100%')
              .font({ size: 14 })
              .selectedOptionFont({ size: 14 })
              .optionFont({ size: 14 })
              .backgroundColor($r('app.color.surface_card'))
              .margin({ left: 16, right: 16, bottom: 14 })
          }
          .width('92%')
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)

          Row() {
            Text($r('app.string.settings_reset_entry'))
              .fontSize(15)
              .fontColor(this.connMode === 'none' ? $r('app.color.text_hint') : $r('app.color.danger'))
            Blank()
            Text('>')
              .fontSize(15)
              .fontColor($r('app.color.text_hint'))
          }
          .width('92%')
          .padding(16)
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)
          .enabled(this.connMode !== 'none')
          .onClick(() => {
            this.resetInput = '';
            this.resetDialogVisible = true;
          })

          Row() {
            Text($r('app.string.settings_saved_passwords'))
              .fontSize(15)
            Blank()
            Text('>')
              .fontSize(15)
              .fontColor($r('app.color.text_hint'))
          }
          .width('92%')
          .padding(16)
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)
          .onClick(() => {
            // 管理本地持久化数据，与连接状态无关（不随连接置灰）
            this.navPathStack.pushPathByName('savedPasswords', null);
          })

          Row() {
            Text($r('app.string.settings_about'))
              .fontSize(15)
            Blank()
            Text('>')
              .fontSize(15)
              .fontColor($r('app.color.text_hint'))
          }
          .width('92%')
          .padding(16)
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)
          .onClick(() => {
            this.aboutVisible = true;
          })
        }
        .width('100%')
        .padding({ top: 72, bottom: 156 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Start)

      if (this.resetDialogVisible) {
        this.resetDialog()
      }

      if (this.aboutVisible) {
        this.aboutDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  themeRow(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
      Blank()
      Radio({ value: value, group: 'theme' })
        .checked(this.themeValue === value)
        .onChange((checked: boolean) => {
          if (!checked) {
            return;
          }
          this.themeValue = value;
          AppPreferences.putString('ui_theme', value);
          const ctx = AppContextHolder.context;
          if (ctx !== undefined) {
            ThemeManager.apply(ctx);
          }
        })
    }
    .width('100%')
  }

  // ---------- 语言设置（app-i18n US1 / D6） ----------

  private languageOptions(): Array<SelectOption> {
    return [
      { value: $r('app.string.lang_follow_system') },
      { value: $r('app.string.lang_chinese') },
      { value: $r('app.string.lang_english') }
    ];
  }

  /** 当前偏好对应的选项下标 */
  private languageIndex(): number {
    const idx = LANGUAGE_VALUES.indexOf(this.langValue);
    return idx >= 0 ? idx : 0;
  }

  /** Select 收起态显示文本（跟随语言切换取资源） */
  private languageLabelRes(): Resource {
    if (this.langValue === LanguageManager.ZH_HANS) {
      return $r('app.string.lang_chinese');
    }
    if (this.langValue === LanguageManager.EN_US) {
      return $r('app.string.lang_english');
    }
    return $r('app.string.lang_follow_system');
  }

  /** 下拉框选择：即时生效 + 持久化；跟随系统按平台约束提示重启生效（D1） */
  private onLanguageSelect(index: number): void {
    const value = index >= 0 && index < LANGUAGE_VALUES.length
      ? LANGUAGE_VALUES[index] : LanguageManager.FOLLOW_SYSTEM;
    this.langValue = value;
    LanguageManager.persistAndApply(value);
    if (value === LanguageManager.FOLLOW_SYSTEM) {
      this.toast(ResUtil.str($r('app.string.settings_language_restart_hint')));
    }
  }

  @Builder
  resetDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Text($r('app.string.settings_reset_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Text($r('app.string.settings_reset_warning'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ placeholder: $r('app.string.settings_reset_input_hint'), text: this.resetInput })
          .onChange((v: string) => {
            this.resetInput = v;
          })
        Row({ space: 40 }) {
          Button($r('app.string.common_cancel'))
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .fontColor($r('app.color.button_neutral_fg'))
            .onClick(() => {
              this.resetDialogVisible = false;
            })
          Button(this.resetBusy ? $r('app.string.settings_reset_busy') : $r('app.string.settings_reset_confirm'))
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.danger'))
            .enabled(!this.resetBusy)
            .onClick(() => {
              this.confirmReset();
            })
        }
      }
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_sheet'))
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.mask'))
  }

  private async confirmReset(): Promise<void> {
    if (this.resetInput !== 'RESETTHEKEY') {
      this.toast(ResUtil.str($r('app.string.settings_reset_input_required')));
      return;
    }
    this.resetBusy = true;
    try {
      await OathSessionManager.getInstance().resetCard(this.toast);
      this.resetDialogVisible = false;
      this.toast(ResUtil.str($r('app.string.settings_reset_done')));
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.resetBusy = false;
    }
  }

  @Builder
  aboutDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Text($r('app.string.settings_about'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Column({ space: 12 }) {
          this.aboutRow($r('app.string.settings_about_author'), 'ShigureMoe', ABOUT_URL_AUTHOR)
          this.aboutRow($r('app.string.settings_about_repo'), ABOUT_URL_REPO, ABOUT_URL_REPO)
          this.aboutRow($r('app.string.settings_about_issues'), ABOUT_URL_ISSUES, ABOUT_URL_ISSUES)
          this.aboutRow($r('app.string.settings_about_license'), 'GPL-3.0 license', ABOUT_URL_LICENSE)
          this.aboutRow($r('app.string.settings_about_compat'), 'Yubikey 5 NFC、Canokeys Pigeon', '')
        }
        .width('100%')
        Button($r('app.string.common_close'))
          .width(110)
          .height(38)
          .fontSize(14)
          .backgroundColor($r('app.color.button_neutral_bg'))
          .fontColor($r('app.color.button_neutral_fg'))
          .onClick(() => {
            this.aboutVisible = false;
          })
      }
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_sheet'))
      .width('86%')
      .onClick(() => {
        // 空回调拦截卡片区域点击（onClick 为非冒泡系统手势、子组件优先识别），
        // 避免点卡片内容误触外层遮罩导致弹窗关闭
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.mask'))
    .onClick(() => {
      this.aboutVisible = false;
    })
  }

  // url 传空串表示纯文本行（不可点击，无点击态反馈）
  @Builder
  aboutRow(label: Resource, content: string, url: string) {
    if (url !== '') {
      Row() {
        this.aboutRowContent(label, content, true)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.openExternal(url);
      })
    } else {
      Row() {
        this.aboutRowContent(label, content, false)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
  }

  @Builder
  aboutRowContent(label: Resource, content: string, isLink: boolean) {
    Text(label)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .width(72)
    Text(content)
      .layoutWeight(1)
      .fontSize(14)
      .fontColor(isLink ? $r('app.color.token_accent') : $r('app.color.text_primary'))
      .decoration({
        type: isLink ? TextDecorationType.Underline : TextDecorationType.None,
        color: isLink ? $r('app.color.token_accent') : $r('app.color.text_primary')
      })
      .maxLines(2)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  private openExternal(url: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: OpenLinkOptions = { appLinkingOnly: false };
      context.openLink(url, options).catch(() => {
        this.toast(ResUtil.str($r('app.string.settings_open_link_failed')));
      });
    } catch (err) {
      this.toast(ResUtil.str($r('app.string.settings_open_link_failed')));
    }
  }
}