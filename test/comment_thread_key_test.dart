import 'package:duanju_app/comment_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same drama and episode give the same thread key', () {
    expect(commentThreadKey('drama-1', 'ep-3'), commentThreadKey('drama-1', 'ep-3'));
  });

  test('different episodes of the same drama give different keys', () {
    expect(commentThreadKey('drama-1', 'ep-3'), isNot(commentThreadKey('drama-1', 'ep-4')));
  });

  test('same episode number of different dramas gives different keys', () {
    expect(commentThreadKey('drama-1', 'ep-3'), isNot(commentThreadKey('drama-2', 'ep-3')));
  });
}
