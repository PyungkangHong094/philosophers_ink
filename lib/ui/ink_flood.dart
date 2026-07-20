/// 시그니처 전환 — 잉크 플러드 (GDD 8.4.5).
///
/// 레벨 셀 탭 좌표를 기점으로 챕터색(=인게임 배경색) 원이 방사형으로 확장되어 화면을
/// 삼키고 그대로 인게임 배경이 된다. 복귀(pop)는 역방향 수축. 셸→인게임의 유일한 유채색 순간.
/// reduced motion 시 즉시 컷. 폴리시(입자·룬)는 M5.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// [origin](전역 좌표)에서 원형으로 확장하며 [builder]의 화면을 드러내는 라우트.
/// 원 밖은 투명 — 아래의 셸(블랙)이 비쳐, 색이 탭 지점에서 번지는 인상을 준다.
///
/// [floodColor]가 주어지면 확장하는 원의 앞머리에 그 색을 밝게 올린 잉크 메니스커스
/// 링을 얹어 마감한다(골드가 아닌 플러드색 자체 — GDD "유일한 유채색" 순수성 유지).
Route<T> inkFloodRoute<T>({
  required WidgetBuilder builder,
  required Offset origin,
  required bool reducedMotion,
  Color? floodColor,
}) {
  return PageRouteBuilder<T>(
    opaque: false,
    barrierColor: null,
    transitionDuration: reducedMotion ? Duration.zero : InkMotion.ritual,
    reverseTransitionDuration: reducedMotion ? Duration.zero : InkMotion.ritual,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondary, child) {
      if (reducedMotion) return child;
      final curved = CurvedAnimation(parent: animation, curve: InkMotion.flood);
      // 메니스커스 링 색 = 플러드색을 양피지(웜 화이트) 쪽으로 살짝 당긴 밝은 변주.
      // 순백 대신 parchment 토큰으로 당겨 셸 웜 톤 유지(순백 금지 규율).
      final edge = floodColor == null
          ? null
          : Color.lerp(floodColor, InkColor.parchment, 0.35);
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => Stack(
          children: [
            ClipPath(
              clipper: _CircleReveal(origin: origin, fraction: curved.value),
              child: child,
            ),
            if (edge != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _FloodEdge(
                      origin: origin,
                      fraction: curved.value,
                      color: edge,
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

/// 확장하는 원 앞머리의 잉크 메니스커스 링 (플러드색 밝은 변주, 소프트 글로우).
class _FloodEdge extends CustomPainter {
  final Offset origin;
  final double fraction;
  final Color color;
  _FloodEdge(
      {required this.origin, required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (fraction <= 0 || fraction >= 1) return; // 시작·완료 시엔 링 없음.
    final dx = origin.dx > size.width / 2 ? origin.dx : size.width - origin.dx;
    final dy = origin.dy > size.height / 2 ? origin.dy : size.height - origin.dy;
    final maxR = Offset(dx, dy).distance;
    final r = maxR * fraction;
    // 앞머리에 가까울수록 진하고, 끝에서 사라진다.
    final alpha = (1 - fraction) * 0.7;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(origin, r, paint);
  }

  @override
  bool shouldRepaint(_FloodEdge old) =>
      old.fraction != fraction || old.origin != origin || old.color != color;
}

class _CircleReveal extends CustomClipper<Path> {
  final Offset origin;
  final double fraction;
  const _CircleReveal({required this.origin, required this.fraction});

  double _maxRadius(Size size) {
    // 원점에서 가장 먼 모서리까지 거리 → 그 반경이면 화면 전체를 덮는다.
    final dx = origin.dx > size.width / 2 ? origin.dx : size.width - origin.dx;
    final dy = origin.dy > size.height / 2 ? origin.dy : size.height - origin.dy;
    return Offset(dx, dy).distance;
  }

  @override
  Path getClip(Size size) {
    final r = _maxRadius(size) * fraction.clamp(0.0, 1.0);
    return Path()..addOval(Rect.fromCircle(center: origin, radius: r));
  }

  @override
  bool shouldReclip(_CircleReveal old) =>
      old.fraction != fraction || old.origin != origin;
}
