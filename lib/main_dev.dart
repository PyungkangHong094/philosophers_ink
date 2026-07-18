/// 개발용 엔트리 — 부팅 후 즉시 레벨 001 플레이 화면으로 진입 (재현·디버깅 전용).
/// 실행: flutter run -t lib/main_dev.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'audio/audio_service.dart';
import 'level/loader.dart';
import 'meta/level_catalog.dart';
import 'meta/progress.dart';
import 'meta/progress_store.dart';
import 'ui/app.dart';
import 'ui/game/play_screen.dart';
import 'ui/settings_controller.dart';
import 'ui/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _DevApp());
}

class _DevApp extends StatelessWidget {
  const _DevApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: InkColor.black1,
      ),
      home: FutureBuilder<Widget>(
        future: _buildPlay(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(
              body: Center(
                  child: Text('DEV 로드 실패: ${snap.error}',
                      style: const TextStyle(color: Colors.red))),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return snap.data!;
        },
      ),
    );
  }

  Future<Widget> _buildPlay() async {
    final store = await ProgressStore.open();
    final settings = SettingsController.fromStore(store);
    final onboarding = store.loadOnboarding();
    final json = await rootBundle.loadString('assets/levels/level_001.json');
    final level = loadLevelFromJson(json, source: 'level_001.json');
    final entry = LevelEntry(
      id: 1,
      chapter: 1,
      name: level.meta.name,
      assetPath: 'assets/levels/level_001.json',
      level: level,
    );
    const audio = SilentAudioService();
    return InkServices(
      settings: settings,
      progress: GameProgress(),
      catalog: LevelCatalog([entry]),
      audio: audio,
      onboarding: onboarding,
      child: PlayScreen(
        entry: entry,
        progress: GameProgress(),
        settings: settings,
        audio: audio,
        onboarding: onboarding,
      ),
    );
  }
}
