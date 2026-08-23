import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { OtpauthParser } from '../main/ets/utils/OtpauthParser';
import { OtpType } from '../main/ets/model/Credential';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('parseOtpauth 标准 URI 可解析', 0, () => {
      const out = OtpauthParser.parseAny('otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&period=30');
      expect(out.credentials.length).assertEqual(1);
      expect(out.credentials[0].account).assertEqual('alice@example.com');
      expect(out.credentials[0].issuer).assertEqual('Example');
    });
    it('parseOtpauth 不含前缀的 URI 可解析', 0, () => {
      const out = OtpauthParser.parseAny('totp/Issuer:user?secret=JBSWY3DPEHPK3PXP');
      expect(out.credentials.length).assertEqual(1);
      expect(out.credentials[0].issuer).assertEqual('Issuer');
    });
    it('parseOtpauth hotp 类型识别', 0, () => {
      const out = OtpauthParser.parseAny('otpauth://hotp/Issuer:user?secret=JBSWY3DPEHPK3PXP&counter=7');
      expect(out.credentials[0].otpType).assertEqual(OtpType.HOTP);
    });
    it('不支持的内容抛错', 0, () => {
      let threw = false;
      try {
        OtpauthParser.parseAny('just-a-plain-text');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
    it('缺少 secret 抛错', 0, () => {
      let threw = false;
      try {
        OtpauthParser.parseAny('otpauth://totp/Issuer:user?issuer=Issuer');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}