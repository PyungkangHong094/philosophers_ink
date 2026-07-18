/// 클리어 오버레이 (GDD 8.4.4 클리어 화면).
///
/// black0 오버레이 → 아이브로우(챕터·레벨) → 한글 Display "정제 완료" → 골드 별 순차 스탬프
/// (햅틱 동기) → 잉크 잔량 게이지 → CTA [다음 레벨](골드) / [다시 정제](고스트).
/// reduced motion 시 스탬프는 페이드로 대체.
library;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../widgets.dart';

class ClearOverlay extends StatefulWidget {
  final String eyebrow;
  final int stars;

  /// 잉크 잔량 비율 0~1 (게이지).
  final double inkRemainingFraction;
  final String inkGaugeLabel;

  final VoidCallback? onNext;
  final VoidCallback onRetry;

  final bool reducedMotion;

  /// 별 1개가 스탬프될 때마다 호출 (햅틱).
  final VoidCallback? onStarStamped;

  const ClearOverlay({
    super.key,
    required this.eyebrow,
    required this.stars,
    required this.inkRemainingFraction,
    required this.inkGaugeLabel,
    required this.onNext,
    required this.onRetry,
    required this.reducedMotion,
    this.onStarStamped,
  });

  @override
  State<ClearOverlay> createState() => _ClearOverlayState();
}

class _ClearOverlayState extends State<ClearOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _stampedCount = 0;

  @override
  void initState() {
    super.initState();
    final total = widget.stars.clamp(0, 3);
    _controller = AnimationController(
      vsync: this,
      duration: widget.reducedMotion
          ? InkMotion.base
          : InkMotion.starStagger * (total == 0 ? 1 : total),
    )..addListener(_onTick);
    _controller.forward();
  }

  void _onTick() {
    final total = widget.stars.clamp(0, 3);
    if (total == 0) return;
    // 진행에 따라 landed 별 수를 계산, 새로 착지할 때마다 햅틱.
    final landed = (_controller.value * total).floor().clamp(0, total);
    if (landed > _stampedCount) {
      _stampedCount = landed;
      widget.onStarStamped?.call();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: InkColor.black0,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(InkSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkEyebrow(widget.eyebrow),
              const SizedBox(height: InkSpace.md),
              Text('정제 완료',
                  style: InkText.headingKo, textAlign: TextAlign.center),
              const SizedBox(height: InkSpace.lg),
              StarRow(
                filled: widget.stars,
                size: 40,
                stampProgress:
                    widget.reducedMotion ? 1.0 : _controller.value,
              ),
              const SizedBox(height: InkSpace.xl),
              SizedBox(
                width: 220,
                child: InkGauge(
                  fraction: widget.inkRemainingFraction,
                  valueLabel: widget.inkGaugeLabel,
                ),
              ),
              const SizedBox(height: InkSpace.xl),
              if (widget.onNext != null) ...[
                SizedBox(
                  width: 220,
                  child: InkCTA(label: '다음 레벨', onTap: widget.onNext),
                ),
                const SizedBox(height: InkSpace.sm),
              ],
              SizedBox(
                width: 220,
                child: InkGhostButton(label: '다시 정제', onTap: widget.onRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 실패(오염) 오버레이 — 재시작 유도. 별 없음, 골드 없음(무채).
class FailOverlay extends StatelessWidget {
  final String eyebrow;
  final VoidCallback onRetry;
  const FailOverlay({super.key, required this.eyebrow, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: InkColor.scrim90,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(InkSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkEyebrow(eyebrow),
              const SizedBox(height: InkSpace.md),
              Text('오염', style: InkText.headingKo),
              const SizedBox(height: InkSpace.sm),
              Text('순수가 깨졌다. 다시 정제해야 한다.',
                  style: InkText.body, textAlign: TextAlign.center),
              const SizedBox(height: InkSpace.xl),
              SizedBox(
                width: 220,
                child: InkGhostButton(label: '다시 정제', onTap: onRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
