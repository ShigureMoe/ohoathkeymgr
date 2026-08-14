/** UI 状态枚举：连接模式/连接状态/令牌列表项状态 */

/** 连接模式（同时最多一种） */
export enum ConnMode {
  NONE = 0,
  NFC = 1,
  USB = 2
}

/** 连接状态（NFC 模式不进入 CONNECTING/CONNECTED，仅用于 USB） */
export enum ConnStatus {
  DISCONNECTED = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  FAILED = 3
}

/** 令牌列表项状态机 */
export enum TokenItemState {
  /** 显示令牌 + 倒计时（权威数据） */
  ACTIVE = 0,
  /** 倒计时到期/断开：置灰 */
  STALE = 1,
  /** HOTP：显示刷新按钮 */
  HOTP_IDLE = 2,
  /** 触摸凭据图标（未计算） */
  TOUCH = 3,
  /** 已点击，等待用户触摸卡片 */
  TOUCH_PROMPTING = 4,
  /** 计算失败 */
  ERROR = 5
}

/** NFC 可用性细分（模拟器等环境与真机需要区别提示） */
export enum NfcAvailability {
  /** 正常可用 */
  READY = 0,
  /** 系统 NFC 开关未打开 */
  SWITCH_OFF = 1,
  /** 平台（系统能力）不支持 NFC */
  UNSUPPORTED = 2,
  /** 平台声明支持但芯片/硬件不可用（如模拟器） */
  HARDWARE_MISSING = 3
}