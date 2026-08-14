/**
 * OATH 会话编排（REQ M4-2 验证流程 S3 / S4~S10 凭据操作入口）
 * 统一入口：所有与卡片交互的功能都经本类 withSession（内部委托 CardChannel），
 * 业务层不区分 NFC/USB——连接建立/断开由 ConnectionManager 负责并注入 channel。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OathSession } from '../protocol/OathProtocol';
import { CredentialData, CredentialInfo, OathName, OtpType } from '../model/Credential';
import { TokenItemState } from '../model/UiState';
import { AppState, UiDialogBridge } from '../viewmodel/AppState';
import { DeviceInfoStore } from '../viewmodel/DeviceInfoStore';
import { TokenStore } from '../viewmodel/TokenStore';
import { SessionPasswordStore } from '../security/SessionPasswordStore';
import { ParseOutcome } from '../utils/OtpauthParser';
import { CardChannel, NfcCardChannel } from './CardChannel';
import { tag } from '@kit.ConnectivityKit';

/** PUT 结果：重名时需要 UI 确认覆盖 */
export class PutResult {
  alreadyExists: boolean = false;
}

/** 批量导入结果（扫码/链接）：新增数与重名清单 */
export class AddOutcomeResult {
  added: number = 0;
  conflicts: Array<string> = [];
}

/** NFC 日志常量 */
export class NfcLog {
  static readonly DOMAIN = 0x0000;
  static readonly TAG = 'OathKeeper';
}

export class OathSessionManager {
  private static instance: OathSessionManager | undefined = undefined;
  private channel: CardChannel | undefined = undefined;
  private hasCardKey: boolean = false;
  private touchRequestId: number = 0;

  static getInstance(): OathSessionManager {
    if (OathSessionManager.instance === undefined) {
      OathSessionManager.instance = new OathSessionManager();
    }
    return OathSessionManager.instance;
  }

  /** 连接建立后注入当前通道（USB/NFC 通用） */
  setChannel(channel: CardChannel, hasKey: boolean): void {
    this.channel = channel;
    this.hasCardKey = hasKey;
  }

  clearChannel(): void {
    this.channel = undefined;
    this.hasCardKey = false;
  }

  getChannel(): CardChannel | undefined {
    return this.channel;
  }

  /** 卡片是否设置了安全密码（设备页展示） */
  getHasKey(): boolean {
    return this.hasCardKey;
  }

  /**
   * 统一会话执行入口：业务层对 NFC/USB 无感。
   * USB 复用长连接会话；NFC 触发碰卡会话（先验证 S3 再执行）。
   */
  async withSession<T>(work: (session: OathSession) => Promise<T>, toast: (msg: string) => void): Promise<T> {
    const ch = this.channel;
    if (ch === undefined) {
      throw new Error('请先选择连接方式');
    }
    return ch.withSession(async (session: OathSession) => {
      const ok = await this.authenticate(session, toast);
      if (!ok) {
        throw new Error('解锁失败');
      }
      return work(session);
    }, toast);
  }

  /**
   * S3 验证：手动会话密码 → 弹窗输入；失败仅 Toast
   */
  async authenticate(session: OathSession, toast: (msg: string) => void): Promise<boolean> {
    if (!session.isLocked()) {
      this.hasCardKey = session.getHasKey();
      return true;
    }
    this.hasCardKey = true;
    const manual = SessionPasswordStore.get();
    if (manual !== undefined && manual.length > 0) {
      try {
        await this.tryValidate(session, manual);
        return true;
      } catch (e) {
        toast('密码错误，解锁失败');
        return false;
      }
    }
    if (manual !== undefined && manual.length === 0) {
      toast('会话密码为空且卡片已设置密码');
      return false;
    }
    const input = await UiDialogBridge.requestPassword('输入安全密码', false,
      '卡片已设置安全密码，请输入后继续');
    if (input === null) {
      toast('已取消解锁');
      return false;
    }
    try {
      await this.tryValidate(session, input);
      SessionPasswordStore.set(input);
      return true;
    } catch (e) {
      toast('密码错误');
      return false;
    }
  }

