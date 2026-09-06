/**
 * 密码输入对话框（全局订阅 AppStorage）：
 *  - 钥匙按钮配置会话密码（allowEmpty=true，可清空）
 *  - 验证弹窗（allowEmpty=false）
 * 提交/取消通过 UiDialogBridge 回传服务层。
 */
import { UiDialogBridge } from '../viewmodel/AppState';

@Component
export struct PasswordInputDialog {
  @StorageProp('passwordDialogVisible') visible: boolean = false;
  @StorageProp('passwordDialogTitle') dialogTitle: string = '';
  @StorageProp('passwordDialogAllowEmpty') allowEmpty: boolean = false;
  @StorageProp('passwordDialogHint') dialogHint: string = '';
  @State inputValue: string = '';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.visible) {
        Column({ space: 14 }) {
          Text(this.dialogTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
          Text(this.dialogHint)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          TextInput({ placeholder: '安全密码', text: this.inputValue })
            .type(InputType.Password)
            .width('100%')
            .onChange((value: string) => {
              this.inputValue = value;
            })
          Row({ space: 40 }) {
            Button('取消')
              .width(110)
              .height(38)
              .fontSize(14)
              .backgroundColor($r('app.color.button_neutral_bg'))
              .fontColor($r('app.color.button_neutral_fg'))
              .onClick(() => {
                UiDialogBridge.cancel();
              })
            Button('确定')
              .width(110)
              .height(38)
              .fontSize(14)
              .backgroundColor($r('app.color.accent'))
              .fontColor($r('app.color.on_accent'))
              .onClick(() => {
                UiDialogBridge.submit(this.inputValue);
              })
          }
          .margin({ top: 6 })
        }
        .padding(22)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_sheet'))
        .width('84%')
        .shadow({ radius: 20, color: '#33000000', offsetY: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.visible ? $r('app.color.mask') : '#00000000')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.Transparent)
  }
}