/// 레벨 랩 힌트 베이크 — 솔버가 찾은 최소 잉크 해의 **주 스트로크 1개**를 레벨 JSON
/// `meta.hint_stroke`에 폴리라인으로 굽는다 (GDD 12장 리워드 힌트, 13장 오픈이슈 3 해소).
///
///   dart run tool/level_lab/bake_hints.dart          # 챕터 1(001~010) 베이크
///   dart run tool/level_lab/bake_hints.dart --dry-run # 검증만, 파일 미수정
///
/// 포맷 계약: `hint_stroke`는 힌트 스트로크 객체 배열 `[{ "ink","x0","y0","x1","y1" }]`
/// (모델 HintStroke, 잉크 종류 포함). GDD 12장 "정답 스트로크 **1개**를 고스트 라인으로"에
/// 따라 다중 스트로크 해에서도 **주 스트로크 1개**(가장 긴 선분)만 1원소 배열로 굽는다.
/// 잉크 필드는 셸이 잉크색 고스트로 렌더할 근거(챕터 1은 석필 단일).
///
/// 대상: **챕터 1(001~010)만**. 챕터 2~4 아카이브는 구 물리 해라 무효(재스윕 후 베이크 백로그).
/// 제외: OPERATIO(11배수, 힌트 비활성) + 솔버 미해결 레벨 → hint_stroke null 유지.
///
/// **거짓말 안 하는 힌트 보증**: 베이크 전, 아카이브 원본 해(전체 스트로크 + 중력 탭)를 그대로
/// 적용한 HeadlessSession 롤아웃이 실제 클리어되는지 검증한다. 실패하면 그 레벨은 null로 두고
/// 보고에 명시한다 — 유효하지 않은 해의 선을 굽지 않는다. 단, 베이크되는 힌트는 그 해의
/// **1개 선분**이므로, 힌트 선 하나만으로는(특히 중력 탭 의존 레벨) 클리어가 안 될 수 있다.
// CLI 도구라 stdout 출력이 정상 — avoid_print 억제.
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:philosophers_ink/gameplay/headless_session.dart';

import 'src/candidate.dart';
import 'src/level_io.dart';
import 'src/rollout.dart';

/// 검증 롤아웃 틱 상한 — 느린 확산 레벨도 클리어를 놓치지 않게 넉넉히
/// (solver.dart probeCap과 동일 취지). stall 중단 없이 이 상한까지 돈다.
const int _verifyTickCap = 3600;

/// 베이크 대상 챕터 1 레벨 번호.
const List<int> _chapterOneLevels = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

void main(List<String> argv) {
  final dryRun = argv.contains('--dry-run');
  final rows = <_BakeRow>[];

  for (final id in _chapterOneLevels) {
    rows.add(_bakeLevel(id, dryRun: dryRun));
  }

  _printReport(rows, dryRun: dryRun);

  final failed = rows.where((r) => r.wroteError).toList();
  if (failed.isNotEmpty) {
    exitCode = 1;
  }
}

class _BakeRow {
  final int id;
  final String status; // baked | null(verify-fail) | null(no-sol) | null(no-out)
  final int? inkUsed;
  final int? ticks;
  final int solStrokes; // 원본 해 선분 수
  final int taps; // 원본 해 중력 탭 수
  final bool wroteError;

  const _BakeRow(this.id, this.status,
      {this.inkUsed,
      this.ticks,
      this.solStrokes = 0,
      this.taps = 0,
      this.wroteError = false});
}

String _pad3(int n) => n.toString().padLeft(3, '0');

