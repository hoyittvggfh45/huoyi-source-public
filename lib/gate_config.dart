class GateFeature {
  static const download = 'download';
  static const watchroom = 'watchroom';
  static const comment = 'comment';
  static const danmaku = 'danmaku';
  static const proxyKernel = 'proxy_kernel';
  static const mediaLibrary = 'media_library';

  static const all = [
    download,
    watchroom,
    comment,
    danmaku,
    proxyKernel,
    mediaLibrary,
  ];

  static const labels = {
    download: '下载',
    watchroom: '一起看',
    comment: '评论',
    danmaku: '弹幕',
    proxyKernel: '代理内核',
    mediaLibrary: '媒体库',
  };
}

class GateModule {
  static const drama = 'drama';
  static const vod = 'vod';
  static const midnight = 'midnight';
  static const live = 'live';
  static const novel = 'novel';
  static const comic = 'comic';
  static const audio = 'audio';
  static const miniapp = 'miniapp';

  static const all = [drama, vod, midnight, live, novel, comic, audio, miniapp];

  static const labels = {
    drama: '短剧',
    vod: '点播',
    midnight: '午夜区',
    live: '直播',
    novel: '小说',
    comic: '漫画',
    audio: '听书',
    miniapp: '小程序',
  };
}

class GateRegion {
  static const cn = 'cn';
  static const overseas = 'overseas';

  static const all = [cn, overseas];

  static const labels = {cn: '中国大陆', overseas: '大陆以外'};
}

bool _mapsEqual(Map<String, bool> a, Map<String, bool> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

Map<String, bool> _readKnown(
  Object? raw,
  List<String> keys,
  Map<String, bool> fallback,
) {
  if (raw is! Map) return Map<String, bool>.from(fallback);
  final result = <String, bool>{};
  for (final key in keys) {
    final value = raw[key];
    result[key] = value is bool ? value : (fallback[key] ?? true);
  }
  return result;
}

class GateConfig {
  const GateConfig({
    required this.version,
    required this.features,
    required this.modules,
    required this.regions,
  });

  factory GateConfig.defaults() => GateConfig(
    version: 1,
    features: {for (final key in GateFeature.all) key: true},
    modules: {for (final key in GateModule.all) key: true},
    regions: {for (final key in GateRegion.all) key: true},
  );

  factory GateConfig.fromJson(Map<String, dynamic> json) {
    final fallback = GateConfig.defaults();
    final version = json['version'];
    return GateConfig(
      version: version is int ? version : fallback.version,
      features: _readKnown(
        json['features'],
        GateFeature.all,
        fallback.features,
      ),
      modules: _readKnown(json['modules'], GateModule.all, fallback.modules),
      regions: _readKnown(json['regions'], GateRegion.all, fallback.regions),
    );
  }

  final int version;
  final Map<String, bool> features;
  final Map<String, bool> modules;
  final Map<String, bool> regions;

  GateConfig copyWith({
    int? version,
    Map<String, bool>? features,
    Map<String, bool>? modules,
    Map<String, bool>? regions,
  }) => GateConfig(
    version: version ?? this.version,
    features: features ?? Map<String, bool>.from(this.features),
    modules: modules ?? Map<String, bool>.from(this.modules),
    regions: regions ?? Map<String, bool>.from(this.regions),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'features': Map<String, bool>.from(features),
    'modules': Map<String, bool>.from(modules),
    'regions': Map<String, bool>.from(regions),
  };

  @override
  bool operator ==(Object other) =>
      other is GateConfig &&
      other.version == version &&
      _mapsEqual(other.features, features) &&
      _mapsEqual(other.modules, modules) &&
      _mapsEqual(other.regions, regions);

  @override
  int get hashCode => Object.hash(
    version,
    Object.hashAllUnordered(
      features.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(
      modules.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAllUnordered(
      regions.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}
