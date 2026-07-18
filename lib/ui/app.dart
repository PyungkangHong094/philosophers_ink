/// 셸 앱 루트 — 서비스(설정·진행·레벨 카탈로그) 부트스트랩 + 라우팅.
///
/// 부팅 시 SharedPreferences와 레벨 카탈로그를 로드한 뒤 타이틀로 진입한다. 로드 실패나
/// 레벨 0개에도 견고하게 동작한다(빈 상태 안내). 서비스는 [InkServices]로 하위에 전달.
library;

import 'package:flutter/material.dart';

import '../meta/level_catalog.dart';
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

  const InkServices({
    super.key,
    required this.settings,
    required this.progress,
    required this.catalog,
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
      catalog != old.catalog;
}

class InkApp extends StatelessWidget {
  const InkApp({super.key});

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
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  SettingsController? _settings;
  GameProgress? _progress;
  LevelCatalog? _catalog;
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
      if (!mounted) return;
      setState(() {
        _settings = SettingsController.fromStore(store);
        _progress = store.loadProgress();
        _catalog = catalog;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _Splash(child: Text('초기화 실패: $_error', style: InkText.body));
    }
    final settings = _settings;
    final progress = _progress;
    final catalog = _catalog;
    if (settings == null || progress == null || catalog == null) {
      return const _Splash(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(InkColor.gold),
          ),
        ),
      );
    }
    return InkServices(
      settings: settings,
      progress: progress,
      catalog: catalog,
      child: const TitleScreen(),
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
