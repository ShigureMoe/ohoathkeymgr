/**
 * NFC 一次性会话执行器（M1-6 / REQ S2）：
 *  - run()：操作式会话（添加/删除/HOTP 等）——注册 readerMode → 碰卡 → work → 退订
 *  - startIdle()：NFC 模式下的"待碰卡"常驻监听——碰卡即自动执行 idleOnTap（刷新列表）
 * 互斥：同一时刻仅一个会话；操作会话会临时让出 idle 监听，结束后恢复。
 */
import { bundleManager } from '@kit.AbilityKit';
import { tag } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppContextHolder } from '../common/AppContextHolder';
import { NfcListener, NfcCardTransport } from '../common/NfcCardTransport';
import { OathSession } from '../protocol/OathProtocol';
import { AppState } from '../viewmodel/AppState';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'OathKeeper';

export class NfcSessionRunner {
  private static busy: boolean = false;
  private static pendingReject: ((reason: Error) => void) | undefined = undefined;
  private static idleOnTap: ((tagInfo: tag.TagInfo) => void) | undefined = undefined;

  static isBusy(): boolean {
    return NfcSessionRunner.busy;
  }

  /** NFC 模式是否处于待碰卡监听中 */
  static isIdleListening(): boolean {
    return NfcSessionRunner.idleOnTap !== undefined;
  }

  /** 注册"待碰卡"常驻监听：碰卡后回调 onTap（由调用方执行完整会话） */
  static startIdle(onTap: (tagInfo: tag.TagInfo) => void): void {
    if (NfcSessionRunner.busy) {
      return;
    }
    NfcSessionRunner.idleOnTap = onTap;
    if (NfcListener.isListening()) {
      return;
    }
    NfcSessionRunner.listen((tagInfo: tag.TagInfo) => {
      NfcSessionRunner.handleIdleTap(tagInfo);
    }, false);
  }

  /** 停止待碰卡监听（切换连接/断开时） */
  static stopIdle(): void {
    NfcSessionRunner.idleOnTap = undefined;
    if (!NfcSessionRunner.busy) {
      NfcListener.stop();
    }
  }

  /**
   * 执行一次操作式碰卡会话（会临时让出 idle 监听，结束后恢复）。
   * @param work 会话内操作（已 SELECT OATH 但未验证，验证由调用方负责）
   * @param preSession 可选：connect 成功后、SELECT OATH 前的前置检查（如序列号绑定校验），失败则中止
   */
  static run<T>(work: (session: OathSession) => Promise<T>, toast: (message: string) => void,
    preSession?: (transport: NfcCardTransport) => Promise<void>): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
      if (NfcSessionRunner.busy) {
        reject(new Error('正在进行其他 NFC 操作'));
        return;
      }
      const savedIdle = NfcSessionRunner.idleOnTap;
      NfcSessionRunner.stopIdle();
      NfcSessionRunner.busy = true;
      NfcSessionRunner.pendingReject = reject;
      AppState.setNfcPrompt(true);
      const started = NfcSessionRunner.listen((tagInfo: tag.TagInfo) => {
        NfcSessionRunner.handleTag(tagInfo, work, toast, resolve, reject, savedIdle, preSession);
      }, true);
      if (!started) {
        AppState.setNfcPrompt(false);
        NfcSessionRunner.busy = false;
        NfcSessionRunner.pendingReject = undefined;
        reject(new Error('NFC 监听启动失败，请确认 NFC 已开启'));
        return;
      }
    });
  }

  /** 用户取消（监听中）：退出监听并使 promise 失败；复位 busy 防止后续操作卡死 */
  static cancel(): void {
    NfcListener.stop();
    AppState.setNfcPrompt(false);
    const reject = NfcSessionRunner.pendingReject;
    NfcSessionRunner.pendingReject = undefined;
    NfcSessionRunner.busy = false;
    if (reject !== undefined) {
      reject(new Error('已取消'));
    }
  }

  // ---------- 内部 ----------

  /** 注册 readerMode；重复监听返回 false */
  private static listen(onTag: (tagInfo: tag.TagInfo) => void, consume: boolean): boolean {
    const ctx = AppContextHolder.context;
    if (ctx === undefined) {
      return false;
    }
    const info = ctx.abilityInfo;
    const elementName: bundleManager.ElementName = {
      bundleName: info.bundleName,
      abilityName: info.name,
      moduleName: info.moduleName
    };
    return NfcListener.start(elementName, onTag, consume);
  }

  /**
   * idle 碰卡：执行 idleOnTap；完成后延时重启监听——
   * 给卡片离场留时间，避免卡片仍在场时 on('readerMode') 立即重触发同一标签；
   * 同时覆盖系统 presence 机制不重复回调的场景，保证"再次碰卡"可刷新。
   */
  private static async handleIdleTap(tagInfo: tag.TagInfo): Promise<void> {
    if (NfcSessionRunner.busy) {
      return;
    }
    NfcSessionRunner.busy = true;
    hilog.info(LOG_DOMAIN, LOG_TAG, 'NFC idle tap detected');
    const onTap = NfcSessionRunner.idleOnTap;
    try {
      if (onTap !== undefined) {
        await onTap(tagInfo);
      }
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'NFC idle tap error: %{public}s', (e as Error).message);
    } finally {
      NfcSessionRunner.busy = false;
      // 延时重启监听：卡片若仍在场，此处不会立即触发；用户移卡后再放上会重新发现
      setTimeout(() => {
        const cb = NfcSessionRunner.idleOnTap;
        if (cb !== undefined && !NfcSessionRunner.busy) {
          NfcListener.stop();
          NfcSessionRunner.listen((info: tag.TagInfo) => {
            NfcSessionRunner.handleIdleTap(info);
          }, false);
        }
      }, 1000);
    }
  }

  private static async handleTag<T>(tagInfo: tag.TagInfo, work: (session: OathSession) => Promise<T>,
    toast: (message: string) => void, resolve: (value: T) => void, reject: (reason: Error) => void,
    savedIdle: ((tagInfo: tag.TagInfo) => void) | undefined,
    preSession: ((transport: NfcCardTransport) => Promise<void>) | undefined): Promise<void> {
    const transport: NfcCardTransport | undefined = new NfcCardTransport(tagInfo);
    try {
      await transport.connect();
      if (preSession !== undefined) {
        await preSession(transport);
      }
      const session = await OathSession.open(transport);
      const result = await work(session);
      resolve(result);
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'NFC op session failed: %{public}s', (e as Error).message);
      reject(e as Error);
    } finally {
      if (transport !== undefined) {
        try {
          await transport.close();
        } catch (e) {
          // 忽略关闭异常
        }
      }
      // 整个 APDU 流程结束才退出读卡器模式
      NfcListener.stop();
      AppState.setNfcPrompt(false);
      NfcSessionRunner.busy = false;
      NfcSessionRunner.pendingReject = undefined;
      // 恢复此前让出的待卡监听（若仍处于 NFC 模式）
      if (savedIdle !== undefined && AppStorage.get<string>(AppState.KEY_MODE) === 'nfc') {
        NfcSessionRunner.startIdle(savedIdle);
      }
    }
  }
}