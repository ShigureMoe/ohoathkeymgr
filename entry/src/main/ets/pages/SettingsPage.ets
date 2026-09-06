/**
 * 设置页（M5-6 / S10/S12）：
 *  - 暗黑模式三选一（跟随系统/深色/亮色，持久化）
 *  - 重置安全卡片（输入 RESETTHEKEY 确认）
 */
import { AppContextHolder } from '../common/AppContextHolder';
import { AppPreferences } from '../storage/AppPreferences';
import { ThemeManager } from '../service/ThemeManager';
import { OathSessionManager } from '../service/OathSessionManager';

@Component
export struct SettingsPage {
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('connMode') connMode: string = 'none';
  @State themeValue: string = 'system';
  @State resetDialogVisible: boolean = false;
  @State resetInput: string = '';
  @State resetBusy: boolean = false;

  aboutToAppear(): void {
    this.themeValue = AppPreferences.getString('ui_theme', ThemeManager.THEME_SYSTEM);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column({ space: 12 }) {
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
          .margin({ left: 20, top: 72 })

        Column({ space: 0 }) {
          Row() {
            Text('暗黑模式')
              .fontSize(15)
            Blank()
          }
          .width('100%')
          .padding(16)
          Column({ space: 12 }) {
            this.themeRow('跟随系统', ThemeManager.THEME_SYSTEM)
            this.themeRow('深色', ThemeManager.THEME_DARK)
            this.themeRow('亮色', ThemeManager.THEME_LIGHT)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 14 })
        }
        .width('92%')
        .backgroundColor($r('app.color.surface_card'))
        .borderRadius(10)

        Row() {
          Text('重置安全卡片')
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

        Blank()
      }
      .width('100%')
      .height('100%')

      if (this.resetDialogVisible) {
        this.resetDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  themeRow(label: string, value: string) {
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

  @Builder
  resetDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Text('重置 OATH 应用')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Text('当前操作会重置安全卡片的 OATH 应用数据（删除全部凭据与安全密码），请谨慎操作，确认操作请输入 RESETTHEKEY')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        TextInput({ placeholder: '输入 RESETTHEKEY', text: this.resetInput })
          .onChange((v: string) => {
            this.resetInput = v;
          })
        Row({ space: 40 }) {
          Button('取消')
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .fontColor($r('app.color.button_neutral_fg'))
            .onClick(() => {
              this.resetDialogVisible = false;
            })
          Button(this.resetBusy ? '重置中…' : '确认重置')
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
      this.toast('请输入 RESETTHEKEY');
      return;
    }
    this.resetBusy = true;
    try {
      await OathSessionManager.getInstance().resetCard(this.toast);
      this.resetDialogVisible = false;
      this.toast('卡片已重置');
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.resetBusy = false;
    }
  }
}