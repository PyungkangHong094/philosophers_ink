/// 셸 공용 컴포넌트 (GDD 8.4.6). 전부 tokens.dart 참조 — hex·매직 수치 없음.
///
/// 골드 희소성: 골드를 쓰는 컴포넌트는 [InkCTA]·별 획득·현재 레벨 셀뿐. 나머지는 무채.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Primary CTA — 골드 필 + black0 텍스트. 프레스 시 goldDeep. radius 2 (샤프).
class InkCTA extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  const InkCTA({super.key, required this.label, this.onTap, this.expand = false});

  @override
  State<InkCTA> createState() => _InkCTAState();
}

class _InkCTAState extends State<InkCTA> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InkMotion.fast,
          width: widget.expand ? double.infinity : null,
          constraints: const BoxConstraints(minHeight: InkSpace.touchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              horizontal: InkSpace.lg, vertical: InkSpace.md),
          decoration: BoxDecoration(
            color: !enabled
                ? InkColor.goldDeep
                : (_pressed ? InkColor.goldDeep : InkColor.gold),
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
          child: Text(widget.label.toUpperCase(), style: InkText.cta),
        ),
      ),
    );
  }
}

/// Ghost 버튼 — 투명 + 헤어라인 보더 + parchment. 프레스 시 black3.
class InkGhostButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool expand;
  const InkGhostButton(
      {super.key, required this.label, this.onTap, this.expand = false});

  @override
  State<InkGhostButton> createState() => _InkGhostButtonState();
}

class _InkGhostButtonState extends State<InkGhostButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InkMotion.fast,
          width: widget.expand ? double.infinity : null,
          constraints: const BoxConstraints(minHeight: InkSpace.touchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              horizontal: InkSpace.lg, vertical: InkSpace.md),
          decoration: BoxDecoration(
            color: _pressed ? InkColor.black3 : Colors.transparent,
            border: Border.all(color: InkColor.hairline),
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
          child: Text(
            widget.label.toUpperCase(),
            style: InkText.cta.copyWith(
              color: enabled ? InkColor.parchment : InkColor.text3,
            ),
          ),
        ),
      ),
    );
  }
}

/// 아이브로우 라벨 — 넓은 자간 대문자 소형.
class InkEyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  const InkEyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: color == null
            ? InkText.eyebrow
            : InkText.eyebrow.copyWith(color: color),
      );
}

/// 별 1~3 표시 행. 획득 = 골드+글로우, 미획득 = 헤어라인 아웃라인.
class StarRow extends StatelessWidget {
  final int filled;
  final int total;
  final double size;

  /// 스탬프 애니메이션 진행 (0~1). null이면 정적.
  final double? stampProgress;

  const StarRow({
    super.key,
    required this.filled,
    this.total = 3,
    this.size = 16,
    this.stampProgress,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.12),
            child: _Star(
              filled: i < filled,
              size: size,
              // 스태거: i번째 별은 progress가 (i/total) 이후 구간에서 나타난다.
              appear: stampProgress == null
                  ? 1.0
                  : (((stampProgress! * total) - i).clamp(0.0, 1.0)),
            ),
          ),
      ],
    );
  }
}

class _Star extends StatelessWidget {
  final bool filled;
  final double size;
  final double appear; // 0~1, 스탬프 등장
  const _Star({required this.filled, required this.size, required this.appear});

  @override
  Widget build(BuildContext context) {
    // 오버슛 스케일 1.6→1.0.
    final scale = filled ? (1.0 + 0.6 * (1.0 - appear)) : 1.0;
    final opacity = filled ? appear : 1.0;
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Icon(
          filled ? Icons.star : Icons.star_border,
          size: size,
          color: filled ? InkColor.gold : InkColor.hairline,
          shadows: filled && appear >= 0.999
              ? const [Shadow(color: InkColor.goldHi, blurRadius: 8)]
              : null,
        ),
      ),
    );
  }
}

/// 게이지 — 트랙 헤어라인 1px, 필 골드, 값 tabular. 잉크 잔량 등.
class InkGauge extends StatelessWidget {
  final double fraction;
  final String? valueLabel;
  const InkGauge({super.key, required this.fraction, this.valueLabel});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (valueLabel != null) ...[
          Text(valueLabel!, style: InkText.caption),
          const SizedBox(height: InkSpace.xs),
        ],
        Container(
          height: 6,
          decoration: BoxDecoration(
            border: Border.all(color: InkColor.hairline),
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: f,
            child: Container(
              decoration: BoxDecoration(
                color: InkColor.gold,
                borderRadius: BorderRadius.circular(InkSpace.radius),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 카드 — black2 + 헤어라인 + radius 2. 그림자 금지 (깊이는 명도로만).
class InkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  /// 좌측 챕터색 스파인 (챕터 카드). null이면 없음.
  final Color? spine;
  final bool highlighted; // 현재 챕터 — 골드 보더.

  const InkCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.spine,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(InkSpace.md),
      decoration: BoxDecoration(
        color: InkColor.black2,
        border: Border.all(
          color: highlighted ? InkColor.gold : InkColor.hairline,
        ),
        borderRadius: BorderRadius.circular(InkSpace.radius),
      ),
      child: child,
    );
    if (spine != null) {
      content = Stack(
        children: [
          content,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: spine),
          ),
        ],
      );
    }
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}
