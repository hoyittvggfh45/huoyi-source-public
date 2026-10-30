import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('oversea source retags a domestic prefixed id', () {
    final drama = Drama.fromJson({
      'id': 'hongguo:123',
      'source': 'hongguo-oversea',
    });
    expect(drama.id, 'hongguo-oversea:123');
  });

  test('domestic source retags an oversea prefixed id', () {
    final drama = Drama.fromJson({
      'id': 'hongguo-oversea:123',
      'source': 'hongguo',
    });
    expect(drama.id, 'hongguo:123');
  });

  test('matching prefix and bare ids', () {
    expect(
      Drama.fromJson({'id': 'hongguo-oversea:123', 'source': 'hongguo-oversea'})
          .id,
      'hongguo-oversea:123',
    );
    expect(
      Drama.fromJson({'id': '123', 'source': 'hongguo-oversea'}).id,
      'hongguo-oversea:123',
    );
    expect(Drama.fromJson({'id': '', 'source': 'hongguo-oversea'}).id, '');
  });

  test('foreign sources and urls are untouched', () {
    expect(
      Drama.fromJson({'id': 'hongguo:123', 'source': 'huangdou'}).id,
      'hongguo:123',
    );
    expect(
      Drama.fromJson({
        'id': 'https://example.com/123',
        'source': 'hongguo-oversea',
      }).id,
      'https://example.com/123',
    );
  });

  test('peers are retagged through fromJson', () {
    final drama = Drama.fromJson({
      'id': 'hongguo-oversea:1',
      'source': 'hongguo-oversea',
      'peers': [
        {'id': 'hongguo:2', 'source': 'hongguo-oversea'},
      ],
    });
    expect(drama.peers.single.id, 'hongguo-oversea:2');
  });
}
