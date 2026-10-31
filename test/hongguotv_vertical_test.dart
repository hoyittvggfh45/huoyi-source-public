import 'package:duanju_app/hongguotv_vertical_screen.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hongguotv episode groups of twenty', () {
    expect(hongguotvGroupCount(0), 0);
    expect(hongguotvGroupCount(1), 1);
    expect(hongguotvGroupCount(20), 1);
    expect(hongguotvGroupCount(21), 2);
    expect(hongguotvGroupCount(78), 4);
    expect(hongguotvGroupRange(0, 78), (start: 1, end: 20));
    expect(hongguotvGroupRange(3, 78), (start: 61, end: 78));
    expect(hongguotvGroupRange(0, 5), (start: 1, end: 5));
  });

  test('hongguotv ui labels', () {
    expect(hongguotvUiLabel('existing'), '现有界面');
    expect(hongguotvUiLabel('vertical'), '竖版界面');
    expect(hongguotvUiLabel('official'), '官方界面');
    expect(hongguotvUiLabel('unknown'), '现有界面');
  });

  test('hongguotv registered as drama source', () {
    final site = SourceSite.byId('hongguotv');
    expect(site.id, 'hongguotv');
    expect(site.name, '红果TV');
    expect(site.isDramaSection, isTrue);
    expect(site.onlineSearch, isTrue);
    expect(SourceSite.knownValues.any((item) => item.id == 'hongguotv'),
        isTrue);
    expect(
        SourceSite.allValues.any((item) => item.id == 'hongguotv'), isTrue);
  });
}
