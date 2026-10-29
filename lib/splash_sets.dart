import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'splash_selection.dart';

class SplashSet {
  const SplashSet({
    required this.id,
    required this.name,
    required this.effect,
    required this.build,
  });

  final String id;
  final String name;
  final String effect;
  final Widget Function() build;
}

const List<SplashSet> splashSets = [
  SplashSet(
    id: splashSetAntCinema,
    name: '蚂蚁看电影',
    effect: '影院座椅前红蚁看银幕，银幕光晕呼吸，爆米花轻跳',
    build: AntCinemaSplash.new,
  ),
  SplashSet(
    id: splashSetWindows,
    name: 'Windows 风格',
    effect: '四格窗口标志配转圈圆点',
    build: WindowsSplash.new,
  ),
  SplashSet(
    id: splashSetIos,
    name: 'iOS 风格',
    effect: '黑底蚂蚁吃苹果标志居中淡入',
    build: IosSplash.new,
  ),
  SplashSet(
    id: splashSetHuawei,
    name: '华为鸿蒙风格',
    effect: '简洁明亮开机界面，蚂蚁标志配横向光扫',
    build: HuaweiSplash.new,
  ),
  SplashSet(
    id: splashSetNeonAnt,
    name: '霓虹火蚁',
    effect: '红蚁配粉蓝霓虹圆环，闪电微光闪烁',
    build: NeonAntSplash.new,
  ),
  SplashSet(
    id: splashSetStarryAnt,
    name: '星空蚂蚁',
    effect: '星空闪烁，流星划过，红蚁缓缓漂浮',
    build: StarryAntSplash.new,
  ),
  SplashSet(
    id: splashSetFilm,
    name: '胶片放映',
    effect: '胶片条循环滚动，放映机光束闪烁',
    build: FilmSplash.new,
  ),
  SplashSet(
    id: splashSetMinimalLines,
    name: '极简线条',
    effect: '白底线条蚂蚁一笔一笔描出又隐去',
    build: MinimalLinesSplash.new,
  ),
  SplashSet(
    id: splashSetMidnightCinema,
    name: '暗夜影院',
    effect: '暗夜影厅银幕微光，尘埃上浮',
    build: MidnightCinemaSplash.new,
  ),
  SplashSet(
    id: splashSetLaserAnt,
    name: '激光电影',
    effect: '机械蚂蚁向前投射激光光束，成像放映画面',
    build: LaserAntSplash.new,
  ),
];

SplashSet? splashSetById(String id) {
  for (final set in splashSets) {
    if (set.id == id) return set;
  }
  return null;
}

String splashSelectionDisplayName(String id) {
  if (id == splashSelectionCustom) return '自定义图片';
  if (id == splashSelectionDefault) return '默认启动图';
  return splashSetById(id)?.name ?? '默认启动图';
}

class AntPainter extends CustomPainter {
  const AntPainter({
    required this.bodyColor,
    required this.abdomenColor,
    required this.legColor,
  });

  final Color bodyColor;
  final Color abdomenColor;
  final Color legColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 200, size.height / 150);
    canvas.translate(
      (size.width - 200 * scale) / 2,
      (size.height - 150 * scale) / 2,
    );
    canvas.scale(scale);
    final body = Paint()..color = bodyColor;
    final abdomen = Paint()..color = abdomenColor;
    final leg = Paint()
      ..color = legColor
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final eye = Paint()..color = Colors.white;
    canvas.drawOval(const Rect.fromLTWH(96, 58, 96, 76), abdomen);
    canvas.drawOval(const Rect.fromLTWH(70, 64, 52, 44), body);
    canvas.drawCircle(const Offset(52, 52), 26, body);
    canvas.drawCircle(const Offset(46, 46), 6, eye);
    canvas.drawCircle(const Offset(46, 46), 3, Paint()..color = Colors.black);
    final antenna = Paint()
      ..color = legColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final a1 = Path()
      ..moveTo(44, 30)
      ..quadraticBezierTo(30, 6, 12, 4);
    final a2 = Path()
      ..moveTo(58, 28)
      ..quadraticBezierTo(62, 2, 84, 0);
    canvas.drawPath(a1, antenna);
    canvas.drawPath(a2, antenna);
    for (var i = 0; i < 3; i++) {
      final x = 78.0 + i * 26;
      canvas.drawLine(Offset(x, 100), Offset(x - 18, 140), leg);
      canvas.drawLine(Offset(x, 100), Offset(x + 18, 140), leg);
    }
  }

  @override
  bool shouldRepaint(AntPainter oldDelegate) =>
      bodyColor != oldDelegate.bodyColor ||
      abdomenColor != oldDelegate.abdomenColor ||
      legColor != oldDelegate.legColor;
}

