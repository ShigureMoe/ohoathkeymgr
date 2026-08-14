/**
 * USB CCID 传输适配器
 * CCID 为公开规范（USB CCID Class Spec 1.1），ykman 的 USB 后端依赖 pyscard(PCSC)，
 * HarmonyOS 无 PCSC，故按规范直接实现 bulk 消息层：
 *  - 消息编解码/seq 校验/链式拼接/背靠背缓冲全部在 CcidProtocol（纯逻辑，可单测）
 *  - 本文件仅负责：USB 枚举、权限、pipe 管理、bulk 收发、超时 Abort 恢复
 */
import { usbManager } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardTransport } from './ApduUtils';
import { CcidProtocol, ByteStream } from './CcidProtocol';

const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'OathKeeper';

/** 供测试页展示的 USB 安全卡片（含 CCID 接口的设备） */
export interface UsbCardDevice {
  device: usbManager.USBDevice;
  config: usbManager.USBConfiguration;
  iface: usbManager.USBInterface;
  label: string;
}

/** USB 接口类值：CCID（bInterfaceClass=0x0B） */
const USB_CLASS_CCID = 0x0B;
/** bulk 端点 type 值 */
const EP_TYPE_BULK = 2;
const EP_DIR_IN = 0x80;
const EP_DIR_OUT = 0x00;
const BULK_TIMEOUT_MS = 2000;

/** 枚举当前连接的 USB 安全卡片（CCID 接口） */
export class UsbDeviceLister {
  static list(): UsbCardDevice[] {
    const out: UsbCardDevice[] = [];
    let devices: Array<usbManager.USBDevice> = [];
    try {
      devices = usbManager.getDevices();
    } catch (e) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'USB_ENUM getDevices error: %{public}s', (e as BusinessError).message);
      return out;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'USB_ENUM total devices: %{public}d', devices.length);
    for (const dev of devices) {
      let ifaceDesc = '';
      if (dev.configs === undefined || dev.configs.length === 0) {
        ifaceDesc = 'no-configs';
      } else {
        const parts: string[] = [];
        for (const cfg of dev.configs) {
          for (const iface of cfg.interfaces) {
            parts.push('clazz=0x' + iface.clazz.toString(16) + '/sub=' + iface.subClass + '/proto=' + iface.protocol);
          }
        }
        ifaceDesc = parts.join(',');
      }
      // hilog 不支持 %x 格式，VID/PID 用字符串拼接（%{public}s）打印
      hilog.info(LOG_DOMAIN, LOG_TAG, 'USB_ENUM dev: name=%{public}s vid=0x%{public}s pid=0x%{public}s ifaces=[%{public}s]',
        dev.name, dev.vendorId.toString(16), dev.productId.toString(16), ifaceDesc);
      if (dev.configs !== undefined) {
        for (const cfg of dev.configs) {
          for (const iface of cfg.interfaces) {
            if (iface.clazz === USB_CLASS_CCID) {
              out.push(UsbDeviceLister.wrap(dev, cfg, iface));
            }
          }
        }
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG, 'USB_ENUM ccid devices found: %{public}d', out.length);
    return out;
  }

  private static wrap(dev: usbManager.USBDevice, config: usbManager.USBConfiguration,
    iface: usbManager.USBInterface): UsbCardDevice {
    let label = dev.name;
    if (dev.manufacturerName !== undefined && dev.manufacturerName.length > 0) {
      label = dev.manufacturerName;
    }
    if (dev.productName !== undefined && dev.productName.length > 0) {
      label = label + ' ' + dev.productName;
    }
    label = label + ' (VID=0x' + dev.vendorId.toString(16) + ', PID=0x' + dev.productId.toString(16) + ')';
    return { device: dev, config: config, iface: iface, label: label };
  }
}

/** bulk 端点字节流：把 CCID 消息层与 USB 传输解耦，超时后触发 Abort 恢复 */
class UsbByteStream implements ByteStream {
  private pipe: usbManager.USBDevicePipe;
  private outEp: usbManager.USBEndpoint;
  private inEp: usbManager.USBEndpoint;
  private onTimeout: () => void;

  constructor(pipe: usbManager.USBDevicePipe, outEp: usbManager.USBEndpoint,
    inEp: usbManager.USBEndpoint, onTimeout: () => void) {
    this.pipe = pipe;
    this.outEp = outEp;
    this.inEp = inEp;
    this.onTimeout = onTimeout;
  }

  async write(data: Uint8Array): Promise<number> {
    try {
      return usbManager.bulkTransfer(this.pipe, this.outEp, data, BULK_TIMEOUT_MS);
    } catch (e) {
      this.onTimeout();
      throw new Error('USB bulk write error: ' + (e as BusinessError).message);
    }
  }

  async read(buf: Uint8Array): Promise<number> {
    try {
      return await usbManager.bulkTransfer(this.pipe, this.inEp, buf, BULK_TIMEOUT_MS);
    } catch (e) {
      this.onTimeout();
      throw new Error('USB bulk read error: ' + (e as BusinessError).message);
    }
  }
}

