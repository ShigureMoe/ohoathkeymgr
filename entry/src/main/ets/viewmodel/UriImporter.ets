/**
 * 凭据导入执行器（UI 侧公共逻辑）：解析结果 → 写入（重名收集）→ 需要时弹覆盖确认。
 * 扫码（ScanService）与"从链接添加"（AddByUriSheet）共用。
 */
import { promptAction } from '@kit.ArkUI';
import { ParseOutcome } from '../utils/OtpauthParser';
import { OathSessionManager } from '../service/OathSessionManager';

export class UriImporter {
  /** 解析结果写入卡片；重名凭据弹窗确认后覆盖 */
  static async importAndConfirm(ui: UIContext, outcome: ParseOutcome,
    toast: (msg: string) => void): Promise<void> {
    const result = await OathSessionManager.getInstance().addOutcome(outcome, toast);
    if (result.conflicts.length === 0) {
      if (result.added > 0) {
        toast('已添加 ' + result.added + ' 条凭据');
      } else {
        toast('未添加凭据');
      }
      return;
    }
    const message = '以下凭据已存在：' + result.conflicts.join('、') + '。是否覆盖？';
    await new Promise<void>((resolve: () => void) => {
      ui.getPromptAction().showDialog({
        title: '凭据已存在',
        message: message,
        buttons: [
          { text: '取消', color: $r('app.color.text_secondary') },
          { text: '全部覆盖', color: $r('app.color.danger') }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          OathSessionManager.getInstance().addOutcomeForce(outcome.credentials, toast).then((ok: number) => {
            toast('已添加 ' + (result.added + ok) + ' 条凭据');
            resolve();
          }).catch((err: Error) => {
            toast(err.message);
            resolve();
          });
          return;
        }
        toast(result.added > 0 ? '已添加 ' + result.added + ' 条' : '未添加凭据');
        resolve();
      }).catch(() => {
        resolve();
      });
    });
  }
}