import 'package:duanju_app/aggregation_dashboard.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SourceSite _site(String id, String name) => SourceSite(
  id,
  name,
  '',
  section: SourceSite.sectionVideo,
  origin: SourceSite.originImport,
);

List<AggregationStationEntry> _entries() {
  final resolved = {
    'jar:zakatv:hgtv': _site('jar:zakatv:hgtv', '红果镜像'),
    'jar:zakatv:go_lego': _site('jar:zakatv:go_lego', 'Lego'),
  };
  return [
    for (final def in aggregationStationDefs)
      AggregationStationEntry(def: def, site: resolved[def.siteId]),
  ];
}

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('聚合仪表盘按栏目分组并区分启用与未启用', (tester) async {
    final opened = <SourceSite>[];
    await tester.pumpWidget(
      _wrap(
        AggregationDashboard(
          entries: _entries(),
          onOpenStation: opened.add,
          onSearch: (_) async => [],
          onOpenResult: (_) {},
          onOpenAi: () {},
          onOpenLz: () {},
          onOpenExperiment: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('聚合'), findsOneWidget);
    expect(find.text('红果镜像'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aggregation-station-hgtv')));
    await tester.pumpAndSettle();
    expect(opened.map((site) => site.id), ['jar:zakatv:hgtv']);
    await tester.tap(find.byKey(const ValueKey('aggregation-column-novel')));
    await tester.pumpAndSettle();
    expect(find.text('Lego'), findsOneWidget);
    expect(find.text('NovelBd'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aggregation-column-tools')));
    await tester.pumpAndSettle();
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('lz 规则管理'), findsOneWidget);
    expect(find.text('实验区'), findsOneWidget);
  });

  testWidgets('聚合搜索出结果并可打开', (tester) async {
    final queries = <String>[];
    final opened = <Drama>[];
    final drama = Drama(
      id: 'd1',
      source: 'jar:zakatv:hgtv',
      title: '测试剧',
    );
    await tester.pumpWidget(
      _wrap(
        AggregationDashboard(
          entries: _entries(),
          onOpenStation: (_) {},
          onSearch: (query) async {
            queries.add(query);
            return [drama];
          },
          onOpenResult: opened.add,
          onOpenAi: () {},
          onOpenLz: () {},
          onOpenExperiment: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('aggregation-search-field')),
      '测试',
    );
    await tester.tap(find.byKey(const ValueKey('aggregation-search-button')));
    await tester.pumpAndSettle();
    expect(queries, ['测试']);
    expect(find.text('测试剧'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aggregation-result-d1')));
    await tester.pumpAndSettle();
    expect(opened, [drama]);
  });

  testWidgets('工具入口回调逐个触发', (tester) async {
    var ai = 0;
    var lz = 0;
    var experiment = 0;
    var settings = 0;
    await tester.pumpWidget(
      _wrap(
        AggregationDashboard(
          entries: _entries(),
          onOpenStation: (_) {},
          onSearch: (_) async => [],
          onOpenResult: (_) {},
          onOpenAi: () => ai++,
          onOpenLz: () => lz++,
          onOpenExperiment: () => experiment++,
          onOpenSettings: () => settings++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('aggregation-settings-button')),
    );
    await tester.pumpAndSettle();
    expect(settings, 1);
    await tester.tap(find.byKey(const ValueKey('aggregation-column-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aggregation-tool-ai')));
    await tester.tap(find.byKey(const ValueKey('aggregation-tool-lz')));
    await tester.tap(find.byKey(const ValueKey('aggregation-tool-experiment')));
    await tester.tap(find.byKey(const ValueKey('aggregation-tool-settings')));
    await tester.pumpAndSettle();
    expect(ai, 1);
    expect(lz, 1);
    expect(experiment, 1);
    expect(settings, 2);
  });
}
