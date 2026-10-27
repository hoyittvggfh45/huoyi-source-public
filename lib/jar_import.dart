import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'jar_bridge.dart';
import 'models.dart';

class StandaloneJarSite {
  const StandaloneJarSite({
    required this.siteId,
    required this.jarId,
    required this.jarUrl,
    required this.jarMd5,
    required this.className,
    required this.name,
    this.ext = '',
  });

  final String siteId;
  final String jarId;
  final String jarUrl;
  final String jarMd5;
  final String className;
  final String name;
  final String ext;

  JarSiteSpec get spec => JarSiteSpec(
    siteId: siteId,
    configId: jarId,
    name: name,
    className: className,
    jarUrl: jarUrl,
    jarMd5: jarMd5,
    ext: ext,
  );

  StandaloneJarSite copyWith({String? ext}) => StandaloneJarSite(
    siteId: siteId,
    jarId: jarId,
    jarUrl: jarUrl,
    jarMd5: jarMd5,
    className: className,
    name: name,
    ext: ext ?? this.ext,
  );

  Map<String, dynamic> toJson() => {
    'siteId': siteId,
    'jarId': jarId,
    'jarUrl': jarUrl,
    'jarMd5': jarMd5,
    'className': className,
    'name': name,
    if (ext.isNotEmpty) 'ext': ext,
  };

  factory StandaloneJarSite.fromJson(Map<String, dynamic> json) =>
      StandaloneJarSite(
        siteId: json['siteId'] as String? ?? '',
        jarId: json['jarId'] as String? ?? '',
        jarUrl: json['jarUrl'] as String? ?? '',
        jarMd5: json['jarMd5'] as String? ?? '',
        className: json['className'] as String? ?? '',
        name: json['name'] as String? ?? '',
        ext: json['ext'] as String? ?? '',
      );
}

class JarImport {
  static const _prefsKey = 'standalone_jar_sites';
  static final Map<String, StandaloneJarSite> _sites = {};

  static List<StandaloneJarSite> get sites => List.unmodifiable(_sites.values);

  static StandaloneJarSite? siteFor(String siteId) => _sites[siteId];

  static void restore(SharedPreferences preferences) {
    _sites.clear();
    final raw = preferences.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final rows = jsonDecode(raw) as List;
      for (final row in rows) {
        if (row is! Map) continue;
        final site = StandaloneJarSite.fromJson(Map<String, dynamic>.from(row));
        if (site.siteId.isEmpty || site.className.isEmpty) continue;
        _sites[site.siteId] = site;
        _register(site);
      }
    } catch (_) {}
  }

  static void _register(StandaloneJarSite site) {
    JarBridge.register(site.spec);
    SourceSite.importedSites[site.siteId] = SourceSite(
      site.siteId,
      site.name,
      'jar 导入 · ${site.className}',
      section: SourceSite.sectionVideo,
      origin: SourceSite.originImport,
    );
  }

  static Future<List<JarClassInfo>> scanAndRegister({
    required String jarId,
    required String jarUrl,
    String jarMd5 = '',
  }) async {
    final jarPath = await JarBridge.ensureJarPath(
      configId: jarId,
      url: jarUrl,
      md5: jarMd5,
    );
    final storedUrl = jarUrl.startsWith('http') ? jarUrl : jarPath;
    final classes = await JarBridge.enumerate(jarPath);
    for (final info in classes) {
      if (!info.instantiable) continue;
      final siteId = JarSiteSpec.siteIdFor(jarId, info.simpleName);
      if (_sites.containsKey(siteId)) continue;
      final site = StandaloneJarSite(
        siteId: siteId,
        jarId: jarId,
        jarUrl: storedUrl,
        jarMd5: jarMd5,
        className: info.className,
        name: info.simpleName,
      );
      _sites[siteId] = site;
      _register(site);
    }
    await _persist();
    return classes;
  }

  static Future<void> registerClass({
    required String jarId,
    required String jarUrl,
    String jarMd5 = '',
    required String className,
    String name = '',
    String ext = '',
  }) async {
    final simple = className.split('.').last;
    final siteId = JarSiteSpec.siteIdFor(jarId, simple);
    final site = StandaloneJarSite(
      siteId: siteId,
      jarId: jarId,
      jarUrl: jarUrl,
      jarMd5: jarMd5,
      className: className,
      name: name.isNotEmpty ? name : simple,
      ext: ext,
    );
    _sites[siteId] = site;
    _register(site);
    await _persist();
  }

  static Future<void> remove(String siteId) async {
    if (_sites.remove(siteId) == null) return;
    JarBridge.unregister(siteId);
    SourceSite.importedSites.remove(siteId);
    await _persist();
  }

  static Future<void> updateExt(String siteId, String ext) async {
    final site = _sites[siteId];
    if (site == null || site.ext == ext) return;
    _sites[siteId] = site.copyWith(ext: ext);
    await JarBridge.updateExt(siteId, ext);
    await _persist();
  }

  static Future<void> _persist() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _prefsKey,
      jsonEncode([for (final site in _sites.values) site.toJson()]),
    );
  }
}
