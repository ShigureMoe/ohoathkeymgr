# OATH Key Manager

基于 HarmonyOS（ArkTS / API 26）的 OATH 安全卡片管理应用，用于管理 YubiKey 等兼容安全卡片上的 TOTP/HOTP 凭据。

## 功能特性

- **凭据管理**
  - 令牌列表实时展示动态码，TOTP 自动倒计时刷新，HOTP 手动刷新
  - 长按复制动态码，左滑确认删除凭据（TODO）
  - 支持触摸（touch）凭据：请求时提示触摸卡片完成计算、NFC下无需触摸
- **添加凭据（三种方式）**
  - 扫码添加：调用系统 Scan Kit 默认扫码界面，识别 `otpauth://` 二维码
  - 手动表单：填写 Issuer / Account / Secret / 算法 / 位数 / 周期等
- **连接方式**
  - USB：CCID 传输，长连接会话，支持后台自动刷新与失联检测（30s 心跳）
  - NFC：碰卡会话，序列号绑定校验（防止误碰其他卡片）
- **安全能力**
  - 卡片安全密码验证：解锁后会话内记忆（临时保存），验证失败仅提示
  - 修改 / 移除卡片安全密码
  - 重置 OATH 应用（需输入 `RESETTHEKEY` 确认，清空全部凭据与密码）
- **设备信息**：设备类型、序列号、固件版本、OATH 版本、密码保护状态、凭据数量
- **其他**：暗黑模式三选一（跟随系统 / 深色 / 亮色）

## 系统要求

- DevEco Studio 5.x（HarmonyOS SDK API 26）
- 设备：phone / tablet / 2in1，需支持 NFC（扫码与 NFC 连接需要）
- 安全卡片：YubiKey 5 系列等支持 OATH 的应用（CCID 接口，可有密码保护）、Canokeys 系列卡片（已测试Canokeys Pigeon）

## 构建与运行

```bash
# 构建 debug 包
devecocli build

# 部署到已连接设备/模拟器
devecocli run
```

也可在 DevEco Studio 中打开工程后直接 Run。应用权限：`ohos.permission.NFC_TAG`（扫码使用系统 Scan Kit 默认界面，无需相机权限）。真机调试需自行配置签名。

## 使用说明

1. **连接卡片**：点击顶栏连接按钮，选择 USB 设备（列表自动枚举）或 NFC 模式（进入"请将卡片靠近 NFC 感应区"状态）。
2. **解锁**：卡片设置过安全密码时弹出输入框；也可在顶栏钥匙按钮处预先设置会话密码。
3. **添加凭据**：令牌页右下角 "+" 菜单 → 扫码 / 手动添加 / 从链接添加。
4. **删除凭据**：令牌条目左滑 → 确认删除。
5. **修改密码**：设备管理页 → 修改安全密码（留空提交 = 移除密码）。
6. **重置卡片**：设置页 → 重置安全卡片 → 输入 `RESETTHEKEY` 确认。

## 项目结构

```
entry/src/main/ets/
├── entryability/        # EntryAbility（生命周期、权限申请、连接初始化）
├── protocol/            # OathProtocol：OATH APDU 协议层
├── common/              # 传输与工具
│   ├── UsbCcidTransport # USB CCID 传输
│   ├── CcidProtocol     # CCID 消息层（消息头/分片/链路）
│   ├── NfcCardTransport # NFC 传输
│   ├── ApduUtils        # APDU 组装
│   ├── CardInfoCollector# 设备信息采集（Management 应用）
├── service/             # 业务服务
│   ├── ConnectionManager    # 连接编排（USB 长连接 / NFC 待卡监听）
│   ├── OathSessionManager   # 统一会话入口（解锁编排 + 凭据操作）
│   ├── CardChannel          # USB/NFC 统一通道抽象
│   ├── NfcSessionRunner     # NFC 会话执行器
│   ├── ScanService          # Scan Kit 扫码封装
│   └── TokenRefreshScheduler# USB 30s 自动刷新
├── viewmodel/           # TokenStore / UriImporter / AppState / DeviceInfoStore
├── utils/               # OtpauthParser（otpauth/migration 解析）、Base32
├── security/            # SessionPasswordStore（会话密码记忆）
├── storage/             # AppPreferences（设置持久化）
├── pages/               # 令牌列表 / 设备管理 / 设置
├── components/          # 顶栏、连接弹窗、添加表单、令牌条目等
└── model/               # 数据模型（Credential / UiState / DeviceInfoModel）
```

## 架构说明

- 业务层（`OathSessionManager`）只面向 `CardChannel` 接口，不区分 NFC/USB：
  - USB：复用已验证的长连接会话，支持后台自动刷新
  - NFC：每次操作触发"碰卡会话"，触碰的卡片序列号与绑定值不一致时拒绝（防误碰）
- 凭据导入管线：`ScanService` / `AddByUriSheet` → `OtpauthParser.parseAny` → `UriImporter.importAndConfirm`（重名收集 + 覆盖确认）→ `OathSessionManager.addOutcome`
- 验证流程：`CALCULATE ALL` 前检查会话锁定状态，已锁定则用会话密码 `DERIVE KEY + VALIDATE` 解锁

## 许可证

[GPL-3.0](COPYING)
