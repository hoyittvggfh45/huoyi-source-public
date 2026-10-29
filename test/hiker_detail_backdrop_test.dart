import 'package:duanju_app/hiker_miniapp/hiker_detail_backdrop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first non-empty still wins over poster', () {
    expect(
      hikerDetailBackdropUrl(
        stills: ['https://example.invalid/still1.jpg'],
        poster: 'https://example.invalid/poster.jpg',
      ),
      'https://example.invalid/still1.jpg',
    );
  });

  test('empty stills are skipped', () {
    expect(
      hikerDetailBackdropUrl(
        stills: ['', 'https://example.invalid/still2.jpg'],
        poster: 'https://example.invalid/poster.jpg',
      ),
      'https://example.invalid/still2.jpg',
    );
  });

  test('poster is used when no stills exist', () {
    expect(
      hikerDetailBackdropUrl(
        stills: const [],
        poster: 'https://example.invalid/poster.jpg',
      ),
      'https://example.invalid/poster.jpg',
    );
  });

  test('empty string when neither stills nor poster exist', () {
    expect(hikerDetailBackdropUrl(stills: const [], poster: ''), '');
  });

  test('poster wins for poster element', () {
    expect(
      hikerDetailPosterUrl(
        stills: ['https://example.invalid/still1.jpg'],
        poster: 'https://example.invalid/poster.jpg',
      ),
      'https://example.invalid/poster.jpg',
    );
  });

  test('first non-empty still fills in when poster is empty', () {
    expect(
      hikerDetailPosterUrl(
        stills: ['', 'https://example.invalid/still2.jpg'],
        poster: '',
      ),
      'https://example.invalid/still2.jpg',
    );
  });

  test('poster element is empty when neither poster nor stills exist', () {
    expect(hikerDetailPosterUrl(stills: const [], poster: ''), '');
  });
}
