/// 에디터 테스트플레이 전용 잉크 HUD (디버그 수준, 폴리시 금지).
///
/// 하단 잉크병 3개(숨김 제외) + 잔량 게이지 + 선택 표시. Container/Row 수준의
/// 기능 UI만 담는다. 인게임(사장) 셸 HUD는 셸 디자인 시스템(트루 블랙+골드, GDD 8.4)으로
/// shell-ui-engineer가 별도 구현한다. 이 위젯은 그 대체 대상이 아니라, 에디터
/// 테스트플레이 스택(level_player)에 상주하는 개발자용 HUD로 유지된다.
library;

import 'package:flutter/material.dart';

import '../sim/materials.dart';
import 'ink.dart';
import 'ink_controller.dart';

/// InkController를 구독해 잉크병 바를 그린다. 병 탭 → 선택 변경.
class InkHud extends StatelessWidget {
  final InkController controller;
  const InkHud({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final inks = controller.visibleInks;
        if (inks.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final ink in inks)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _InkBottle(
                    ink: ink,
                    selected: controller.selected == ink,
                    remaining: controller.budget.remaining(ink),
                    initial: controller.budget.initial(ink),
                    fraction: controller.budget.fraction(ink),
                    depleted: controller.budget.isDepleted(ink),
                    onTap: () => controller.select(ink),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 잉크병 1개: 색 스와치 + 세로 게이지 + 잔량 숫자 + 라벨. 선택 시 골드 보더.
class _InkBottle extends StatelessWidget {
  final InkType ink;
  final bool selected;
  final int remaining;
  final int initial;
  final double fraction;
  final bool depleted;
  final VoidCallback onTap;

  const _InkBottle({
    required this.ink,
    required this.selected,
    required this.remaining,
    required this.initial,
    required this.fraction,
    required this.depleted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inkColor = Color(propsOf(ink.material.index).argb);
    // 선택은 골드 보더, 고갈은 반투명으로 구분 (기능 표시만, 폴리시 아님).
    final borderColor =
        selected ? const Color(0xFFC9A227) : const Color(0xFF29271F);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: depleted ? 0.4 : 1.0,
        // 터치 타겟 최소 44px (GDD 8.4.7).
        child: Container(
          width: 52,
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 세로 게이지: 트랙 위에 잔량 비율만큼 잉크색 채움.
              _VerticalGauge(color: inkColor, fraction: fraction),
              const SizedBox(height: 4),
              Text(
                '$remaining',
                style: const TextStyle(
                  color: Color(0xFFF2EDDF),
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                ink.debugLabel,
                style: const TextStyle(
                  color: Color(0xFF9C968A),
                  fontSize: 10,
                ),
              ),
            ],
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
        border: Border.all(color: const Color(0xFF29271F)),
        borderRadius: BorderRadius.circular(2),
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
