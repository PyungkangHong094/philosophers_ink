/// 잉크 소진 넛지 (실플레이 P2) — 모든 잉크 잔량 0 + 미클리어로 방치될 때, 실패 개념이 없는
/// 게임이라 막막해지는 것을 막는다. 하단 1줄 안내 + 재시작 버튼으로 부드럽게 시선 유도.
///
/// 골드 희소성 준수 — 골드 아님(무채). 등장 시 1회 펄스(reduced motion 시 정적).
library;

import 'package:flutter/material.dart';

import '../tokens.dart';

class InkExhaustNudge extends StatefulWidget {
  final VoidCallback onRetry;
  final bool reducedMotion;
  const InkExhaustNudge({
    super.key,
    required this.onRetry,
    required this.reducedMotion,
  });

  /// 안내 문구 (알림 톤 -어요 + 가운뎃점 분리, 감사안).
  static const String message = '잉크가 떨어졌어요 · 다시 하기';

  @override
  State<InkExhaustNudge> createState() => _InkExhaustNudgeState();
}

class _InkExhaustNudgeState extends State<InkExhaustNudge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: InkMotion.ritual, // 1회 부드러운 펄스
    );
    if (!widget.reducedMotion) {
      _pulse.forward();
    } else {
      _pulse.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: InkExhaustNudge.message,
      child: GestureDetector(
        onTap: widget.onRetry,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            // 1회 펄스: 0→1 구간에서 살짝 부풀었다 가라앉는다.
            final t = _pulse.value;
            final bump = widget.reducedMotion ? 0.0 : (t < 0.5 ? t * 2 : (1 - t) * 2);
            final scale = 1.0 + 0.04 * bump;
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: InkSpace.md, vertical: InkSpace.sm),
            decoration: BoxDecoration(
              color: InkColor.black2,
              border: Border.all(color: InkColor.hairline),
              borderRadius: BorderRadius.circular(InkSpace.radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  InkExhaustNudge.message,
                  style: InkText.body.copyWith(color: InkColor.parchment),
                ),
                const SizedBox(width: InkSpace.sm),
                const Icon(Icons.refresh, color: InkColor.text2, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
