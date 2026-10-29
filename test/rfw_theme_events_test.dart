import 'package:duanju_app/rfw_theme/rfw_theme_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('openItem requires a valid index', () {
    final action = parseRfwThemeEvent('openItem', {'index': 3});
    expect(action?.kind, RfwThemeActionKind.openItem);
    expect(action?.index, 3);
    expect(parseRfwThemeEvent('openItem', {}), isNull);
    expect(parseRfwThemeEvent('openItem', {'index': -1}), isNull);
    expect(parseRfwThemeEvent('openItem', {'index': '3'}), isNull);
  });

  test('openRecommend requires a valid index', () {
    final action = parseRfwThemeEvent('openRecommend', {'index': 0});
    expect(action?.kind, RfwThemeActionKind.openRecommend);
    expect(action?.index, 0);
    expect(parseRfwThemeEvent('openRecommend', {'index': -2}), isNull);
  });

  test('selectType maps to selectCategory', () {
    final action = parseRfwThemeEvent('selectType', {'typeId': 'guzhuang'});
    expect(action?.kind, RfwThemeActionKind.selectCategory);
    expect(action?.typeId, 'guzhuang');
    expect(parseRfwThemeEvent('selectType', {}), isNull);
  });

  test('selectFilter carries key and value', () {
    final action = parseRfwThemeEvent('selectFilter', {
      'key': 'area',
      'value': 'cn',
    });
    expect(action?.kind, RfwThemeActionKind.selectFilter);
    expect(action?.key, 'area');
    expect(action?.value, 'cn');
    expect(parseRfwThemeEvent('selectFilter', {'key': 'area'}), isNull);
  });

  test('plain events map to their kinds', () {
    expect(
      parseRfwThemeEvent('toggleFilters', {})?.kind,
      RfwThemeActionKind.toggleFilters,
    );
    expect(
      parseRfwThemeEvent('showDisplayStylePicker', {})?.kind,
      RfwThemeActionKind.showDisplayStylePicker,
    );
    expect(parseRfwThemeEvent('refresh', {})?.kind, RfwThemeActionKind.refresh);
    expect(
      parseRfwThemeEvent('showCategoryPicker', {})?.kind,
      RfwThemeActionKind.showCategoryPicker,
    );
    expect(
      parseRfwThemeEvent('showSourcePicker', {})?.kind,
      RfwThemeActionKind.showSourcePicker,
    );
    expect(
      parseRfwThemeEvent('openSearch', {})?.kind,
      RfwThemeActionKind.openSearch,
    );
    expect(
      parseRfwThemeEvent('navigateBack', {})?.kind,
      RfwThemeActionKind.navigateBack,
    );
  });

  test('newly mapped theme events', () {
    final longPress = parseRfwThemeEvent('longPressItem', {'index': 1});
    expect(longPress?.kind, RfwThemeActionKind.longPressItem);
    expect(longPress?.index, 1);
    expect(parseRfwThemeEvent('longPressItem', {}), isNull);
    expect(
      parseRfwThemeEvent('showFilterPicker', {})?.kind,
      RfwThemeActionKind.showFilterPicker,
    );
    expect(
      parseRfwThemeEvent('showNativeAppBar', {})?.kind,
      RfwThemeActionKind.showNativeAppBar,
    );
    expect(
      parseRfwThemeEvent('showApiConfigPicker', {})?.kind,
      RfwThemeActionKind.showApiConfigPicker,
    );
  });

  test('unmapped events are ignored', () {
    expect(parseRfwThemeEvent('openPush', {}), isNull);
    expect(parseRfwThemeEvent('openHistory', {}), isNull);
    expect(parseRfwThemeEvent('openFavorite', {}), isNull);
    expect(parseRfwThemeEvent('unknownEvent', {}), isNull);
  });
}
