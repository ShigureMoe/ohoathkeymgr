/**
 * 已保存的会话密码管理页（session-password-persist v2 US3）：
 *  - Navigation 子页面（NavDestination），经 Index.pageMap 按路由名 'savedPasswords' 挂载
 *  - 列表仅展示已登记卡片的序列号（listSerials 仅查询 Asset 属性，机制上不触碰密码明文）
 *  - v2 布局修复：根 Stack alignContent=Top（水平居中 + 顶部对齐），92% 宽列表不再贴左（FR-015）
 *  - v2 手动添加：列表末尾"添加密码"入口行 + 居中添加弹窗——序列号数字键盘输入（有连接时
 *    自动带入当前卡序列号可改/无连接手输）、密码与确认密码二次一致校验、序列号已存在提示
 *    不覆盖（FR-004，plan.md D9）；条目仅经此入口手动创建
 *  - 删除需居中二次确认（复用遮罩+卡片+取消/危险色确认范式）；仅支持删除与添加，
 *    不提供任何修改途径（FR-003）；无条目时空状态提示并引导手动添加（FR-012）
 */
import { SavedPasswordStore } from '../security/SavedPasswordStore';
import { AppState } from '../viewmodel/AppState';
import { ResUtil } from '../common/ResUtil';

@Component
export struct SavedPasswordPage {
  @State serials: Array<number> = [];
  @State confirmVisible: boolean = false;
  @State pendingSerial: number = -1;
  @State removeBusy: boolean = false;
  // 添加弹窗自持状态（v2）：三输入 + 提交中 busy 防重复点击
  @State addVisible: boolean = false;
  @State serialInput: string = '';
  @State passwordInput: string = '';
  @State confirmInput: string = '';
  @State addBusy: boolean = false;

  aboutToAppear(): void {
    this.reload();
  }

