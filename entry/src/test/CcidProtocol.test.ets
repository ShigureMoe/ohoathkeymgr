/**
 * CCID 消息层单元测试：用 MockByteStream 模拟设备响应，
 * 覆盖消息头编解码、powerSelect 位置、seq 校验、SlotStatus 分发、
 * 分片拼接、背靠背缓冲、链式响应、超长 APDU 防御。
 */
import { describe, it, expect } from '@ohos/hypium';
import { CcidProtocol, CcidMsgType, CcidStatus, CcidResponse, ByteStream } from '../main/ets/common/CcidProtocol';

/** 模拟设备：sent 记录收到的请求；queue 按序弹出每次 read 的字节 */
class MockByteStream implements ByteStream {
  sent: Uint8Array[] = [];
  queue: Uint8Array[] = [];
  failWrite: boolean = false;

  constructor() {
  }

  write(data: Uint8Array): Promise<number> {
    this.sent.push(data);
    if (this.failWrite) {
      return Promise.resolve(data.length - 1);
    }
    return Promise.resolve(data.length);
  }

  read(buf: Uint8Array): Promise<number> {
    if (this.queue.length === 0) {
      return Promise.resolve(0);
    }
    const chunk = this.queue[0];
    this.queue = this.queue.slice(1);
    if (chunk.length > buf.length) {
      return Promise.resolve(0);
    }
    buf.set(chunk, 0);
    return Promise.resolve(chunk.length);
  }

  /** 入队一段设备响应字节 */
  respond(hexStr: string): void {
    this.queue.push(MockByteStream.hex(hexStr));
  }

  /** 入队已拼接好的 Uint8Array 响应 */
  respondBytes(data: Uint8Array): void {
    this.queue.push(data);
  }

  static hex(hexStr: string): Uint8Array {
    const out = new Uint8Array(hexStr.length / 2);
    for (let i = 0; i < out.length; i++) {
      out[i] = parseInt(hexStr.substring(i * 2, i * 2 + 2), 16);
    }
    return out;
  }

  /** 构造 DataBlock 响应（bStatus=0） */
  static dataBlock(seq: number, dataHex: string, chain: number = 0, status: number = 0): Uint8Array {
    const data = MockByteStream.hex(dataHex);
    const msg = new Uint8Array(CcidProtocol.HEADER_LEN + data.length);
    msg[0] = CcidMsgType.DATA_BLOCK;
    msg[1] = data.length & 0xFF;
    msg[2] = (data.length >> 8) & 0xFF;
    msg[5] = 0;
    msg[6] = seq;
    msg[7] = status;
    msg[9] = chain;
    msg.set(data, CcidProtocol.HEADER_LEN);
    return msg;
  }

  /** 构造 SlotStatus 响应（bStatus=0） */
  static slotStatus(seq: number): Uint8Array {
    const msg = new Uint8Array(CcidProtocol.HEADER_LEN);
    msg[0] = CcidMsgType.SLOT_STATUS;
    msg[5] = 0;
    msg[6] = seq;
    return msg;
  }
}

