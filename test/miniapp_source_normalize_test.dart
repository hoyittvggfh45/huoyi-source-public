import 'package:duanju_app/miniapp/renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry id passes through unchanged', () {
    expect(miniappNormalizedSourceId('v_senlin'), 'v_senlin');
  });

  test('slot id normalizes to the registry id', () {
    expect(miniappNormalizedSourceId('yh_senlin'), 'v_senlin');
  });

  test('display name with and without the adult mark normalizes', () {
    expect(miniappNormalizedSourceId('🔞森林资源'), 'v_senlin');
    expect(miniappNormalizedSourceId('森林资源'), 'v_senlin');
  });

  test('unknown identifiers pass through untouched', () {
    expect(miniappNormalizedSourceId('no_such_source'), 'no_such_source');
    expect(miniappNormalizedSourceId(''), '');
  });

  test('effective drama id keeps prefixed ids and prefixes bare ids', () {
    expect(
      miniappEffectiveDramaId('v_senlin', 'v_senlin:123'),
      'v_senlin:123',
    );
    expect(miniappEffectiveDramaId('v_senlin', '123'), 'v_senlin:123');
    expect(
      miniappEffectiveDramaId('v_senlin', 'yh_senlin:123'),
      'v_senlin:123',
    );
  });

  test('effective drama id leaves urls, empty and foreign ids alone', () {
    expect(
      miniappEffectiveDramaId('v_senlin', 'https://example.com/1.mp4'),
      'https://example.com/1.mp4',
    );
    expect(miniappEffectiveDramaId('v_senlin', ''), '');
    expect(
      miniappEffectiveDramaId('v_senlin', 'other:123'),
      'other:123',
    );
  });
}
