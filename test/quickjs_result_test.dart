import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/quickjs_bridge.dart';

void main() {
  test('quickjs result parses ok and error', () {
    final ok = QuickJSResult.fromJson({
      'ok': true,
      'result': {'a': 1},
    });
    expect(ok.ok, true);
    expect((ok.result as Map)['a'], 1);
    final err = QuickJSResult.fromJson({
      'ok': false,
      'error': 'InternalError: interrupted',
    });
    expect(err.ok, false);
    expect(err.error, contains('interrupted'));
  });
}
