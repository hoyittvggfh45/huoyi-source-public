import 'package:flutter/material.dart';

import 'content_models.dart';
import 'content_zone_binding.dart';
import 'content_zone_screen.dart';

class MergedComicNovelScreen extends StatefulWidget {
  const MergedComicNovelScreen({super.key, this.binding, this.initialSection});

  final ContentZoneBinding? binding;
  final ContentSection? initialSection;

  @override
  State<MergedComicNovelScreen> createState() => _MergedComicNovelScreenState();
}

class _MergedComicNovelScreenState extends State<MergedComicNovelScreen> {
  late ContentSection _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? ContentSection.comic;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<ContentSection>(
            segments: const [
              ButtonSegment(value: ContentSection.comic, label: Text('漫画')),
              ButtonSegment(value: ContentSection.novel, label: Text('小说')),
            ],
            selected: {_section},
            onSelectionChanged: (selected) =>
                setState(() => _section = selected.first),
          ),
        ),
        Expanded(
          child: ContentZoneScreen(
            key: ValueKey('merged-content-zone-${_section.name}'),
            section: _section,
            binding: widget.binding,
          ),
        ),
      ],
    );
  }
}