_BakeRow _bakeLevel(int id, {required bool dryRun}) {
  final outPath = '$kDefaultOutDir/level_${_pad3(id)}.json';
  final assetPath = '$kDefaultLevelsDir/level_${_pad3(id)}.json';

  final outFile = File(outPath);
  if (!outFile.existsSync()) {
    return _BakeRow(id, 'null(no-out)');
  }

  final archive = jsonDecode(outFile.readAsStringSync()) as Map<String, dynamic>;
  final sols = (archive['solutions'] as List?) ?? const [];
  if (sols.isEmpty) {
    // 솔버 미해결(solvable:false) → 힌트 없음.
    return _BakeRow(id, 'null(no-sol)');
  }

  // 최소 잉크 해 = solutions[0] (아카이브가 잉크 오름차순). 전체 스트로크 + 중력 탭.
  final best = Candidate.fromJson((sols.first as Map).cast<String, dynamic>());
  if (best.strokes.isEmpty) {
    return _BakeRow(id, 'null(no-sol)');
  }

  // --- 거짓말 안 하는 힌트 보증: 원본 해 전체(탭 포함)를 재생해 실제 클리어 검증 ---
  final level = loadLevelFile(assetPath);
  final session = HeadlessSession(level);
  final r = rollout(
    session,
    best,
    const RolloutConfig(
      tickCap: _verifyTickCap,
      stallTicks: _verifyTickCap,
      forbidInFlask: false,
    ),
  );

  if (!r.solved) {
    // 원본 해가 현재 물리에서 클리어 안 됨(아카이브 노후 등) → 힌트 null 유지.
    return _BakeRow(id, 'null(verify-fail)',
        solStrokes: best.strokes.length,
        taps: best.gravityTaps.length,
        ticks: r.ticks);
  }

  // 주 스트로크 = 가장 긴 선분. 이걸 폴리라인 [[x0,y0],[x1,y1]]로 굽는다.
  final primary = _longestStroke(best.strokes);

  if (dryRun) {
    return _BakeRow(id, 'baked',
        inkUsed: r.inkUsed,
        ticks: r.ticks,
        solStrokes: best.strokes.length,
        taps: best.gravityTaps.length);
  }

  final ok = _writeHint(assetPath, primary);
  final roundTripOk = ok && _verifyRoundTrip(assetPath, primary);

  return _BakeRow(id, 'baked',
      inkUsed: r.inkUsed,
      ticks: r.ticks,
      solStrokes: best.strokes.length,
      taps: best.gravityTaps.length,
      wroteError: !roundTripOk);
}

/// 선분 목록에서 유클리드 길이가 가장 긴 것(주 스트로크). 동률이면 앞선 것.
StrokePrimitive _longestStroke(List<StrokePrimitive> strokes) {
  StrokePrimitive best = strokes.first;
  double bestLen = _len(best);
  for (final s in strokes.skip(1)) {
    final l = _len(s);
    if (l > bestLen) {
      best = s;
      bestLen = l;
    }
  }
  return best;
}

double _len(StrokePrimitive s) {
  final dx = (s.x1 - s.x0).toDouble();
  final dy = (s.y1 - s.y0).toDouble();
  return math.sqrt(dx * dx + dy * dy);
}

/// asset JSON의 `"hint_stroke": null`을 객체 배열 `[{ "ink":..,"x0":..,.. }]`로 교체한다.
/// 파일 나머지 포맷을 건드리지 않아 diff가 hint_stroke 필드에 국한된다.
/// 토큰이 정확히 1개가 아니면 false(안전 실패).
bool _writeHint(String assetPath, StrokePrimitive s) {
  const token = '"hint_stroke": null';
  final file = File(assetPath);
  final text = file.readAsStringSync();
  // String은 Pattern이라 리터럴 매칭. 토큰이 정확히 1개일 때만 교체(안전).
  if (token.allMatches(text).length != 1) return false;

  final obj = '{ "ink": "${inkKey(s.ink)}", "x0": ${s.x0}, '
      '"y0": ${s.y0}, "x1": ${s.x1}, "y1": ${s.y1} }';
  final replacement = '"hint_stroke": [ $obj ]';
  file.writeAsStringSync(text.replaceFirst(token, replacement));
  return true;
}

/// 베이크된 파일이 로더·검증기를 통과하고 힌트가 되살아나는지 왕복 재검증.
bool _verifyRoundTrip(String assetPath, StrokePrimitive s) {
  final reloaded = loadLevelFile(assetPath);
  final hint = reloaded.meta.hintStroke;
  return hint != null &&
      hint.length == 1 &&
      hint[0].ink == s.ink &&
      hint[0].x0 == s.x0 &&
      hint[0].y0 == s.y0 &&
      hint[0].x1 == s.x1 &&
      hint[0].y1 == s.y1;
}

void _printReport(List<_BakeRow> rows, {required bool dryRun}) {
  print(dryRun ? '=== 힌트 베이크 (DRY RUN) ===' : '=== 힌트 베이크 ===');
  print('레벨  | 힌트          | 잉크  | 틱   | 해선분 | 탭');
  print('------|---------------|-------|------|--------|----');
  for (final r in rows) {
    final ink = r.inkUsed?.toString() ?? '-';
    final tk = r.ticks?.toString() ?? '-';
    final ss = r.solStrokes > 0 ? r.solStrokes.toString() : '-';
    final tp = r.solStrokes > 0 ? r.taps.toString() : '-';
    final flag = r.wroteError ? ' ⚠️왕복실패' : '';
    print('L${_pad3(r.id)}  | ${r.status.padRight(13)} | '
        '${ink.padLeft(5)} | ${tk.padLeft(4)} | ${ss.padLeft(6)} | $tp$flag');
  }
  final baked = rows.where((r) => r.status == 'baked' && !r.wroteError).length;
  final nulled = rows.length - baked;
  print('------|---------------|-------|------|--------|----');
  print('베이크 $baked개 / null $nulled개 (총 ${rows.length})');
}
