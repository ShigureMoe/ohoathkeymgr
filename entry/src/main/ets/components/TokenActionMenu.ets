/**
 * 令牌操作菜单（accessibility-optimization US2）：
 *  - 页面内自绘弹层（全屏遮罩 + 居中卡片 + 垂直选项列表），与 ConnectSheet/语言选项弹卡同范式
 *    （无 Menu 子窗口，弹层内控件可被屏幕朗读正常聚焦与激活）
 *  - 选项集合随目标令牌类型/状态动态构造：复制验证码（空码置灰）、获取新验证码（仅 HOTP）、
 *    触摸计算（仅触摸凭据，TOUCH_PROMPTING 置灰）、删除（危险色）
 *  - 无障碍：选项行独立聚焦（accessibilityLevel('yes')）+ 可用性语义；卡片 accessibilityDefaultFocus
 *    引导屏幕朗读首焦点进入；遮罩不抢焦点（accessibilityLevel('no')）
 */
import { TokenListItem } from '../viewmodel/TokenStore';
import { TokenItemState } from '../model/UiState';
import { OtpType } from '../model/Credential';
import { ResUtil } from '../common/ResUtil';

/** 菜单选项实体（label 为资源；actionName 标识执行哪类回调） */
export class TokenActionOption {
  label: Resource;
  danger: boolean;
  enabled: boolean;
  actionName: string;

  constructor(label: Resource, danger: boolean, enabled: boolean, actionName: string) {
    this.label = label;
    this.danger = danger;
    this.enabled = enabled;
    this.actionName = actionName;
  }
}

@Component
export struct TokenActionMenu {
  @Link visible: boolean;
  /** 目标令牌（undefined 时整体不渲染内容且不拦截点击） */
  item: TokenListItem | undefined = undefined;
  onCopy: (name: string) => void = () => {
  };
  onHotpRefresh: (name: string) => void = () => {
  };
  onTouchTap: (name: string) => void = () => {
  };
  onDelete: (name: string) => void = () => {
  };
  onDismiss: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.visible && this.item !== undefined) {
        Column({ space: 4 }) {
          Text($r('app.string.menu_token_actions_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .alignSelf(ItemAlign.Start)
            .margin({ left: 4, bottom: 4 })

          ForEach(this.buildOptions(), (opt: TokenActionOption) => {
            Row() {
              Text(opt.label)
                .fontSize(15)
                .fontColor(this.optionColor(opt))
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
            .padding({ left: 14, right: 14, top: 13, bottom: 13 })
            .borderRadius(10)
            .backgroundColor(opt.enabled ? $r('app.color.surface_card') : Color.Transparent)
            .enabled(opt.enabled)
            .onClick(() => {
              this.onOption(opt);
            })
            .accessibilityLevel('yes')
            .accessibilityText(this.optionA11yText(opt))
            .accessibilityRole(AccessibilityRoleType.BUTTON)
          }, (opt: TokenActionOption) => opt.actionName)
        }
        .padding(20)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_sheet'))
        .width('82%')
        .shadow({ radius: 20, color: '#33000000', offsetY: 4 })
        .accessibilityDefaultFocus(true)
        .onClick(() => {
          // 空回调拦截卡片区域点击（onClick 为非冒泡系统手势、子组件优先识别），
          // 避免点卡片内容误触遮罩导致关闭
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.visible && this.item !== undefined ? $r('app.color.mask') : '#00000000')
    .hitTestBehavior(this.visible && this.item !== undefined ? HitTestMode.Default : HitTestMode.Transparent)
    .accessibilityLevel('no')
    .onClick(() => {
      this.visible = false;
      this.onDismiss();
    })
  }

  /** 按目标令牌类型/状态构造选项集合 */
  private buildOptions(): Array<TokenActionOption> {
    const item = this.item;
    const opts: Array<TokenActionOption> = [];
    if (item === undefined) {
      return opts;
    }
    // 复制验证码：全部令牌；空码（未计算/触摸未算）置灰不执行空复制
    opts.push(new TokenActionOption($r('app.string.menu_copy_code'), false, item.code.length > 0, 'copy'));
    // 获取新验证码：仅 HOTP
    if (item.cred.otpType === OtpType.HOTP) {
      opts.push(new TokenActionOption($r('app.string.menu_request_new_code'), false, true, 'hotp'));
    }
    // 触摸计算：触摸凭据（cred.touch 在 LIST 阶段可能未知，触摸态兜底）；等待触摸期间置灰
    if (item.cred.touch || item.state === TokenItemState.TOUCH || item.state === TokenItemState.TOUCH_PROMPTING) {
      opts.push(new TokenActionOption($r('app.string.menu_touch_calc'), false,
        item.state !== TokenItemState.TOUCH_PROMPTING, 'touch'));
    }
    // 删除：全部令牌（危险色）
    opts.push(new TokenActionOption($r('app.string.menu_delete_token'), true, true, 'delete'));
    return opts;
  }

  private onOption(opt: TokenActionOption): void {
    const item = this.item;
    if (item === undefined || !opt.enabled) {
      return;
    }
    this.visible = false;
    if (opt.actionName === 'copy') {
      this.onCopy(item.cred.name);
    } else if (opt.actionName === 'hotp') {
      this.onHotpRefresh(item.cred.name);
    } else if (opt.actionName === 'touch') {
      this.onTouchTap(item.cred.name);
    } else if (opt.actionName === 'delete') {
      this.onDelete(item.cred.name);
    }
  }

  private optionColor(opt: TokenActionOption): ResourceColor {
    if (!opt.enabled) {
      return $r('app.color.text_hint');
    }
    if (opt.danger) {
      return $r('app.color.danger');
    }
    return $r('app.color.text_primary');
  }

  /** 选项朗读文本：可用性语义并入（置灰选项后缀「当前不可用」） */
  private optionA11yText(opt: TokenActionOption): string {
    const label = ResUtil.str(opt.label);
    if (!opt.enabled) {
      return ResUtil.strWithArgs($r('app.string.a11y_settings_row'), label,
        ResUtil.str($r('app.string.a11y_disabled')));
    }
    return label;
  }
}
