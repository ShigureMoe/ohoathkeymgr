import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import { Log } from '../common/Log';

export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup() {
    Log.info('onBackup ok');
    await Promise.resolve();
  }

  async onRestore(bundleVersion: BundleVersion) {
    Log.info('onRestore ok %{public}s', JSON.stringify(bundleVersion));
    await Promise.resolve();
  }
}