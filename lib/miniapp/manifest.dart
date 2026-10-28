import 'permissions.dart';

class MiniAppManifest {
  const MiniAppManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.versionCode,
    required this.renderer,
    required this.entry,
    required this.description,
    required this.permissions,
    required this.networkAllowlist,
    this.unsupportedPermissions = const [],
  });

  final String id;
  final String name;
  final String version;
  final int versionCode;
  final String renderer;
  final String entry;
  final String description;
  final List<String> permissions;
  final List<String> networkAllowlist;
  final List<String> unsupportedPermissions;

  List<String> get unavailablePermissions => [
    for (final permission in permissions)
      if (!MiniAppPermissions.supported.contains(permission)) permission,
    ...unsupportedPermissions,
  ];

  factory MiniAppManifest.fromJson(Map<String, Object?> json) {
    var id = _string(json, 'id');
    if (id.isEmpty) id = _string(json, 'appId');
    if (id.isEmpty) id = _string(json, 'app_id');
    final name = _string(json, 'name');
    final entry = _string(json, 'entry');
    if (id.isEmpty || name.isEmpty || entry.isEmpty) {
      throw const FormatException(
        'miniapp manifest requires id, name and entry',
      );
    }
    if (id.contains('/') || id.contains('\\') || id.contains('..')) {
      throw FormatException('miniapp id is not a plain directory name: $id');
    }
    if (entry.startsWith('/') || entry.contains('..')) {
      throw FormatException('miniapp entry must be a relative path: $entry');
    }
    final renderer = _string(json, 'renderer', fallback: 'webview');
    if (renderer != 'webview') {
      throw FormatException('miniapp renderer is not supported: $renderer');
    }
    final declared = _stringList(json, 'permissions')
        .map(
          (permission) => permission == 'navigate'
              ? MiniAppPermissions.navigation
              : permission,
        )
        .toList();
    final permissions = <String>[];
    final unsupportedPermissions = <String>[];
    for (final permission in declared) {
      if (MiniAppPermissions.known.contains(permission)) {
        permissions.add(permission);
      } else {
        unsupportedPermissions.add(permission);
      }
    }
    return MiniAppManifest(
      id: id,
      name: name,
      version: _string(json, 'version', fallback: ''),
      versionCode: _int(json, 'versionCode'),
      renderer: renderer,
      entry: entry,
      description: _string(json, 'description', fallback: ''),
      permissions: permissions,
      unsupportedPermissions: unsupportedPermissions,
      networkAllowlist: _stringList(
        json,
        'networkAllowlist',
      ).map(_normalizeHost).where((host) => host.isNotEmpty).toList(),
    );
  }

  static String _string(
    Map<String, Object?> json,
    String key, {
    String fallback = '',
  }) {
    final value = json[key];
    if (value == null) return fallback;
    if (value is! String) {
      throw FormatException('miniapp manifest field $key must be a string');
    }
    return value;
  }

  static int _int(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw FormatException('miniapp manifest field $key must be a number');
  }

  static List<String> _stringList(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) return [];
    if (value is! List) {
      throw FormatException('miniapp manifest field $key must be an array');
    }
    for (final item in value) {
      if (item is! String) {
        throw FormatException('miniapp manifest field $key must hold strings');
      }
    }
    return value.cast<String>();
  }

  static String _normalizeHost(String raw) {
    var host = raw.trim().toLowerCase();
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    for (final stop in ['/', '?', '#']) {
      final at = host.indexOf(stop);
      if (at >= 0) host = host.substring(0, at);
    }
    final port = host.indexOf(':');
    if (port >= 0) host = host.substring(0, port);
    return host;
  }
}
