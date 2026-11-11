import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef _Cell = ({int lane, int row, int x});

String _cellKey(_Cell cell) => '${cell.lane}_${cell.row}_${cell.x}';

Future<String?> showHongguoTvSearchPanel({
  required BuildContext context,
  required TextEditingController controller,
  required String hint,
  Future<List<String>> Function(String)? suggestions,
  List<String> recentSearches = const [],
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SizedBox(
        width: 920,
        height: 560,
        child: _HongguoTvSearchPanel(
          controller: controller,
          hint: hint,
          suggestions: suggestions,
          recentSearches: recentSearches,
        ),
      ),
    ),
  );
}

class _HongguoTvSearchPanel extends StatefulWidget {
  const _HongguoTvSearchPanel({
    required this.controller,
    required this.hint,
    this.suggestions,
    this.recentSearches = const [],
  });

  final TextEditingController controller;
  final String hint;
  final Future<List<String>> Function(String)? suggestions;
  final List<String> recentSearches;

  @override
  State<_HongguoTvSearchPanel> createState() =>
      _HongguoTvSearchPanelState();
}

class _HongguoTvSearchPanelState extends State<_HongguoTvSearchPanel> {
  static const _keys = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final _nodes = <String, FocusNode>{};
  final _suggestionCache = <String, List<String>>{};
  Timer? _debounce;
  int _ticket = 0;
  List<String> _suggestions = const [];
  bool _suggestionsFailed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleSuggestions);
    _scheduleSuggestions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _node(const (lane: 0, row: 1, x: 0)).requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_scheduleSuggestions);
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _node(_Cell cell) => _nodes.putIfAbsent(
    _cellKey(cell),
    () => FocusNode(debugLabel: 'hongguo-tv-search-${_cellKey(cell)}'),
  );

  List<_Cell> _cells() {
    final cells = <_Cell>[(lane: 0, row: 0, x: 0)];
    for (var row = 1; row <= 6; row++) {
      for (var x = 0; x < 6; x++) {
        cells.add((lane: 0, row: row, x: x));
      }
    }
    for (var x = 0; x < 3; x++) {
      cells.add((lane: 0, row: 7, x: x));
    }
    cells.add((lane: 0, row: 8, x: 0));
    final middle = _suggestions.length + widget.recentSearches.length;
    for (var row = 0; row < middle; row++) {
      cells.add((lane: 1, row: row, x: 0));
    }
    cells.add((lane: 2, row: 0, x: 0));
    return cells;
  }

  void _scheduleSuggestions() {
    _debounce?.cancel();
    final query = widget.controller.text.trim();
    if (query.isEmpty || widget.suggestions == null) {
      setState(() {
        _suggestions = const [];
        _suggestionsFailed = false;
      });
      return;
    }
    final cached = _suggestionCache[query];
    if (cached != null) {
      setState(() {
        _suggestions = cached;
        _suggestionsFailed = false;
      });
      return;
    }
    final ticket = ++_ticket;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final fetched = await widget.suggestions!
          .call(query)
          .then((values) => values.toSet().take(8).toList())
          .catchError((_) => <String>[]);
      if (!mounted || ticket != _ticket) return;
      if (fetched.isEmpty && widget.controller.text.trim() != query) return;
      setState(() {
        _suggestions = fetched;
        _suggestionsFailed = fetched.isEmpty;
      });
      if (fetched.isNotEmpty) _suggestionCache[query] = fetched;
    });
  }

  void _insert(String value) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? start : selection.end;
    widget.controller.text = text.replaceRange(start, end, value);
    widget.controller.selection = TextSelection.collapsed(
      offset: start + value.length,
    );
  }

  void _delete() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (selection.start >= 0 &&
        selection.end > selection.start) {
      widget.controller.text = text.replaceRange(
        selection.start,
        selection.end,
        '',
      );
      widget.controller.selection = TextSelection.collapsed(
        offset: selection.start,
      );
      return;
    }
    if (text.isEmpty) return;
    final runes = text.runes.toList()..removeLast();
    widget.controller.text = String.fromCharCodes(runes);
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
  }

  void _submit([String? value]) {
    final query = (value ?? widget.controller.text).trim();
    if (query.isEmpty) return;
    if (value != null) widget.controller.text = query;
    Navigator.of(context).pop(query);
  }

  void _runAction(_Cell cell) {
    switch (cell.lane) {
      case 0:
        if (cell.row == 0) {
          _submit();
        } else if (cell.row >= 1 && cell.row <= 6) {
          final index = (cell.row - 1) * 6 + cell.x;
          if (index < _keys.length) {
            _insert(_keys[index].toLowerCase());
          }
        } else if (cell.row == 7) {
          if (cell.x == 0) {
            _delete();
          } else if (cell.x == 1) {
            widget.controller.clear();
          } else {
            _submit();
          }
        } else if (cell.row == 8) {
          Navigator.of(context).pop();
        }
      case 1:
        if (cell.row < _suggestions.length) {
          _submit(_suggestions[cell.row]);
        } else {
          final index = cell.row - _suggestions.length;
          if (index < widget.recentSearches.length) {
            _submit(widget.recentSearches[index]);
          }
        }
      case 2:
        _submit();
    }
  }

  _Cell? _move(_Cell from, TraversalDirection direction) {
    final cells = _cells();
    if (direction == TraversalDirection.up ||
        direction == TraversalDirection.down) {
      final vertical = direction == TraversalDirection.up ? -1 : 1;
      final sameLane = cells.where(
        (cell) =>
            cell.lane == from.lane &&
            (vertical < 0 ? cell.row < from.row : cell.row > from.row),
      );
      if (sameLane.isEmpty) return null;
      final row = vertical < 0
          ? sameLane.map((cell) => cell.row).reduce((a, b) => a > b ? a : b)
          : sameLane.map((cell) => cell.row).reduce((a, b) => a < b ? a : b);
      final rowCells = sameLane.where((cell) => cell.row == row).toList()
        ..sort(
          (a, b) =>
              (a.x - from.x).abs().compareTo((b.x - from.x).abs()),
        );
      return rowCells.first;
    }
    final targetLane = from.lane + (direction == TraversalDirection.left ? -1 : 1);
    if (targetLane < 0 || targetLane > 2) return null;
    final inLane = cells.where((cell) => cell.lane == targetLane).toList();
    if (inLane.isEmpty) return null;
    inLane.sort((a, b) {
      final rowScore = (a.row - from.row).abs().compareTo(
        (b.row - from.row).abs(),
      );
      return rowScore != 0
          ? rowScore
          : (a.x - from.x).abs().compareTo((b.x - from.x).abs());
    });
    return inLane.first;
  }

  KeyEventResult _handleKey(_Cell cell, FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final direction = switch (key) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
        _ => TraversalDirection.right,
      };
      final target = _move(cell, direction);
      if (target == null) return KeyEventResult.handled;
      _node(target).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA) {
      _runAction(cell);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _keyButton(_Cell cell, Widget child) {
    return _TvKey(
      focusNode: _node(cell),
      onKey: (node, event) => _handleKey(cell, node, event),
      onPressed: () => _runAction(cell),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text;
    final recents = widget.recentSearches.take(8).toList();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 330,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '遥控器搜索',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    query.isEmpty ? widget.hint : query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: query.isEmpty ? Colors.grey : null,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (var row = 0; row < 6; row++)
                        Expanded(
                          child: Row(
                            children: [
                              for (var x = 0; x < 6; x++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: _keyButton(
                                      (lane: 0, row: row + 1, x: x),
                                      Center(
                                        child: Text(
                                          _keys[row * 6 + x],
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          for (final action in [
                            (0, '删除'),
                            (1, '清空'),
                            (2, '搜索'),
                          ])
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: _keyButton(
                                  (lane: 0, row: 7, x: action.$1),
                                  Center(child: Text(action.$2)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: _keyButton(
                                (lane: 0, row: 8, x: 0),
                                const Center(child: Text('返回')),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '方向键选字 · 确定输入\n输入拼音首字母，点联想词搜索',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 200,
            child: ListView(
              children: [
                const Text(
                  '联想词',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_suggestionsFailed)
                  const Text(
                    '联想暂不可用，可直接按搜索',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                for (var i = 0; i < _suggestions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _keyButton(
                      (lane: 1, row: i, x: 0),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          _suggestions[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  '最近搜索',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (recents.isEmpty)
                  const Text(
                    '搜索后会保留历史',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                for (var i = 0; i < recents.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _keyButton(
                      (lane: 1, row: _suggestions.length + i, x: 0),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          recents[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '搜索结果',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  query.isEmpty ? '输入关键词后按搜索，结果在剧场列表里展示。' : '将搜索“$query”',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: _keyButton(
                    (lane: 2, row: 0, x: 0),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text('搜索', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TvKey extends StatefulWidget {
  const _TvKey({
    required this.focusNode,
    required this.onKey,
    required this.onPressed,
    required this.child,
  });

  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKey;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_TvKey> createState() => _TvKeyState();
}

class _TvKeyState extends State<_TvKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: widget.onKey,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          decoration: BoxDecoration(
            color: _focused ? colors.primary : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: _focused ? colors.onPrimary : colors.onSurface,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
