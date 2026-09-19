/**
 * 通用令牌手动添加表单（M5-4 / S5）：
 *  Issuer / Account / Secret / 类型 / 算法 / 位数 / 周期(TOTP) / 计数器(HOTP) / 需要触摸
 * 提交时校验 Base32、触摸支持（固件 <4.2.6 禁用开关）、上限与重名确认由服务层处理。
 */
import { Base32 } from '../utils/Base32';
import { CredentialData, HashAlgorithm, OtpType } from '../model/Credential';
import { DeviceInfoStore } from '../viewmodel/DeviceInfoStore';
import { OathSessionManager } from '../service/OathSessionManager';
import { ResUtil } from '../common/ResUtil';
import { promptAction } from '@kit.ArkUI';

@Component
export struct ManualAddSheet {
  @Link visible: boolean;
  toast: (msg: string) => void = (msg: string) => {
  };
  @State issuer: string = '';
  @State account: string = '';
  @State secret: string = '';
  @State totpSelected: boolean = true;
  @State algorithmIdx: number = 0;
  @State digitsIdx: number = 0;
  @State periodIdx: number = 0;
  @State hotpCounter: string = '0';
  @State touchChecked: boolean = false;
  @State busy: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.visible) {
        Scroll() {
          Column({ space: 10 }) {
            Row() {
              Text($r('app.string.add_manual_title'))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
              Blank()
              Text($r('app.string.common_close'))
                .fontSize(13)
                .fontColor($r('app.color.text_secondary'))
                .onClick(() => {
                  this.visible = false;
                })
                .accessibilityRole(AccessibilityRoleType.BUTTON)
            }
            .width('100%')

            TextInput({ placeholder: $r('app.string.add_issuer_hint'), text: this.issuer })
              .onChange((v: string) => {
                this.issuer = v;
              })
            TextInput({ placeholder: $r('app.string.add_account_hint'), text: this.account })
              .onChange((v: string) => {
                this.account = v;
              })
            TextInput({ placeholder: $r('app.string.add_secret_hint'), text: this.secret })
              .onChange((v: string) => {
                this.secret = v;
              })

            this.labelRow($r('app.string.add_type'))
            Row({ space: 24 }) {
              Radio({ value: 'totp', group: 'type' })
                .checked(this.totpSelected)
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.totpSelected = true;
                  }
                })
              Text('TOTP')
                .fontSize(14)
              Radio({ value: 'hotp', group: 'type' })
                .checked(!this.totpSelected)
                .onChange((checked: boolean) => {
                  if (checked) {
                    this.totpSelected = false;
                  }
                })
              Text('HOTP')
                .fontSize(14)
            }
            .width('100%')

            this.labelRow($r('app.string.add_algo'))
            Row({ space: 18 }) {
              ForEach([0, 1, 2], (idx: number) => {
                Row({ space: 4 }) {
                  Radio({ value: 'alg' + idx, group: 'alg' })
                    .checked(this.algorithmIdx === idx)
                    .onChange((checked: boolean) => {
                      if (checked) {
                        this.algorithmIdx = idx;
                      }
                    })
                  Text(this.algName(idx))
                    .fontSize(13)
                }
              }, (idx: number) => 'alg' + idx)
            }
            .width('100%')

            this.labelRow($r('app.string.add_digits'))
            Row({ space: 18 }) {
              ForEach([6, 7, 8], (digits: number) => {
                Row({ space: 4 }) {
                  Radio({ value: 'd' + digits, group: 'digits' })
                    .checked(this.digitsIdx === (digits - 6))
                    .onChange((checked: boolean) => {
                      if (checked) {
                        this.digitsIdx = digits - 6;
                      }
                    })
                  Text(String(digits))
                    .fontSize(13)
                }
              }, (digits: number) => 'd' + digits)
            }
            .width('100%')

            if (this.totpSelected) {
              this.labelRow($r('app.string.add_period'))
              Row({ space: 18 }) {
                ForEach([15, 30, 60], (period: number) => {
                  Row({ space: 4 }) {
                    Radio({ value: 'p' + period, group: 'period' })
                      .checked(this.periodIdx === this.periodIndex(period))
                      .onChange((checked: boolean) => {
                        if (checked) {
                          this.periodIdx = this.periodIndex(period);
                        }
                      })
                    Text(String(period))
                      .fontSize(13)
                  }
                }, (period: number) => 'p' + period)
              }
              .width('100%')
            } else {
              this.labelRow($r('app.string.add_counter'))
              TextInput({ placeholder: $r('app.string.add_counter_hint'), text: this.hotpCounter })
                .type(InputType.Number)
                .onChange((v: string) => {
                  this.hotpCounter = v;
                })
            }

            Row() {
              Text($r('app.string.add_require_touch'))
                .fontSize(14)
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.touchChecked })
                .enabled(DeviceInfoStore.supportsTouch())
                .onChange((on: boolean) => {
                  this.touchChecked = on;
                })
            }
            .width('100%')
            if (!DeviceInfoStore.supportsTouch()) {
              Text($r('app.string.add_touch_unsupported'))
                .fontSize(11)
                .fontColor($r('app.color.warning'))
                .alignSelf(ItemAlign.Start)
            }

            Button(this.busy ? $r('app.string.add_busy') : $r('app.string.add_submit'))
              .width('100%')
              .height(44)
              .fontSize(15)
              .backgroundColor($r('app.color.accent'))
              .fontColor($r('app.color.on_accent'))
              .enabled(!this.busy)
              .margin({ top: 6 })
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
        .height(600)
        .backgroundColor('#00000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.visible ? $r('app.color.mask') : '#00000000')
    .hitTestBehavior(this.visible ? HitTestMode.Default : HitTestMode.Transparent)
  }

  @Builder
  labelRow(label: Resource) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.text_secondary'))
      .alignSelf(ItemAlign.Start)
      .width('100%')
  }

  private algName(idx: number): string {
    if (idx === 1) {
      return 'SHA256';
    }
    if (idx === 2) {
      return 'SHA512';
    }
    return 'SHA1';
  }

  private periodIndex(period: number): number {
    if (period === 15) {
      return 0;
    }
    if (period === 60) {
      return 2;
    }
    return 1;
  }

  private async submit(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (this.account.length === 0) {
      this.toast(ResUtil.str($r('app.string.add_account_required')));
      return;
    }
    const secretBytes = Base32.tryDecode(this.secret);
    if (secretBytes === null) {
      this.toast(ResUtil.str($r('app.string.add_secret_invalid')));
      return;
    }
    const cred = new CredentialData();
    cred.issuer = this.issuer.trim();
    cred.account = this.account.trim();
    cred.secret = secretBytes;
    cred.otpType = this.totpSelected ? OtpType.TOTP : OtpType.HOTP;
    cred.algorithm = this.algorithmIdx === 1 ? HashAlgorithm.SHA256
      : (this.algorithmIdx === 2 ? HashAlgorithm.SHA512 : HashAlgorithm.SHA1);
    cred.digits = [6, 7, 8][this.digitsIdx];
    if (cred.otpType === OtpType.TOTP) {
      cred.period = [15, 30, 60][this.periodIdx];
    } else {
      const c = parseInt(this.hotpCounter);
      cred.counter = Number.isNaN(c) ? 0 : Math.max(0, c);
    }
    cred.touch = this.touchChecked && DeviceInfoStore.supportsTouch();

    this.busy = true;
    try {
      const result = await OathSessionManager.getInstance().putCredential(cred, this.toast);
      if (result.alreadyExists) {
        this.getUIContext().getPromptAction().showDialog({
          title: $r('app.string.add_exists_title'),
          message: $r('app.string.add_exists_message', cred.getDisplayName()),
          buttons: [
            { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
            { text: $r('app.string.add_overwrite'), color: $r('app.color.danger') }
          ]
        }).then((res: promptAction.ShowDialogSuccessResponse) => {
          if (res.index !== 1) {
            return;
          }
          OathSessionManager.getInstance().putCredentialForce(cred, this.toast).then(() => {
            this.toast(ResUtil.str($r('app.string.add_overwritten')));
            this.visible = false;
          }).catch((err: Error) => {
            this.toast(err.message);
          });
        }).catch(() => {
        });
      } else {
        this.toast(ResUtil.str($r('app.string.add_done')));
        this.visible = false;
      }
    } catch (err) {
      this.toast((err as Error).message);
    } finally {
      this.busy = false;
    }
  }
}