  private async tryValidate(session: OathSession, password: string): Promise<void> {
    const key = await session.deriveKey(password);
    await session.validate(key);
  }

  /**
   * 全量刷新：LIST + CALCULATE ALL → TokenStore。
   * 触摸凭据：通道 autoCalculateTouch()=true（NFC）时自动补算，不再由业务层判断模式。
   */
  async refreshAll(session: OathSession): Promise<void> {
    const nowSec = Math.floor(Date.now() / 1000);
    const creds = await session.listCredentials();
    const entries = await session.calculateAll(nowSec);
    const ch = this.channel;
    if (ch !== undefined && ch.autoCalculateTouch()) {
      for (const entry of entries) {
        if (!entry.touch || entry.code !== null) {
          continue;
        }
        try {
          const code = await session.calculate(entry.credId, entry.otpType, entry.period, nowSec);
          entry.code = code;
        } catch (e) {
          // 计算失败：保留 touch 状态，列表显示触摸项
        }
      }
    }
    AppState.setCredentialCount(creds.length);
    TokenStore.getInstance().setFromRefresh(creds, entries);
  }

  /** 当前连接的刷新（USB 30s 自动刷新 / 通用） */
  async refreshCurrent(toast: (msg: string) => void): Promise<void> {
    await this.withSession(async (session: OathSession) => {
      await this.refreshAll(session);
    }, toast);
  }

  /** NFC 待卡监听回调（S2）：碰卡 → 会话 → 验证 → CALCULATE ALL → 展示 */
  async handleNfcIdleTap(tagInfo: tag.TagInfo, toast: (msg: string) => void): Promise<void> {
    const ch = this.channel;
    if (ch === undefined || !(ch instanceof NfcCardChannel)) {
      return;
    }
    try {
      await ch.withTagSession(tagInfo, async (session: OathSession) => {
        const ok = await this.authenticate(session, toast);
        if (!ok) {
          return;
        }
        await this.refreshAll(session);
      }, toast);
    } catch (e) {
      hilog.error(NfcLog.DOMAIN, NfcLog.TAG, 'NFC idle tap failed: %{public}s', (e as Error).message);
      toast((e as Error).message);
    }
  }

  /**
   * 添加凭据（M2-5/M3-4/M3-5）：上限检查；重名返回 alreadyExists 由 UI 确认后调用 putCredentialForce
   */
  async putCredential(cred: CredentialData, toast: (msg: string) => void): Promise<PutResult> {
    return this.withSession(async (session: OathSession) => {
      const creds = await session.listCredentials();
      const limit = DeviceInfoStore.getCredentialLimit();
      if (creds.length >= limit) {
        throw new Error('卡片凭据数量已达上限（' + limit + ' 个）');
      }
      const target = OathName.format(cred.issuer, cred.account, cred.otpType, cred.period);
      const exists = creds.some((c: CredentialInfo) => c.name === target);
      if (exists) {
        const result = new PutResult();
        result.alreadyExists = true;
        return result;
      }
      await session.putCredential(cred);
      await this.refreshAll(session);
      return new PutResult();
    }, toast);
  }

  /** 重名确认后强制写入 */
  async putCredentialForce(cred: CredentialData, toast: (msg: string) => void): Promise<void> {
    await this.withSession(async (session: OathSession) => {
      await session.putCredential(cred);
      await this.refreshAll(session);
    }, toast);
  }

  /**
   * 批量导入（扫码 S4 / 链接）：逐条 PUT，收集重名清单；
   * 失败项单独 Toast 不中断整体流程。
   */
  async addOutcome(outcome: ParseOutcome, toast: (msg: string) => void): Promise<AddOutcomeResult> {
    const result = new AddOutcomeResult();
    const creds = outcome.credentials;
    for (let i = 0; i < creds.length; i++) {
      const cred = creds[i];
      try {
        const put = await this.putCredential(cred, toast);
        if (put.alreadyExists) {
          result.conflicts.push(cred.getDisplayName());
        } else {
          result.added += 1;
        }
      } catch (e) {
        toast((e as Error).message);
      }
    }
    return result;
  }

