/// 타이틀 화면 (GDD 8.4.4 타이틀).
///
/// black0. 중앙 골드 플라스크 라인아트 — 내부 골드 입자 상승 + 글로우 4초 호흡. 로고는
/// 라틴 Display 2행. 하단 "화면을 터치하여 시작" 펄스. 골드 요소: 플라스크 1개.
/// reduced motion 시 호흡·펄스·입자 정지. 화면 어디든 탭 → 챕터 선택.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../tokens.dart';
import 'chapter_select_screen.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // 글로우 호흡 4s 주기 (GDD 8.4.5).
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  void _start() {
    final settings = InkServices.of(context).settings;
    settings.hapticSelection();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration:
            settings.reducedMotion ? Duration.zero : InkMotion.base,
        pageBuilder: (context, animation, secondary) => const ChapterSelectScreen(),
        transitionsBuilder: (context, anim, secondary, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = InkServices.of(context).settings.reducedMotion ||
        MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: InkColor.black0,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _start,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              // 골드 플라스크 (유일한 골드 요소).
              SizedBox(
                width: 160,
                height: 200,
                child: AnimatedBuilder(
                  animation: _breath,
                  builder: (context, _) => CustomPaint(
                    painter: _FlaskPainter(
                      phase: reduced ? 0.25 : _breath.value,
                      animate: !reduced,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: InkSpace.xl),
              // 로고 라틴 2행.
              Text('PHILOSOPHER’S', style: InkText.displayM),
              Text('INK', style: InkText.displayL),
              const SizedBox(height: InkSpace.md),
              Text('현자의 잉크', style: InkText.body),
              const Spacer(flex: 2),
              // 시작 펄스.
              _StartPulse(animate: !reduced, listenable: _breath),
              const SizedBox(height: InkSpace.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartPulse extends StatelessWidget {
  final bool animate;
  final Listenable listenable;
  const _StartPulse({required this.animate, required this.listenable});

  @override
  Widget build(BuildContext context) {
    final label = Text('화면을 터치하여 시작',
        style: InkText.eyebrow.copyWith(color: InkColor.text2));
    if (!animate) return label;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, child) {
        final t = (listenable as AnimationController).value;
        final opacity = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
        return Opacity(opacity: opacity, child: child);
      },
      child: label,
    );
  }
}

/// 골드 플라스크 라인아트 + 내부 상승 입자 + 글로우 호흡.
class _FlaskPainter extends CustomPainter {
  final double phase; // 0~1 (호흡·입자 위상)
  final bool animate;
  _FlaskPainter({required this.phase, required this.animate});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // 플라스크 실루엣 경로 (목 + 둥근 몸통).
    final neckW = w * 0.18;
    final neckTop = h * 0.06;
    final neckBottom = h * 0.34;
    final bodyR = w * 0.36;
    final bodyCy = h * 0.66;

    final path = Path()
      ..moveTo(cx - neckW / 2, neckTop)
      ..lineTo(cx - neckW / 2, neckBottom)
      ..arcToPoint(Offset(cx + neckW / 2, neckBottom),
          radius: Radius.circular(bodyR), largeArc: true, clockwise: false)
      ..lineTo(cx + neckW / 2, neckTop);

    // 글로우 (호흡 사인파).
    final glow = 0.5 + 0.5 * math.sin(phase * 2 * math.pi);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = InkColor.goldHi.withValues(alpha: 0.25 + 0.35 * glow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + 6 * glow);
    canvas.drawCircle(Offset(cx, bodyCy), bodyR, glowPaint);

    // 플라스크 라인.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..color = InkColor.gold;
    canvas.drawCircle(Offset(cx, bodyCy), bodyR, line);
    canvas.drawPath(path, line);

    // 목 마개.
    canvas.drawLine(
      Offset(cx - neckW / 2 - 4, neckTop),
      Offset(cx + neckW / 2 + 4, neckTop),
      line,
    );

    // 내부 상승 입자 (7개, 불규칙 딜레이).
    final dot = Paint()..color = InkColor.goldHi;
    for (var i = 0; i < 7; i++) {
      final seed = (i * 0.137) % 1.0;
      final t = ((phase + seed) % 1.0);
      final py = bodyCy + bodyR * 0.7 - t * bodyR * 1.3;
      final px = cx + math.sin((t + seed) * 6.28) * bodyR * 0.35;
      final r = 1.5 + 1.5 * (1 - t);
      dot.color = InkColor.goldHi.withValues(alpha: (1 - t) * 0.8);
      canvas.drawCircle(Offset(px, py), r, dot);
    }
  }

  @override
  bool shouldRepaint(_FlaskPainter old) =>
      old.phase != phase || old.animate != animate;
}