/** USB CCID CardTransport 实现 */
export class UsbCcidTransport implements CardTransport {
  private pipe: usbManager.USBDevicePipe;
  private iface: usbManager.USBInterface;
  private protocol: CcidProtocol;
  private closed: boolean = false;

  private constructor(pipe: usbManager.USBDevicePipe, iface: usbManager.USBInterface,
    protocol: CcidProtocol) {
    this.pipe = pipe;
    this.iface = iface;
    this.protocol = protocol;
  }

  /** 打开并初始化：申请权限 → open → claim → 设置配置/接口 → 找端点 → 上电（失败释放资源） */
  static async open(card: UsbCardDevice): Promise<UsbCcidTransport> {
    // 1. 权限
    let hasRight = false;
    try {
      hasRight = usbManager.hasRight(card.device.name);
    } catch (e) {
      hasRight = false;
    }
    if (!hasRight) {
      try {
        hasRight = await usbManager.requestRight(card.device.name);
      } catch (e) {
        hasRight = false;
      }
    }
    if (!hasRight) {
      throw new Error('USB access right denied for ' + card.device.name);
    }

    // 2. 打开设备
    let pipe: usbManager.USBDevicePipe;
    try {
      pipe = usbManager.connectDevice(card.device);
    } catch (e) {
      throw new Error('USB connectDevice error: ' + (e as BusinessError).message);
    }
    if (pipe === undefined || pipe === null) {
      throw new Error('USB connectDevice failed');
    }

    // 3. 声明接口
    let claimRet = -1;
    try {
      claimRet = usbManager.claimInterface(pipe, card.iface);
    } catch (e) {
      claimRet = -1;
    }
    if (claimRet !== 0) {
      try {
        usbManager.closePipe(pipe);
      } catch (e) {
        // 忽略
      }
      throw new Error('USB claimInterface failed, code=' + claimRet);
    }

    // 4. 设置配置与接口（bulkTransfer 的前置条件，缺失会导致传输失败，见官方 FAQ）
    let cfgRet = -1;
    try {
      cfgRet = usbManager.setConfiguration(pipe, card.config);
    } catch (e) {
      cfgRet = -1;
    }
    if (cfgRet !== 0) {
      UsbCcidTransport.release(pipe, card.iface);
      throw new Error('USB setConfiguration failed, code=' + cfgRet);
    }
    let ifaceRet = -1;
    try {
      ifaceRet = usbManager.setInterface(pipe, card.iface);
    } catch (e) {
      ifaceRet = -1;
    }
    if (ifaceRet !== 0) {
      UsbCcidTransport.release(pipe, card.iface);
      throw new Error('USB setInterface failed, code=' + ifaceRet);
    }

    // 5. 查找 bulk 端点
    let outEp: usbManager.USBEndpoint | undefined = undefined;
    let inEp: usbManager.USBEndpoint | undefined = undefined;
    for (const ep of card.iface.endpoints) {
      if (ep.type !== EP_TYPE_BULK) {
        continue;
      }
      if (ep.direction === EP_DIR_OUT && outEp === undefined) {
        outEp = ep;
      } else if (ep.direction === EP_DIR_IN && inEp === undefined) {
        inEp = ep;
      }
    }
    if (outEp === undefined || inEp === undefined) {
      UsbCcidTransport.release(pipe, card.iface);
      throw new Error('USB CCID bulk endpoints not found');
    }

    // 6. 上电；失败路径释放资源，避免 USB 句柄泄漏
    let protocol: CcidProtocol | undefined = undefined;
    try {
      const stream = new UsbByteStream(pipe, outEp, inEp, () => {
        // bulk 超时后尽力 Abort 恢复设备状态（不等待结果）
        const p = protocol;
        if (p !== undefined) {
          p.abort().then(() => {
          }).catch(() => {
          });
        }
      });
      protocol = new CcidProtocol(stream);
      await protocol.powerOn();
    } catch (e) {
      UsbCcidTransport.release(pipe, card.iface);
      throw (e as Error);
    }

    return new UsbCcidTransport(pipe, card.iface, protocol);
  }

  transmit(apdu: Uint8Array): Promise<Uint8Array> {
    return this.protocol.transmit(apdu);
  }

  /** 关闭：先下电（PC_to_RDR_IccPowerOff，响应为 SlotStatus），再释放接口与管道 */
  async close(): Promise<void> {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      await this.protocol.powerOff();
    } catch (e) {
      // 忽略下电失败（设备可能已拔出）
    }
    try {
      usbManager.releaseInterface(this.pipe, this.iface);
    } catch (e) {
      // 忽略
    }
    try {
      usbManager.closePipe(this.pipe);
    } catch (e) {
      // 忽略
    }
  }

  /** 释放接口与关闭管道（幂等，全部异常吞掉） */
  private static release(pipe: usbManager.USBDevicePipe, iface: usbManager.USBInterface): void {
    try {
      usbManager.releaseInterface(pipe, iface);
    } catch (e) {
      // 忽略
    }
    try {
      usbManager.closePipe(pipe);
    } catch (e) {
      // 忽略
    }
  }
}
