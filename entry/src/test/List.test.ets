import localUnitTest from './LocalUnit.test';
import ccidProtocolTest from './CcidProtocol.test';

export default function testsuite() {
  localUnitTest();
  ccidProtocolTest();
}