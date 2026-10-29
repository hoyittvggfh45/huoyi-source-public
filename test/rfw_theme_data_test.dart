import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/rfw_theme/rfw_theme_data.dart';

void main() {
  const first = Drama(
    id: 'd1',
    source: 'hongguo',
    title: '第一部',
    cover: 'https://example.com/cover1.jpg',
    episodes: 120,
    category: '古装',
    onlineDate: '2026',
  );
  const second = Drama(
    id: 'd2',
    source: 'hongguo',
    title: '第二部',
    cover: 'https://example.com/cover2.jpg',
    heat: '9.8分',
    category: '现代',
  );

  Map<String, Object?> buildData({
    List<CatalogCategory> categories = const [
      CatalogCategory('', '全部'),
      CatalogCategory('guzhuang', '古装'),
    ],
    String category = 'guzhuang',
    List<Drama> items = const [first, second],
    List<Drama> recommend = const [first],
    List<CatalogFilterGroup> filters = const [],
    Map<String, String> selectedFilters = const {},
    String displayStyle = 'grid',
    bool showFilters = false,
    double screenWidth = 390,
  }) {
    return buildRfwHomeData(
      RfwHomeDataInput(
        categories: categories,
        category: category,
        items: items,
        recommend: recommend,
        filters: filters,
        selectedFilters: selectedFilters,
        displayStyle: displayStyle,
        showFilters: showFilters,
        screenWidth: screenWidth,
      ),
    );
  }

  test('items carry index name pic remarks rank and year', () {
    final data = buildData();
    final items = data['items'] as List;
    final firstMap = items.first as Map;
    expect(firstMap['index'], 0);
    expect(firstMap['name'], '第一部');
    expect(firstMap['pic'], 'https://example.com/cover1.jpg');
    expect(firstMap['remarks'], '120集');
    expect(firstMap['rankLabel'], '1');
    expect(firstMap['year'], '2026');
    final secondMap = items[1] as Map;
    expect(secondMap['remarks'], '9.8分');
    expect(secondMap['selected'], false);
  });

  test('classes mark the selected category', () {
    final data = buildData();
    final classes = data['classes'] as List;
    expect((classes[0] as Map)['selected'], false);
    expect((classes[1] as Map)['typeId'], 'guzhuang');
    expect((classes[1] as Map)['selected'], true);
    expect(data['hasManyClasses'], false);
  });

  test('filters prepend an all option and mark selection', () {
    const filters = [
      CatalogFilterGroup('area', '地区', [
        CatalogFilterOption('cn', '大陆'),
        CatalogFilterOption('hk', '香港'),
      ]),
    ];
    final data = buildData(
      filters: filters,
      selectedFilters: const {'area': 'hk'},
    );
    final groups = data['filters'] as List;
    final group = groups.first as Map;
    expect(group['key'], 'area');
    expect(group['canExpand'], false);
    final options = group['options'] as List;
    expect(options.length, 3);
    expect((options[0] as Map)['value'], '');
    expect((options[0] as Map)['name'], '全部');
    expect((options[0] as Map)['selected'], false);
    expect((options[2] as Map)['selected'], true);
    expect(data['hasFilters'], true);
  });

  test('ratios follow screen width and header heights add up', () {
    final data = buildData(screenWidth: 390);
    expect(data['wideListRatio'], 390 / 128.0);
    expect(data['textListRatio'], 390 / 52.0);
    expect(data['stickyHeaderHeight'], 84.0);
    expect(data['filterPanelHeight'], 0.0);
    const filters = [
      CatalogFilterGroup('area', '地区', [CatalogFilterOption('cn', '大陆')]),
    ];
    final filtered = buildData(filters: filters, showFilters: true);
    expect(filtered['filterPanelHeight'], 52.0);
    expect(filtered['stickyHeaderHeight'], 136.0);
  });

  test('icons are material code points and recommend is exposed', () {
    final data = buildData();
    final icons = data['icons'] as Map;
    expect(icons['search'], Icons.search.codePoint);
    expect(icons['refresh'], Icons.refresh.codePoint);
    expect(data['hasRecommend'], true);
    expect(data['heroHeight'], 150.0);
    final home = data['home'] as Map;
    expect((home['recommend'] as List).length, 1);
    final immersive = data['immersive'] as Map;
    expect(immersive['imageUrl'], 'https://example.com/cover1.jpg');
    final empty = buildData(recommend: const []);
    expect(empty['hasRecommend'], false);
    expect(empty['heroHeight'], 0.0);
  });

  test('display style and labels pass through', () {
    final data = buildData(displayStyle: 'list');
    expect(data['displayStyle'], 'list');
    expect(data['gridColumns'], 3);
    expect(data['largeGridColumns'], 2);
    expect(data['bannerColumns'], 1);
    expect(data['loading'], false);
    expect(data['errorMessage'], '');
  });
}
