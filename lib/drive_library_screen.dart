import 'package:flutter/material.dart';

import 'app_page_route.dart';
import 'drive_library.dart';

enum DriveLibraryViewMode { files, media }

class DriveLibraryScreen extends StatefulWidget {
  const DriveLibraryScreen({super.key});

  @override
  State<DriveLibraryScreen> createState() => _DriveLibraryScreenState();
}

class _DriveLibraryScreenState extends State<DriveLibraryScreen> {
  DriveLibraryViewMode _mode = DriveLibraryViewMode.files;
  String? _filterId;

  IconData _iconFor(DriveKind kind) => switch (kind) {
    DriveKind.webdav => Icons.storage_rounded,
    DriveKind.alist => Icons.dns_rounded,
    DriveKind.pan115 => Icons.cloud_rounded,
    DriveKind.alipan => Icons.cloud_queue_rounded,
    DriveKind.baidu => Icons.cloud_done_rounded,
    DriveKind.quark => Icons.cloud_download_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网盘媒体库')),
      body: ListenableBuilder(
        listenable: driveLibraryRegistry,
        builder: (context, _) {
          final sources = driveLibraryRegistry.sources;
          final effectiveFilter = sources.any((item) => item.id == _filterId)
              ? _filterId
              : null;
          final visible = effectiveFilter == null
              ? sources
              : sources.where((item) => item.id == effectiveFilter).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('drive-mode-files'),
                    label: const Text('文件'),
                    selected: _mode == DriveLibraryViewMode.files,
                    onSelected: (_) =>
                        setState(() => _mode = DriveLibraryViewMode.files),
                  ),
                  ChoiceChip(
                    key: const ValueKey('drive-mode-media'),
                    label: const Text('媒体'),
                    selected: _mode == DriveLibraryViewMode.media,
                    onSelected: (_) =>
                        setState(() => _mode = DriveLibraryViewMode.media),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      key: const ValueKey('drive-filter-all'),
                      label: const Text('全部'),
                      selected: effectiveFilter == null,
                      onSelected: (_) => setState(() => _filterId = null),
                    ),
                    for (final source in sources) ...[
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: ValueKey('drive-filter-${source.id}'),
                        label: Text(source.name),
                        selected: effectiveFilter == source.id,
                        onSelected: (_) =>
                            setState(() => _filterId = source.id),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _mode == DriveLibraryViewMode.files ? '文件列表' : '媒体库',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (sources.isEmpty)
                const Center(
                  key: ValueKey('drive-library-empty'),
                  child: Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 48),
                        SizedBox(height: 16),
                        Text(
                          '尚未接入网盘源',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '接入 115、阿里、百度、夸克、WebDAV、AList 后，这里会显示网盘文件与媒体库。',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final source in visible)
                  Card(
                    key: ValueKey('drive-source-${source.id}'),
                    child: ListTile(
                      leading: Icon(_iconFor(source.kind)),
                      title: Text(source.name),
                      subtitle: Text(source.kind.label),
                      trailing: source.browser == null
                          ? const Text('即将接入')
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: source.browser == null
                          ? null
                          : () => Navigator.of(context).push(
                              appPageRoute<void>(builder: source.browser!),
                            ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