class AntLinePainter extends CustomPainter {
  const AntLinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  Path _antPath() {
    final path = Path();
    path.addOval(Rect.fromCircle(center: Offset(52, 52), radius: 26));
    path.addOval(const Rect.fromLTWH(70, 64, 52, 44));
    path.addOval(const Rect.fromLTWH(96, 58, 96, 76));
    path.moveTo(44, 30);
    path.quadraticBezierTo(30, 6, 12, 4);
    path.moveTo(58, 28);
    path.quadraticBezierTo(62, 2, 84, 0);
    for (var i = 0; i < 3; i++) {
      final x = 78.0 + i * 26;
      path.moveTo(x, 100);
      path.lineTo(x - 18, 140);
      path.moveTo(x, 100);
      path.lineTo(x + 18, 140);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 200, size.height / 150);
    canvas.translate(
      (size.width - 200 * scale) / 2,
      (size.height - 150 * scale) / 2,
    );
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final metrics = _antPath().computeMetrics().toList();
    var total = 0.0;
    for (final m in metrics) {
      total += m.length;
    }
    var remaining = total * progress.clamp(0.0, 1.0);
    for (final m in metrics) {
      if (remaining <= 0) break;
      final take = math.min(m.length, remaining);
      canvas.drawPath(m.extractPath(0, take), paint);
      remaining -= take;
    }
  }

  @override
  bool shouldRepaint(AntLinePainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}

class NeonRingPainter extends CustomPainter {
  const NeonRingPainter({required this.glow});

  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final pink = Paint()
      ..color = const Color(0xFFFF2E9A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + glow * 8);
    final blue = Paint()
      ..color = const Color(0xFF2EC5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + glow * 8);
    canvas.drawCircle(center, radius, pink);
    canvas.drawCircle(center, radius * 0.82, blue);
    canvas.drawCircle(center, radius, pink..maskFilter = null);
    canvas.drawCircle(center, radius * 0.82, blue..maskFilter = null);
  }

  @override
  bool shouldRepaint(NeonRingPainter oldDelegate) => glow != oldDelegate.glow;
}

class LightningPainter extends CustomPainter {
  const LightningPainter({required this.opacity, required this.color});

  final double opacity;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final path = Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width * 0.4, size.height * 0.45)
      ..lineTo(size.width * 0.6, size.height * 0.45)
      ..lineTo(size.width * 0.3, size.height);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(LightningPainter oldDelegate) =>
      opacity != oldDelegate.opacity || color != oldDelegate.color;
}

class StarFieldPainter extends CustomPainter {
  const StarFieldPainter({required this.time});

  final double time;

