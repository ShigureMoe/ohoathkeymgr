/**
 * 设备管理页（M5-5 / S8）：
 *  上半部分设备信息（对标 ykman info + oath info），下半部分修改密码入口。
 */
import { CardInfoResult } from '../model/DeviceInfoModel';
import { OathSessionManager } from '../service/OathSessionManager';
import { AppState } from '../viewmodel/AppState';

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
      Column({ space: 14 }) {
        Text('设备信息')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .alignSelf(ItemAlign.Start)
          .margin({ top: 72, left: 20 })

        if (this.deviceInfo === undefined) {
          Text('请先连接安全卡片')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .alignSelf(ItemAlign.Start)
            .margin({ left: 20, top: 12 })
        } else {
          Column({ space: 10 }) {
            this.infoRow('设备类型', this.deviceInfo.ykmanInfo.deviceType)
            this.infoRow('序列号', this.serialText())
            this.infoRow('固件版本', this.deviceInfo.ykmanInfo.firmwareVersion)
            this.infoRow('OATH 版本', this.deviceInfo.oathInfo.oathVersion)
            this.infoRow('密码保护', this.pwdProtectionText())
            this.infoRow('凭据数量', String(this.credentialCount))
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4 })
        }

        Row() {
          Text('修改安全密码')
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

        if (this.showChangePass) {
          Column({ space: 10 }) {
            Text(this.changePassHint())
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            TextInput({ placeholder: '新密码（留空并确认 = 移除密码）', text: this.newPwd })
              .type(InputType.Password)
              .onChange((v: string) => {
                this.newPwd = v;
              })
            TextInput({ placeholder: '确认新密码', text: this.confirmPwd })
              .type(InputType.Password)
              .onChange((v: string) => {
                this.confirmPwd = v;
              })
            Button(this.busy ? '提交中…' : '提交')
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
        Blank()
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  infoRow(label: string, value: string) {
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
      return '不可读';
    }
    return String(serial);
  }

  private pwdProtectionText(): string {
    const info = this.deviceInfo;
    if (info === undefined) {
      return '-';
    }
    return info.oathInfo.passwordProtection === 'enabled' ? '已设置' : '未设置';
  }

  /** 修改密码提示：卡片已设密码（会话已解锁即可直接修改）；无密码则直接设置 */
  private changePassHint(): string {
    if (OathSessionManager.getInstance().getHasKey()) {
      return '卡片已设置安全密码，当前会话已验证，可直接修改';
    }
    return '留空并确认即移除密码；设置后生效于当前卡片';
  }

  private async submitChange(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.newPwd !== this.confirmPwd) {
      this.toast('两次输入的新密码不一致');
      return;
    }
    this.busy = true;
    try {
      await OathSessionManager.getInstance().modifyPassword(this.newPwd, this.toast);
      this.newPwd = '';
      this.confirmPwd = '';
      this.toast('安全密码已更新');
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.busy = false;
    }
  }
}