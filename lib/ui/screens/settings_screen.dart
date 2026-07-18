/// 설정 화면 (GDD 8.4.4 설정) — 리스트 + 헤어라인 구분. 토글 온 상태만 골드.
///
/// 사운드(M5 훅)·햅틱·모션 줄이기 토글. 기존 인앱 에디터는 디버그 빌드에서만 하단
/// 히든 진입 경로로 유지한다(GDD 10.6, kDebugMode 가드).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../level/editor/editor_screen.dart';
import '../app.dart';
import '../tokens.dart';
import '../widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = InkServices.of(context).settings;
    return Scaffold(
      backgroundColor: InkColor.black1,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    InkSpace.md, InkSpace.sm, InkSpace.md, 0),
                child: Row(
                  children: [
                    _BackButton(),
                    const SizedBox(width: InkSpace.sm),
                    Text('설정', style: InkText.titleKo),
                  ],
                ),
              ),
              const SizedBox(height: InkSpace.md),
              _ToggleRow(
                label: '사운드',
                caption: '효과음·앰비언트',
                value: settings.sound,
                onChanged: (v) => settings.sound = v,
              ),
              if (settings.sound)
                _VolumeRow(
                  value: settings.volume,
                  onChanged: (v) => settings.volume = v,
                  onChangeEnd: (_) => InkServices.of(context).audio.uiTap(),
                ),
              _ToggleRow(
                label: '햅틱',
                caption: '진동 피드백',
                value: settings.haptics,
                onChanged: (v) => settings.haptics = v,
              ),
              _ToggleRow(
                label: '모션 줄이기',
                caption: '전환·애니메이션 최소화',
                value: settings.reducedMotion,
                onChanged: (v) => settings.reducedMotion = v,
              ),
              _ActionRow(
                label: '안내 다시 보기',
                caption: '목표·조작·별점 안내를 처음처럼',
                actionLabel: '초기화',
                onTap: () {
                  InkServices.of(context).onboarding.reset();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('안내를 초기화했다'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const Spacer(),
              if (kDebugMode)
                Padding(
                  padding: const EdgeInsets.all(InkSpace.lg),
                  child: InkGhostButton(
                    label: '레벨 에디터 (디버그)',
                    expand: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const EditorScreen()),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 액션 행 — 우측에 고스트 버튼(초기화 등). 헤어라인 구분.
class _ActionRow extends StatelessWidget {
  final String label;
  final String caption;
  final String actionLabel;
  final VoidCallback onTap;

  const _ActionRow({
    required this.label,
    required this.caption,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: InkSpace.touchTarget),
      padding: const EdgeInsets.symmetric(
          horizontal: InkSpace.lg, vertical: InkSpace.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: InkColor.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: InkText.body.copyWith(color: InkColor.parchment)),
                Text(caption, style: InkText.caption),
              ],
            ),
          ),
          InkGhostButton(label: actionLabel, onTap: onTap),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String caption;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.caption,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(
        constraints: const BoxConstraints(minHeight: InkSpace.touchTarget),
        padding: const EdgeInsets.symmetric(
            horizontal: InkSpace.lg, vertical: InkSpace.md),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: InkColor.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: InkText.body
                          .copyWith(color: InkColor.parchment)),
                  Text(caption, style: InkText.caption),
                ],
              ),
            ),
            _Switch(value: value),
          ],
        ),
      ),
    );
  }
}

/// 볼륨 슬라이더 행 — 활성 트랙만 골드. 사운드 켜짐일 때만 노출.
class _VolumeRow extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _VolumeRow({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: InkSpace.touchTarget),
      padding: const EdgeInsets.symmetric(
          horizontal: InkSpace.lg, vertical: InkSpace.sm),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: InkColor.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text('볼륨', style: InkText.body),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: InkColor.gold,
                inactiveTrackColor: InkColor.hairline,
                thumbColor: InkColor.gold,
                overlayColor: InkColor.goldDeep,
                trackHeight: 2,
              ),
              child: Slider(
                value: value,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${(value * 100).round()}',
              textAlign: TextAlign.end,
              style: InkText.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// 토글 스위치 — 온 상태만 골드 (GDD 8.4.4).
class _Switch extends StatelessWidget {
  final bool value;
  const _Switch({required this.value});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: AnimatedContainer(
        duration: InkMotion.fast,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? InkColor.gold : InkColor.black3,
          border: Border.all(
              color: value ? InkColor.gold : InkColor.hairline),
          borderRadius: BorderRadius.circular(InkSpace.radius),
        ),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: value ? InkColor.black0 : InkColor.text2,
            borderRadius: BorderRadius.circular(InkSpace.radius),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '뒤로',
        child: GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: InkSpace.touchTarget,
            height: InkSpace.touchTarget,
            alignment: Alignment.center,
            child: const Icon(Icons.arrow_back,
                color: InkColor.text2, size: 22),
          ),
        ),
      );
}
