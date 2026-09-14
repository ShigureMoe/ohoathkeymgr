/**
 * 令牌列表项（M5-3/7 + S6/S13）：
 *  - 上下两区对角错开布局：上区 Issuer/Account 两行文本靠左独占整行宽度（超长省略截断）；
 *    下区码值 24px + 长按复制提示整体靠右，操作控件（倒计时环/刷新/触摸按钮）位于最右
 *  - TOTP 环形倒计时；到期/断开置灰；HOTP 刷新按钮；触摸凭据触摸按钮（点击后等待触摸）
 *  - 码值分段显示（6 位 → 3+3、8 位 → 4+4，其他原样）；长按复制原始连续码值
 *  - 左滑删除（回调给页面弹确认）
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { TokenListItem } from '../viewmodel/TokenStore';
import { TokenItemState } from '../model/UiState';
import { OtpType } from '../model/Credential';
import { CountdownArc } from './CountdownArc';
import { ResUtil } from '../common/ResUtil';

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

  @Builder
  deleteButton() {
    Row() {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.icon_delete'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.surface_sheet'))
      }
      .width(40)
      .height(40)
      .backgroundColor($r('app.color.danger_bg'))
      .onClick(() => {
        this.callbacks.onDelete(this.item.cred.name);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.End)
    .padding({ right: 16 })
  }

  build() {
    ListItem() {
      Column() {
        // ---- 上区：Issuer / Account（独占整行宽度，超长省略截断） ----
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
        .margin({ left: 16 })

        // ---- 下区：码值 + 提示（整体右对齐） + 操作控件（最右，从左到右：码值→控件） ----
        Row() {
          // 左侧：空占位（推码值区贴右；触摸/HOTP 未计算等无码值形态同样保持控件贴右）
          Blank()
            .layoutWeight(1)

          // 码值 + 长按复制提示：右缘对齐，紧邻操作控件左侧（触摸凭据无码值，不渲染内容）
          Column({ space: 2 }) {
            if (this.item.state !== TokenItemState.TOUCH &&
              this.item.state !== TokenItemState.TOUCH_PROMPTING) {
              if (this.item.cred.otpType === OtpType.HOTP) {
                // HOTP：无倒计时；未计算时仅刷新按钮，计算后显示码值（可多次刷新，卡片计数器+1）
                if (this.item.state === TokenItemState.ACTIVE && this.item.code.length > 0) {
                  Text(this.formatCode(this.item.code))
                    .fontSize(24)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.token_accent'))
                    .letterSpacing(2)
                    .gesture(
                      LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                        this.copyCode();
                      })
                    )
                }
              } else {
                // ACTIVE / STALE / ERROR：空码以 '--' 占位，到期/错误置灰
                Text(this.item.code.length > 0 ? this.formatCode(this.item.code) : '--')
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isDim() ? $r('app.color.text_secondary') : $r('app.color.token_accent'))
                  .letterSpacing(2)
                  .gesture(
                    LongPressGesture({ repeat: false }).onAction((event: GestureEvent) => {
                      this.copyCode();
                    })
                  )
                Text($r('app.string.token_long_press_copy'))
                  .fontSize(10)
                  .fontColor($r('app.color.text_hint'))
              }
            }
          }
          .alignItems(HorizontalAlign.End)
          .margin({ right: 12 })

          // 最右：按形态放置操作控件
          if (this.item.cred.otpType === OtpType.HOTP) {
            Button({ type: ButtonType.Circle }) {
              Image($r('app.media.icon_refresh'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.on_token_accent'))
            }
            .width(36)
            .height(36)
            .backgroundColor($r('app.color.token_accent'))
            .margin({ right: 16 })
            .onClick(() => {
              this.callbacks.onHotpRefresh(this.item.cred.name);
            })
          } else if (this.item.state === TokenItemState.TOUCH ||
            this.item.state === TokenItemState.TOUCH_PROMPTING) {
            Button(this.item.state === TokenItemState.TOUCH_PROMPTING
              ? $r('app.string.token_touch_waiting') : $r('app.string.token_touch'))
              .width(64)
              .height(30)
              .fontSize(12)
              .backgroundColor(this.item.state === TokenItemState.TOUCH_PROMPTING ? $r('app.color.warning') : $r('app.color.text_secondary'))
              .margin({ right: 16 })
              .enabled(this.item.state === TokenItemState.TOUCH)
              .onClick(() => {
                this.callbacks.onTouchTap(this.item.cred.name);
              })
          } else if (this.item.cred.otpType === OtpType.TOTP) {
            CountdownArc({
              remaining: this.item.remainingSec,
              total: this.item.cred.period,
              stale: this.item.state !== TokenItemState.ACTIVE
            })
              .margin({ right: 12 })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(80)
      .alignItems(HorizontalAlign.Start) // 上区文本列贴左（修复 Column 默认水平居中导致的漂移）
    }
    .swipeAction({ end: this.deleteButton })
  }

  private isDim(): boolean {
    return this.item.state === TokenItemState.STALE || this.item.state === TokenItemState.ERROR;
  }

  /** 码值分段显示（仅显示层）：6 位 → 3+3、8 位 → 4+4，其他长度原样；复制仍用原始连续码值 */
  private formatCode(code: string): string {
    if (code.length === 6) {
      return code.slice(0, 3) + ' ' + code.slice(3);
    }
    if (code.length === 8) {
      return code.slice(0, 4) + ' ' + code.slice(4);
    }
    return code;
  }

  private copyCode(): void {
    if (this.item.code.length === 0) {
      return;
    }
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.item.code);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.getUIContext().getPromptAction().showToast({
        message: ResUtil.str($r('app.string.token_copied'))
      });
    }).catch(() => {
    });
  }
}