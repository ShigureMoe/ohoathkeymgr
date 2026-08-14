/**
 * 令牌列表页（M5-3）：列表 + 空态/错误态 + 浮动"+"菜单 + 手动添加弹层
 * 交互：长按复制（item 内）、左滑删除（确认后 DELETE）、HOTP 刷新、触摸凭据计算
 */
import { TokenListItem } from '../viewmodel/TokenStore';
import { TokenStore } from '../viewmodel/TokenStore';
import { OathSessionManager } from '../service/OathSessionManager';
import { ScanService } from '../service/ScanService';
import { UriImporter } from '../viewmodel/UriImporter';
import { OtpauthParser } from '../utils/OtpauthParser';
import { TokenListItemComp, TokenItemCallbacks } from '../components/TokenListItem';
import { AddFabMenu } from '../components/AddFabMenu';
import { ManualAddSheet } from '../components/ManualAddSheet';
import { AddByUriSheet } from '../components/AddByUriSheet';
import { AppState } from '../viewmodel/AppState';
import { promptAction } from '@kit.ArkUI';

@Component
export struct TokenListPage {
  @ObjectLink store: TokenStore;
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('connMode') connMode: string = 'none';
  @State showManual: boolean = false;
  @State showUriSheet: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.store.items.length === 0) {
        Column({ space: 8 }) {
          Text(this.emptyTitle())
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          if (this.connMode === 'none') {
            Text('点击右上角选择连接方式')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.store.items, (item: TokenListItem) => {
            ListItem() {
              TokenListItemComp({
                item: item,
                callbacks: this.itemCallbacks()
              })
            }
          }, (item: TokenListItem) => item.cred.name)
        }
        .width('100%')
        .height('100%')
        .padding({ top: 8, bottom: 84 })
      }

      AddFabMenu({
        onScan: () => {
          this.scanAndImport();
        },
        onManual: () => {
          this.showManual = true;
        }
      })

      ManualAddSheet({
        visible: this.showManual,
        toast: this.toast
      })

      AddByUriSheet({
        visible: this.showUriSheet,
        toast: this.toast
      })
    }
    .width('100%')
    .height('100%')
  }

  private itemCallbacks(): TokenItemCallbacks {
    const cb = new TokenItemCallbacks();
    cb.onDelete = (name: string) => {
      this.confirmDelete(name);
    };
    cb.onHotpRefresh = (name: string) => {
      this.refreshHotp(name);
    };
    cb.onTouchTap = (name: string) => {
      this.touchCalculate(name);
    };
    return cb;
  }

  private emptyTitle(): string {
    if (this.connMode === 'nfc') {
      return '碰卡以读取令牌';
    }
    if (this.connMode === 'usb') {
      return '连接成功，暂无凭据';
    }
    return '请先选择连接方式';
  }

  private confirmDelete(name: string): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除凭据',
      message: '确定从安全卡片删除该凭据？',
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '删除', color: $r('app.color.danger') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index !== 1) {
        return;
      }
      OathSessionManager.getInstance().deleteCredential(name, this.toast).then(() => {
        this.toast('凭据已删除');
      }).catch((err: Error) => {
        this.toast(err.message);
      });
    }).catch(() => {
    });
  }

  private refreshHotp(name: string): void {
    OathSessionManager.getInstance().requestHotp(name, this.toast).catch((err: Error) => {
      this.toast(err.message);
    });
  }

  /** 扫码 → otpauth 解析 → 导入（S4） */
  private async scanAndImport(): Promise<void> {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      this.toast('未获取到应用上下文');
      return;
    }
    try {
      const raw = await ScanService.scan(hostContext);
      if (raw.length === 0) {
        this.toast('未识别到二维码内容');
        return;
      }
      const outcome = OtpauthParser.parseAny(raw);
      await UriImporter.importAndConfirm(this.getUIContext(), outcome, this.toast);
    } catch (err) {
      this.toast((err as Error).message);
    }
  }

  private touchCalculate(name: string): void {
    OathSessionManager.getInstance().requestTouch(name, this.toast).catch((err: Error) => {
      this.toast(err.message);
      AppState.setTouchPrompt(false);
    });
  }
}