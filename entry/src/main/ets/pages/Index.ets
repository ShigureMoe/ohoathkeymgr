/**
 * 主框架（M5-1/2）：顶栏 + 三页 Tabs + 全局覆盖层
 *  - 顶栏：钥匙按钮（会话密码）、连接按钮（NFC/USB 选择弹窗）
 *  - 全局覆盖层：NFC 碰卡提示、触摸等待提示、密码输入框
 *  - 连接状态订阅：握手 ConnectionManager，FAILED → Toast
 */
import { UsbDeviceLister, UsbCardDevice } from '../common/UsbCcidTransport';
import { ConnectionManager, ConnectionListener } from '../service/ConnectionManager';
import { OathSessionManager } from '../service/OathSessionManager';
import { SessionPasswordStore } from '../security/SessionPasswordStore';
import { NfcSessionRunner } from '../service/NfcSessionRunner';
import { NfcSupport } from '../service/NfcSupport';
import { ConnMode, ConnStatus, NfcAvailability, TokenItemState } from '../model/UiState';
import { TokenStore } from '../viewmodel/TokenStore';
import { AppState, UiDialogBridge } from '../viewmodel/AppState';
import { TopBar } from '../components/TopBar';
import { ConnectSheet } from '../components/ConnectSheet';
import { PasswordInputDialog } from '../components/PasswordInputDialog';
import { TokenListPage } from './TokenListPage';
import { DevicePage } from './DevicePage';
import { SettingsPage } from './SettingsPage';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State connectVisible: boolean = false;
  @State usbDevices: Array<UsbCardDevice> = [];
  @State nfcAvailability: NfcAvailability = NfcAvailability.READY;
  @State currentModeText: string = 'none';
  @State currentUsbSerial: string = '';
  @State tokenStore: TokenStore = TokenStore.getInstance();
  private connListener: ConnectionListener | undefined = undefined;
  @StorageProp('nfcPromptVisible') nfcPromptVisible: boolean = false;
  @StorageProp('touchPromptVisible') touchPromptVisible: boolean = false;

  aboutToAppear(): void {
    this.connListener = this.buildListener();
    ConnectionManager.getInstance().subscribe(this.connListener);
  }

  aboutToDisappear(): void {
    const l = this.connListener;
    if (l !== undefined) {
      ConnectionManager.getInstance().unsubscribe(l);
      this.connListener = undefined;
    }
  }

  private buildListener(): ConnectionListener {
    const l = new ConnectionListener();
    l.onStatusChanged = (mode: ConnMode, status: ConnStatus) => {
      this.currentModeText = mode === ConnMode.USB ? 'usb' : (mode === ConnMode.NFC ? 'nfc' : 'none');
      this.currentUsbSerial = status === ConnStatus.CONNECTED ? 'connected' : '';
      if (status === ConnStatus.FAILED && mode === ConnMode.USB) {
        this.toast('连接已断开，令牌列表已置灰');
      }
    };
    l.onDeviceLost = (message: string) => {
      this.toast(message);
    };
    return l;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        TopBar({
          onKeyClick: () => {
            this.configureSessionPassword();
          },
          onConnectClick: () => {
            this.openConnectSheet();
          }
        })

        Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
          TabContent() {
            TokenListPage({
              store: this.tokenStore,
              toast: (msg: string) => {
                this.toast(msg);
              }
            })
          }
          .tabBar('令牌')

          TabContent() {
            DevicePage({
              toast: (msg: string) => {
                this.toast(msg);
              }
            })
          }
          .tabBar('设备管理')

          TabContent() {
            SettingsPage({
              toast: (msg: string) => {
                this.toast(msg);
              }
            })
          }
          .tabBar('设置')
        }
        .onChange((index: number) => {
          this.currentTab = index;
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      // ---- 全局覆盖层 ----
      ConnectSheet({
        visible: this.connectVisible,
        devices: this.usbDevices,
        currentMode: this.currentModeText,
        currentUsbSerial: this.currentUsbSerial,
        nfcAvailability: this.nfcAvailability,
        onSelectNfc: () => {
          this.connectNfc();
        },
        onSelectUsb: (device: UsbCardDevice) => {
          this.connectUsb(device);
        }
      })
      PasswordInputDialog()

      if (this.nfcPromptVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column({ space: 10 }) {
            Text('请将安全卡片靠近手机 NFC 感应区')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
            Button('取消')
              .width(120)
              .height(34)
              .fontSize(13)
              .backgroundColor($r('app.color.button_neutral_bg'))
              .fontColor($r('app.color.button_neutral_fg'))
              .onClick(() => {
                NfcSessionRunner.cancel();
                AppState.setNfcPrompt(false);
              })
          }
          .padding(22)
          .borderRadius(14)
          .backgroundColor($r('app.color.surface_sheet'))
          .shadow({ radius: 16, color: '#44000000', offsetY: 3 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mask'))
      }

      if (this.touchPromptVisible) {
        Stack({ alignContent: Alignment.Center }) {
          Column({ space: 10 }) {
            Text('请触摸安全卡片以完成验证')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
            Button('取消')
              .width(120)
              .height(34)
              .fontSize(13)
              .backgroundColor($r('app.color.button_neutral_bg'))
              .fontColor($r('app.color.button_neutral_fg'))
              .onClick(() => {
                const item = TokenStore.getInstance().items.find(
                  (it) => it.state === TokenItemState.TOUCH_PROMPTING);
                if (item !== undefined) {
                  OathSessionManager.getInstance().cancelTouch(item.cred.name);
                } else {
                  AppState.setTouchPrompt(false);
                }
              })
          }
          .padding(22)
          .borderRadius(14)
          .backgroundColor($r('app.color.surface_sheet'))
          .shadow({ radius: 16, color: '#44000000', offsetY: 3 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.mask'))
      }
    }
    .width('100%')
    .height('100%')
  }

  private configureSessionPassword(): void {
    UiDialogBridge.requestPassword('会话安全密码', true,
      '留空表示无会话密码（影响下次验证）').then((value: string | null) => {
      if (value === null) {
        return;
      }
      SessionPasswordStore.set(value);
      this.toast('会话密码已设置');
    });
  }

  private openConnectSheet(): void {
    this.usbDevices = UsbDeviceLister.list();
    this.nfcAvailability = NfcSupport.check();
    const cm = ConnectionManager.getInstance();
    this.currentModeText = cm.getMode() === ConnMode.USB ? 'usb' : (cm.getMode() === ConnMode.NFC ? 'nfc' : 'none');
    this.currentUsbSerial = cm.getStatus() === ConnStatus.CONNECTED ? 'connected' : '';
    this.connectVisible = true;
  }

  private connectNfc(): void {
    this.connectVisible = false;
    ConnectionManager.getInstance().connectNfc((msg: string) => {
      this.toast(msg);
    });
  }

  private connectUsb(device: UsbCardDevice): void {
    this.connectVisible = false;
    ConnectionManager.getInstance().connectUsb(device, (msg: string) => {
      this.toast(msg);
    }).then(() => {
      this.toast('已连接 ' + device.label);
    }).catch((err: Error) => {
      this.toast(err.message);
    });
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // 忽略 Toast 异常
    }
  }
}