  static const stars = [
    (0.08, 0.12, 2.2, 0.0),
    (0.22, 0.30, 1.6, 1.1),
    (0.35, 0.08, 2.6, 2.2),
    (0.52, 0.22, 1.4, 0.6),
    (0.68, 0.10, 2.0, 1.8),
    (0.82, 0.28, 1.8, 0.3),
    (0.93, 0.14, 2.4, 2.6),
    (0.15, 0.48, 1.5, 1.4),
    (0.44, 0.42, 2.1, 0.9),
    (0.60, 0.50, 1.3, 2.0),
    (0.78, 0.44, 2.3, 1.2),
    (0.90, 0.55, 1.5, 0.1),
    (0.06, 0.62, 1.9, 2.4),
    (0.28, 0.66, 1.4, 0.7),
    (0.50, 0.62, 2.2, 1.6),
    (0.66, 0.70, 1.6, 0.4),
    (0.85, 0.72, 2.0, 2.8),
    (0.18, 0.82, 1.7, 1.0),
    (0.38, 0.86, 1.3, 2.3),
    (0.58, 0.80, 2.1, 0.5),
    (0.74, 0.88, 1.5, 1.9),
    (0.94, 0.84, 1.8, 0.8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in stars) {
      final twinkle = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(time * 2 + star.$4));
      final paint = Paint()..color = Colors.white.withValues(alpha: twinkle);
      canvas.drawCircle(
        Offset(star.$1 * size.width, star.$2 * size.height),
        star.$3,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StarFieldPainter oldDelegate) => time != oldDelegate.time;
}

class _ApplePainter extends CustomPainter {
  const _ApplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final apple = Path()
      ..addOval(Rect.fromCircle(center: const Offset(55, 62), radius: 40));
    final bite = Path()
      ..addOval(Rect.fromCircle(center: const Offset(88, 38), radius: 14));
    final body = Path.combine(PathOperation.difference, apple, bite);
    canvas.drawPath(body, Paint()..color = const Color(0xFFE53935));
    final stem = Paint()
      ..color = const Color(0xFF6D4C41)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(55, 24), const Offset(58, 8), stem);
    canvas.save();
    canvas.translate(66, 16);
    canvas.rotate(-0.5);
    canvas.drawOval(
      const Rect.fromLTWH(-14, -6, 28, 12),
      Paint()..color = const Color(0xFF43A047),
    );
    canvas.restore();
    canvas.drawOval(
      Rect.fromCircle(center: const Offset(40, 48), radius: 8),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(_ApplePainter oldDelegate) => false;
}

class _RobotAntPainter extends CustomPainter {
  const _RobotAntPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = const Color(0xFF232833);
    final panel = Paint()..color = const Color(0xFF313848);
    final edge = Paint()
      ..color = const Color(0xFF4A5468)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cyan = Paint()..color = const Color(0xFF00E5FF);
    final glow = Paint()
      ..color = const Color(0xFF00E5FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 50, 48, 50),
        const Radius.circular(14),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(58, 55, 38, 40),
        const Radius.circular(8),
      ),
      panel,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(96, 50, 40, 50),
        const Radius.circular(12),
      ),
      body,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(96, 50, 40, 50),
        const Radius.circular(12),
      ),
      edge,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(136, 62, 12, 26),
        const Radius.circular(4),
      ),
      panel,
    );
    canvas.drawCircle(const Offset(118, 68), 9, glow);
    canvas.drawCircle(const Offset(118, 68), 5, cyan);
    final antenna = Paint()
      ..color = const Color(0xFF4A5468)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(110, 52), const Offset(100, 28), antenna);
    canvas.drawLine(const Offset(126, 52), const Offset(136, 28), antenna);
    canvas.drawCircle(const Offset(100, 28), 4, cyan);
    canvas.drawCircle(const Offset(136, 28), 4, cyan);
    final leg = Paint()
      ..color = const Color(0xFF313848)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final x in [30.0, 72.0, 108.0]) {
      canvas.drawLine(Offset(x, 98), Offset(x - 10, 122), leg);
      canvas.drawLine(Offset(x - 10, 122), Offset(x - 22, 140), leg);
      canvas.drawCircle(Offset(x - 10, 122), 4, cyan);
    }
    canvas.drawLine(const Offset(58, 62), const Offset(58, 88), edge);
    canvas.drawLine(const Offset(77, 62), const Offset(77, 88), edge);
  }

  @override
  bool shouldRepaint(_RobotAntPainter oldDelegate) => false;
}

class _LaserBeamPainter extends CustomPainter {
  const _LaserBeamPainter({required this.progress, required this.flicker});

  final double progress;
  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = size.width * progress.clamp(0.0, 1.0);
    if (reach <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, reach, size.height));
    final mid = size.height / 2;
    final outer = Path()
      ..moveTo(0, mid - 5)
      ..lineTo(size.width, mid - 24)
      ..lineTo(size.width, mid + 24)
      ..lineTo(0, mid + 5)
      ..close();
    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF00E5FF).withValues(alpha: 0.55),
            const Color(0xFF00E5FF).withValues(alpha: 0.10),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    final core = Paint()
      ..color = Colors.white.withValues(alpha: 0.65 + flicker * 0.3)
      ..strokeWidth = 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), core);
    final dot = Paint()..color = const Color(0xFFB2F5FF);
    for (var i = 1; i <= 4; i++) {
      final x = size.width * i / 5;
      final y = mid + math.sin(flicker * 6 + i * 1.7) * 10;
      canvas.drawCircle(Offset(x, y), 2.5, dot);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LaserBeamPainter oldDelegate) =>
      progress != oldDelegate.progress || flicker != oldDelegate.flicker;
}

