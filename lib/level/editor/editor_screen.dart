/// 인앱 레벨 에디터 (디버그 빌드 전용, GDD 10.6). 폴리시 없는 기능 UI.
///
/// 배치(방출구/플라스크/지형) → 테스트 플레이([LevelPlayer]) → JSON 익스포트.
/// 파일 쓰기는 주입형 [onExport] sink로 분리한다(팀 결정 b안: path_provider 유예).
/// 기본 sink는 클립보드 복사 + 디버그 콘솔 출력. 익스포트 문자열↔로더 왕복은
/// [EditorDocument]가 보장하며 테스트로 고정돼 있다.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../gameplay/level_player.dart';
import '../../render/world_painter.dart';
import '../level_exception.dart';
import '../level_model.dart';
import 'editor_document.dart';

/// 현재 배치 도구.
enum _Tool { emitter, flask, terrain, erase }

/// 익스포트 sink: (json, 파일명) → 처리. 기본은 클립보드+콘솔.
typedef ExportSink = Future<void> Function(String json, String suggestedName);

Future<void> _defaultExportSink(String json, String name) async {
  // ignore: avoid_print
  debugPrint('=== LEVEL EXPORT ($name) ===\n$json\n=== END ===');
  try {
    await Clipboard.setData(ClipboardData(text: json));
  } catch (_) {
    // 클립보드 불가 환경이면 콘솔 출력만으로 충분(디버그).
  }
}

class EditorScreen extends StatefulWidget {
  /// 편집 시작 문서(없으면 빈 문서). 기존 레벨 편집 진입점.
  final EditorDocument? initial;

  /// 익스포트 처리기(주입). null이면 클립보드+콘솔 기본 sink.
  final ExportSink? onExport;

