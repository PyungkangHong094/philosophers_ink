/// 셸 앱 루트 — 서비스(설정·진행·레벨 카탈로그) 부트스트랩 + 라우팅.
///
/// 부팅 시 SharedPreferences와 레벨 카탈로그를 로드한 뒤 타이틀로 진입한다. 로드 실패나
/// 레벨 0개에도 견고하게 동작한다(빈 상태 안내). 서비스는 [InkServices]로 하위에 전달.
library;

import 'package:flutter/material.dart';

import '../audio/audio_service.dart';
import '../audio/soloud_audio_service.dart';
import '../meta/level_catalog.dart';
import '../meta/onboarding.dart';
import '../meta/progress.dart';
import '../meta/progress_store.dart';
import 'screens/title_screen.dart';
import 'settings_controller.dart';
import 'tokens.dart';

/// 하위 위젯에 서비스를 노출하는 InheritedWidget.
class InkServices extends InheritedWidget {
  final SettingsController settings;
  final GameProgress progress;
  final LevelCatalog catalog;
  final AudioService audio;
  final OnboardingState onboarding;

  const InkServices({
    super.key,
    required this.settings,
    required this.progress,
    required this.catalog,
    required this.audio,
    required this.onboarding,
    required super.child,
  });

  static InkServices of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<InkServices>();
    assert(s != null, 'InkServices가 위젯 트리에 없다');
    return s!;
  }

  @override
  bool updateShouldNotify(InkServices old) =>
      settings != old.settings ||
      progress != old.progress ||
      catalog != old.catalog ||
      audio != old.audio ||
      onboarding != old.onboarding;
}

class InkApp extends StatelessWidget {
  /// 오디오 서비스 주입 (테스트에서 [SilentAudioService]). null이면 실제 SoLoud.
  final AudioService? audioOverride;
  const InkApp({super.key, this.audioOverride});

  @override
  Widget build(BuildContext context) => _Bootstrap(audioOverride: audioOverride);
}

/// MaterialApp 셸. [InkServices]는 반드시 이 바깥(위)에 있어야 한다 —
/// Navigator.push로 생기는 라우트는 home의 형제라서, InheritedWidget이
/// MaterialApp 안쪽에 있으면 푸시된 화면에서 InkServices.of가 실패한다.
class _MaterialShell extends StatelessWidget {
  final Widget home;
  const _MaterialShell({required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Philosopher's Ink",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: InkColor.black1,
        colorScheme: const ColorScheme.dark(
          surface: InkColor.black1,
          primary: InkColor.gold,
        ),
      ),
      home: home,
    );
  }
}

class _Bootstrap extends StatefulWidget {
  final AudioService? audioOverride;
  const _Bootstrap({this.audioOverride});

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  SettingsController? _settings;
  GameProgress? _progress;
  LevelCatalog? _catalog;
  AudioService? _audio;
  OnboardingState? _onboarding;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final store = await ProgressStore.open();
      final catalog = await LevelCatalog.discover();
      final settings = SettingsController.fromStore(store);
      final audio = widget.audioOverride ?? SoLoudAudioService();
      // 오디오 초기화 실패는 내부에서 무음화(게임을 막지 않는다).
      await audio.init();
      audio.configure(
          enabled: settings.sound,
          volume: settings.volume,
          bgmEnabled: settings.bgm);
      // 설정 변경 → 오디오 반영 (음소거·볼륨·BGM).
      settings.addListener(
        () => audio.configure(
            enabled: settings.sound,
            volume: settings.volume,
            bgmEnabled: settings.bgm),
      );
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _progress = store.loadProgress();
        _catalog = catalog;
        _audio = audio;
        _onboarding = store.loadOnboarding();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _MaterialShell(
          home: _Splash(child: Text('초기화 실패: $_error', style: InkText.body)));
    }
    final settings = _settings;
    final progress = _progress;
    final catalog = _catalog;
    final audio = _audio;
    final onboarding = _onboarding;
    if (settings == null ||
        progress == null ||
        catalog == null ||
        audio == null ||
        onboarding == null) {
      return const _MaterialShell(
        home: _Splash(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(InkColor.gold),
            ),
          ),
        ),
      );
    }
    // InkServices가 MaterialApp(=Navigator)보다 위에 있어야 푸시된 모든
    // 라우트에서 InkServices.of가 성립한다.
    return InkServices(
      settings: settings,
      progress: progress,
      catalog: catalog,
      audio: audio,
      onboarding: onboarding,
      child: const _MaterialShell(home: TitleScreen()),
    );
  }
}

class _Splash extends StatelessWidget {
  final Widget child;
  const _Splash({required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: InkColor.black0,
        body: Center(child: child),
      );
}
