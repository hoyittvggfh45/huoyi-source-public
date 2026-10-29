import 'package:duanju_app/comment_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('identity generates an id and a default nickname on first ensure', () async {
    CommentIdentity.instance.debugReset();
    SharedPreferences.setMockInitialValues({});
    await CommentIdentity.instance.ensure();
    final id = CommentIdentity.instance.userId;
    expect(id.length, 36);
    expect(id[8], '-');
    expect(id[13], '-');
    expect(id[18], '-');
    expect(id[23], '-');
    expect(
      CommentIdentity.instance.nickname,
      '用户${id.substring(id.length - 4)}',
    );
    expect(CommentIdentity.instance.ready, isTrue);
  });

  test('ensure keeps the stored id and rename persists valid nicknames', () async {
    CommentIdentity.instance.debugReset();
    SharedPreferences.setMockInitialValues({
      commentUserIdKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      commentNicknameKey: '老名字',
    });
    await CommentIdentity.instance.ensure();
    expect(
      CommentIdentity.instance.userId,
      'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    );
    expect(CommentIdentity.instance.nickname, '老名字');
    expect(await CommentIdentity.instance.rename('新名字'), isTrue);
    expect(CommentIdentity.instance.nickname, '新名字');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(commentNicknameKey), '新名字');
    expect(await CommentIdentity.instance.rename(''), isFalse);
    expect(await CommentIdentity.instance.rename('x' * 21), isFalse);
    expect(CommentIdentity.instance.nickname, '新名字');
    await CommentIdentity.instance.ensure();
    expect(
      CommentIdentity.instance.userId,
      'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
    );
  });

  test('nickname validation trims and caps length', () {
    expect(validCommentNickname('名字'), isTrue);
    expect(validCommentNickname(''), isFalse);
    expect(validCommentNickname('   '), isFalse);
    expect(validCommentNickname('x' * 21), isFalse);
    expect(validCommentNickname('x' * 20), isTrue);
  });
}
