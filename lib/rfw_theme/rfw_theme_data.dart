import 'package:flutter/material.dart';

import '../models.dart';

class RfwHomeDataInput {
  const RfwHomeDataInput({
    required this.categories,
    required this.category,
    required this.items,
    required this.recommend,
    required this.filters,
    required this.selectedFilters,
    this.displayStyle = 'grid',
    this.showFilters = false,
    this.loading = false,
    this.errorMessage = '',
    this.totalLabel = '',
    this.sourceName = '',
    this.screenWidth = 390,
    this.gridColumns = 3,
    this.largeGridColumns = 2,
    this.bannerColumns = 1,
    this.isLandscape = false,
    this.canNavigateBack = false,
  });

  final List<CatalogCategory> categories;
  final String category;
  final List<Drama> items;
  final List<Drama> recommend;
  final List<CatalogFilterGroup> filters;
  final Map<String, String> selectedFilters;
  final String displayStyle;
  final bool showFilters;
  final bool loading;
  final String errorMessage;
  final String totalLabel;
  final String sourceName;
  final double screenWidth;
  final int gridColumns;
  final int largeGridColumns;
  final int bannerColumns;
  final bool isLandscape;
  final bool canNavigateBack;
}

Map<String, Object?> buildRfwHomeData(RfwHomeDataInput input) {
  final width = input.screenWidth > 0 ? input.screenWidth : 390.0;
  final filterPanelHeight = input.filters.isEmpty
      ? 0.0
      : input.filters.length * 40.0 + 12.0;
  final stickyHeaderHeight =
      84.0 + (input.showFilters ? filterPanelHeight : 0.0);
  final recommend = input.recommend
      .asMap()
      .entries
      .map((entry) => _itemMap(entry.key, entry.value))
      .toList();
  final firstCover = recommend.isNotEmpty
      ? recommend.first['pic'] as String? ?? ''
      : input.items.isNotEmpty
      ? input.items.first.cover
      : '';
  return <String, Object?>{
    'icons': <String, Object?>{
      'expand': Icons.keyboard_arrow_down.codePoint,
      'refresh': Icons.refresh.codePoint,
      'filter': Icons.filter_list.codePoint,
      'layout': Icons.grid_view.codePoint,
      'topBar': Icons.tune.codePoint,
      'open': Icons.open_in_new.codePoint,
      'back': Icons.arrow_back.codePoint,
      'search': Icons.search.codePoint,
    },
    'displayStyle': input.displayStyle,
    'gridColumns': input.gridColumns,
    'largeGridColumns': input.largeGridColumns,
    'bannerColumns': input.bannerColumns,
    'wideListRatio': width / 128.0,
    'textListRatio': width / 52.0,
    'showFilters': input.showFilters,
    'hasRecommend': recommend.isNotEmpty,
    'hasManyClasses': input.categories.length > 6,
    'hasFilters': input.filters.isNotEmpty,
    'errorMessage': input.errorMessage,
    'items': input.items
        .asMap()
        .entries
        .map((entry) => _itemMap(entry.key, entry.value))
        .toList(),
    'classes': input.categories
        .map(
          (category) => <String, Object?>{
            'typeId': category.id,
            'typeName': category.name,
            'selected': category.id == input.category,
          },
        )
        .toList(),
    'filters': input.filters
        .map(
          (group) => <String, Object?>{
            'key': group.key,
            'name': group.name,
            'canExpand': group.options.length > 6,
            'options': <Object?>[
              <String, Object?>{
                'filterKey': group.key,
                'value': '',
                'name': '全部',
                'selected': (input.selectedFilters[group.key] ?? '').isEmpty,
              },
              ...group.options.map(
                (option) => <String, Object?>{
                  'filterKey': group.key,
                  'value': option.id,
                  'name': option.name,
                  'selected': input.selectedFilters[group.key] == option.id,
                },
              ),
            ],
          },
        )
        .toList(),
    'home': <String, Object?>{'recommend': recommend},
    'stickyHeaderHeight': stickyHeaderHeight,
    'filterPanelHeight': filterPanelHeight,
    'loading': input.loading,
    'source': input.sourceName,
    'totalLabel': input.totalLabel,
    'heroHeight': recommend.isEmpty ? 0.0 : 150.0,
    'immersive': <String, Object?>{
      'imageUrl': firstCover,
      'primaryColor': 0xFF8A7CFF,
      'secondaryColor': 0xFF4A3A8A,
      'backgroundColor': 0xFF0D0D19,
    },
    'canNavigateBack': input.canNavigateBack,
    'isLandscape': input.isLandscape,
  };
}

Map<String, Object?> _itemMap(int index, Drama drama) {
  final remarks = drama.episodes > 0
      ? '${drama.episodes}集'
      : drama.heat.isNotEmpty
      ? drama.heat
      : drama.category;
  return <String, Object?>{
    'index': index,
    'name': drama.title,
    'pic': drama.cover,
    'remarks': remarks,
    'selected': false,
    'rankLabel': '${index + 1}',
    'typeName': drama.category,
    'typeId': '',
    'year': drama.onlineDate,
    'indexLabel': '${index + 1}',
    'style': '',
    'titleLogo': '',
    'vodTag': '',
  };
}
