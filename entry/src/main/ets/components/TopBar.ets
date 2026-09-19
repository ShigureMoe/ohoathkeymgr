/**
 * 顶栏（M5-1/M5-2）：app 名 + 钥匙按钮（会话密码）+ 连接方式按钮（图标状态机）
 * 图标状态：NFC 恒 nfc.svg；
 *          USB connecting→LoadingProgress；connected→checkmark；否则/failed→link_slash
 * 无障碍（US3）：钥匙/连接按钮 accessibilityText（连接按钮按 mode/status 动态朗读状态）
 */
import { ResUtil } from '../common/ResUtil';

@Component
export struct TopBar {
  onKeyClick: () => void = () => {
  };
  onConnectClick: () => void = () => {
  };
  @StorageLink('connMode') mode: string = 'none';
  @StorageLink('connStatus') status: string = 'disconnected';

  build() {
    Row() {
      Text($r('app.string.app_name'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 16 })
      Blank()
      Button() {
        Image($r('app.media.key_horizontal'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.text_primary'))
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.button_neutral_bg'))
      .margin({ right: 8 })
      .onClick(() => {
        this.onKeyClick();
      })
      .accessibilityText(ResUtil.str($r('app.string.a11y_topbar_key')))
      Button() {
        if (this.mode === 'nfc') {
          Image($r('app.media.nfc'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
        } else if (this.status === 'connecting') {
          LoadingProgress()
            .width(22)
            .height(22)
            .color($r('app.color.text_primary'))
        } else if (this.status === 'connected') {
          Image($r('app.media.checkmark_square_fill'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
        } else {
          Image($r('app.media.link_slash'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_primary'))
        }
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.button_neutral_bg'))
      .margin({ right: 16 })
      .onClick(() => {
        this.onConnectClick();
      })
      .accessibilityText(ResUtil.str(this.connectA11yRes()))
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .backgroundBlurStyle(BlurStyle.Thin)
  }

  /** 连接按钮朗读文本（与图标状态机一致）：未连接=选择连接方式；NFC=已连接；USB 按连接状态；其余=已断开 */
  private connectA11yRes(): Resource {
    if (this.mode === 'nfc') {
      return $r('app.string.a11y_topbar_connect_nfc');
    }
    if (this.mode === 'usb') {
      if (this.status === 'connecting') {
        return $r('app.string.a11y_topbar_connect_usb_connecting');
      }
      if (this.status === 'connected') {
        return $r('app.string.a11y_topbar_connect_usb_connected');
      }
      return $r('app.string.a11y_topbar_connect_disconnected');
    }
    return $r('app.string.a11y_topbar_connect_none');
  }
}