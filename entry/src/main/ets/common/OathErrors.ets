/**
 * 结构化错误类型（app-i18n / D4 / FR-007）：
 * PasswordValidationError——OATH VALIDATE 密码比对失败的专属错误类型。
 * "密码错误"识别判据由消息文本子串匹配（includes('密码错误')）重构为 instanceof 判断，
 * 消息资源化（中英双语）后双语言下的失效回落分流行为保持一致。
 */
export class PasswordValidationError extends Error {
}
