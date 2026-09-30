import 'package:flutter_test/flutter_test.dart';
import 'package:sy_im_flutter_sdk/sy_im.dart';

void main() {
  test('codes match backend errcode and native SDKs', () {
    expect(SyImErrorCode.imNotEnabled, 3001);
    expect(SyImErrorCode.quotaMau, 3003);
    expect(SyImErrorCode.quotaMessages, 3004);
    expect(SyImErrorCode.trialRetired, 4003);
    expect(SyImErrorCode.sensitiveRejected, 4005);
    expect(SyImErrorCode.contentRejected, 4006);
    expect(SyImErrorCode.credentialSuspended, 4031);
    expect(SyImErrorCode.credentialRevoked, 4032);
    expect(SyImErrorCode.credentialExpired, 4033);
    expect(SyImErrorCode.rateLimited, 4290);
  });

  test('success responses decode data', () {
    expect(decodeControlPlaneResponse(200, '{"code":0,"data":{"token":"t"}}'),
        {'token': 't'});
    expect(decodeControlPlaneResponse(200, ''), isEmpty);
    expect(decodeControlPlaneResponse(200, '{"code":0,"data":[1]}'), {
      'value': [1]
    });
  });

  test('business and http failures carry codes', () {
    SyImControlPlaneException fail(int status, String body) {
      try {
        decodeControlPlaneResponse(status, body);
      } on SyImControlPlaneException catch (e) {
        return e;
      }
      throw StateError('expected failure');
    }

    final rejected = fail(200, '{"code":4006,"msg":"内容审核拒绝"}');
    expect(rejected.code, 4006);
    expect(rejected.httpStatus, 200);
    expect(rejected.message, '内容审核拒绝');
    expect(rejected.isContentRejected, isTrue);
    expect(fail(200, '{"code":4032,"msg":"x"}').isCredentialBlocked, isTrue);
    expect(fail(429, '').code, 429);
    expect(fail(429, '{"code":4290,"msg":"slow"}').code,
        SyImErrorCode.rateLimited);
    expect(fail(502, '<html>').code, 502);
    expect(fail(502, '<html>'), isA<Exception>());
  });
}
