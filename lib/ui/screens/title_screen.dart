/// 타이틀 화면 (GDD 8.4.4 타이틀).
///
/// black0. 중앙 골드 플라스크 라인아트 — 내부 골드 입자 상승 + 글로우 4초 호흡. 로고는
/// 라틴 Display 2행. 하단 "화면을 터치해 시작" 펄스. 골드 요소: 플라스크 1개.
/// reduced motion 시 호흡·펄스·입자 정지. 화면 어디든 탭 → 챕터 선택.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app.dart';
import '../tokens.dart';
import 'chapter_select_screen.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key});

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // 글로우 호흡 4s 주기 (GDD 8.4.5).
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  // 트리에서 분리될 때 호흡 컨트롤러를 멈춘다(감사 P3-4). 다른 라우트가 위를 덮는
  // 경우는 Flutter의 TickerMode가 이미 vsync를 뮤트하므로, 여기선 명시적 분리(pop/이동)만 다룬다.
  @override
  void deactivate() {
    _breath.stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (!_breath.isAnimating) _breath.repeat();
  }

  void _start() {
    final services = InkServices.of(context);
    final settings = services.settings;
    settings.hapticSelection();
    services.audio.uiTap();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration:
            settings.reducedMotion ? Duration.zero : InkMotion.base,
        pageBuilder: (context, animation, secondary) => const ChapterSelectScreen(),
        transitionsBuilder: (context, anim, secondary, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = InkServices.of(context).settings.reducedMotion ||
        MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: InkColor.black0,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _start,
        child: SafeArea(
          // 느슨한 제약에서 Column이 최광 자식 폭으로 수축해 좌측에 붙는 것을
          // 방지 — 전체 폭을 강제해 수평 중앙 정렬을 성립시킨다.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              children: [
              const Spacer(flex: 2),
              // 골드 로고 (만년필 펜촉 + 플라스크 + 잉크 S — 유일한 골드 요소).
              // 투명 배경 마크. reduced motion 시 완전 정적, 그 외 극미세 스케일 호흡만
              // (사각 글로우 점멸은 제거 — 실플레이 피드백 "붉은 번쩍임").
              SizedBox(
                width: 200,
                height: 240,
                child: reduced
                    ? const _LogoMark()
                    : AnimatedBuilder(
                        animation: _breath,
                        builder: (context, child) {
                          final t = 1 - (2 * _breath.value - 1).abs();
                          return Transform.scale(
                              scale: 1.0 + t * 0.015, child: child);
                        },
                        child: const _LogoMark(),
                      ),
              ),
              const SizedBox(height: InkSpace.xl),
              // 로고 라틴 2행.
              Text('PHILOSOPHER’S', style: InkText.displayM),
              Text('INK', style: InkText.displayL),
              const SizedBox(height: InkSpace.md),
              Text('현자의 잉크', style: InkText.body),
              const Spacer(flex: 2),
              // 시작 펄스.
              _StartPulse(animate: !reduced, listenable: _breath),
              const SizedBox(height: InkSpace.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartPulse extends StatelessWidget {
  final bool animate;
  final Listenable listenable;
  const _StartPulse({required this.animate, required this.listenable});

  @override
  Widget build(BuildContext context) {
    final label = Text('화면을 터치해 시작',
        style: InkText.eyebrow.copyWith(color: InkColor.text2));
    if (!animate) return label;
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, child) {
        final t = (listenable as AnimationController).value;
        final opacity = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi));
        return Opacity(opacity: opacity, child: child);
      },
      child: label,
    );
  }
}

/// 타이틀 로고 마크 (투명 배경 PNG). 배경 사각·글로우 없이 로고만 — 트루 블랙 위에
/// 깨끗하게 얹힌다.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/icon/logo_mark.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
}