export default function ccidProtocolTest() {
  describe('CcidProtocol', () => {
    it('powerOn 消息头正确（powerSelect 位于 offset 9，offset 7/8 为 RFU）', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, '3b8f8001804f0ca0000003060300020000000068'));
      const protocol = new CcidProtocol(stream);
      return protocol.powerOn().then(() => {
        expect(stream.sent.length).assertEqual(1);
        const msg = stream.sent[0];
        expect(msg[0]).assertEqual(CcidMsgType.ICC_POWER_ON);
        expect(msg[1]).assertEqual(0);
        expect(msg[2]).assertEqual(0);
        expect(msg[3]).assertEqual(0);
        expect(msg[4]).assertEqual(0);
        expect(msg[5]).assertEqual(0); // slot 0
        expect(msg[6]).assertEqual(0); // seq 0
        expect(msg[7]).assertEqual(0); // RFU
        expect(msg[8]).assertEqual(0); // RFU
        expect(msg[9]).assertEqual(CcidStatus.SUCCESS); // powerSelect: Auto
      });
    });

    it('powerOn 返回 ATR 数据', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, '3b8f8001804f0ca0000003060300020000000068'));
      const protocol = new CcidProtocol(stream);
      return protocol.powerOn().then((atr: Uint8Array) => {
        expect(atr.length).assertEqual(20);
        expect(atr[0]).assertEqual(0x3b);
        expect(atr[19]).assertEqual(0x68);
      });
    });

    it('powerOn 收到 SlotStatus（如卡未就绪）时报错', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.slotStatus(0));
      const protocol = new CcidProtocol(stream);
      return protocol.powerOn().then(() => {
        expect(true).assertEqual(false);
      }).catch((e: Error) => {
        expect(e.message).assertContain('unexpected response type 0x81');
      });
    });

    it('XfrBlock 消息 dwLength 小端且 payload 位于 offset 10 起', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, '9000'));
      const protocol = new CcidProtocol(stream);
      const apdu = MockByteStream.hex('00a4040005a0000005272101');
      return protocol.transmit(apdu).then(() => {
        const msg = stream.sent[0];
        expect(msg[0]).assertEqual(CcidMsgType.XFR_BLOCK);
        expect(msg[1]).assertEqual(12); // Lc = 12（4 头 + 1 Lc + 7 AID）
        expect(msg[2]).assertEqual(0);
        expect(msg[6]).assertEqual(0);
        for (let i = 0; i < apdu.length; i++) {
          expect(msg[CcidProtocol.HEADER_LEN + i]).assertEqual(apdu[i]);
        }
      });
    });

    it('transmit 返回响应数据（不含头）', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, '797d0133'));
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then((resp: Uint8Array) => {
        expect(resp.length).assertEqual(4);
        expect(resp[0]).assertEqual(0x79);
        expect(resp[3]).assertEqual(0x33);
      });
    });

    it('响应 bStatus 非 0 时报错', 0, () => {
      const stream = new MockByteStream();
      const bad = MockByteStream.dataBlock(0, '');
      bad[7] = CcidStatus.HW_ERROR;
      bad[8] = 0x82;
      stream.respondBytes(bad);
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then(() => {
        expect(true).assertEqual(false);
      }).catch((e: Error) => {
        expect(e.message).assertContain('status=130');
      });
    });

    it('乱序响应（滞留/重复）被丢弃，继续读到正确响应', 0, () => {
      const stream = new MockByteStream();
      // CanoKey 场景：先重复上一条响应（seq=1，与请求 seq=0 不符），正确响应在后
      stream.respondBytes(MockByteStream.dataBlock(1, '9000'));
      stream.respondBytes(MockByteStream.dataBlock(0, '797d0133'));
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then((resp: Uint8Array) => {
        expect(resp[0]).assertEqual(0x79);
        expect(resp[3]).assertEqual(0x33);
      });
    });

    it('时间扩展响应（bStatus=0x11）被跳过，等待真正响应', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, '', 0, 0x11)); // time extension
      stream.respondBytes(MockByteStream.dataBlock(0, '9000'));
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then((resp: Uint8Array) => {
        expect(resp[0]).assertEqual(0x90);
      });
    });

    it('连续乱序响应超过容忍上限时报错', 0, () => {
      const stream = new MockByteStream();
      const protocol = new CcidProtocol(stream);
      for (let i = 0; i < 5; i++) {
        stream.respondBytes(MockByteStream.dataBlock(7, '9000')); // 全部与期望 seq=0 不符
      }
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then(() => {
        expect(true).assertEqual(false);
      }).catch((e: Error) => {
        expect(e.message).assertContain('seq mismatch');
      });
    });

    it('seq 随请求递增', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, '9000'));
      stream.respondBytes(MockByteStream.dataBlock(1, '9000'));
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101'))
        .then(() => protocol.transmit(MockByteStream.hex('00c00000')))
        .then(() => {
          expect(stream.sent[0][6]).assertEqual(0);
          expect(stream.sent[1][6]).assertEqual(1);
        });
    });

    it('powerOff 发送 0x63 且接受 SlotStatus 响应', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.slotStatus(0));
      const protocol = new CcidProtocol(stream);
      return protocol.powerOff().then(() => {
        expect(stream.sent[0][0]).assertEqual(CcidMsgType.ICC_POWER_OFF);
        expect(stream.sent[0][1]).assertEqual(0);
      });
    });

    it('abort 发送 0x6A 且接受 SlotStatus 响应', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.slotStatus(0));
      const protocol = new CcidProtocol(stream);
      return protocol.abort().then(() => {
        expect(stream.sent[0][0]).assertEqual(CcidMsgType.ABORT);
      });
    });

    it('响应被分片（两次 read）时仍正确解析', 0, () => {
      const stream = new MockByteStream();
      const full = MockByteStream.dataBlock(0, '797d0133745588aa');
      stream.respondBytes(full.subarray(0, 12)); // 头 10 + 2 字节
      stream.respondBytes(full.subarray(12)); // 剩余 6 字节
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then((resp: Uint8Array) => {
        expect(resp.length).assertEqual(8);
        expect(resp[7]).assertEqual(0xaa);
      });
    });

    it('背靠背响应：一次 read 返回两条消息，第二条进入缓冲供下次使用', 0, () => {
      const stream = new MockByteStream();
      const first = MockByteStream.dataBlock(0, '9000');
      const second = MockByteStream.dataBlock(1, '797d0133');
      const joined = new Uint8Array(first.length + second.length);
      joined.set(first, 0);
      joined.set(second, first.length);
      stream.respondBytes(joined);
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101'))
        .then((resp1: Uint8Array) => {
          expect(resp1[0]).assertEqual(0x90);
          return protocol.transmit(MockByteStream.hex('00c00000'));
        })
        .then((resp2: Uint8Array) => {
          expect(resp2[0]).assertEqual(0x79);
        });
    });

    it('链式响应：bChainParameter>0 时继续读取并拼接', 0, () => {
      const stream = new MockByteStream();
      stream.respondBytes(MockByteStream.dataBlock(0, 'aaaaaaaaaaaaaaaa', 1));
      stream.respondBytes(MockByteStream.dataBlock(1, 'bbbbbbbbbbbbbbbb', 0));
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then((resp: Uint8Array) => {
        expect(resp.length).assertEqual(16);
        expect(resp[0]).assertEqual(0xaa);
        expect(resp[15]).assertEqual(0xbb);
      });
    });

    it('超长 APDU（>261 字节）拒绝发送', 0, () => {
      const stream = new MockByteStream();
      const apdu = new Uint8Array(262);
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(apdu).then(() => {
        expect(true).assertEqual(false);
      }).catch((e: Error) => {
        expect(e.message).assertContain('too long');
        expect(stream.sent.length).assertEqual(0);
      });
    });

    it('write 不完整时报错', 0, () => {
      const stream = new MockByteStream();
      stream.failWrite = true;
      stream.respondBytes(MockByteStream.dataBlock(0, '9000'));
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then(() => {
        expect(true).assertEqual(false);
      }).catch((e: Error) => {
        expect(e.message).assertContain('write incomplete');
      });
    });

    it('dwLength 支持多字节小端（>255 字节响应）', 0, () => {
      const stream = new MockByteStream();
      const data = new Uint8Array(300);
      for (let i = 0; i < data.length; i++) {
        data[i] = i & 0xFF;
      }
      const msg = new Uint8Array(CcidProtocol.HEADER_LEN + data.length);
      msg[0] = CcidMsgType.DATA_BLOCK;
      msg[1] = 0x2c; // 300 = 0x012c
      msg[2] = 0x01;
      msg[5] = 0;
      msg[6] = 0;
      msg.set(data, CcidProtocol.HEADER_LEN);
      stream.respondBytes(msg);
      const protocol = new CcidProtocol(stream);
      return protocol.transmit(MockByteStream.hex('00c00000')).then((resp: Uint8Array) => {
        expect(resp.length).assertEqual(300);
        expect(resp[299]).assertEqual(0x2b);
      });
    });

    it('链式块数超上限时报错（防御死循环）', 0, () => {
      const stream = new MockByteStream();
      const protocol = new CcidProtocol(stream);
      for (let i = 0; i < 9; i++) {
        stream.respondBytes(MockByteStream.dataBlock(i, 'aa', 1));
      }
      return protocol.transmit(MockByteStream.hex('00a4040005a0000005272101')).then(() => {
        expect(true).assertEqual(false);
      }).catch((e: Error) => {
        expect(e.message).assertContain('chain too long');
      });
    });
  });
}
