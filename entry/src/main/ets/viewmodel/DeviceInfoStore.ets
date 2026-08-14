/** 设备信息状态（设备管理页数据源；服务层连接成功后写入） */
import { CardInfoResult } from '../model/DeviceInfoModel';
import { AppState } from './AppState';

export class DeviceInfoStore {
  private static result: CardInfoResult | undefined = undefined;

  static set(result: CardInfoResult): void {
    DeviceInfoStore.result = result;
    AppState.setDeviceInfo(result);
  }

  static get(): CardInfoResult | undefined {
    return DeviceInfoStore.result;
  }

  static clear(): void {
    DeviceInfoStore.result = undefined;
    AppState.setDeviceInfo(undefined);
  }

  /** 凭据数量上限：CanoKey ≈100，YubiKey 5 = 32（M3-4） */
  static getCredentialLimit(): number {
    const info = DeviceInfoStore.result;
    if (info === undefined) {
      return 32;
    }
    const type = info.ykmanInfo.deviceType;
    if (type.indexOf('Cano') >= 0) {
      return 100;
    }
    return 32;
  }

  /** 设备是否支持触摸属性：YubiKey 固件 ≥4.2.6 / CanoKey（M2-5） */
  static supportsTouch(): boolean {
    const info = DeviceInfoStore.result;
    if (info === undefined) {
      return false;
    }
    const type = info.ykmanInfo.deviceType;
    if (type.indexOf('Cano') >= 0) {
      return true;
    }
    const fw = info.ykmanInfo.firmwareVersion;
    const parts = fw.split('.');
    if (parts.length < 3) {
      return false;
    }
    const major = parseInt(parts[0]);
    const minor = parseInt(parts[1]);
    if (major > 4) {
      return true;
    }
    if (major < 4) {
      return false;
    }
    return minor >= 2;
  }
}