import 'models.dart';

class ImportedSiteRecord {
  const ImportedSiteRecord({
    required this.id,
    required this.name,
    required this.type,
    required this.fileName,
    required this.contentHash,
    this.enabled = true,
    this.importedAtMs = 0,
  });

  final String id;
  final String name;
  final String type;
  final String fileName;
  final String contentHash;
  final bool enabled;
  final int importedAtMs;

  static const typePy = 'py';
  static const typeJs = 'js';

  ImportedSiteRecord copyWith({bool? enabled, String? name}) =>
      ImportedSiteRecord(
        id: id,
        name: name ?? this.name,
        type: type,
        fileName: fileName,
        contentHash: contentHash,
        enabled: enabled ?? this.enabled,
        importedAtMs: importedAtMs,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'fileName': fileName,
    'contentHash': contentHash,
    'enabled': enabled,
    'importedAtMs': importedAtMs,
  };

  factory ImportedSiteRecord.fromJson(Map<String, dynamic> json) =>
      ImportedSiteRecord(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        contentHash: json['contentHash'] as String? ?? '',
        enabled: json['enabled'] != false,
        importedAtMs: json['importedAtMs'] as int? ?? 0,
      );

  SourceSite get asSite => SourceSite(
    id,
    name,
    type == typePy ? 'Python 蜘蛛导入站' : 'JS 蜘蛛导入站（引擎未就绪）',
    section: SourceSite.sectionVideo,
    origin: SourceSite.originImport,
    importType: type,
  );
}
