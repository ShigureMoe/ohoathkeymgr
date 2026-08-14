/**
 * 从链接添加凭据：粘贴 otpauth:// 或 otpauth-migration:// 链接，
 * 解析后走与扫码相同的导入管线（UriImporter）。
 */
import { OtpauthParser } from '../utils/OtpauthParser';
import { UriImporter } from '../viewmodel/UriImporter';

@Component
export struct AddByUriSheet {
  @Link visible: boolean;
  toast: (msg: string) => void = (msg: string) => {
  };
  @State uriText: string = '';
  @State busy: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.visible) {
        Scroll() {
          Column({ space: 12 }) {
            Row() {
              Text('从链接添加')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
              Blank()
              Text('关闭')
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .onClick(() => {
                  this.visible = false;
                })
            }
            .width('100%')

            Text('粘贴 otpauth:// 或 otpauth-migration:// 链接（也可使用菜单"扫描二维码"直接扫码）')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Start)
              .width('100%')

            TextArea({ placeholder: 'otpauth://totp/...', text: this.uriText })
              .height(120)
              .onChange((v: string) => {
                this.uriText = v;
              })

            Button(this.busy ? '解析中…' : '解析并添加')
              .width('100%')
              .height(44)
              .fontSize(15)
              .backgroundColor($r('app.color.accent'))
              .enabled(!this.busy)
              .onClick(() => {
                this.submit();
              })
          }
          .padding(20)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface_sheet'))
          .width('92%')
        }
        .width('100%')
        .height(560)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.visible ? $r('app.color.mask') : '#00000000')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.Transparent)
  }

  private async submit(): Promise<void> {
    if (this.busy || this.uriText.trim().length === 0) {
      this.toast('请粘贴链接');
      return;
    }
    this.busy = true;
    try {
      const outcome = OtpauthParser.parseAny(this.uriText);
      this.uriText = '';
      await UriImporter.importAndConfirm(this.getUIContext(), outcome, this.toast);
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.busy = false;
    }
  }
}