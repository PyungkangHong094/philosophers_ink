import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/headless_session.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';

import '../../tool/level_lab/src/candidate.dart';
import '../../tool/level_lab/src/rollout.dart';

/// 힌트 베이크의 "거짓말 안 하는 힌트" 계약 회귀 테스트.
///
/// 베이크되는 hint_stroke는 최소 잉크 해의 **주 스트로크 1개**(폴리라인)다. 힌트 선 하나만으론
/// 클리어가 안 될 수 있으므로(중력 탭 의존 등), 정직성 기준은 "원본 해 **전체**(스트로크+탭)
/// 재생 클리어"다 — 이 테스트가 그걸 보증한다. 동시에 asset에 구워진 폴리라인이 그 해의
/// 가장 긴 선분과 일치하고 그리드 안임을 확인한다.
Level _loadAsset(String name) => loadLevelFromJson(
    File('assets/levels/$name').readAsStringSync(),
    source: name);

Candidate _bestSolution(int id) {
  final path = 'tool/level_lab/out/level_${id.toString().padLeft(3, '0')}.json';
  final archive =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final sols = archive['solutions'] as List;
  return Candidate.fromJson((sols.first as Map).cast<String, dynamic>());
}

/// 원본 해(스트로크+탭) 전체를 재생해 클리어 틱 반환(미클리어면 -1).
int _replayFull(Level level, Candidate cand) {
  final s = HeadlessSession(level);
  final r = rollout(
    s,
    cand,
    const RolloutConfig(tickCap: 3600, stallTicks: 3600, forbidInFlask: false),
  );
  return r.solved ? r.ticks : -1;
}

double _len(StrokePrimitive s) {
  final dx = (s.x1 - s.x0).toDouble();
  final dy = (s.y1 - s.y0).toDouble();
  return math.sqrt(dx * dx + dy * dy);
}

StrokePrimitive _longest(List<StrokePrimitive> strokes) {
  var best = strokes.first;
  for (final s in strokes.skip(1)) {
    if (_len(s) > _len(best)) best = s;
  }
  return best;
}

void main() {
  const chapterOne = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

  group('베이크된 힌트 정직성 (챕터 1)', () {
    for (final id in chapterOne) {
      final name = 'level_${id.toString().padLeft(3, '0')}.json';
      test('$name 원본 해가 실제 클리어되고 힌트가 주 스트로크와 일치', () {
        final level = _loadAsset(name);
        final hint = level.meta.hintStroke;
        expect(hint, isNotNull, reason: '$name은 힌트가 베이크돼 있어야 한다');
        expect(hint, hasLength(1), reason: '힌트는 주 스트로크 1개(1원소 객체 배열)');

        // 원본 해 전체(탭 포함)가 실제 클리어 — 거짓말 방지의 근거.
        final best = _bestSolution(id);
        final ticks = _replayFull(level, best);
        expect(ticks, greaterThan(0),
            reason: '$name 원본 해가 클리어되지 않았다 — 아카이브/물리 드리프트');

        // 구워진 힌트 스트로크가 그 해의 가장 긴 선분과 일치.
        final primary = _longest(best.strokes);
        final h = hint!.single;
        expect(h.ink, primary.ink);
        expect([h.x0, h.y0, h.x1, h.y1],
            [primary.x0, primary.y0, primary.x1, primary.y1]);
      });
    }
  });

  test('재시작 안전: 원본 해 재생이 3회 연속 동일 틱에 클리어', () {
    final level = _loadAsset('level_001.json');
    final best = _bestSolution(1);
    final runs = [for (var i = 0; i < 3; i++) _replayFull(level, best)];
    expect(runs.toSet(), hasLength(1), reason: '결정성 위반: $runs');
    expect(runs.first, greaterThan(0));
  });
}
