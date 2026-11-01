import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jar_bridge.dart';
import 'jar_site_config.dart';
import 'models.dart';
import 'zakatv_builtin.dart';

class StandaloneJarSite {
  const StandaloneJarSite({
    required this.siteId,
    required this.jarId,
    required this.jarUrl,
    required this.jarMd5,
    required this.className,
    required this.name,
    this.ext = '',
    this.missingConfig = false,
  });

  final String siteId;
  final String jarId;
  final String jarUrl;
  final String jarMd5;
  final String className;
  final String name;
  final String ext;
  final bool missingConfig;

  JarSiteSpec get spec => JarSiteSpec(
    siteId: siteId,
    configId: jarId,
    name: name,
    className: className,
    jarUrl: jarUrl,
    jarMd5: jarMd5,
    ext: ext,
  );

  StandaloneJarSite copyWith({
    String? ext,
    String? name,
    bool? missingConfig,
  }) => StandaloneJarSite(
    siteId: siteId,
    jarId: jarId,
    jarUrl: jarUrl,
    jarMd5: jarMd5,
    className: className,
    name: name ?? this.name,
    ext: ext ?? this.ext,
    missingConfig: missingConfig ?? this.missingConfig,
  );

  Map<String, dynamic> toJson() => {
    'siteId': siteId,
    'jarId': jarId,
    'jarUrl': jarUrl,
    'jarMd5': jarMd5,
    'className': className,
    'name': name,
    if (ext.isNotEmpty) 'ext': ext,
    if (missingConfig) 'missingConfig': true,
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
        missingConfig: json['missingConfig'] == true,
      );
}

class JarImport {
  static const _prefsKey = 'standalone_jar_sites';
  static final Map<String, StandaloneJarSite> _sites = {};
  static final Map<String, StandaloneJarSite> _builtinSites = {};
  static bool _builtinRegistered = false;

  static List<StandaloneJarSite> get sites =>
      List.unmodifiable(_sites.values);

  static List<StandaloneJarSite> get builtinSites =>
      List.unmodifiable(_builtinSites.values);

  static bool isBuiltinSite(String siteId) =>
      _builtinSites.containsKey(siteId);

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
      importType: 'jar',
    );
  }

  static void _registerBuiltin(StandaloneJarSite site) {
    JarBridge.register(site.spec);
    SourceSite.importedSites[site.siteId] = SourceSite(
      site.siteId,
      site.name,
      'ZakaTV jar 内置 · ${site.className}',
      section: SourceSite.sectionVideo,
      origin: SourceSite.originImport,
      importType: 'jar',
    );
  }

  static Future<bool> registerBuiltinZakatv() async {
    if (_builtinRegistered || !JarBridge.supported) return _builtinRegistered;
    try {
      final bytes = await rootBundle.load(zakatvJarAsset);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/zakatv.jar');
      await tempFile.writeAsBytes(bytes.buffer.asUint8List());
      final jarPath = await JarBridge.ensureJarPath(
        configId: zakatvJarId,
        url: tempFile.path,
        md5: zakatvJarMd5,
      );
      for (final builtin in zakatvBuiltinSites) {
        final site = StandaloneJarSite(
          siteId: JarSiteSpec.siteIdFor(zakatvJarId, builtin.key),
          jarId: zakatvJarId,
          jarUrl: jarPath,
          jarMd5: zakatvJarMd5,
          className: builtin.className,
          name: builtin.name,
          ext: builtin.ext,
        );
        _builtinSites[site.siteId] = site;
        _registerBuiltin(site);
      }
      _builtinRegistered = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<
      ({
        List<JarClassInfo> all,
        List<JarClassInfo> newly,
        List<String> updated,
        List<String> configured,
        List<String> missing,
      })>
      scanAndRegister({
    required String jarId,
    required String jarUrl,
    String jarMd5 = '',
    List<JarSiteConfig> configs = const [],
  }) async {
    final jarPath = await JarBridge.ensureJarPath(
      configId: jarId,
      url: jarUrl,
      md5: jarMd5,
    );
    final storedUrl = jarUrl.startsWith('http') ? jarUrl : jarPath;
    final classes = await JarBridge.enumerate(jarPath);
    final newly = <JarClassInfo>[];
    final updated = <String>[];
    final configured = <String>[];
    final missing = <String>[];
    var changed = false;
    final existingByClass = <String, StandaloneJarSite>{};
    for (final site in _sites.values) {
      if (site.jarId == jarId) existingByClass[site.className] = site;
    }
    for (final info in classes) {
      if (!info.instantiable) continue;
      final config = matchJarSiteConfig(info.className, configs);
      final previous = existingByClass[info.className];
      if (previous != null) {
        if (config != null) {
          final name = config.name.isNotEmpty ? config.name : previous.name;
          if (previous.name != name ||
              previous.ext != config.ext ||
              previous.missingConfig) {
            final site = previous.copyWith(
              name: name,
              ext: config.ext,
              missingConfig: false,
            );
            _sites[site.siteId] = site;
            _register(site);
            updated.add(site.siteId);
            configured.add(site.name);
            changed = true;
          }
        }
        continue;
      }
      var siteId = JarSiteSpec.siteIdFor(
        jarId,
        config != null && config.key.isNotEmpty ? config.key : info.simpleName,
      );
      final collision = _sites[siteId];
      if (collision != null && collision.className != info.className) {
        siteId = JarSiteSpec.siteIdFor(
          jarId,
          info.className.replaceAll('.', '_'),
        );
      }
      if (_sites.containsKey(siteId)) continue;
      final site = StandaloneJarSite(
        siteId: siteId,
        jarId: jarId,
        jarUrl: storedUrl,
        jarMd5: jarMd5,
        className: info.className,
        name: config != null && config.name.isNotEmpty
            ? config.name
            : info.simpleName,
        ext: config?.ext ?? '',
        missingConfig: config == null,
      );
      _sites[siteId] = site;
      _register(site);
      newly.add(info);
      changed = true;
      if (config == null) {
        missing.add(site.name);
      } else {
        configured.add(site.name);
      }
    }
    if (changed) await _persist();
    return (
      all: classes,
      newly: newly,
      updated: updated,
      configured: configured,
      missing: missing,
    );
  }

  static List<String> siteIdsForJar(String jarId) {
    final prefix = 'jar:$jarId:';
    return [
      for (final entry in _sites.entries)
        if (entry.key.startsWith(prefix)) entry.key,
    ];
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
      missingConfig: ext.isEmpty,
    );
    _sites[siteId] = site;
    _register(site);
    await _persist();
  }

  static Future<void> remove(String siteId) async {
    if (_builtinSites.containsKey(siteId)) return;
    if (_sites.remove(siteId) == null) return;
    JarBridge.unregister(siteId);
    SourceSite.importedSites.remove(siteId);
    await _persist();
  }

  static Future<void> updateExt(String siteId, String ext) async {
    final builtin = _builtinSites[siteId];
    if (builtin != null) {
      if (builtin.ext == ext) return;
      _builtinSites[siteId] = builtin.copyWith(ext: ext);
      await JarBridge.updateExt(siteId, ext);
      return;
    }
    final site = _sites[siteId];
    if (site == null || (site.ext == ext && !site.missingConfig)) return;
    _sites[siteId] = site.copyWith(
      ext: ext,
      missingConfig: ext.isEmpty ? site.missingConfig : false,
    );
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
