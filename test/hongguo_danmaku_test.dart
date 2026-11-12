import 'package:duanju_app/hongguo_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hongguoNumericId', () {
    test('extracts the series id from a drama id', () {
      expect(
        hongguoNumericId('hongguo:7706075648741084185'),
        '7706075648741084185',
      );
    });

    test('extracts the video id from a compound episode id', () {
      expect(
        hongguoNumericId('hongguo:7706075648741084185:7706075655309364248'),
        '7706075655309364248',
      );
    });

    test('accepts a bare numeric id', () {
      expect(
        hongguoNumericId('7698294694886788121'),
        '7698294694886788121',
      );
    });

    test('rejects short or non-numeric ids', () {
      expect(hongguoNumericId('hongguo:123'), isNull);
      expect(hongguoNumericId('hongguo:abc'), isNull);
      expect(hongguoNumericId(''), isNull);
      expect(hongguoNumericId('hongguo:'), isNull);
      expect(hongguoNumericId('hongguo:7706075648741084185:abc'), isNull);
    });

    test('trims surrounding whitespace', () {
      expect(
        hongguoNumericId('  hongguo:7706075648741084185  '),
        '7706075648741084185',
      );
    });
  });
}
