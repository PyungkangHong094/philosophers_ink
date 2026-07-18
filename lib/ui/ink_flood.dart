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
Route<T> inkFloodRoute<T>({
  required WidgetBuilder builder,
  required Offset origin,
  required bool reducedMotion,
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
      return AnimatedBuilder(
        animation: curved,
        builder: (context, _) => ClipPath(
          clipper: _CircleReveal(origin: origin, fraction: curved.value),
          child: child,
        ),
      );
    },
  );
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
