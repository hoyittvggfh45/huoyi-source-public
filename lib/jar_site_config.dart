import 'dart:convert';

import 'jar_bridge.dart';

class JarSiteConfig {
  const JarSiteConfig({
    required this.key,
    required this.name,
    required this.api,
    required this.ext,
  });

  final String key;
  final String name;
  final String api;
  final String ext;
}

String _encodeExt(Object? ext) {
  if (ext == null) return '';
  if (ext is Map || ext is List) return jsonEncode(ext);
  return ext.toString().trim();
}

JarSiteConfig? _configOf(Map<String, dynamic> entry) {
  final key = entry['key']?.toString().trim() ?? '';
  final name = entry['name']?.toString().trim() ?? '';
  final api = entry['api']?.toString().trim() ?? '';
  if (key.isEmpty && name.isEmpty && api.isEmpty) return null;
  return JarSiteConfig(
    key: key,
    name: name,
    api: api,
    ext: _encodeExt(entry['ext']),
  );
}

List<JarSiteConfig> parseJarSiteConfigs(String text) {
  final dynamic decoded = jsonDecode(text);
  final configs = <JarSiteConfig>[];
  if (decoded is Map<String, dynamic>) {
    final sites = decoded['sites'];
    if (sites is List) {
      for (final entry in sites) {
        if (entry is Map) {
          final config = _configOf(Map<String, dynamic>.from(entry));
          if (config != null) configs.add(config);
        }
      }
      return configs;
    }
    final single = _configOf(decoded);
    if (single != null && single.api.isNotEmpty) configs.add(single);
    return configs;
  }
  if (decoded is List) {
    for (final entry in decoded) {
      if (entry is Map) {
        final config = _configOf(Map<String, dynamic>.from(entry));
        if (config != null) configs.add(config);
      }
    }
  }
  return configs;
}

bool looksLikeJarSiteConfig(String text) {
  try {
    return parseJarSiteConfigs(text).isNotEmpty;
  } catch (_) {
    return false;
  }
}

String _classNameOfApi(String api) {
  if (!api.startsWith('csp_') && api.contains('.')) return api;
  return JarSiteSpec.classNameForApi(api);
}

JarSiteConfig? matchJarSiteConfig(
  String className,
  List<JarSiteConfig> configs,
) {
  for (final config in configs) {
    if (config.api.isEmpty) continue;
    if (_classNameOfApi(config.api) == className) return config;
  }
  final simple = className.split('.').last;
  for (final config in configs) {
    if (config.key.isNotEmpty &&
        config.key.toLowerCase() == simple.toLowerCase()) {
      return config;
    }
  }
  return null;
}
