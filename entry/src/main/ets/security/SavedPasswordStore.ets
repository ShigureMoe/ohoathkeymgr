/**
 * 会话密码持久化存储（session-password-persist v2）：基于 Asset Store Kit 的关键资产封装。
 * 以卡片序列号为键保存 OATH 会话密码（SECRET 由系统在安全环境加密落库，满足不明文落盘）。
 * v2 语义：条目仅由用户在管理页手动添加（add，已存在不覆盖）；
 * 此后面板对已存在条目做变动同步（sync，读-比-写：不存在不创建/相同不写/不同才覆盖）；
 * 失效密码不删条目（remove 仅用于管理页手动删除与改空密码/重置卡片联动）：
 *  - add：手动添加（CONFLICT_RESOLUTION=THROW_ERROR 冲突检测一步到位，DUPLICATED 返回 false）
 *  - sync：变动同步（验证成功路径自动调用：条目存在且密码不同才 asset.update 覆盖）
 *  - get：按序列号读取密码明文（仅瞬时用于卡片验证，不进入任何 UI 状态或缓存）
 *  - remove：删除条目（管理页手动删除 / 改空密码与重置卡片联动；失效不删除）
 *  - listSerials：批量查询全部序列号（RETURN_TYPE=ATTRIBUTES 仅查属性，永不解密密码）
 * 容错策略（plan.md D6）：sync/remove 内部吞异常仅记日志（fire-and-forget 语义）；
 * add 异常返回 false 交由调用方提示；get/listSerials 在 NOT_FOUND/服务异常/数据损坏时
 * 返回 undefined/空数组，不阻断连接主流程。sync 读-比-写两步非原子（plan.md D11，
 * 写者单一无并发，可接受）。
 */
import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Log, errorMessage } from '../common/Log';

/** Asset ALIAS 前缀：完整别名 = 前缀 + 序列号（前缀长度满足 asset alias ≥8 字节下限） */
const ALIAS_PREFIX: string = 'oath.session.pwd.';
/** 业务标识（DATA_LABEL_NORMAL_1）：批量查询本应用全部会话密码条目的匹配键 */
const BUSINESS_LABEL: string = 'ohoathkeymgr.session.pwd';

