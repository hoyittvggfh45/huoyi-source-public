import 'package:flutter/material.dart';

import 'models.dart';

class RoomDanmakuOverlay extends StatefulWidget {
  const RoomDanmakuOverlay({super.key, required this.chat});

  final List<RoomChatMessage> chat;

  @override
  State<RoomDanmakuOverlay> createState() => _RoomDanmakuOverlayState();
}

class _RoomDanmakuFlight {
  _RoomDanmakuFlight({required this.key, required this.text, required this.lane});

  final String key;
  final String text;
  final int lane;
}

class _RoomDanmakuOverlayState extends State<RoomDanmakuOverlay> {
  final _flights = <_RoomDanmakuFlight>[];
  final _seen = <String>{};
  final _laneFreeAt = <int>[0, 0, 0];

  String _keyOf(RoomChatMessage message) =>
      '${message.sender}|${message.sentAt}|${message.text}';

  @override
  void initState() {
    super.initState();
    for (final message in widget.chat) {
      _seen.add(_keyOf(message));
    }
  }

  @override
  void didUpdateWidget(RoomDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    var changed = false;
    for (final message in widget.chat) {
      final key = _keyOf(message);
      if (!_seen.add(key)) continue;
      if (_flights.length >= 12) continue;
      final now = DateTime.now().millisecondsSinceEpoch;
      var lane = 0;
      for (var i = 1; i < _laneFreeAt.length; i++) {
        if (_laneFreeAt[i] < _laneFreeAt[lane]) lane = i;
      }
      _laneFreeAt[lane] = now + 8000;
      final text = message.nickname.isNotEmpty
          ? '${message.nickname}：${message.text}'
          : message.text;
      _flights.add(_RoomDanmakuFlight(key: key, text: text, lane: lane));
      changed = true;
    }
    if (changed) setState(() {});
  }

  void _removeFlight(String key) {
    if (!mounted) return;
    setState(
      () => _flights.removeWhere((flight) => flight.key == key),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_flights.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedWidth) return const SizedBox.shrink();
          return Stack(
            children: [
              for (final flight in _flights)
                Positioned(
                  key: ValueKey('room-danmaku-${flight.key}'),
                  top: 8 + flight.lane * 24,
                  left: 0,
                  right: 0,
                  height: 24,
                  child: _RoomDanmakuFlightWidget(
                    flight: flight,
                    width: constraints.maxWidth,
                    onDone: () => _removeFlight(flight.key),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RoomDanmakuFlightWidget extends StatefulWidget {
  const _RoomDanmakuFlightWidget({
    required this.flight,
    required this.width,
    required this.onDone,
  });

  final _RoomDanmakuFlight flight;
  final double width;
  final VoidCallback onDone;

  @override
  State<_RoomDanmakuFlightWidget> createState() =>
      _RoomDanmakuFlightWidgetState();
}

class _RoomDanmakuFlightWidgetState
    extends State<_RoomDanmakuFlightWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 8000),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
  double _textWidth = 0;

  @override
  void initState() {
    super.initState();
    final style = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.2,
    );
    final painter = TextPainter(
      text: TextSpan(text: widget.flight.text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    _textWidth = painter.width + 8;
    painter.dispose();
    _motion.forward();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, _) => Transform.translate(
        offset: Offset(
          widget.width - (widget.width + _textWidth) * _motion.value,
          0,
        ),
        child: Text(
          widget.flight.text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.2,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 3, offset: Offset(1, 1)),
            ],
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}
