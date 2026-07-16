/// 레벨 JSON 로더 (GDD 10.6). 문자열 → [Level]. 구조 파싱에서 타입/필수 위반을
/// 모아 [LevelException]으로 던지고, 통과하면 [validateLevel]로 의미 검증까지 강제한다.
///
/// 조용한 스킵 금지 — 어떤 실패도 명시적 예외. 순수 Dart.
library;

import 'dart:convert';

import 'level_exception.dart';
import 'level_model.dart';
import 'validator.dart';

InkType? _inkFromKey(String k) => switch (k) {
      'chalk' => InkType.chalk,
      'heat' => InkType.heat,
      'frost' => InkType.frost,
      _ => null,
    };

/// JSON 문자열을 파싱·검증해 [Level]을 만든다. 실패 시 [LevelException].
Level loadLevelFromJson(String jsonText, {String source = 'level'}) {
  final dynamic root;
  try {
    root = jsonDecode(jsonText);
  } on FormatException catch (e) {
    throw LevelException.single('JSON 파싱 실패: ${e.message}', source: source);
  }
  if (root is! Map) {
    throw LevelException.single('최상위가 JSON 객체가 아니다', source: source);
  }

  final p = _Parser(source);
  final level = p.parseLevel(root.cast<String, dynamic>());
  if (p.problems.isNotEmpty) {
    throw LevelException(p.problems, source: source);
  }
  // 구조가 온전하면 의미 검증 (좌표·해금 등).
  validateLevel(level, source: source);
  return level;
}

/// 구조 파싱 중 위반을 모으는 헬퍼. 오류가 있어도 기본값으로 진행해 최대한 많이 모은다.
class _Parser {
  final String source;
  final List<String> problems = [];
  _Parser(this.source);

  void _err(String path, String msg) => problems.add('$path: $msg');

  Map<String, dynamic>? _obj(dynamic v, String path) {
    if (v is Map) return v.cast<String, dynamic>();
    _err(path, '객체가 필요 (got ${v.runtimeType})');
    return null;
  }

  List? _list(dynamic v, String path) {
    if (v == null) return const [];
    if (v is List) return v;
    _err(path, '배열이 필요 (got ${v.runtimeType})');
    return null;
  }

  int _int(dynamic v, String path, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    _err(path, '정수가 필요 (got ${v.runtimeType})');
    return fallback;
  }

  num _num(dynamic v, String path, {num fallback = 0}) {
    if (v is num) return v;
    _err(path, '숫자가 필요 (got ${v.runtimeType})');
    return fallback;
  }

  String _str(dynamic v, String path, {String fallback = ''}) {
    if (v is String) return v;
    _err(path, '문자열이 필요 (got ${v.runtimeType})');
    return fallback;
  }

  bool _bool(dynamic v, String path, {bool fallback = false}) {
    if (v is bool) return v;
    if (v == null) return fallback;
    _err(path, '불리언이 필요 (got ${v.runtimeType})');
    return fallback;
  }

  Material _material(dynamic v, String path) {
    final name = _str(v, path);
    final m = materialFromName(name);
    if (m == null) {
      _err(path, '알 수 없는 물질 "$name"');
      return Material.empty;
    }
    return m;
  }

  Level parseLevel(Map<String, dynamic> root) {
    final metaMap = _obj(root['meta'], 'meta') ?? const {};
    final meta = _parseMeta(metaMap);

    final background = _parseColor(root['background'], 'background');

    final emitters = <EmitterSpec>[];
    final el = _list(root['emitters'], 'emitters') ?? const [];
    for (var i = 0; i < el.length; i++) {
      final m = _obj(el[i], 'emitters[$i]');
      if (m != null) emitters.add(_parseEmitter(m, 'emitters[$i]'));
    }

    final flasks = <FlaskSpec>[];
    final fl = _list(root['flasks'], 'flasks') ?? const [];
    for (var i = 0; i < fl.length; i++) {
      final m = _obj(fl[i], 'flasks[$i]');
      if (m != null) flasks.add(_parseFlask(m, 'flasks[$i]'));
    }

    final terrain = <TerrainRect>[];
    final tl = _list(root['terrain'], 'terrain') ?? const [];
    for (var i = 0; i < tl.length; i++) {
      final m = _obj(tl[i], 'terrain[$i]');
      if (m != null) terrain.add(_parseTerrain(m, 'terrain[$i]'));
    }

    final gimmicks = <GimmickSpec>[];
    final gl = _list(root['gimmicks'], 'gimmicks') ?? const [];
    for (var i = 0; i < gl.length; i++) {
      final m = _obj(gl[i], 'gimmicks[$i]');
      if (m != null) {
        gimmicks.add(GimmickSpec(
          type: _str(m['type'], 'gimmicks[$i].type'),
          params: (m['params'] is Map)
              ? (m['params'] as Map).cast<String, dynamic>()
              : const {},
        ));
      }
    }

    final inkBudget = _parseInkMap(root['ink_budget'], 'ink_budget') ??
        {InkType.chalk: 0, InkType.heat: 0, InkType.frost: 0};

    return Level(
      meta: meta,
      background: background,
      emitters: emitters,
      flasks: flasks,
      terrain: terrain,
      gimmicks: gimmicks,
      inkBudget: inkBudget,
      starThresholds: _parseStarThresholds(root['star_thresholds']),
    );
  }

