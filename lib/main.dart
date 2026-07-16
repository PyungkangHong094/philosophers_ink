import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'gameplay/level_player.dart';
import 'level/editor/editor_screen.dart';
import 'level/level_model.dart';
import 'level/loader.dart';

void main() => runApp(const PhilosophersInkApp());

class PhilosophersInkApp extends StatelessWidget {
  const PhilosophersInkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: "Philosopher's Ink — M2",
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

/// M2 코어 루프의 셸 (디버그): 에셋 레벨 목록을 순회하며 [LevelPlayer]로 플레이한다.
/// 디버그 빌드에서는 인앱 에디터 진입 버튼을 노출한다 (GDD 10.6, kDebugMode 가드).
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const List<String> _levelAssets = [
    'assets/levels/level_001.json',
    'assets/levels/level_021.json',
  ];
  int _index = 0;
  Level? _level;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int i) async {
    setState(() {
      _index = i;
      _level = null;
      _error = null;
    });
    try {
      final text = await rootBundle.loadString(_levelAssets[i]);
      final level = loadLevelFromJson(text, source: _levelAssets[i]);
      if (mounted) setState(() => _level = level);
    } catch (e) {
      // 스키마 오류·에셋 로드 실패 모두 조용히 넘기지 않고 화면에 노출.
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _next() => _load((_index + 1) % _levelAssets.length);

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditorScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final level = _level;
    if (error != null) {
      return _MessageScreen(
        title: '레벨 로드 실패',
        body: error,
        onRetry: () => _load(_index),
      );
    }
    if (level == null) {
      return const _MessageScreen(title: '로딩', body: '레벨을 불러오는 중…');
    }
    return Stack(
      children: [
        LevelPlayer(level: level, key: ValueKey(_index), onNext: _next),
        if (kDebugMode)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _openEditor,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    border: Border.all(color: const Color(0xFF29271F)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'EDITOR',
                    style: TextStyle(
                      color: Color(0xFFC9A227),
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageScreen extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback? onRetry;
  const _MessageScreen({required this.title, required this.body, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A09),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFF2EDDF),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9C968A), fontSize: 12),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF29271F)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const Text('다시',
                        style: TextStyle(
                            color: Color(0xFFF2EDDF), fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
