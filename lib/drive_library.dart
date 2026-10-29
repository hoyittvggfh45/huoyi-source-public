import 'package:flutter/widgets.dart';

enum DriveKind { webdav, alist, pan115, alipan, baidu, quark }

extension DriveKindLabel on DriveKind {
  String get label => switch (this) {
    DriveKind.webdav => 'WebDAV',
    DriveKind.alist => 'AList',
    DriveKind.pan115 => '115',
    DriveKind.alipan => '阿里',
    DriveKind.baidu => '百度',
    DriveKind.quark => '夸克',
  };
}

class DriveLibrarySourceDescriptor {
  const DriveLibrarySourceDescriptor({
    required this.id,
    required this.kind,
    required this.name,
    this.browser,
  });

  final String id;
  final DriveKind kind;
  final String name;
  final WidgetBuilder? browser;
}

class DriveLibraryRegistry extends ChangeNotifier {
  final _sources = <DriveLibrarySourceDescriptor>[];

  List<DriveLibrarySourceDescriptor> get sources => List.unmodifiable(_sources);

  void register(DriveLibrarySourceDescriptor source) {
    _sources.removeWhere((item) => item.id == source.id);
    _sources.add(source);
    notifyListeners();
  }

  bool unregister(String id) {
    final before = _sources.length;
    _sources.removeWhere((item) => item.id == id);
    if (_sources.length != before) {
      notifyListeners();
      return true;
    }
    return false;
  }
}

final driveLibraryRegistry = DriveLibraryRegistry();