  build() {
    NavDestination() {
      // Top：水平居中 + 顶部对齐（v1 为 TopStart 导致 92% 列表贴左，plan.md D10 修复）
      Stack({ alignContent: Alignment.Top }) {
        if (this.serials.length === 0) {
          this.emptyState()
        } else {
          List({ space: 10 }) {
            ForEach(this.serials, (serial: number) => {
              ListItem() {
                Row() {
                  Text(serial.toString())
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  Button($r('app.string.common_delete'))
                    .height(30)
                    .fontSize(12)
                    .padding({ left: 14, right: 14 })
                    .backgroundColor($r('app.color.danger'))
                    .enabled(!this.removeBusy)
                    .onClick(() => {
                      this.pendingSerial = serial;
                      this.confirmVisible = true;
                    })
                }
                .width('100%')
                .padding(16)
                .backgroundColor($r('app.color.surface_card'))
                .borderRadius(10)
              }
            }, (serial: number) => 'serial-' + serial)
            ListItem() {
              this.addEntryRow()
            }
          }
          .width('92%')
          .margin({ top: 12 })
        }

        if (this.confirmVisible) {
          this.confirmDialog()
        }
        if (this.addVisible) {
          this.addDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .title($r('app.string.saved_pwd_title'))
  }

  /** 空状态（v2）：文字提示引导手动添加，下方直接提供添加入口行（保证可添加第一条） */
  @Builder
  emptyState() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Text($r('app.string.saved_pwd_empty'))
          .fontSize(15)
          .fontColor($r('app.color.text_hint'))
        Text($r('app.string.saved_pwd_empty_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_hint'))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 32 })

      this.addEntryRow()
    }
    .width('92%')
    .margin({ top: 12 })
  }

  /** "添加密码"入口行：与条目行同风格 surface_card 卡片，列表末尾与空状态共用（FR-004） */
  @Builder
  addEntryRow() {
    Row() {
      Text($r('app.string.saved_pwd_add'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding(16)
    .backgroundColor($r('app.color.surface_card'))
    .borderRadius(10)
    .onClick(() => {
      this.openAddDialog();
    })
  }

  @Builder
  confirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Text($r('app.string.saved_pwd_delete_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Text($r('app.string.saved_pwd_delete_message', this.pendingSerial))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Row({ space: 40 }) {
          Button($r('app.string.common_cancel'))
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .fontColor($r('app.color.button_neutral_fg'))
            .enabled(!this.removeBusy)
            .onClick(() => {
              this.confirmVisible = false;
            })
          Button(this.removeBusy ? $r('app.string.saved_pwd_delete_busy') : $r('app.string.saved_pwd_delete_confirm'))
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.danger'))
            .enabled(!this.removeBusy)
            .onClick(() => {
              this.confirmRemove();
            })
        }
      }
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_sheet'))
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.mask'))
  }

  /** 添加弹窗（v2）：复用确认弹窗的遮罩+卡片+取消/确认范式；输入状态由本页自持（D9） */
  @Builder
  addDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        Text($r('app.string.saved_pwd_add_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
        Text($r('app.string.saved_pwd_add_hint'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        TextInput({ placeholder: $r('app.string.saved_pwd_serial'), text: this.serialInput })
          .type(InputType.Number)
          .width('100%')
          .onChange((value: string) => {
            this.serialInput = value;
          })
        TextInput({ placeholder: $r('app.string.saved_pwd_password'), text: this.passwordInput })
          .type(InputType.Password)
          .width('100%')
          .onChange((value: string) => {
            this.passwordInput = value;
          })
        TextInput({ placeholder: $r('app.string.saved_pwd_confirm'), text: this.confirmInput })
          .type(InputType.Password)
          .width('100%')
          .onChange((value: string) => {
            this.confirmInput = value;
          })
        Row({ space: 40 }) {
          Button($r('app.string.common_cancel'))
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.button_neutral_bg'))
            .fontColor($r('app.color.button_neutral_fg'))
            .enabled(!this.addBusy)
            .onClick(() => {
              this.addVisible = false;
            })
          Button(this.addBusy ? $r('app.string.saved_pwd_add_busy') : $r('app.string.saved_pwd_add_confirm'))
            .width(110)
            .height(38)
            .fontSize(14)
            .backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent'))
            .enabled(!this.addBusy)
            .onClick(() => {
              this.confirmAdd();
            })
        }
        .margin({ top: 6 })
      }
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface_sheet'))
      .width('86%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.mask'))
  }

  /** 打开添加弹窗：有连接（boundSerial≥0）预填当前卡序列号（可修改清空），无连接留空手输 */
  private openAddDialog(): void {
    const bound = AppState.getBoundSerial();
    this.serialInput = bound >= 0 ? bound.toString() : '';
    this.passwordInput = '';
    this.confirmInput = '';
    this.addVisible = true;
  }

  /**
   * 确认添加：先校验后写入（FR-004）——序列号非空且解析为 ≥0 整数、密码非空、
   * 两次输入完全一致；任一失败仅 toast 不提交。写入成功关闭弹窗并刷新列表；
   * 返回 false（序列号已存在）弹窗保留供修改后重试；addBusy 防重复提交。
   */
  private async confirmAdd(): Promise<void> {
    if (this.addBusy) {
      return;
    }
    const serialText = this.serialInput.trim();
    const serial = Number(serialText);
    if (serialText.length === 0 || !Number.isInteger(serial) || serial < 0) {
      this.toast(ResUtil.str($r('app.string.saved_pwd_serial_invalid')));
      return;
    }
    if (this.passwordInput.length === 0) {
      this.toast(ResUtil.str($r('app.string.saved_pwd_password_required')));
      return;
    }
    if (this.passwordInput !== this.confirmInput) {
      this.toast(ResUtil.str($r('app.string.saved_pwd_mismatch')));
      return;
    }
    this.addBusy = true;
    try {
      const ok = await SavedPasswordStore.add(serial, this.passwordInput);
      if (!ok) {
        // 序列号已存在：提示且不覆盖（需先删除再添加），弹窗不关闭
        this.toast(ResUtil.str($r('app.string.saved_pwd_exists')));
        return;
      }
      this.addVisible = false;
      this.toast(ResUtil.str($r('app.string.saved_pwd_added')));
      this.reload();
    } finally {
      this.addBusy = false;
    }
  }

  private reload(): void {
    SavedPasswordStore.listSerials().then((list: Array<number>) => {
      this.serials = list;
    });
  }

  private async confirmRemove(): Promise<void> {
    if (this.removeBusy) {
      return;
    }
    this.removeBusy = true;
    try {
      await SavedPasswordStore.remove(this.pendingSerial);
      this.confirmVisible = false;
      this.toast(ResUtil.str($r('app.string.saved_pwd_deleted')));
      this.reload();
    } finally {
      this.removeBusy = false;
    }
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (e) {
      // 忽略 Toast 异常
    }
  }
}
