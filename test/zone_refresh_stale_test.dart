import 'package:duanju_app/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 30, 9, 30);
  test('no fetch record never refreshes on restore', () {
    expect(shouldSilentRefreshOnRestore(null, now), isFalse);
  });
  test('fresh snapshot never refreshes on restore', () {
    expect(
      shouldSilentRefreshOnRestore(
        now.subtract(const Duration(minutes: 1)),
        now,
      ),
      isFalse,
    );
    expect(
      shouldSilentRefreshOnRestore(
        now.subtract(const Duration(minutes: 4, seconds: 59)),
        now,
      ),
      isFalse,
    );
  });
  test('stale snapshot never refreshes on restore', () {
    expect(
      shouldSilentRefreshOnRestore(
        now.subtract(const Duration(minutes: 5)),
        now,
      ),
      isFalse,
    );
    expect(
      shouldSilentRefreshOnRestore(
        now.subtract(const Duration(minutes: 30)),
        now,
      ),
      isFalse,
    );
  });
}