export class SavedPasswordStore {
  /**
   * 手动添加条目（管理页添加弹窗唯一入口）：
   * CONFLICT_RESOLUTION=THROW_ERROR 冲突检测一步到位（plan.md D1-v2）。
   * serial<0 / 空密码 → false（不写入）；已存在（DUPLICATED 24000003）→ false 不覆盖
   * （需先删除再添加）；成功 → true；其他异常记日志并返回 false（调用方按失败提示）。
   */
  static async add(serial: number, password: string): Promise<boolean> {
    if (serial < 0 || password.length === 0) {
      return false;
    }
    try {
      const attrs: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      attrs.set(asset.Tag.ALIAS, SavedPasswordStore.toBytes(SavedPasswordStore.aliasOf(serial)));
      attrs.set(asset.Tag.SECRET, SavedPasswordStore.toBytes(password));
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      attrs.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
      attrs.set(asset.Tag.DATA_LABEL_NORMAL_1, SavedPasswordStore.toBytes(BUSINESS_LABEL));
      attrs.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.THROW_ERROR);
      await asset.add(attrs);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === asset.ErrorCode.DUPLICATED) {
        // 序列号已存在：不覆盖，返回 false 由 UI 提示（FR-004）
        return false;
      }
      Log.error('SavedPasswordStore.add failed: %{public}s', errorMessage(e));
      return false;
    }
  }

  /**
   * 变动同步（验证成功路径自动调用，fire-and-forget）：读-比-写（plan.md D1-v2/D11）。
   * serial<0 / 空密码 → 返回；条目不存在 → 直接返回（绝不创建，FR-009）；
   * 密码相同 → 返回（无变动不写）；不同 → asset.update 按 ALIAS 查询覆盖 SECRET。
   * 异常仅记日志不阻断验证主流程。
   */
  static async sync(serial: number, password: string): Promise<void> {
    if (serial < 0 || password.length === 0) {
      return;
    }
    try {
      const saved = await SavedPasswordStore.get(serial);
      if (saved === undefined) {
        // 未登记卡片：不创建任何条目
        return;
      }
      if (saved === password) {
        // 密码未变动：不写
        return;
      }
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, SavedPasswordStore.toBytes(SavedPasswordStore.aliasOf(serial)));
      const attrsToUpdate: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      attrsToUpdate.set(asset.Tag.SECRET, SavedPasswordStore.toBytes(password));
      await asset.update(query, attrsToUpdate);
    } catch (e) {
      Log.error('SavedPasswordStore.sync failed: %{public}s', errorMessage(e));
    }
  }

  /**
   * 读取指定序列号的密码明文。
   * NOT_FOUND（未登记过）/ 服务异常 / 数据损坏解密失败一律返回 undefined，调用方回落弹窗流程。
   */
  static async get(serial: number): Promise<string | undefined> {
    if (serial < 0) {
      return undefined;
    }
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, SavedPasswordStore.toBytes(SavedPasswordStore.aliasOf(serial)));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: Array<asset.AssetMap> = await asset.query(query);
      if (result.length === 0) {
        return undefined;
      }
      const secret: asset.Value | undefined = result[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return undefined;
      }
      return SavedPasswordStore.fromBytes(secret);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        Log.error('SavedPasswordStore.get failed: %{public}s', errorMessage(e));
      }
      return undefined;
    }
  }

  /** 删除指定序列号条目；NOT_FOUND 视为幂等成功，其他异常仅记日志 */
  static async remove(serial: number): Promise<void> {
    if (serial < 0) {
      return;
    }
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, SavedPasswordStore.toBytes(SavedPasswordStore.aliasOf(serial)));
      await asset.remove(query);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === asset.ErrorCode.NOT_FOUND) {
        return;
      }
      Log.error('SavedPasswordStore.remove failed: %{public}s', errorMessage(e));
    }
  }

  /**
   * 查询全部已保存条目的序列号（无排序承诺）。
   * 仅按业务标识查询属性（不含明文）；无条目（NOT_FOUND）或服务异常均返回空数组。
   */
  static async listSerials(): Promise<Array<number>> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.DATA_LABEL_NORMAL_1, SavedPasswordStore.toBytes(BUSINESS_LABEL));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
      const result: Array<asset.AssetMap> = await asset.query(query);
      const serials: Array<number> = [];
      for (const item of result) {
        const value: asset.Value | undefined = item.get(asset.Tag.ALIAS);
        if (value === undefined || !(value instanceof Uint8Array)) {
          continue;
        }
        const serial = SavedPasswordStore.serialFromAlias(SavedPasswordStore.fromBytes(value));
        if (serial >= 0) {
          serials.push(serial);
        }
      }
      return serials;
    } catch (e) {
      const err = e as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        Log.error('SavedPasswordStore.listSerials failed: %{public}s', errorMessage(e));
      }
      return [];
    }
  }

  private static aliasOf(serial: number): string {
    return ALIAS_PREFIX + serial;
  }

  /** 从 ALIAS 反解序列号：非本业务前缀或后缀非纯数字时返回 -1（忽略该条目） */
  private static serialFromAlias(alias: string): number {
    if (!alias.startsWith(ALIAS_PREFIX)) {
      return -1;
    }
    const suffix = alias.substring(ALIAS_PREFIX.length);
    if (suffix.length === 0) {
      return -1;
    }
    const serial = Number(suffix);
    if (!Number.isInteger(serial) || serial < 0) {
      return -1;
    }
    return serial;
  }

  private static toBytes(text: string): Uint8Array {
    const encoder = new util.TextEncoder('utf-8');
    return encoder.encodeInto(text);
  }

  private static fromBytes(data: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(data);
  }
}
