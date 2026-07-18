/// 인게임 하단 잉크 팔레트 바 (GDD 8.3). debug_hud를 대체하는 정식 HUD.
///
/// InkController를 구독해 노출 잉크병(색 스와치 + 세로 게이지 + 잔량 tabular)을 그린다.
/// 병 탭 → 선택 변경. 선택은 골드 보더, 고갈은 명도 저하. 셸 토큰만 사용.
library;

import 'package:flutter/material.dart';

import '../../gameplay/ink_controller.dart';
import '../../sim/materials.dart';
import '../tokens.dart';

/// 잉크 종류별 한글 라벨 (인게임 표기).
String _inkLabel(InkType t) => switch (t) {
      InkType.chalk => '석필',
      InkType.heat => '화염',
      InkType.frost => '서리',
    };

class InkPaletteBar extends StatelessWidget {
  final InkController controller;

  /// 병 선택 시 콜백 (햅틱 훅).
  final VoidCallback? onSelect;

  const InkPaletteBar({super.key, required this.controller, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final inks = controller.visibleInks;
        if (inks.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: InkSpace.sm, vertical: InkSpace.sm),
          decoration: BoxDecoration(
            color: InkColor.black2,
            border: Border.all(color: InkColor.hairline),
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final ink in inks)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: InkSpace.xs),
                  child: _InkBottle(
                    label: _inkLabel(ink),
                    color: Color(propsOf(materialForInk(ink).index).argb),
                    selected: controller.selected == ink,
                    remaining: controller.budget.remaining(ink),
                    fraction: controller.budget.fraction(ink),
                    depleted: controller.budget.isDepleted(ink),
                    onTap: () {
                      controller.select(ink);
                      onSelect?.call();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InkBottle extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final int remaining;
  final double fraction;
  final bool depleted;
  final VoidCallback onTap;

  const _InkBottle({
    required this.label,
    required this.color,
    required this.selected,
    required this.remaining,
    required this.fraction,
    required this.depleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label 잉크 $remaining',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: depleted ? 0.4 : 1.0,
          child: Container(
            width: InkSpace.levelCell, // 56 — 터치 타겟.
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.symmetric(
                horizontal: InkSpace.sm, vertical: InkSpace.sm),
            decoration: BoxDecoration(
              color: selected ? InkColor.black3 : Colors.transparent,
              border: Border.all(
                color: selected ? InkColor.gold : InkColor.hairline,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(InkSpace.radius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VerticalGauge(color: color, fraction: fraction),
                const SizedBox(height: InkSpace.xs),
                Text(
                  '$remaining',
                  style: InkText.caption.copyWith(color: InkColor.parchment),
                ),
                Text(
                  label,
                  style: InkText.caption.copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalGauge extends StatelessWidget {
  final Color color;
  final double fraction;
  const _VerticalGauge({required this.color, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Container(
      width: 14,
      height: 40,
      decoration: BoxDecoration(
        border: Border.all(color: InkColor.hairline),
        borderRadius: BorderRadius.circular(InkSpace.radius),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: f,
          widthFactor: 1,
          child: Container(color: color),
        ),
      ),
    );
  }
}
