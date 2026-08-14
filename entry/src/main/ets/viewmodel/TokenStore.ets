/** 令牌列表内存模型（M3-6/7）：@Observed（V1）驱动每秒倒计时局部刷新 */
import { CalculateAllEntry } from '../protocol/OathProtocol';
import { CodeInfo, CredentialInfo, OtpType } from '../model/Credential';
import { TokenItemState } from '../model/UiState';

/** 列表项（凭据 + 令牌展示状态） */
@Observed
export class TokenListItem {
  cred: CredentialInfo;
  state: TokenItemState = TokenItemState.STALE;
  code: string = '';
  remainingSec: number = 0;
  validFrom: number = 0;
  validTo: number = 0;

  constructor(cred: CredentialInfo) {
    this.cred = cred;
  }
}

/** 全局令牌列表（单例；服务层写、UI 订阅） */
@Observed
export class TokenStore {
  items: TokenListItem[] = [];
  private credMap: Map<string, CredentialInfo> = new Map<string, CredentialInfo>();
  private static instance: TokenStore | undefined = undefined;

  static getInstance(): TokenStore {
    if (TokenStore.instance === undefined) {
      TokenStore.instance = new TokenStore();
    }
    return TokenStore.instance;
  }

  getCredential(name: string): CredentialInfo | undefined {
    return this.credMap.get(name);
  }

  /**
   * 全量刷新（就地合并）：以 LIST 为权威更新状态。
   * 复用已有 item 实例（同键）只更新属性——若整体重建数组，
   * 会导致 UI @ObjectLink 绑定脱钩（列表不刷新 + 倒计时卡死）。
   */
  setFromRefresh(creds: CredentialInfo[], entries: CalculateAllEntry[]): void {
    const entryMap = new Map<string, CalculateAllEntry>();
    for (const entry of entries) {
      entryMap.set(entry.name, entry);
    }
    // 现有 item 映射（复用实例，维持 UI 绑定）
    const existing = new Map<string, TokenListItem>();
    for (const it of this.items) {
      existing.set(it.cred.name, it);
    }
    const newOrder: TokenListItem[] = [];
    const newCredMap = new Map<string, CredentialInfo>();
    for (const cred of creds) {
      newCredMap.set(cred.name, cred);
      let item = existing.get(cred.name);
      if (item === undefined) {
        item = new TokenListItem(cred);
      } else {
        existing.delete(cred.name);
        item.cred = cred;
      }
      this.applyEntry(item, entryMap.get(cred.name));
      newOrder.push(item);
    }
    newOrder.sort((a: TokenListItem, b: TokenListItem) => {
      const la = a.cred.getLabel().toLowerCase();
      const lb = b.cred.getLabel().toLowerCase();
      if (la !== lb) {
        return la < lb ? -1 : 1;
      }
      const ca = a.cred.account.toLowerCase();
      const cb = b.cred.account.toLowerCase();
      return ca < cb ? -1 : (ca > cb ? 1 : 0);
    });
    this.items = newOrder;
    this.credMap = newCredMap;
  }

  /** 将 CALCULATE ALL 单条结果应用到 item（触摸/HOTP/有码 TOTP） */
  private applyEntry(item: TokenListItem, entry: CalculateAllEntry | undefined): void {
    // 有码值优先（含 NFC 下已补算的触摸凭据）
    if (entry !== undefined && entry.code !== null) {
      item.state = TokenItemState.ACTIVE;
      item.code = entry.code.code;
      item.validFrom = entry.code.validFrom;
      item.validTo = entry.code.validTo;
      item.remainingSec = Math.max(0, Math.ceil(item.validTo - Date.now() / 1000));
      return;
    }
    if (entry !== undefined && entry.touch) {
      // USB 触摸凭据：已计算且未到期则保留显示，否则回到触摸态
      const nowSec = Date.now() / 1000;
      if (item.state === TokenItemState.ACTIVE && item.validTo > nowSec) {
        return;
      }
      item.state = TokenItemState.TOUCH;
      item.code = '';
      return;
    }
    if (entry !== undefined && entry.otpType === OtpType.HOTP) {
      // HOTP：已有码值（此前计算过）则保持 ACTIVE 显示，否则回到刷新按钮态
      if (item.state === TokenItemState.ACTIVE && item.code.length > 0) {
        return;
      }
      item.state = TokenItemState.HOTP_IDLE;
      item.code = '';
      return;
    }
    if (entry !== undefined && entry.code !== null) {
      item.state = TokenItemState.ACTIVE;
      item.code = entry.code.code;
      item.validFrom = entry.code.validFrom;
      item.validTo = entry.code.validTo;
      item.remainingSec = Math.max(0, Math.ceil(item.validTo - Date.now() / 1000));
      return;
    }
    if (item.cred.otpType === OtpType.HOTP) {
      item.state = TokenItemState.HOTP_IDLE;
      item.code = '';
      return;
    }
    item.state = TokenItemState.ERROR;
    item.code = '';
  }

