/**
 * 设备管理页（M5-5 / S8）：
 *  上半部分设备信息（对标 ykman info + oath info），下半部分修改密码入口。
 */
import { CardInfoResult } from '../model/DeviceInfoModel';
import { OathSessionManager } from '../service/OathSessionManager';
import { AppState } from '../viewmodel/AppState';
import { ResUtil } from '../common/ResUtil';

@Component
export struct DevicePage {
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('deviceInfo') deviceInfo: CardInfoResult | undefined = undefined;
  @StorageProp('credentialCount') credentialCount: number = 0;
  @StorageProp('connMode') connMode: string = 'none';
  @State showChangePass: boolean = false;
  @State newPwd: string = '';
  @State confirmPwd: string = '';
  @State busy: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: 14 }) {
          Text($r('app.string.device_info_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .alignSelf(ItemAlign.Start)
            .margin({ left: 20 })

          if (this.deviceInfo === undefined) {
            Text($r('app.string.device_not_connected'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .alignSelf(ItemAlign.Start)
              .margin({ left: 20, top: 12 })
          } else {
            Column({ space: 10 }) {
              this.infoRow($r('app.string.device_type'), this.deviceInfo.ykmanInfo.deviceType)
              this.infoRow($r('app.string.device_serial'), this.serialText())
              this.infoRow($r('app.string.device_firmware'), this.deviceInfo.ykmanInfo.firmwareVersion)
              this.infoRow($r('app.string.device_oath_version'), this.deviceInfo.oathInfo.oathVersion)
              this.infoRow($r('app.string.device_password_protection'), this.pwdProtectionText())
              this.infoRow($r('app.string.device_account_count'), String(this.credentialCount))
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 4 })
          }

          Row() {
            Text($r('app.string.device_change_password'))
              .fontSize(15)
              .fontColor($r('app.color.accent'))
            Blank()
            Text('>')
              .fontSize(15)
              .fontColor($r('app.color.text_hint'))
          }
          .width('92%')
          .padding(16)
          .backgroundColor($r('app.color.surface_card'))
          .borderRadius(10)
          .margin({ top: 20 })
          .onClick(() => {
            this.showChangePass = !this.showChangePass;
          })
          .accessibilityGroup(true)
          .accessibilityText(ResUtil.str($r('app.string.device_change_password')))

          if (this.showChangePass) {
            Column({ space: 10 }) {
              Text(this.changePassHintRes())
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              TextInput({ placeholder: $r('app.string.device_new_password_hint'), text: this.newPwd })
                .type(InputType.Password)
                .onChange((v: string) => {
                  this.newPwd = v;
                })
              TextInput({ placeholder: $r('app.string.device_confirm_password'), text: this.confirmPwd })
                .type(InputType.Password)
                .onChange((v: string) => {
                  this.confirmPwd = v;
                })
              Button(this.busy ? $r('app.string.device_busy') : $r('app.string.device_submit'))
                .width('100%')
                .height(40)
                .fontSize(14)
                .backgroundColor($r('app.color.accent'))
                .fontColor($r('app.color.on_accent'))
                .enabled(!this.busy)
                .onClick(() => {
                  this.submitChange();
                })
            }
            .width('92%')
            .padding(14)
            .backgroundColor($r('app.color.surface_card'))
            .borderRadius(10)
          }
        }
        .width('100%')
        .padding({ top: 72, bottom: 156 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Start)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  infoRow(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
  }

  private serialText(): string {
    const info = this.deviceInfo;
    if (info === undefined) {
      return '-';
    }
    const serial = info.ykmanInfo.serialNumber;
    if (serial === null) {
      return ResUtil.str($r('app.string.device_serial_unknown'));
    }
    return String(serial);
  }

  private pwdProtectionText(): string {
    const info = this.deviceInfo;
    if (info === undefined) {
      return '-';
    }
    // 判据 'enabled' 为卡片数据串（逻辑字面量不动），仅展示层映射为资源文案
    return info.oathInfo.passwordProtection === 'enabled'
      ? ResUtil.str($r('app.string.device_protection_enabled'))
      : ResUtil.str($r('app.string.device_protection_disabled'));
  }

  /** 修改密码提示：卡片已设密码（会话已解锁即可直接修改）；无密码则直接设置 */
  private changePassHintRes(): Resource {
    if (OathSessionManager.getInstance().getHasKey()) {
      return $r('app.string.device_hint_change');
    }
    return $r('app.string.device_hint_clear');
  }

  private async submitChange(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.newPwd !== this.confirmPwd) {
      this.toast(ResUtil.str($r('app.string.device_password_mismatch')));
      return;
    }
    this.busy = true;
    try {
      await OathSessionManager.getInstance().modifyPassword(this.newPwd, this.toast);
      this.newPwd = '';
      this.confirmPwd = '';
      this.toast(ResUtil.str($r('app.string.device_password_updated')));
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.busy = false;
    }
  }
}