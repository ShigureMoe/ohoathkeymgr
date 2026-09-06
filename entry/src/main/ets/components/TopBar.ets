/**
 * 顶栏（M5-1/M5-2）：app 名 + 钥匙按钮（会话密码）+ 连接方式按钮（图标状态机）
 * 图标状态：NFC 恒 nfc.svg；
 *          USB connecting→LoadingProgress；connected→checkmark；否则/failed→link_slash
 */
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
      Text('OathKeeper')
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
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .backgroundBlurStyle(BlurStyle.Thin)
  }
}