  LevelMeta _parseMeta(Map<String, dynamic> m) {
    return LevelMeta(
      id: _int(m['id'], 'meta.id'),
      name: _str(m['name'], 'meta.name'),
      chapter: _int(m['chapter'], 'meta.chapter'),
      difficulty: _int(m['difficulty'], 'meta.difficulty'),
      teaches: _strList(m['teaches'], 'meta.teaches'),
      tags: _strList(m['tags'], 'meta.tags'),
      optimalInk: _parseInkMap(m['optimal_ink'], 'meta.optimal_ink'),
      solutionsVerified: m['solutions_verified'] == null
          ? 0
          : _int(m['solutions_verified'], 'meta.solutions_verified'),
      hintStroke: _parseHintStroke(m['hint_stroke']),
    );
  }

  List<String> _strList(dynamic v, String path) {
    final l = _list(v, path) ?? const [];
    return [for (var i = 0; i < l.length; i++) _str(l[i], '$path[$i]')];
  }

  EmitterSpec _parseEmitter(Map<String, dynamic> m, String path) {
    return EmitterSpec(
      x: _int(m['x'], '$path.x'),
      y: _int(m['y'], '$path.y'),
      width: m['width'] == null ? 1 : _int(m['width'], '$path.width'),
      material: _material(m['material'], '$path.material'),
      rate: _num(m['rate'], '$path.rate'),
      total: m['total'] == null ? null : _int(m['total'], '$path.total'),
      ashRatio:
          m['ash_ratio'] == null ? 0.0 : _num(m['ash_ratio'], '$path.ash_ratio').toDouble(),
    );
  }

  FlaskSpec _parseFlask(Map<String, dynamic> m, String path) {
    Material? mat;
    if (m['material'] != null) mat = _material(m['material'], '$path.material');
    FlaskState? state;
    if (m['state'] != null) {
      final key = _str(m['state'], '$path.state');
      state = flaskStateFromKey(key);
      if (state == null) _err('$path.state', '알 수 없는 상태 "$key"');
    }
    return FlaskSpec(
      x: _int(m['x'], '$path.x'),
      y: _int(m['y'], '$path.y'),
      w: _int(m['w'], '$path.w'),
      h: _int(m['h'], '$path.h'),
      goal: _int(m['goal'], '$path.goal'),
      material: mat,
      state: state,
      pure: _bool(m['pure'], '$path.pure'),
    );
  }

  TerrainRect _parseTerrain(Map<String, dynamic> m, String path) {
    return TerrainRect(
      x: _int(m['x'], '$path.x'),
      y: _int(m['y'], '$path.y'),
      w: _int(m['w'], '$path.w'),
      h: _int(m['h'], '$path.h'),
      material: m['material'] == null
          ? Material.wall
          : _material(m['material'], '$path.material'),
    );
  }

  /// `{chalk,heat,frost}` 맵을 잉크 예산 맵으로. null이면 null 반환(미검증 표시).
  Map<InkType, int>? _parseInkMap(dynamic v, String path) {
    if (v == null) return null;
    final m = _obj(v, path);
    if (m == null) return null;
    final out = <InkType, int>{};
    m.forEach((k, val) {
      final ink = _inkFromKey(k);
      if (ink == null) {
        _err(path, '알 수 없는 잉크 키 "$k"');
      } else {
        out[ink] = _int(val, '$path.$k');
      }
    });
    return out;
  }

  StarThresholds? _parseStarThresholds(dynamic v) {
    if (v == null) return null;
    final m = _obj(v, 'star_thresholds');
    if (m == null) return null;
    return StarThresholds(
      twoStar: _int(m['two_star'], 'star_thresholds.two_star'),
      threeStar: _int(m['three_star'], 'star_thresholds.three_star'),
    );
  }

  List<List<int>>? _parseHintStroke(dynamic v) {
    if (v == null) return null;
    final l = _list(v, 'meta.hint_stroke');
    if (l == null) return null;
    final out = <List<int>>[];
    for (var i = 0; i < l.length; i++) {
      final pt = _list(l[i], 'meta.hint_stroke[$i]');
      if (pt == null) continue;
      out.add([for (var j = 0; j < pt.length; j++) _int(pt[j], 'meta.hint_stroke[$i][$j]')]);
    }
    return out;
  }

  /// "#RRGGBB" 또는 "#AARRGGBB" → 0xAARRGGBB. 실패 시 불투명 검정.
  int _parseColor(dynamic v, String path) {
    if (v is! String) {
      _err(path, '색 문자열이 필요 (got ${v.runtimeType})');
      return 0xFF000000;
    }
    var s = v.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) {
      _err(path, '색은 #RRGGBB 또는 #AARRGGBB (got "$v")');
      return 0xFF000000;
    }
    final parsed = int.tryParse(s, radix: 16);
    if (parsed == null) {
      _err(path, '색 16진 파싱 실패 (got "$v")');
      return 0xFF000000;
    }
    return parsed;
  }
}