  /** 每秒 tick：按当前时间重算剩余秒；TOTP ACTIVE 到期 → STALE；HOTP 无有效期不参与倒计时（官方：DateTimeOffset.MaxValue） */
  tick(): void {
    const nowSec = Date.now() / 1000;
    for (const item of this.items) {
      if (item.cred.otpType === OtpType.HOTP) {
        // HOTP：计数器驱动，不置灰
        continue;
      }
      if (item.state === TokenItemState.ACTIVE) {
        const remain = Math.max(0, Math.ceil(item.validTo - nowSec));
        item.remainingSec = remain;
        if (remain <= 0) {
          item.state = TokenItemState.STALE;
        }
      }
    }
  }

  /** 单条计算完成（TOTP / 触摸计算）：置 ACTIVE 展示码值 */
  setActive(name: string, code: CodeInfo): void {
    const item = TokenStore.findByName(this.items, name);
    if (item === undefined) {
      return;
    }
    item.state = TokenItemState.ACTIVE;
    item.code = code.code;
    item.validFrom = code.validFrom;
    item.validTo = code.validTo;
    item.remainingSec = Math.max(0, Math.ceil(code.validTo - Date.now() / 1000));
  }

  /** HOTP 计算后置 ACTIVE；HOTP 无有效期（不置灰），列表项显示码值+刷新按钮 */
  setHotpResult(name: string, code: CodeInfo): void {
    const item = TokenStore.findByName(this.items, name);
    if (item === undefined) {
      return;
    }
    item.state = TokenItemState.ACTIVE;
    item.code = code.code;
    item.validFrom = code.validFrom;
    item.validTo = code.validTo;
    item.remainingSec = 0;
  }

  /** 触摸计算后置 ACTIVE（等价 setActive，语义名） */
  setTouchResult(name: string, code: CodeInfo): void {
    this.setActive(name, code);
  }

  /** 触摸等待提示态 */
  setTouchPrompting(name: string): void {
    const item = TokenStore.findByName(this.items, name);
    if (item !== undefined) {
      item.state = TokenItemState.TOUCH_PROMPTING;
    }
  }

  /** 删除一项（删除凭据后） */
  removeByName(name: string): void {
    const idx = this.items.findIndex((it: TokenListItem) => it.cred.name === name);
    if (idx >= 0) {
      this.items.splice(idx, 1);
    }
    if (this.credMap.has(name)) {
      this.credMap.delete(name);
    }
  }

  /** 连接失败/断开：TOTP 置灰保留数据；HOTP 码值无时效性，保持显示 */
  markAllStale(): void {
    for (const item of this.items) {
      if (item.cred.otpType === OtpType.HOTP) {
        continue;
      }
      if (item.state === TokenItemState.ACTIVE || item.state === TokenItemState.STALE) {
        item.state = TokenItemState.STALE;
      }
    }
  }

  /** 清空（切换连接/重置卡片） */
  clear(): void {
    this.items = [];
    this.credMap = new Map<string, CredentialInfo>();
  }

  getCount(): number {
    return this.items.length;
  }

  private static findByName(items: TokenListItem[], name: string): TokenListItem | undefined {
    for (const item of items) {
      if (item.cred.name === name) {
        return item;
      }
    }
    return undefined;
  }
}