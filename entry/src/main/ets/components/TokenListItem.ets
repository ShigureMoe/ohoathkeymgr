/**
 * 令牌列表项（M5-3/7 + S6/S13）：
 *  - 左侧 Issuer/Account，右侧令牌（蓝粗/长按复制）
 *  - TOTP 环形倒计时；到期/断开置灰
 *  - HOTP 显示刷新按钮；触摸凭据显示触摸按钮（点击后等待触摸）
 *  - 左滑删除（回调给页面弹确认）
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { TokenListItem } from '../viewmodel/TokenStore';
import { TokenItemState } from '../model/UiState';
import { OtpType } from '../model/Credential';
import { CountdownArc } from './CountdownArc';

/** 列表项回调（struct 字段不能为 interface 类型，故用 class） */
export class TokenItemCallbacks {
  onDelete: (name: string) => void = () => {
  };
  onHotpRefresh: (name: string) => void = () => {
  };
  onTouchTap: (name: string) => void = () => {
  };
}

@Component
export struct TokenListItemComp {
  @ObjectLink item: TokenListItem;
  callbacks: TokenItemCallbacks = new TokenItemCallbacks();
  @State showDelete: boolean = false;

  @Builder
  deleteButton() {
    Button('删除')
      .width(64)
      .height('100%')
      .backgroundColor($r('app.color.danger_bg'))
      .fontColor($r('app.color.surface_sheet'))
      .fontSize(14)
      .borderRadius(0)
      .onClick(() => {
        this.callbacks.onDelete(this.item.cred.name);
      })
  }

  build() {
    ListItem() {
      Row() {
        // ---- 左侧：Issuer / Account ----
        Column({ space: 2 }) {
          Text(this.item.cred.getLabel())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDim() ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.item.cred.account)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 16 })

        // ---- 右侧：令牌 / 按钮 ----
        if (this.item.cred.otpType === OtpType.HOTP) {
          // HOTP：无倒计时；未计算时仅刷新按钮，计算后显示码值+刷新按钮（可多次刷新，卡片计数器+1）
          Row({ space: 10 }) {
            if (this.item.state === TokenItemState.ACTIVE && this.item.code.length > 0) {
              Text(this.item.code)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.accent'))
                .letterSpacing(2)
                .gesture(
                  LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                    this.copyCode();
                  })
                )
            }
            Button(this.item.state === TokenItemState.ACTIVE ? '↻' : '刷新')
              .width(this.item.state === TokenItemState.ACTIVE ? 34 : 56)
              .height(30)
              .fontSize(12)
              .backgroundColor($r('app.color.accent'))
              .margin({ right: 16 })
              .onClick(() => {
                this.callbacks.onHotpRefresh(this.item.cred.name);
              })
          }
          .margin({ right: 0 })
        } else if (this.item.state === TokenItemState.TOUCH ||
          this.item.state === TokenItemState.TOUCH_PROMPTING) {
          Button(this.item.state === TokenItemState.TOUCH_PROMPTING ? '等待触摸…' : '触摸')
            .width(64)
            .height(30)
            .fontSize(12)
            .backgroundColor(this.item.state === TokenItemState.TOUCH_PROMPTING ? $r('app.color.warning') : $r('app.color.text_secondary'))
            .margin({ right: 16 })
            .enabled(this.item.state === TokenItemState.TOUCH)
            .onClick(() => {
              this.callbacks.onTouchTap(this.item.cred.name);
            })
        } else {
          // ACTIVE / STALE / ERROR
          Column({ space: 2 }) {
            Text(this.item.code.length > 0 ? this.item.code : '--')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.isDim() ? $r('app.color.text_secondary') : $r('app.color.accent'))
              .letterSpacing(2)
              .gesture(
                LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                  this.copyCode();
                })
              )
            Text('长按复制')
              .fontSize(10)
              .fontColor($r('app.color.text_hint'))
          }
          .alignItems(HorizontalAlign.End)
          .margin({ right: 12 })
          if (this.item.cred.otpType === OtpType.TOTP) {
            CountdownArc({
              remaining: this.item.remainingSec,
              total: this.item.cred.period,
              stale: this.item.state !== TokenItemState.ACTIVE
            })
              .margin({ right: 12 })
          }
        }
      }
      .width('100%')
      .height(64)
      .alignItems(VerticalAlign.Center)
    }
    .swipeAction({ end: this.deleteButton })
  }

  private isDim(): boolean {
    return this.item.state === TokenItemState.STALE || this.item.state === TokenItemState.ERROR;
  }

  private copyCode(): void {
    if (this.item.code.length === 0) {
      return;
    }
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.item.code);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.getUIContext().getPromptAction().showToast({ message: '令牌已复制' });
    }).catch(() => {
    });
  }
}