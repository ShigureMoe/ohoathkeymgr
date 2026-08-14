/** 全局状态键与 UI 弹窗桥（AppStorage 由 UI 订阅，服务层只写键） */
import { CardInfoResult } from '../model/DeviceInfoModel';

/** AppStorage 键常量 */
export class AppState {
  static readonly KEY_MODE = 'connMode';
  static readonly KEY_STATUS = 'connStatus';
  static readonly KEY_DEVICE_INFO = 'deviceInfo';
  static readonly KEY_DEVICE_LABEL = 'deviceLabel';
  static readonly KEY_NFC_PROMPT = 'nfcPromptVisible';
  static readonly KEY_TOUCH_PROMPT = 'touchPromptVisible';
  static readonly KEY_THEME = 'uiTheme';
  static readonly KEY_CREDENTIAL_COUNT = 'credentialCount';
  /** 当前连接绑定的卡片序列号（NFC/USB 统一"当前连接"概念） */
  static readonly KEY_BOUND_SERIAL = 'boundSerial';

  static setMode(mode: string): void {
    AppStorage.setOrCreate<string>(AppState.KEY_MODE, mode);
  }

  static setStatus(status: string): void {
    AppStorage.setOrCreate<string>(AppState.KEY_STATUS, status);
  }

  static setDeviceInfo(info: CardInfoResult | undefined): void {
    AppStorage.setOrCreate<CardInfoResult | undefined>(AppState.KEY_DEVICE_INFO, info);
  }

  static setDeviceLabel(label: string): void {
    AppStorage.setOrCreate<string>(AppState.KEY_DEVICE_LABEL, label);
  }

  static setNfcPrompt(visible: boolean): void {
    AppStorage.setOrCreate<boolean>(AppState.KEY_NFC_PROMPT, visible);
  }

  static setTouchPrompt(visible: boolean): void {
    AppStorage.setOrCreate<boolean>(AppState.KEY_TOUCH_PROMPT, visible);
  }

  static setCredentialCount(count: number): void {
    AppStorage.setOrCreate<number>(AppState.KEY_CREDENTIAL_COUNT, count);
  }

  /** 设置当前连接绑定序列号（-1 = 未绑定） */
  static setBoundSerial(serial: number): void {
    AppStorage.setOrCreate<number>(AppState.KEY_BOUND_SERIAL, serial);
  }

  /** 获取绑定序列号；未绑定返回 -1 */
  static getBoundSerial(): number {
    const v = AppStorage.get<number>(AppState.KEY_BOUND_SERIAL);
    return v === undefined ? -1 : v;
  }
}

/**
 * UI 弹窗桥：服务层通过 requestPassword 请求 UI 弹出密码输入框，
 * Index 页挂载 PasswordInputDialog 组件并订阅 visible 键。
 */
export interface PasswordRequest {
  title: string;
  allowEmpty: boolean;
}

export class UiDialogBridge {
  static readonly KEY_VISIBLE = 'passwordDialogVisible';
  static readonly KEY_TITLE = 'passwordDialogTitle';
  static readonly KEY_ALLOW_EMPTY = 'passwordDialogAllowEmpty';
  static readonly KEY_HINT = 'passwordDialogHint';
  private static pending: ((value: string | null) => void) | undefined = undefined;

  /** 请求密码输入（UI 层响应；返回 null 表示取消） */
  static requestPassword(title: string, allowEmpty: boolean, hint: string): Promise<string | null> {
    return new Promise<string | null>((resolve: (value: string | null) => void) => {
      UiDialogBridge.pending = resolve;
      AppStorage.setOrCreate<string>(UiDialogBridge.KEY_TITLE, title);
      AppStorage.setOrCreate<boolean>(UiDialogBridge.KEY_ALLOW_EMPTY, allowEmpty);
      AppStorage.setOrCreate<string>(UiDialogBridge.KEY_HINT, hint);
      AppStorage.setOrCreate<boolean>(UiDialogBridge.KEY_VISIBLE, true);
    });
  }

  /** UI 提交 */
  static submit(value: string): void {
    const p = UiDialogBridge.pending;
    UiDialogBridge.pending = undefined;
    AppStorage.setOrCreate<boolean>(UiDialogBridge.KEY_VISIBLE, false);
    if (p !== undefined) {
      p(value);
    }
  }

  /** UI 取消 */
  static cancel(): void {
    const p = UiDialogBridge.pending;
    UiDialogBridge.pending = undefined;
    AppStorage.setOrCreate<boolean>(UiDialogBridge.KEY_VISIBLE, false);
    if (p !== undefined) {
      p(null);
    }
  }
}