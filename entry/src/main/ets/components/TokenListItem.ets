/**
 * 令牌列表项（M5-3/7 + S6/S13 + accessibility-optimization）：
 *  - 上下两区对角错开布局：上区 Issuer/Account 两行文本靠左独占整行宽度（超长省略截断）；
 *    下区码值 24px 整体靠右，操作控件（倒计时环/刷新/触摸按钮）位于最右
 *  - TOTP 环形倒计时；到期/断开置灰；HOTP 刷新按钮；触摸凭据触摸按钮（点击后等待触摸）
 *  - 码值分段显示（6 位 → 3+3、8 位 → 4+4，其他原样）
 *  - 无障碍（US1）：主体信息区合并为单一焦点，显式动态 accessibilityText 一次朗读
 *    发行方/账户/验证码/剩余秒数/状态；HOTP 刷新与触摸按钮 accessibilityLevel('yes') 穿透分组独立聚焦
 *  - 交互（US2）：移除长按复制与左滑删除手势，点击列表项主体弹出令牌操作菜单（onItemTap 回调）；
 *    复制逻辑迁移至页面层（单一来源）
 */
import { TokenListItem } from '../viewmodel/TokenStore';
import { TokenItemState } from '../model/UiState';
import { OtpType } from '../model/Credential';
import { CountdownArc } from './CountdownArc';
import { ResUtil } from '../common/ResUtil';

/** 列表项回调（struct 字段不能为 interface 类型，故用 class） */
export class TokenItemCallbacks {
  onItemTap: (name: string) => void = () => {
  };
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

        // ---- 下区：码值（整体右对齐） + 操作控件（最右，从左到右：码值→控件） ----
        Row() {
          // 左侧：空占位（推码值区贴右；触摸/HOTP 未计算等无码值形态同样保持控件贴右）
          Blank()
            .layoutWeight(1)

          // 码值：右缘对齐，紧邻操作控件左侧（触摸凭据无码值，不渲染内容）
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
                }
              } else {
                // ACTIVE / STALE / ERROR：空码以 '--' 占位，到期/错误置灰
                Text(this.item.code.length > 0 ? this.formatCode(this.item.code) : '--')
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.isDim() ? $r('app.color.text_secondary') : $r('app.color.token_accent'))
                  .letterSpacing(2)
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
            .accessibilityLevel('yes')
            .accessibilityText(ResUtil.str($r('app.string.a11y_btn_hotp_refresh')))
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
              .accessibilityLevel('yes')
              .accessibilityText(this.touchBtnText())
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
      .onClick(() => {
        // 点击列表项主体弹出令牌操作菜单（操作按钮自身 onClick 优先消费，不触发此处）
        this.callbacks.onItemTap(this.item.cred.name);
      })
      .accessibilityGroup(true)
      .accessibilityText(this.a11yText())
    }
  }

  private isDim(): boolean {
    return this.item.state === TokenItemState.STALE || this.item.state === TokenItemState.ERROR;
  }

  /** 码值分段显示（显示与朗读共用）：6 位 → 3+3、8 位 → 4+4，其他长度原样；复制仍用原始连续码值 */
  private formatCode(code: string): string {
    if (code.length === 6) {
      return code.slice(0, 3) + ' ' + code.slice(3);
    }
    if (code.length === 8) {
      return code.slice(0, 4) + ' ' + code.slice(4);
    }
    return code;
  }

  /** 触摸按钮朗读文本（与显示状态同步：等待触摸期间朗读等待文案） */
  private touchBtnText(): string {
    if (this.item.state === TokenItemState.TOUCH_PROMPTING) {
      return ResUtil.str($r('app.string.a11y_item_touch_waiting'));
    }
    return ResUtil.str($r('app.string.a11y_btn_touch'));
  }

  /**
   * 列表项合并朗读文本（US1）：
   * - TOTP ACTIVE：{label}，{account}，验证码 {code 分段}，剩余 {n} 秒
   * - TOTP STALE/ERROR：{label}，{account}，已过期/计算错误
   * - HOTP 已计算：{label}，{account}，验证码 {code 分段}；HOTP_IDLE：未生成验证码
   * - TOUCH/TOUCH_PROMPTING：{label}，{account}，需要触摸的凭据/等待触摸
   * - 发行方为空（label 即 account）时账户名不重复朗读；朗读文本独立于显示截断
   */
  private a11yText(): string {
    const sep = ResUtil.str($r('app.string.list_separator'));
    const parts: Array<string> = [];
    parts.push(this.item.cred.getLabel());
    if (this.item.cred.issuer.length > 0) {
      parts.push(this.item.cred.account);
    }
    const stateParts = this.stateA11yParts();
    for (const p of stateParts) {
      parts.push(p);
    }
    return parts.join(sep);
  }

  /** 状态段朗读文本（码值分段 + 剩余秒数/状态语义，可多段） */
  private stateA11yParts(): Array<string> {
    if (this.item.state === TokenItemState.TOUCH) {
      return [ResUtil.str($r('app.string.a11y_item_touch'))];
    }
    if (this.item.state === TokenItemState.TOUCH_PROMPTING) {
      return [ResUtil.str($r('app.string.a11y_item_touch_waiting'))];
    }
    if (this.item.cred.otpType === OtpType.HOTP) {
      if (this.item.state === TokenItemState.ACTIVE && this.item.code.length > 0) {
        return [ResUtil.strWithArgs($r('app.string.a11y_item_code'), this.formatCode(this.item.code))];
      }
      return [ResUtil.str($r('app.string.a11y_item_hotp_idle'))];
    }
    // TOTP：ACTIVE 读码值 + 剩余秒数；ERROR 读计算错误；STALE（及防御性空码）读已过期
    if (this.item.state === TokenItemState.ERROR) {
      return [ResUtil.str($r('app.string.a11y_item_error'))];
    }
    if (this.item.state === TokenItemState.ACTIVE && this.item.code.length > 0) {
      return [
        ResUtil.strWithArgs($r('app.string.a11y_item_code'), this.formatCode(this.item.code)),
        ResUtil.strWithArgs($r('app.string.a11y_item_remaining'), this.item.remainingSec)
      ];
    }
    return [ResUtil.str($r('app.string.a11y_item_expired'))];
  }
}
