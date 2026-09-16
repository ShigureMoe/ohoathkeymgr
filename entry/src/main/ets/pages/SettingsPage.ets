/**
 * 设置页（M5-6 / S10/S12）：
 *  - 暗黑模式三选一（跟随系统/深色/亮色，持久化）
 *  - 语言设置（fix-lang-switch-jank）：自绘下拉弹卡选择（无 Menu 子窗口），持久化即时 + 防抖应用
 *  - 重置安全卡片（输入 RESETTHEKEY 确认）
 *  - 已保存的会话密码（session-password-persist：Navigation 跳转管理页，仅展示/删除）
 *  - 兼容性测试（独立选项弹窗展示已测试设备列表）
 *  - 关于应用（作者/项目地址/问题反馈/License，外链跳转）
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

@Component
export struct SettingsPage {
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('connMode') connMode: string = 'none';
  // Navigation 路由栈（与 Index 的 @Provide('navPathStack') 配对）：跳转已保存会话密码管理页
  @Consume('navPathStack') navPathStack: NavPathStack;
  @State themeValue: string = 'system';
  @State langValue: string = LanguageManager.FOLLOW_SYSTEM;
  // 语言下拉展开标志（fix-lang-switch-jank D1）：收起为默认态；点选项/点遮罩置 false
  @State langDropdownOpen: boolean = false;
  @State resetDialogVisible: boolean = false;
  @State resetInput: string = '';
  @State resetBusy: boolean = false;
  @State aboutVisible: boolean = false;
  @State compatVisible: boolean = false;

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

          // 语言设置组（fix-lang-switch-jank US2）：自绘下拉——收起行点击展开根层选项弹卡（无 Menu 子窗口）
          Column({ space: 0 }) {
            Row() {
              Text($r('app.string.settings_language'))
                .fontSize(15)
              Blank()
            }
            .width('100%')
            .padding(16)

            // 收起态整行：当前语言文字 + 下拉箭头；排版对齐暗黑模式选项区
            Row() {
              Text(this.languageLabelRes())
                .fontSize(14)
              Blank()
              Text('▾')
                .fontSize(14)
                .fontColor($r('app.color.text_hint'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 14 })
          }
          .width('92%')
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)
          // 整卡可点击展开（US2）：标题行/值行/卡片空白均可命中，扩大点击热区
          .onClick(() => {
            this.langDropdownOpen = !this.langDropdownOpen;
          })

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
            Text($r('app.string.settings_about_compat'))
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
            this.compatVisible = true;
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

      if (this.compatVisible) {
        this.compatDialog()
      }

      // 语言下拉展开态（fix-lang-switch-jank US2/D5）：先渲染全屏半透明遮罩（点击仅收起、不切换语言），
      // 后渲染自绘选项弹卡（层级高于遮罩，与 ConnectSheet 弹层同范式：页面内组件、无 Menu 子窗口）
      if (this.langDropdownOpen) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.mask'))
          .onClick(() => {
            this.langDropdownOpen = false;
          })

        this.langOptionsCard()
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

  // ---------- 语言设置（fix-lang-switch-jank US1/US2） ----------

  /** 收起行显示文本（跟随语言切换取资源） */
  private languageLabelRes(): Resource {
    if (this.langValue === LanguageManager.ZH_HANS) {
      return $r('app.string.lang_chinese');
    }
    if (this.langValue === LanguageManager.EN_US) {
      return $r('app.string.lang_english');
    }
    return $r('app.string.lang_follow_system');
  }

  /**
   * 选项点击（US1/D4 时序）：先收起弹卡并移除遮罩 → 更新选中态 → 持久化 + 300ms 防抖应用，
   * 确保语言应用触发的全局 $r 刷新发生时页面无展开弹层/遮罩；
   * 跟随系统按平台约束提示重启生效
   */
  private onLanguagePick(value: string): void {
    this.langDropdownOpen = false;
    this.langValue = value;
    LanguageManager.persistAndApply(value);
    if (value === LanguageManager.FOLLOW_SYSTEM) {
      this.toast(ResUtil.str($r('app.string.settings_language_restart_hint')));
    }
  }

  /**
   * 语言选项弹卡（根 Stack 层渲染、层级高于遮罩）：偏上居中卡片内三行选项，
   * 与 ConnectSheet 弹层同范式；空白区域点击穿透至遮罩收起
   */
  @Builder
  langOptionsCard() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 4 }) {
        Text($r('app.string.settings_language'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
          .margin({ left: 4 })
        this.langOptionRow($r('app.string.lang_follow_system'), LanguageManager.FOLLOW_SYSTEM)
        this.langOptionRow($r('app.string.lang_chinese'), LanguageManager.ZH_HANS)
        this.langOptionRow($r('app.string.lang_english'), LanguageManager.EN_US)
      }
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_sheet'))
      .width('88%')
      .margin({ bottom: '20%' })
      .onClick(() => {
        // 空回调拦截卡片区域点击（onClick 为非冒泡系统手势、子组件优先识别），
        // 避免点卡片内容误触外层遮罩导致收起
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /** 选项行（D3）：排版参照暗黑模式单选行；当前生效项 accent_soft 高亮背景 + token_accent 主题色文字 */
  @Builder
  langOptionRow(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.langValue === value ? $r('app.color.token_accent') : $r('app.color.text_primary'))
      Blank()
      if (this.langValue === value) {
        Text('✓')
          .fontSize(14)
          .fontColor($r('app.color.token_accent'))
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(8)
    .backgroundColor(this.langValue === value ? $r('app.color.accent_soft') : Color.Transparent)
    .onClick(() => {
      this.onLanguagePick(value);
    })
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

  // 兼容性测试独立弹窗（从关于应用拆出）：标题 + 说明 + 已测试设备列表
  @Builder
  compatDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Text($r('app.string.settings_about_compat'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Text($r('app.string.settings_compat_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Column({ space: 10 }) {
          Text('Yubikey 5 NFC')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text('Canokeys Pigeon (USB Mode)')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 4 })
        Button($r('app.string.common_close'))
          .width(110)
          .height(38)
          .fontSize(14)
          .backgroundColor($r('app.color.button_neutral_bg'))
          .fontColor($r('app.color.button_neutral_fg'))
          .onClick(() => {
            this.compatVisible = false;
          })
      }
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_sheet'))
      .width('86%')
      .onClick(() => {
        // 空回调拦截卡片区域点击，避免点卡片内容误触外层遮罩导致弹窗关闭
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.mask'))
    .onClick(() => {
      this.compatVisible = false;
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