class BucketPainter extends CustomPainter {
  const BucketPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width * 0.15, 0)
      ..lineTo(size.width * 0.85, 0)
      ..lineTo(size.width * 0.72, size.height)
      ..lineTo(size.width * 0.28, size.height)
      ..close();
    canvas.drawPath(path, paint);
    final kernel = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size.width * 0.3, 2), 6, kernel);
    canvas.drawCircle(Offset(size.width * 0.5, 0), 7, kernel);
    canvas.drawCircle(Offset(size.width * 0.7, 2), 6, kernel);
  }

  @override
  bool shouldRepaint(BucketPainter oldDelegate) => color != oldDelegate.color;
}

class _DustPainter extends CustomPainter {
  const _DustPainter({required this.time});

  final double time;

  static const dust = [
    (0.10, 0.20, 2.0),
    (0.25, 0.55, 1.5),
    (0.40, 0.30, 2.2),
    (0.55, 0.70, 1.6),
    (0.70, 0.40, 2.0),
    (0.85, 0.60, 1.4),
    (0.18, 0.80, 1.8),
    (0.48, 0.90, 1.5),
    (0.63, 0.15, 2.1),
    (0.92, 0.85, 1.7),
    (0.33, 0.45, 1.4),
    (0.78, 0.25, 1.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final d in dust) {
      final y = ((d.$2 + time * 0.03) % 1.0) * size.height;
      canvas.drawCircle(
        Offset(d.$1 * size.width, y),
        d.$3,
        Paint()..color = Colors.white.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(_DustPainter oldDelegate) => time != oldDelegate.time;
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({required this.flicker});

  final double flicker;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width * 0.30, size.height * 0.72)
      ..lineTo(size.width * 0.55, size.height * 0.72)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.20 + flicker * 0.08),
          Colors.white.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BeamPainter oldDelegate) =>
      flicker != oldDelegate.flicker;
}

class AntCinemaSplash extends StatefulWidget {
  const AntCinemaSplash({super.key});

  @override
  State<AntCinemaSplash> createState() => _AntCinemaSplashState();
}

