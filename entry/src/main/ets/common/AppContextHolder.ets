/**
 * 全局 UIAbilityContext 持有器：EntryAbility.onCreate 时保存，
 * 供测试页构造 tag.on('readerMode') 所需的 ElementName（bundleName/abilityName/moduleName）
 */
import { common } from '@kit.AbilityKit';

export class AppContextHolder {
  static context: common.UIAbilityContext | undefined = undefined;
}