  const EditorScreen({super.key, this.initial, this.onExport});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorDocument _doc;
  _Tool _tool = _Tool.flask;
  Size _viewSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _doc = widget.initial ?? EditorDocument.blank(id: 1);
    // 테스트 플레이가 가능하도록 석필 예산 기본 지급(비어 있을 때만).
    if (_doc.inkBudget[InkType.chalk] == 0) {
      _doc.setInkBudget(InkType.chalk, 300);
    }
  }

  (int, int)? _cellAt(Offset local) {
    if (_viewSize == Size.zero) return null;
    final vp = GridViewport.fit(
        _viewSize, SimConstants.gridWidth, SimConstants.gridHeight);
    return vp.toGrid(local);
  }

  void _onTapDown(TapDownDetails d) {
    final cell = _cellAt(d.localPosition);
    if (cell == null) return;
    final (x, y) = cell;
    setState(() {
      switch (_tool) {
        case _Tool.emitter:
          _doc.addEmitter(EmitterSpec(
            x: x, y: y, width: 13, material: Material.prima, rate: 1,
          ));
        case _Tool.flask:
          _doc.addFlask(FlaskSpec(x: x, y: y, w: 16, h: 16, goal: 50));
        case _Tool.terrain:
          _doc.addTerrain(
              TerrainRect(x: x, y: y, w: 12, h: 4, material: Material.wall));
        case _Tool.erase:
          _eraseAt(x, y);
      }
    });
  }

  void _eraseAt(int x, int y) {
    bool inRect(int rx, int ry, int rw, int rh) =>
        x >= rx && x < rx + rw && y >= ry && y < ry + rh;
    for (var i = _doc.flasks.length - 1; i >= 0; i--) {
      final f = _doc.flasks[i];
      if (inRect(f.x, f.y, f.w, f.h)) return _doc.removeFlaskAt(i);
    }
    for (var i = _doc.terrain.length - 1; i >= 0; i--) {
      final t = _doc.terrain[i];
      if (inRect(t.x, t.y, t.w, t.h)) return _doc.removeTerrainAt(i);
    }
    for (var i = _doc.emitters.length - 1; i >= 0; i--) {
      final e = _doc.emitters[i];
      if (inRect(e.x, e.y, e.width, 1)) return _doc.removeEmitterAt(i);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  void _test() {
    final Level level;
    try {
      level = _doc.build();
    } on LevelException catch (e) {
      _snack('검증 실패: ${e.problems.first}${e.problems.length > 1 ? ' (외 ${e.problems.length - 1})' : ''}');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LevelPlayer(level: level, onExit: () => Navigator.of(context).pop()),
      ),
    );
  }

  Future<void> _export() async {
    final String json;
    try {
      json = _doc.exportJson();
    } on LevelException catch (e) {
      _snack('검증 실패: ${e.problems.first}');
      return;
    }
    final sink = widget.onExport ?? _defaultExportSink;
    await sink(json, 'level_${_doc.meta.id.toString().padLeft(3, '0')}.json');
    if (mounted) _snack('익스포트 완료 (클립보드/콘솔)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A09),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131311),
        foregroundColor: const Color(0xFFF2EDDF),
        title: const Text('레벨 에디터 (디버그)', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: _test, child: const Text('테스트')),
          TextButton(onPressed: _export, child: const Text('익스포트')),
        ],
      ),
      body: Column(
        children: [
          _ToolBar(
            tool: _tool,
            counts: (_doc.emitters.length, _doc.flasks.length, _doc.terrain.length),
            onSelect: (t) => setState(() => _tool = t),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewSize = Size(constraints.maxWidth, constraints.maxHeight);
                return GestureDetector(
                  onTapDown: _onTapDown,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _EditorPainter(_doc),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  final _Tool tool;
  final (int, int, int) counts;
  final ValueChanged<_Tool> onSelect;
  const _ToolBar(
      {required this.tool, required this.counts, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    Widget btn(_Tool t, String label) {
      final on = t == tool;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: () => onSelect(t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: on ? const Color(0xFFC9A227) : const Color(0xFF29271F),
                width: on ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(label,
                style: const TextStyle(color: Color(0xFFF2EDDF), fontSize: 12)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: const Color(0xFF131311),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          btn(_Tool.emitter, '방출 ${counts.$1}'),
          btn(_Tool.flask, '플라스크 ${counts.$2}'),
          btn(_Tool.terrain, '지형 ${counts.$3}'),
          btn(_Tool.erase, '지우개'),
        ],
      ),
    );
  }
}

/// 배치된 스펙을 그리드 좌표로 그린다 (sim 미실행 — 정적 미리보기).
class _EditorPainter extends CustomPainter {
  final EditorDocument doc;
  _EditorPainter(this.doc);

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);
    double sx(int gx) => vp.offsetX + gx * vp.scale;
    double sy(int gy) => vp.offsetY + gy * vp.scale;

    // 그리드 프레임.
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF29271F);
    canvas.drawRect(
      Rect.fromLTWH(sx(0), sy(0), SimConstants.gridWidth * vp.scale.toDouble(),
          SimConstants.gridHeight * vp.scale.toDouble()),
      frame,
    );

    // 지형(채움).
    final terrainPaint = Paint()..color = const Color(0xFFCDBFA0);
    for (final t in doc.terrain) {
      canvas.drawRect(
        Rect.fromLTWH(sx(t.x), sy(t.y), t.w * vp.scale.toDouble(),
            t.h * vp.scale.toDouble()),
        terrainPaint,
      );
    }

    // 방출구(마커).
    final emitPaint = Paint()..color = const Color(0xFF3F7BD6);
    for (final e in doc.emitters) {
      canvas.drawRect(
        Rect.fromLTWH(sx(e.x), sy(e.y), e.width * vp.scale.toDouble(),
            3 * vp.scale.toDouble()),
        emitPaint,
      );
    }

    // 플라스크(윤곽 + goal).
    final flaskPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFC9A227);
    for (final f in doc.flasks) {
      final rect = Rect.fromLTWH(sx(f.x), sy(f.y),
          f.w * vp.scale.toDouble(), f.h * vp.scale.toDouble());
      canvas.drawRect(rect, flaskPaint);
      final tag = [
        '${f.goal}',
        if (f.material != null) materialName(f.material!),
        if (f.state != null) f.state!.key,
        if (f.pure) '!',
      ].join(' ');
      final tp = TextPainter(
        text: TextSpan(
          text: tag,
          style: const TextStyle(color: Color(0xFFF2EDDF), fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, rect.top - 14));
    }
  }

  @override
  bool shouldRepaint(_EditorPainter oldDelegate) => true;
}