class _AntCinemaSplashState extends State<AntCinemaSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final glow = 0.5 + 0.5 * math.sin(t * math.pi * 2);
        final hop = math.sin(t * math.pi * 4).abs();
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF0D0D12),
          child: Stack(
            children: [
              Align(
                alignment: const Alignment(0, -0.62),
                child: Container(
                  width: 280,
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF7FB2FF,
                        ).withValues(alpha: 0.25 + glow * 0.35),
                        blurRadius: 20 + glow * 30,
                        spreadRadius: glow * 6,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '红蚁TV',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.05),
                child: Transform.translate(
                  offset: Offset(0, -hop * 2),
                  child: const SizedBox(
                    width: 220,
                    height: 165,
                    child: CustomPaint(
                      painter: AntPainter(
                        bodyColor: Color(0xFFE53935),
                        abdomenColor: Color(0xFF1A1A1A),
                        legColor: Color(0xFFB71C1C),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 36,
                bottom: 168,
                child: Transform.translate(
                  offset: Offset(0, -hop * 10),
                  child: const SizedBox(
                    width: 56,
                    height: 64,
                    child: CustomPaint(
                      painter: BucketPainter(color: Color(0xFFD32F2F)),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 56),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 5; i++)
                            Container(
                              width: 56,
                              height: 46,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF2A2A3A),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 6; i++)
                            Container(
                              width: 48,
                              height: 40,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1E1E2C),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(14),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class WindowsSplash extends StatefulWidget {
  const WindowsSplash({super.key});

  @override
  State<WindowsSplash> createState() => _WindowsSplashState();
}

class _WindowsSplashState extends State<WindowsSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF0078D7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(-0.18),
            alignment: Alignment.center,
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 72, height: 72, color: Colors.white),
                    const SizedBox(width: 6),
                    Container(width: 72, height: 72, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 72, height: 72, color: Colors.white),
                    const SizedBox(width: 6),
                    Container(width: 72, height: 72, color: Colors.white),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 56),
          RotationTransition(
            turns: _controller,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                children: [
                  for (var i = 0; i < 8; i++)
                    Align(
                      alignment: Alignment(
                        math.cos(i * math.pi / 4),
                        math.sin(i * math.pi / 4),
                      ),
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: 0.35 + 0.65 * (i / 8),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            '红蚁TV',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class IosSplash extends StatefulWidget {
  const IosSplash({super.key});

  @override
  State<IosSplash> createState() => _IosSplashState();
}

class _IosSplashState extends State<IosSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final fade = t < 0.35 ? t / 0.35 : 1.0;
        final draw = t < 0.55 ? t / 0.55 : 1.0;
        final nibble = math.sin(t * math.pi * 6) * 2;
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Opacity(
            opacity: fade,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  height: 150,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 8,
                        top: 30,
                        child: Transform.scale(
                          scale: t < 0.3 ? 0.6 + 0.4 * (t / 0.3) : 1.0,
                          child: const SizedBox(
                            width: 110,
                            height: 110,
                            child: CustomPaint(painter: _ApplePainter()),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 118,
                        top: 8,
                        child: Transform.translate(
                          offset: Offset(-nibble, 0),
                          child: SizedBox(
                            width: 180,
                            height: 135,
                            child: CustomPaint(
                              painter: AntLinePainter(
                                progress: draw,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '红蚁TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HuaweiSplash extends StatefulWidget {
  const HuaweiSplash({super.key});

  @override
  State<HuaweiSplash> createState() => _HuaweiSplashState();
}

class _HuaweiSplashState extends State<HuaweiSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final rise = t < 0.4 ? t / 0.4 : 1.0;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFE8EEF5)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: Offset(-260 + t * 520, 0),
                  child: Transform.rotate(
                    angle: -0.35,
                    child: Container(
                      width: 90,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.9),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: rise,
                  child: Transform.translate(
                    offset: Offset(0, (1 - rise) * 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 190,
                          height: 143,
                          child: CustomPaint(
                            painter: AntPainter(
                              bodyColor: Color(0xFFE53935),
                              abdomenColor: Color(0xFF1A1A1A),
                              legColor: Color(0xFFB71C1C),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          '红蚁TV',
                          style: TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class NeonAntSplash extends StatefulWidget {
  const NeonAntSplash({super.key});

  @override
  State<NeonAntSplash> createState() => _NeonAntSplashState();
}

class _NeonAntSplashState extends State<NeonAntSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final glow = 0.5 + 0.5 * math.sin(t * math.pi * 2);
        final flicker =
            ((math.sin(t * math.pi * 18) + math.sin(t * math.pi * 46)) / 4 +
                    0.5)
                .clamp(0.0, 1.0);
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF0A0618),
          child: Stack(
            children: [
              Positioned(
                left: 8,
                top: 90,
                width: 90,
                height: 220,
                child: CustomPaint(
                  painter: LightningPainter(
                    opacity: 0.25 + flicker * 0.6,
                    color: const Color(0xFF2EC5FF),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: NeonRingPainter(glow: glow),
                            ),
                          ),
                          const Center(
                            child: SizedBox(
                              width: 200,
                              height: 150,
                              child: CustomPaint(
                                painter: AntPainter(
                                  bodyColor: Color(0xFFE53935),
                                  abdomenColor: Color(0xFF12060A),
                                  legColor: Color(0xFFFF2E9A),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '红蚁TV',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(color: Color(0xFFFF2E9A), blurRadius: 18),
                          Shadow(color: Color(0xFF2EC5FF), blurRadius: 18),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StarryAntSplash extends StatefulWidget {
  const StarryAntSplash({super.key});

  @override
  State<StarryAntSplash> createState() => _StarryAntSplashState();
}

class _StarryAntSplashState extends State<StarryAntSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final drift = math.sin(t * math.pi * 2) * 8;
        final shoot = t < 0.6 ? t / 0.6 : 1.0;
        final shootOpacity = math.sin(shoot * math.pi);
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF050816), Color(0xFF0D1B3E)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: StarFieldPainter(time: t * 10)),
              ),
              Positioned(
                left: -40 + shoot * 420,
                top: 60 + shoot * 140,
                child: Opacity(
                  opacity: shootOpacity,
                  child: Container(
                    width: 60,
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, 0.45),
                child: Transform.translate(
                  offset: Offset(0, drift),
                  child: const SizedBox(
                    width: 220,
                    height: 165,
                    child: CustomPaint(
                      painter: AntPainter(
                        bodyColor: Color(0xFF7A1010),
                        abdomenColor: Color(0xFF120404),
                        legColor: Color(0xFF2A0505),
                      ),
                    ),
                  ),
                ),
              ),
              const Align(
                alignment: Alignment(0, 0.82),
                child: Text(
                  '红蚁TV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FilmSplash extends StatefulWidget {
  const FilmSplash({super.key});

  @override
  State<FilmSplash> createState() => _FilmSplashState();
}

class _FilmSplashState extends State<FilmSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _frame() {
    return Container(
      width: 64,
      height: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C22),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < 4; i++)
                Container(width: 8, height: 8, color: Colors.white38),
            ],
          ),
          Container(width: 40, height: 40, color: Colors.white12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < 4; i++)
                Container(width: 8, height: 8, color: Colors.white38),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final flicker = 0.92 + 0.08 * math.sin(t * math.pi * 40);
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                width: 320,
                height: 420,
                child: CustomPaint(painter: _BeamPainter(flicker: flicker)),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 64,
                child: ClipRect(
                  child: Transform.translate(
                    offset: Offset(0, -t * 96),
                    child: Column(
                      children: [for (var i = 0; i < 8; i++) _frame()],
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: flicker,
                  child: Container(
                    width: 220,
                    height: 140,
                    decoration: BoxDecoration(
                      color: const Color(0xFF101018),
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        '红蚁TV',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MinimalLinesSplash extends StatefulWidget {
  const MinimalLinesSplash({super.key});

  @override
  State<MinimalLinesSplash> createState() => _MinimalLinesSplashState();
}

class _MinimalLinesSplashState extends State<MinimalLinesSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 240,
                height: 180,
                child: CustomPaint(
                  painter: AntLinePainter(
                    progress: _controller.value,
                    color: const Color(0xFFD32F2F),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '红蚁TV',
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MidnightCinemaSplash extends StatefulWidget {
  const MidnightCinemaSplash({super.key});

  @override
  State<MidnightCinemaSplash> createState() => _MidnightCinemaSplashState();
}

class _MidnightCinemaSplashState extends State<MidnightCinemaSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final glow = 0.5 + 0.5 * math.sin(t * math.pi * 2);
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: const Color(0xFF050508),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _DustPainter(time: t * 10)),
              ),
              Align(
                alignment: const Alignment(0, -0.58),
                child: Container(
                  width: 260,
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF1B2A4A), Color(0xFF0D1526)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF3D5A99,
                        ).withValues(alpha: 0.2 + glow * 0.25),
                        blurRadius: 24 + glow * 16,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '红蚁TV',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 64),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 5; i++)
                            Container(
                              width: 54,
                              height: 42,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F0F14),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(14),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 6; i++)
                            Container(
                              width: 46,
                              height: 36,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0B0B10),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class LaserAntSplash extends StatefulWidget {
  const LaserAntSplash({super.key});

  @override
  State<LaserAntSplash> createState() => _LaserAntSplashState();
}

class _LaserAntSplashState extends State<LaserAntSplash>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final beam = t < 0.35 ? t / 0.35 : 1.0;
        final screenIn = t < 0.6 ? ((t - 0.35) / 0.25).clamp(0.0, 1.0) : 1.0;
        final scan = t > 0.6 ? ((t - 0.6) / 0.4) % 1.0 : 0.0;
        final flicker = 0.5 + 0.5 * math.sin(t * math.pi * 24);
        final bob = math.sin(t * math.pi * 2) * 4;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF05060F), Color(0xFF0A1226)],
            ),
          ),
          child: Stack(
            children: [
              Align(
                alignment: const Alignment(-0.78, 0),
                child: Transform.translate(
                  offset: Offset(0, bob),
                  child: const SizedBox(
                    width: 150,
                    height: 150,
                    child: CustomPaint(painter: _RobotAntPainter()),
                  ),
                ),
              ),
              Positioned(
                left: 150,
                right: 190,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SizedBox(
                    height: 120,
                    child: CustomPaint(
                      painter: _LaserBeamPainter(
                        progress: beam,
                        flicker: flicker,
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0.78, 0),
                child: Opacity(
                  opacity: screenIn,
                  child: Container(
                    width: 170,
                    height: 110,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1428),
                      border: Border.all(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.8),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF00E5FF,
                          ).withValues(alpha: 0.3 + flicker * 0.2),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        const Center(
                          child: Text(
                            '红蚁TV',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        if (screenIn > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            top: scan * 108,
                            child: Container(
                              height: 2,
                              color: const Color(
                                0xFF00E5FF,
                              ).withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
