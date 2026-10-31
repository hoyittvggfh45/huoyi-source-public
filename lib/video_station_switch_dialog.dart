import 'package:flutter/material.dart';

import 'video_station_list.dart';

Future<String?> showVideoStationSwitchDialog(
  BuildContext context, {
  required String currentId,
  required Set<String> hiddenIds,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => VideoStationSwitchDialog(
      currentId: currentId,
      hiddenIds: hiddenIds,
    ),
  );
}

class VideoStationSwitchDialog extends StatefulWidget {
  const VideoStationSwitchDialog({
    super.key,
    required this.currentId,
    required this.hiddenIds,
  });

  final String currentId;
  final Set<String> hiddenIds;

  @override
  State<VideoStationSwitchDialog> createState() =>
      _VideoStationSwitchDialogState();
}

class _VideoStationSwitchDialogState extends State<VideoStationSwitchDialog> {
  VideoStationGroup? _filter;

  String _currentName(List<VideoStationEntry> entries) {
    for (final entry in entries) {
      if (entry.id == widget.currentId) {
        return entry.name;
      }
    }
    return widget.currentId;
  }

  Widget _filterChip(
    VideoStationGroup group,
    String label,
    int count,
    Key key,
  ) {
    final selected = _filter == group;
    return FilterChip(
      key: key,
      label: Text('$label $count'),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = selected ? null : group;
        });
      },
      selectedColor: Colors.red.shade50,
      checkmarkColor: Colors.red,
      labelStyle: TextStyle(
        color: selected ? Colors.red : Colors.black87,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected ? Colors.red : Colors.grey.shade300,
      ),
      backgroundColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = videoStationsVisible(widget.hiddenIds);
    final greenCount = visible
        .where((entry) => entry.group == VideoStationGroup.green)
        .length;
    final restrictedCount = visible
        .where((entry) => entry.group == VideoStationGroup.restricted)
        .length;
    final shown = _filter == null
        ? visible
        : visible.where((entry) => entry.group == _filter).toList();
    return AlertDialog(
      key: const Key('video-station-switch-dialog'),
      title: Row(
        children: [
          const Text('切换站源'),
          const Spacer(),
          Text(
            '当前：${_currentName(visible)}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '分类仅筛选列表，点击站源立即切换',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _filterChip(
                  VideoStationGroup.green,
                  '绿色',
                  greenCount,
                  const Key('video-station-filter-green'),
                ),
                _filterChip(
                  VideoStationGroup.restricted,
                  '限制级',
                  restrictedCount,
                  const Key('video-station-filter-restricted'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _filter == VideoStationGroup.green
                        ? '没有绿色站源'
                        : _filter == VideoStationGroup.restricted
                            ? '没有限制级站源'
                            : '没有可用站源',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              )
            else
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.8,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final entry = shown[index];
                    final selected = entry.id == widget.currentId;
                    return InkWell(
                      key: Key('video-station-cell-${entry.id}'),
                      onTap: () => Navigator.of(context).pop(entry.id),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              selected ? Colors.red.shade50 : Colors.white,
                          border: Border.all(
                            color:
                                selected ? Colors.red : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entry.name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected ? Colors.red : Colors.black87,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('video-station-switch-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
