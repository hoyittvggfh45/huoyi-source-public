import 'models.dart';

const Map<String, String> hongguoDiscoveryLabels = {
  'genre': '类型',
  'category_dim_theme': '主题',
  'category_dim_role': '设定',
  'category_dim_epoch': '背景',
  'sort': '推荐',
  'gender': '受众',
  'online_time': '时间',
  'creation_status': '状态',
};

const List<({String id, String label})> hongguoDiscoveryGenres = [
  (id: 'short_play', label: '真人剧'),
  (id: 'comic_series', label: '漫剧'),
  (id: 'ai_series', label: 'AI剧'),
];

bool hongguoDiscoveryValidId(String value) =>
    RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(value);

class HongguoDiscoverySelection {
  const HongguoDiscoverySelection([this.values = const {}]);

  final Map<String, String> values;

  HongguoDiscoverySelection choose(String type, String id) {
    if (!hongguoDiscoveryLabels.containsKey(type)) return this;
    if (id.isNotEmpty && !hongguoDiscoveryValidId(id)) return this;
    final next = type == 'genre' ? <String, String>{} : Map.of(values);
    if (id.isEmpty) {
      next.remove(type);
    } else {
      next[type] = id;
    }
    return HongguoDiscoverySelection(Map.unmodifiable(next));
  }

  String get genre => values['genre'] ?? '';

  Map<String, Object?> requestBody({
    int offset = 0,
    String sessionId = '',
    bool firstPage = true,
  }) {
    final selected = <String, List<String>>{};
    for (final key in hongguoDiscoveryLabels.keys) {
      final value = values[key];
      selected[key] = value == null ? const [] : [value];
    }
    final genre = values['genre'];
    return {
      'offset': offset,
      'limit': 24,
      'need_selector_panel': firstPage,
      'select_items': selected,
      'session_id': sessionId,
      'req_type': firstPage ? 'default' : 'only_content',
      'client_req_type': 3,
      'filter_ids': '',
      'req_scene':
          genre == 'comic_series' || genre == 'ai_series'
              ? genre
              : 'default',
    };
  }

  static HongguoDiscoverySelection fromCategory(
    String categoryId,
    List<CatalogCategory> categories,
  ) {
    final known = hongguoDiscoveryGenres.map((entry) => entry.id).toSet();
    if (!known.contains(categoryId)) {
      return const HongguoDiscoverySelection();
    }
    if (!categories.any((category) => category.id == categoryId)) {
      return const HongguoDiscoverySelection();
    }
    return HongguoDiscoverySelection({'genre': categoryId});
  }
}
