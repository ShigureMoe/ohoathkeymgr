/**
 * 会话安全密码存储（M4-1）：仅内存，退出/断开即丢弃。
 * undefined = 未配置；空串 = 显式配置为空（跳过持久化回退）。
 */
export class SessionPasswordStore {
  private static password: string | undefined = undefined;

  static set(value: string): void {
    SessionPasswordStore.password = value;
  }

  static get(): string | undefined {
    return SessionPasswordStore.password;
  }

  static clear(): void {
    SessionPasswordStore.password = undefined;
  }
}