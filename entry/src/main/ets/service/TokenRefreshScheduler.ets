/**
 * 令牌刷新调度（M3-6 / REQ S1/S2）：每秒 tick 更新倒计时；
 * 30s 时间槽变化且 USB 连接时自动 CALCULATE ALL 刷新。
 */
import { TokenStore } from '../viewmodel/TokenStore';
import { AppState } from '../viewmodel/AppState';
import { OathSessionManager } from './OathSessionManager';

export class TokenRefreshScheduler {
  private static instance: TokenRefreshScheduler | undefined = undefined;
  private timerId: number = -1;
  private lastSlot: number = -1;
  private running: boolean = false;
  private static lostHandler: ((msg: string) => void) | undefined = undefined;

  static getInstance(): TokenRefreshScheduler {
    if (TokenRefreshScheduler.instance === undefined) {
      TokenRefreshScheduler.instance = new TokenRefreshScheduler();
    }
    return TokenRefreshScheduler.instance;
  }

  /** 周期性刷新失败（USB 失联）回调，由 ConnectionManager 注入 */
  static setLostHandler(handler: (msg: string) => void): void {
    TokenRefreshScheduler.lostHandler = handler;
  }

  /** 启动每秒 tick（幂等）；USB 连接切换时由 ConnectionManager 控制 */
  start(): void {
    if (this.running) {
      return;
    }
    this.running = true;
    const self = this;
    this.timerId = setInterval(() => {
      self.tick();
    }, 1000);
    this.tick();
  }

  stop(): void {
    if (this.running) {
      clearInterval(this.timerId);
      this.running = false;
    }
  }

  private tick(): void {
    const nowMs = Date.now();
    TokenStore.getInstance().tick();
    const slot = Math.floor(nowMs / 30000);
    if (this.lastSlot < 0) {
      this.lastSlot = slot;
      return;
    }
    if (slot === this.lastSlot) {
      return;
    }
    this.lastSlot = slot;
    const mode = AppStorage.get<string>(AppState.KEY_MODE);
    const status = AppStorage.get<string>(AppState.KEY_STATUS);
    if (mode === 'usb' && status === 'connected') {
      OathSessionManager.getInstance().refreshCurrent((msg: string) => {
      }).catch(() => {
        const handler = TokenRefreshScheduler.lostHandler;
        if (handler !== undefined && AppStorage.get<string>(AppState.KEY_STATUS) === 'connected') {
          handler('读取令牌失败，卡片可能已断开');
        }
      });
    }
  }
}