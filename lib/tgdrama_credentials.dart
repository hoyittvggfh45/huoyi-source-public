import 'dart:io';

class TgdramaCredentials {
  const TgdramaCredentials._();

  static const String apiId = String.fromEnvironment('TG_API_ID');

  static const String apiHash = String.fromEnvironment('TG_API_HASH');

  static bool get hasCredentials => apiId.isNotEmpty && apiHash.isNotEmpty;

  static String buildConfigYaml({
    required String apiId,
    required String apiHash,
    required String dataDir,
  }) {
    return 'telegram:\n'
        '  api_id: $apiId\n'
        '  api_hash: $apiHash\n'
        'data:\n'
        '  dir: $dataDir\n';
  }

  static Future<bool> ensureConfigYaml(Directory tgdramaDir) async {
    final configFile = File('${tgdramaDir.path}/config.yaml');
    try {
      if (await configFile.exists()) {
        final text = await configFile.readAsString();
        final creds = _parseTelegramCredentials(text);
        if (creds.$1 != null &&
            creds.$1!.isNotEmpty &&
            creds.$2 != null &&
            creds.$2!.isNotEmpty) {
          return true;
        }
      }
    } catch (_) {}
    if (!hasCredentials) return false;
    try {
      await tgdramaDir.create(recursive: true);
      await configFile.writeAsString(
        buildConfigYaml(
          apiId: apiId,
          apiHash: apiHash,
          dataDir: tgdramaDir.path,
        ),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static (String?, String?) _parseTelegramCredentials(String yamlText) {
    String? apiId;
    String? apiHash;
    var inTelegramSection = false;
    for (final rawLine in yamlText.split('\n')) {
      final line = rawLine.split('#').first;
      if (line.trim().isEmpty) continue;
      final indent = line.length - line.trimLeft().length;
      final trimmed = line.trim();
      if (indent == 0 && trimmed.endsWith(':')) {
        inTelegramSection = trimmed == 'telegram:';
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final key = trimmed.substring(0, colon).trim();
      if (key != 'api_id' && key != 'api_hash') continue;
      final value = _unquote(trimmed.substring(colon + 1).trim());
      if (inTelegramSection) {
        if (key == 'api_id') {
          apiId = value;
        } else {
          apiHash = value;
        }
      } else if (indent == 0) {
        if (key == 'api_id' && apiId == null) apiId = value;
        if (key == 'api_hash' && apiHash == null) apiHash = value;
      }
    }
    return (apiId, apiHash);
  }

  static String _unquote(String value) {
    var v = value.trim();
    if (v.length >= 2) {
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
    }
    return v.trim();
  }
}