  /** 覆盖写入指定凭据清单（含此前已新增部分；仅对冲突项强制，成功项跳过） */
  async addOutcomeForce(creds: Array<CredentialData>, toast: (msg: string) => void): Promise<number> {
    let ok = 0;
    for (const cred of creds) {
      try {
        await this.putCredentialForce(cred, toast);
        ok += 1;
      } catch (e) {
        toast((e as Error).message);
      }
    }
    return ok;
  }

  /** 删除凭据（M2-6 / S7） */
  async deleteCredential(name: string, toast: (msg: string) => void): Promise<void> {
    const cred = TokenStore.getInstance().getCredential(name);
    if (cred === undefined) {
      throw new Error('凭据不存在');
    }
    await this.withSession(async (session: OathSession) => {
      await session.deleteCredential(cred.credId);
      TokenStore.getInstance().removeByName(name);
    }, toast);
  }

  /** HOTP 刷新（M3-7 / S6）：CALCULATE 并展示码值 */
  async requestHotp(name: string, toast: (msg: string) => void): Promise<void> {
    const cred = TokenStore.getInstance().getCredential(name);
    if (cred === undefined) {
      throw new Error('凭据不存在');
    }
    await this.withSession(async (session: OathSession) => {
      const code = await session.calculate(cred.credId, OtpType.HOTP, 0, Math.floor(Date.now() / 1000));
      TokenStore.getInstance().setHotpResult(name, code);
    }, toast);
  }

  /** 触摸凭据计算（M2-10 / S13）：提示触摸卡片；取消后忽略迟到结果（USB 专用） */
  async requestTouch(name: string, toast: (msg: string) => void): Promise<void> {
    const cred = TokenStore.getInstance().getCredential(name);
    if (cred === undefined) {
      throw new Error('凭据不存在');
    }
    const requestId = ++this.touchRequestId;
    AppState.setTouchPrompt(true);
    try {
      await this.withSession(async (session: OathSession) => {
        const code = await session.calculate(cred.credId, cred.otpType, cred.period,
          Math.floor(Date.now() / 1000));
        if (requestId === this.touchRequestId) {
          TokenStore.getInstance().setTouchResult(name, code);
        }
      }, toast);
    } finally {
      AppState.setTouchPrompt(false);
    }
  }

  /** 取消触摸等待（S13 超时/取消） */
  cancelTouch(name: string): void {
    this.touchRequestId += 1;
    AppState.setTouchPrompt(false);
    const item = TokenStore.getInstance().items.find((it) => it.cred.name === name);
    if (item !== undefined) {
      item.state = TokenItemState.TOUCH;
    }
  }

  /** 修改/移除安全密码（M2-7 / S8）：当前会话已验证（S3）即可直接执行，成功后同步会话密码 */
  async modifyPassword(newPassword: string, toast: (msg: string) => void): Promise<void> {
    await this.withSession(async (session: OathSession) => {
      if (newPassword.length === 0) {
        await session.setCode(null);
        this.hasCardKey = false;
      } else {
        await session.setCode(await session.deriveKey(newPassword));
        this.hasCardKey = true;
      }
      SessionPasswordStore.set(newPassword);
      await this.refreshAll(session);
    }, toast);
  }

  /** 重置 OATH 应用（M2-8 / S10） */
  async resetCard(toast: (msg: string) => void): Promise<void> {
    await this.withSession(async (session: OathSession) => {
      await session.reset();
      this.hasCardKey = false;
      SessionPasswordStore.clear();
      TokenStore.getInstance().clear();
      AppState.setCredentialCount(0);
    }, toast);
  }
}