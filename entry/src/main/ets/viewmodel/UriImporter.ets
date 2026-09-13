/**
 * 凭据导入执行器（UI 侧公共逻辑）：解析结果 → 写入（重名收集）→ 需要时弹覆盖确认。
 * 扫码（ScanService）与"从链接添加"（AddByUriSheet）共用。
 */
import { promptAction } from '@kit.ArkUI';
import { ParseOutcome } from '../utils/OtpauthParser';
import { OathSessionManager } from '../service/OathSessionManager';
import { ResUtil } from '../common/ResUtil';

export class UriImporter {
  /** 解析结果写入卡片；重名凭据弹窗确认后覆盖 */
  static async importAndConfirm(ui: UIContext, outcome: ParseOutcome,
    toast: (msg: string) => void): Promise<void> {
    const result = await OathSessionManager.getInstance().addOutcome(outcome, toast);
    if (result.conflicts.length === 0) {
      if (result.added > 0) {
        toast(ResUtil.strWithArgs($r('app.string.import_added'), result.added));
      } else {
        toast(ResUtil.str($r('app.string.import_none')));
      }
      return;
    }
    // 重名清单 join 分隔符随语言取词条（zh '、' / en ', '）
    const message = ResUtil.strWithArgs($r('app.string.import_exists_message'),
      result.conflicts.join(ResUtil.str($r('app.string.list_separator'))));
    await new Promise<void>((resolve: () => void) => {
      ui.getPromptAction().showDialog({
        title: $r('app.string.add_exists_title'),
        message: message,
        buttons: [
          { text: $r('app.string.common_cancel'), color: $r('app.color.text_secondary') },
          { text: $r('app.string.import_overwrite_all'), color: $r('app.color.danger') }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          OathSessionManager.getInstance().addOutcomeForce(outcome.credentials, toast).then((ok: number) => {
            toast(ResUtil.strWithArgs($r('app.string.import_added'), result.added + ok));
            resolve();
          }).catch((err: Error) => {
            toast(err.message);
            resolve();
          });
          return;
        }
        toast(result.added > 0
          ? ResUtil.strWithArgs($r('app.string.import_added_short'), result.added)
          : ResUtil.str($r('app.string.import_none')));
        resolve();
      }).catch(() => {
        resolve();
      });
    });
  }
}