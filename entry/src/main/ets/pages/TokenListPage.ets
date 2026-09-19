/**
 * 令牌列表页（M5-3 + accessibility-optimization）：列表 + 空态/错误态 + 浮动"+"菜单 + 手动添加弹层
 * 交互：点击列表项弹出令牌操作菜单（复制验证码/HOTP 刷新/触摸计算/删除确认）、
 * 菜单外点击关闭；复制逻辑单一来源在本页（copyCode）
 */
import { TokenListItem } from '../viewmodel/TokenStore';
import { TokenStore } from '../viewmodel/TokenStore';
import { OathSessionManager } from '../service/OathSessionManager';
import { ScanService } from '../service/ScanService';
import { UriImporter } from '../viewmodel/UriImporter';
import { OtpauthParser } from '../utils/OtpauthParser';
import { TokenListItemComp, TokenItemCallbacks } from '../components/TokenListItem';
import { TokenActionMenu } from '../components/TokenActionMenu';
import { AddFabMenu } from '../components/AddFabMenu';
import { ManualAddSheet } from '../components/ManualAddSheet';
import { AddByUriSheet } from '../components/AddByUriSheet';
import { AppState } from '../viewmodel/AppState';
import { ResUtil } from '../common/ResUtil';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';

@Component
export struct TokenListPage {
  @ObjectLink store: TokenStore;
  toast: (msg: string) => void = (msg: string) => {
  };
  @StorageProp('connMode') connMode: string = 'none';
  @State showManual: boolean = false;
  @State showUriSheet: boolean = false;
  // 令牌操作菜单状态（US2）：目标令牌名（null=关闭）+ 弹层可见标志（@Link 数据源）
  @State actionMenuName: string | null = null;
  @State actionMenuVisible: boolean = false;
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
        onUri: () => {
          this.showUriSheet = true;
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

      // 令牌操作菜单（US2）：if 条件挂载——菜单打开且目标令牌仍存在时渲染；
      // 目标令牌被删除/列表刷新后自动关闭（条件失效即销毁弹层）
      if (this.actionMenuVisible && this.findActionMenuItem() !== undefined) {
        TokenActionMenu({
          visible: this.actionMenuVisible,
          item: this.findActionMenuItem(),
          onCopy: (name: string) => {
            this.closeActionMenu();
            this.copyCode(name);
          },
          onHotpRefresh: (name: string) => {
            this.closeActionMenu();
            this.refreshHotp(name);
          },
          onTouchTap: (name: string) => {
            this.closeActionMenu();
            this.touchCalculate(name);
          },
          onDelete: (name: string) => {
            this.closeActionMenu();
            this.confirmDelete(name);
          },
          onDismiss: () => {
            this.closeActionMenu();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  private itemCallbacks(): TokenItemCallbacks {
    const cb = new TokenItemCallbacks();
    cb.onItemTap = (name: string) => {
      this.openActionMenu(name);
    };
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

  // ---------- 令牌操作菜单（US2） ----------

  /** 查找菜单目标令牌（actionMenuName 失效时返回 undefined，弹层自动关闭） */
  private findActionMenuItem(): TokenListItem | undefined {
    const name = this.actionMenuName;
    if (name === null) {
      return undefined;
    }
    return this.store.items.find((it: TokenListItem) => it.cred.name === name);
  }

  private openActionMenu(name: string): void {
    this.actionMenuName = name;
    this.actionMenuVisible = true;
  }

  private closeActionMenu(): void {
    this.actionMenuVisible = false;
    this.actionMenuName = null;
  }

  /** 复制验证码（自 TokenListItem 迁移，单一来源）：原始连续码值 → 剪贴板 + 「已复制」toast */
  private copyCode(name: string): void {
    const item = this.store.items.find((it: TokenListItem) => it.cred.name === name);
    if (item === undefined || item.code.length === 0) {
      return;
    }
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, item.code);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.toast(ResUtil.str($r('app.string.token_copied')));
    }).catch(() => {
    });
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