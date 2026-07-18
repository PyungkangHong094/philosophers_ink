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

  const PauseOverlay({
    super.key,
    required this.eyebrow,
    required this.onResume,
    required this.onRetry,
    required this.onExit,
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
              Text('멈춤', style: InkText.titleKo),
              const SizedBox(height: InkSpace.xl),
              SizedBox(
                  width: 220,
                  child: InkGhostButton(label: '계속', onTap: onResume)),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                  width: 220,
                  child: InkGhostButton(label: '재시작', onTap: onRetry)),
              const SizedBox(height: InkSpace.sm),
              SizedBox(
                  width: 220,
                  child: InkGhostButton(label: '나가기', onTap: onExit)),
            ],
          ),
        ),
      ),
    );
  }
}
