/// 클리어 오버레이 (GDD 8.4.4 클리어 화면).
///
/// black0 오버레이 → 아이브로우(챕터·레벨) → 한글 Display "정제 완료" → 골드 별 순차 스탬프
/// (햅틱 동기) → 잉크 잔량 게이지 → CTA [다음 레벨](골드) / [다시 정제](고스트).
/// reduced motion 시 스탬프는 페이드로 대체.
library;

import 'dart:math' as math;

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

  /// 레벨 선택(홈)으로 복귀.
  final VoidCallback onHome;

  final bool reducedMotion;

  /// 별 1개가 스탬프될 때마다 호출 (햅틱).
  final VoidCallback? onStarStamped;

  /// 첫 클리어 별점 설명 1줄 (GDD 7.2). null이면 표시 안 함(이미 봄).
  final String? starHelp;

  /// 이번 판 사용량/임계 1줄 (별점 설명과 함께만 노출).
  final String? usageLine;

  const ClearOverlay({
    super.key,
    required this.eyebrow,
    required this.stars,
    required this.inkRemainingFraction,
    required this.inkGaugeLabel,
    required this.onNext,
    required this.onRetry,
    required this.onHome,
    required this.reducedMotion,
    this.onStarStamped,
    this.starHelp,
    this.usageLine,
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
              // 별 스탬프 + 골드 파티클 버스트 (reduced motion 시 파티클 생략).
              SizedBox(
                width: 220,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (!widget.reducedMotion)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _StarParticles(
                            stars: widget.stars,
                            progress: _controller.value,
                          ),
                        ),
                      ),
                    StarRow(
                      filled: widget.stars,
                      size: 40,
                      stampProgress:
                          widget.reducedMotion ? 1.0 : _controller.value,
                    ),
                  ],
                ),
              ),
              // 첫 클리어 별점 설명 1줄 + 사용량/임계 (GDD 7.2).
              if (widget.starHelp != null) ...[
                const SizedBox(height: InkSpace.md),
                Text(widget.starHelp!,
                    style: InkText.body, textAlign: TextAlign.center),
                if (widget.usageLine != null) ...[
                  const SizedBox(height: InkSpace.xs),
                  Text(widget.usageLine!,
                      style: InkText.caption.copyWith(color: InkColor.gold)),
                ],
              ],
              const SizedBox(height: InkSpace.xl),
              SizedBox(
                width: 220,
                child: InkGauge(
                  fraction: widget.inkRemainingFraction,
                  valueLabel: widget.inkGaugeLabel,
                ),
              ),
              const SizedBox(height: InkSpace.xl),
              // 위계: 다음 레벨(골드 CTA, 유일 골드) > 다시 하기 > 홈으로 (고스트).
              if (widget.onNext != null) ...[
                SizedBox(
                  width: 220,
                  child: InkCTA(label: '다음 레벨', onTap: widget.onNext),
                ),
                const SizedBox(height: InkSpace.sm),
              ],
              SizedBox(
                width: 220,
                child: InkGhostButton(label: '다시 하기', onTap: widget.onRetry),
              ),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                width: 220,
                child: InkGhostButton(label: '홈으로', onTap: widget.onHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 별 스탬프 골드 파티클 — 각 별이 착지하는 순간 그 위치에서 골드 입자가 솟아 페이드.
class _StarParticles extends CustomPainter {
  final int stars;
  final double progress; // 0~1 전체 스탬프 진행
  _StarParticles({required this.stars, required this.progress});

  static const int _perStar = 7;
  static const double _spacing = 49.6; // StarRow size 40 * (1+2*0.12)

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final cx = size.width / 2;
    final paint = Paint();
    for (var i = 0; i < stars; i++) {
      // i번째 별 착지 시각과 그 이후 로컬 진행.
      final t0 = i / stars;
      final local = ((progress - t0) * stars).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final sx = cx + (i - (stars - 1) / 2.0) * _spacing;
      for (var k = 0; k < _perStar; k++) {
        final seed = (i * 13 + k * 7) % 100 / 100.0;
        final ang = seed * 2 * math.pi;
        final dist = (8 + seed * 26) * local;
        final px = sx + math.cos(ang) * dist;
        final py = cy - math.sin(ang).abs() * dist * 1.2; // 위로 솟음
        final r = (2.2 * (1 - local)).clamp(0.4, 2.2);
        paint.color = InkColor.goldHi.withValues(alpha: (1 - local) * 0.9);
        canvas.drawCircle(Offset(px, py), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarParticles old) =>
      old.progress != progress || old.stars != stars;
}

/// 실패(오염) 오버레이 — 재시작 유도. 별 없음, 골드 없음(무채).
/// 타이틀·설명은 픽션 톤, 버튼은 평이한 한국어.
class FailOverlay extends StatelessWidget {
  final String eyebrow;
  final VoidCallback onRetry;
  final VoidCallback onHome;
  const FailOverlay({
    super.key,
    required this.eyebrow,
    required this.onRetry,
    required this.onHome,
  });

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
                child: InkGhostButton(label: '다시 하기', onTap: onRetry),
              ),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                width: 220,
                child: InkGhostButton(label: '홈으로', onTap: onHome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
