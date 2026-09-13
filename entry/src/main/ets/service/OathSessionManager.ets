/**
 * OATH 会话编排（REQ M4-2 验证流程 S3 / S4~S10 凭据操作入口）
 * 统一入口：所有与卡片交互的功能都经本类 withSession（内部委托 CardChannel），
 * 业务层不区分 NFC/USB——连接建立/断开由 ConnectionManager 负责并注入 channel。
 * 会话密码持久化（session-password-persist v2）：authenticate 按"当前配置非空密码 >
 * 已保存密码（按序列号） > 弹窗输入"优先级验证；条目仅由用户在管理页手动添加，
 * 验证成功路径仅做变动同步（sync：条目已存在且密码不同才覆盖，未登记不创建）；
 * 已保存密码失效不删条目，直接回落弹窗（新密码成功后由 sync 自愈）；
 * 修改密码联动 sync（改为空密码删条目）；重置卡片联动删除条目。
 */
import { OathSession } from '../protocol/OathProtocol';
import { Log, errorMessage } from '../common/Log';
import { CredentialData, CredentialInfo, OathName, OtpType } from '../model/Credential';
import { TokenItemState } from '../model/UiState';
import { AppState, UiDialogBridge } from '../viewmodel/AppState';
import { DeviceInfoStore } from '../viewmodel/DeviceInfoStore';
import { TokenStore } from '../viewmodel/TokenStore';
import { SessionPasswordStore } from '../security/SessionPasswordStore';
import { SavedPasswordStore } from '../security/SavedPasswordStore';
import { ParseOutcome } from '../utils/OtpauthParser';
import { CardChannel, NfcCardChannel } from './CardChannel';
import { ResUtil } from '../common/ResUtil';
import { PasswordValidationError } from '../common/OathErrors';
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
      throw new Error(ResUtil.str($r('app.string.err_no_connection')));
    }
    return ch.withSession(async (session: OathSession) => {
      const ok = await this.authenticate(session, toast);
      if (!ok) {
        throw new Error(ResUtil.str($r('app.string.err_unlock_failed')));
      }
      return work(session);
    }, toast);
  }

  /**
   * S3 验证：手动会话密码 → 弹窗输入；失败仅 Toast。
   * serial：USB 连接时序中 authenticate 先于 setChannel，须由 connectUsb 显式传参；
   * <0 时回退当前通道序列号（NFC 的 verifySerial 先于 authenticate 执行，已是当前碰卡序列号）。
   */
  async authenticate(session: OathSession, toast: (msg: string) => void, serial: number = -1): Promise<boolean> {
    if (!session.isLocked()) {
      this.hasCardKey = session.getHasKey();
      return true;
    }
    this.hasCardKey = true;
    const sn = serial >= 0 ? serial : (this.channel?.getSerial() ?? -1);
    const manual = SessionPasswordStore.get();
    if (manual !== undefined && manual.length > 0) {
      try {
        await this.tryValidate(session, manual);
        if (sn >= 0) {
          // 验证成功：变动同步（条目已存在且密码不同才覆盖，未登记不创建；fire-and-forget）
          SavedPasswordStore.sync(sn, manual);
        }
        return true;
      } catch (e) {
        toast(ResUtil.str($r('app.string.err_wrong_password_manual')));
        return false;
      }
    }
    // manual 未配置或显式空串：按序列号自动读取已保存密码（FR-006；替换旧空串 Toast 拒绝）
    if (sn >= 0) {
      const saved = await SavedPasswordStore.get(sn);
      if (saved !== undefined) {
        try {
          await this.tryValidate(session, saved);
          return true; // 已保存密码验证成功：不回写 SessionPasswordStore（保持配置态与记忆正交）
        } catch (e) {
          // 判据重构（FR-007）：由消息子串匹配改为结构化 instanceof——
          // 密码比对失败（PasswordValidationError）回落弹窗；通信等其他异常上抛按连接错误处理
          if (!(e instanceof PasswordValidationError)) {
            throw e as Error;
          }
          // 已保存密码失效（卡片密码已在别处被修改）：保留条目不删除，直接回落弹窗输入
          //（输入新密码验证成功后经弹窗分支 sync 自动覆盖，条目自愈；plan.md D5-v2）
        }
      }
    }
    // 回落：无可用已保存密码，弹窗输入（title/hint 经 UiDialogBridge 注入，须取串）
    const input = await UiDialogBridge.requestPassword(ResUtil.str($r('app.string.password_dialog_title_unlock')), false,
      ResUtil.str($r('app.string.password_dialog_hint_unlock')));
    if (input === null) {
      toast(ResUtil.str($r('app.string.err_unlock_cancelled')));
      return false;
    }
    try {
      await this.tryValidate(session, input);
      SessionPasswordStore.set(input);
      if (sn >= 0) {
        // 弹窗输入验证成功：变动同步（失效回落场景在此自愈条目，未登记不创建；fire-and-forget）
        SavedPasswordStore.sync(sn, input);
      }
      return true;
    } catch (e) {
      toast(ResUtil.str($r('app.string.err_wrong_password')));
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
      Log.error('NFC idle tap failed: %{public}s', errorMessage(e));
      toast(errorMessage(e));
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
        throw new Error(ResUtil.strWithArgs($r('app.string.err_account_limit'), limit));
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
        toast(errorMessage(e));
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
        toast(errorMessage(e));
      }
    }
    return ok;
  }

  /** 删除凭据（M2-6 / S7） */
  async deleteCredential(name: string, toast: (msg: string) => void): Promise<void> {
    const cred = TokenStore.getInstance().getCredential(name);
    if (cred === undefined) {
      throw new Error(ResUtil.str($r('app.string.err_credential_not_found')));
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
      throw new Error(ResUtil.str($r('app.string.err_credential_not_found')));
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
      throw new Error(ResUtil.str($r('app.string.err_credential_not_found')));
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
      // 持久化联动（FR-010）：新密码非空变动同步（已存在条目才覆盖，未登记不创建）；
      // 为空删除条目（卡片已无密码，条目失去意义）；serial<0 跳过
      const channelSerial = this.channel?.getSerial() ?? -1;
      if (channelSerial >= 0) {
        if (newPassword.length > 0) {
          SavedPasswordStore.sync(channelSerial, newPassword);
        } else {
          SavedPasswordStore.remove(channelSerial);
        }
      }
      await this.refreshAll(session);
    }, toast);
  }

  /** 重置 OATH 应用（M2-8 / S10） */
  async resetCard(toast: (msg: string) => void): Promise<void> {
    await this.withSession(async (session: OathSession) => {
      await session.reset();
      this.hasCardKey = false;
      SessionPasswordStore.clear();
      // 重置后卡片不再有密码：删除对应序列号的记忆条目（FR-010；serial<0 跳过）
      const channelSerial = this.channel?.getSerial() ?? -1;
      if (channelSerial >= 0) {
        SavedPasswordStore.remove(channelSerial);
      }
      TokenStore.getInstance().clear();
      AppState.setCredentialCount(0);
    }, toast);
  }
}