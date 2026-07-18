/// 온보딩 위젯 (GDD 7.2) — 목표 배너 + 첫 조작 가이드. 무채·1줄·토큰 모션.
///
/// 골드 미사용(목표·안내는 달성이 아니다). reduced motion 시 모션 정지.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// 레벨 목표 1줄 배너 — 상단에 잠깐 표시 후 페이드. [visible]로 노출 제어(3초·첫 터치).
class GoalBanner extends StatelessWidget {
  final String text;
  final bool visible;
  const GoalBanner({super.key, required this.text, required this.visible});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: InkMotion.base,
        curve: Curves.easeOut,
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
              const InkEyebrowInline('목표'),
              const SizedBox(width: InkSpace.sm),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InkText.body.copyWith(color: InkColor.parchment),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 인라인 아이브로우(배너 접두) — 넓은 자간 소형.
class InkEyebrowInline extends StatelessWidget {
  final String text;
  const InkEyebrowInline(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: InkText.eyebrow);
}

/// 첫 조작 가이드 — 1줄 + 아이콘의 부드러운 바브 모션(토큰). 첫 조작과 동시에 소멸(부모가 제어).
class FirstOpGuide extends StatefulWidget {
  final String text;
  final IconData icon;
  final bool reducedMotion;
  const FirstOpGuide({
    super.key,
    required this.text,
    required this.icon,
    required this.reducedMotion,
  });

  @override
  State<FirstOpGuide> createState() => _FirstOpGuideState();
}

class _FirstOpGuideState extends State<FirstOpGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (!widget.reducedMotion) _bob.repeat();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _bob,
            builder: (context, child) {
              final dy = widget.reducedMotion
                  ? 0.0
                  : math.sin(_bob.value * 2 * math.pi) * 5.0;
              return Transform.translate(offset: Offset(0, dy), child: child);
            },
            child: Icon(widget.icon, color: InkColor.text2, size: 30),
          ),
          const SizedBox(height: InkSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: InkSpace.md, vertical: InkSpace.sm),
            decoration: BoxDecoration(
              color: InkColor.scrim90,
              borderRadius: BorderRadius.circular(InkSpace.radius),
            ),
            child: Text(
              widget.text,
              style: InkText.body.copyWith(color: InkColor.parchment),
            ),
          ),
        ],
      ),
    );
  }
}
