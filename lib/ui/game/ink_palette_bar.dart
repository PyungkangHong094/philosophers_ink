/// 인게임 잉크 팔레트 (GDD 8.3). debug_hud를 대체하는 정식 HUD.
///
/// InkController를 구독해 노출 잉크병(색 게이지 + 잔량 tabular)을 그린다. 병 탭 → 선택 변경.
/// 선택은 골드 보더, 고갈은 명도 저하. [vertical]=우측 상단 컴팩트 세로 스택(반투명 배경).
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

class InkPaletteBar extends StatefulWidget {
  final InkController controller;

  /// 병 선택 시 콜백 (햅틱 훅).
  final VoidCallback? onSelect;

  /// 잔량 숫자 강조(마이크로 피드백) — 첫 스트로크 시 잠깐 true (GDD 7.2 게이지 이해).
  final bool emphasizeCount;

  /// 우측 상단 컴팩트 세로 스택 배치(반투명·라벨 생략). false면 가로.
  final bool vertical;

  const InkPaletteBar({
    super.key,
    required this.controller,
    this.onSelect,
    this.emphasizeCount = false,
    this.vertical = false,
  });

  @override
  State<InkPaletteBar> createState() => _InkPaletteBarState();
}

class _InkPaletteBarState extends State<InkPaletteBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    if (widget.emphasizeCount) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(InkPaletteBar old) {
    super.didUpdateWidget(old);
    if (widget.emphasizeCount && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.emphasizeCount && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _pulse]),
      builder: (context, _) {
        final controller = widget.controller;
        final inks = controller.visibleInks;
        if (inks.isEmpty) return const SizedBox.shrink();
        final emphasis = widget.emphasizeCount ? _pulse.value : 0.0;
        final vertical = widget.vertical;
        final bottles = [
          for (final ink in inks)
            Padding(
              padding: vertical
                  ? const EdgeInsets.symmetric(vertical: InkSpace.xs)
                  : const EdgeInsets.symmetric(horizontal: InkSpace.xs),
              child: _InkBottle(
                label: _inkLabel(ink),
                color: Color(propsOf(materialForInk(ink).index).argb),
                selected: controller.selected == ink,
                remaining: controller.budget.remaining(ink),
                fraction: controller.budget.fraction(ink),
                depleted: controller.budget.isDepleted(ink),
                countEmphasis: emphasis,
                compact: vertical,
                onTap: () {
                  controller.select(ink);
                  widget.onSelect?.call();
                },
              ),
            ),
        ];
        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: vertical ? InkSpace.xs : InkSpace.sm,
              vertical: vertical ? InkSpace.xs : InkSpace.sm),
          decoration: BoxDecoration(
            // 반투명 — 드로잉 영역 가림 최소화.
            color: InkColor.black2.withValues(alpha: 0.85),
            border: Border.all(color: InkColor.hairline),
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
          child: vertical
              ? Column(mainAxisSize: MainAxisSize.min, children: bottles)
              : Row(mainAxisSize: MainAxisSize.min, children: bottles),
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
  final double countEmphasis; // 0~1, 잔량 숫자 강조 펄스.
  final bool compact; // 컴팩트(세로 스택) 배치 — 라벨 생략·축소.
  final VoidCallback onTap;

  const _InkBottle({
    required this.label,
    required this.color,
    required this.selected,
    required this.remaining,
    required this.fraction,
    required this.depleted,
    required this.countEmphasis,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 컴팩트도 터치 타겟 44px+ 유지.
    final width = compact ? 46.0 : InkSpace.levelCell;
    final minHeight = compact ? 50.0 : 92.0;
    final gaugeH = compact ? 24.0 : 40.0;
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
            width: width,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? InkSpace.xs : InkSpace.sm,
                vertical: compact ? InkSpace.xs : InkSpace.sm),
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
                _VerticalGauge(color: color, fraction: fraction, height: gaugeH),
                const SizedBox(height: InkSpace.xs),
                Transform.scale(
                  scale: 1.0 + 0.35 * countEmphasis,
                  child: Text(
                    '$remaining',
                    style: InkText.caption.copyWith(
                      color: Color.lerp(InkColor.parchment, InkColor.goldHi,
                          countEmphasis),
                    ),
                  ),
                ),
                // 컴팩트에선 라벨 생략(색으로 식별) — 공간 절약.
                if (!compact)
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
  final double height;
  const _VerticalGauge(
      {required this.color, required this.fraction, this.height = 40});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Container(
      width: 14,
      height: height,
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
