/**
 * 连接方式选择弹窗（M5-2 / S1/S2）：
 *  - NFC：按可用性细分（READY 可点；SWITCH_OFF/UNSUPPORTED/HARDWARE_MISSING 说明并禁用）
 *  - USB：列出 CCID 设备（名称+VID/PID）；无设备则灰色不可选
 */
import { UsbCardDevice } from '../common/UsbCcidTransport';
import { NfcAvailability } from '../model/UiState';
import { NfcSupport } from '../service/NfcSupport';

@Component
export struct ConnectSheet {
  @Link visible: boolean;
  @Link devices: Array<UsbCardDevice>;
  @Link currentMode: string;
  @Link currentUsbSerial: string;
  @Link nfcAvailability: NfcAvailability;
  onSelectNfc: () => void = () => {
  };
  onSelectUsb: (device: UsbCardDevice) => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.visible) {
        Column({ space: 12 }) {
          Text('选择连接方式')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
          Row({ space: 24 }) {
            Column({ space: 4 }) {
              Image(this.currentMode === 'nfc'
                ? $r('app.media.nfc')
                : (this.nfcEnabled() ? $r('app.media.nfc') : $r('app.media.link_slash')))
                .width(28)
                .height(28)
                .opacity(this.nfcEnabled() ? 1 : 0.35)
              Text(NfcSupport.labelFor(this.nfcAvailability))
                .fontSize(13)
                .fontColor(this.nfcEnabled() ? $r('app.color.text_primary') : $r('app.color.text_hint'))
            }
            .justifyContent(FlexAlign.Center)
            .padding(14)
            .borderRadius(10)
            .backgroundColor(this.nfcEnabled()
              ? $r('app.color.accent_soft')
              : $r('app.color.surface_card'))
            .enabled(this.nfcSelectable())
            .onClick(() => {
              this.onSelectNfc();
            })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)

          if (!this.nfcEnabled() && this.nfcAvailability !== NfcAvailability.SWITCH_OFF) {
            Text(NfcSupport.messageFor(this.nfcAvailability))
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
          }
          if (this.nfcAvailability === NfcAvailability.SWITCH_OFF) {
            Text('开关未开启时也可选择 USB 连接，或到系统设置开启 NFC')
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
          }

          Text('USB 设备')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .alignSelf(ItemAlign.Start)
            .margin({ left: 20, top: 8 })

          if (this.devices.length === 0) {
            Text('未发现 USB 安全卡片（需含 CCID 接口）')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          } else {
            List({ space: 8 }) {
              ForEach(this.devices, (dev: UsbCardDevice) => {
                ListItem() {
                  Row() {
                    Column({ space: 2 }) {
                      Text(dev.label)
                        .fontSize(13)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    if (this.isCurrent(dev)) {
                      Text('已连接')
                        .fontSize(11)
                        .fontColor($r('app.color.accent'))
                    }
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  .backgroundColor($r('app.color.surface_card'))
                  .borderRadius(8)
                }
                .onClick(() => {
                  this.onSelectUsb(dev);
                })
              }, (dev: UsbCardDevice) => dev.device.name)
            }
            .width('100%')
            .height(160)
          }
          Button('取消')
            .width(160)
            .height(40)
            .fontSize(14)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .fontColor($r('app.color.button_neutral_fg'))
            .margin({ top: 8 })
            .onClick(() => {
              this.visible = false;
            })
        }
        .padding(20)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface_sheet'))
        .width('88%')
        .shadow({ radius: 20, color: '#33000000', offsetY: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.visible ? $r('app.color.mask') : '#00000000')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.Transparent)
  }

  private isCurrent(dev: UsbCardDevice): boolean {
    return this.currentMode === 'usb' && this.currentUsbSerial === dev.device.name;
  }

  /** NFC 是否可用（非 READY 一律置灰） */
  private nfcEnabled(): boolean {
    return this.nfcAvailability === NfcAvailability.READY;
  }

  /** 点击是否放行（SWITCH_OFF 也放行，由 connectNfc 统一提示引导） */
  private nfcSelectable(): boolean {
    return this.nfcEnabled() || this.nfcAvailability === NfcAvailability.SWITCH_OFF;
  }
}