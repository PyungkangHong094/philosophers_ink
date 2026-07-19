/// 일시정지 오버레이 (GDD 8.4.4 일시정지).
///
/// 배경을 black0 90% 오버레이로 죽인다(챕터색 차단 목적, 블러 금지 — 성능). 세로 고스트
/// 버튼 3개: 계속 / 재시작 / 나가기.
library;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../widgets.dart';

class PauseOverlay extends StatelessWidget {
  final String eyebrow;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  /// 인게임 음소거 접근 (GDD 9 — 설정 + 인게임 접근 필수). 현재 음소거 상태 + 토글.
  final bool muted;
  final VoidCallback onToggleMute;

  /// 이 레벨의 별점 임계 1줄 ("★★ ≤ 42 · ★★★ ≤ 30"). null이면 미검증 — 표시 안 함.
  final String? thresholdLine;

  const PauseOverlay({
    super.key,
    required this.eyebrow,
    required this.onResume,
    required this.onRetry,
    required this.onExit,
    required this.muted,
    required this.onToggleMute,
    this.thresholdLine,
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
              Text('일시정지', style: InkText.titleKo),
              if (thresholdLine != null) ...[
                const SizedBox(height: InkSpace.sm),
                Text(thresholdLine!,
                    style: InkText.caption.copyWith(color: InkColor.gold)),
              ],
              const SizedBox(height: InkSpace.xl),
              // 버튼은 전부 평이한 한국어 (픽션은 타이틀·아이브로우에만).
              SizedBox(
                  width: 220,
                  child: InkGhostButton(label: '계속', onTap: onResume)),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                  width: 220,
                  child: InkGhostButton(label: '다시 하기', onTap: onRetry)),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                  width: 220,
                  child: InkGhostButton(
                      label: muted ? '소리 켜기' : '소리 끄기',
                      onTap: onToggleMute)),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                  width: 220,
                  child: InkGhostButton(label: '홈으로', onTap: onExit)),
            ],
          ),
        ),
      ),
    );
  }
}
