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
import { ResUtil } from '../common/ResUtil';
import { promptAction } from '@kit.ArkUI';

@Component
export struct TokenListPage {
  @ObjectLink store: TokenStore;
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('connMode') connMode: string = 'none';
  @State showManual: boolean = false;
  @State showUriSheet: boolean = false;
  /** 删除执行中标志（Promise 未决期间忽略新的删除触发，UI 不需响应，故非 @State） */
  private deleteBusy: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.store.items.length === 0) {
        Column({ space: 8 }) {
          Text(this.emptyTitleRes())
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
          if (this.connMode === 'none') {
            Text($r('app.string.token_empty_hint'))
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
            TokenListItemComp({
              item: item,
              callbacks: this.itemCallbacks()
            })
          }, (item: TokenListItem) => item.cred.name)
        }
        .width('100%')
        .height('100%')
        .contentStartOffset(72)
        .contentEndOffset(156)
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

  private emptyTitleRes(): Resource {
    if (this.connMode === 'nfc') {
      return $r('app.string.token_empty_nfc');
    }
    if (this.connMode === 'usb') {
      return $r('app.string.token_empty_usb');
    }
    return $r('app.string.token_empty_no_conn');
  }

  private confirmDelete(name: string): void {
    if (this.deleteBusy) {
      return;
    }
    if (this.connMode === 'usb') {
      this.getUIContext().getPromptAction().showDialog({
        title: $r('app.string.token_delete_title'),
        message: $r('app.string.token_delete_message', name),
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.common_delete'), color: $r('app.color.danger') }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index !== 1) {
          return;
        }
        this.executeDelete(name);
      }).catch(() => {
      });
    } else {
      // NFC（及其他模式）：删除需二次碰卡即物理确认，跳过弹窗直接执行
      this.executeDelete(name);
    }
  }

  /** 执行删除：busy 置位 → 发删除命令 → 成功/失败 toast → 复位 busy */
  private executeDelete(name: string): void {
    this.deleteBusy = true;
    OathSessionManager.getInstance().deleteCredential(name, this.toast).then(() => {
      this.toast(ResUtil.str($r('app.string.token_deleted')));
    }).catch((err: Error) => {
      this.toast(err.message);
    }).finally(() => {
      this.deleteBusy = false;
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
      this.toast(ResUtil.str($r('app.string.import_no_context')));
      return;
    }
    try {
      const raw = await ScanService.scan(hostContext);
      if (raw.length === 0) {
        this.toast(ResUtil.str($r('app.string.import_scan_empty')));
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