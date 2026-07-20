/// 레벨 파일 입출력 (레벨 랩 CLI 전용). dart:io — 앱 빌드 미포함.
library;

import 'dart:convert';
import 'dart:io';

import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';

const String kDefaultLevelsDir = 'assets/levels';
const String kDefaultOutDir = 'tool/level_lab/out';

/// 파일 경로 → 검증된 [Level]. 실패 시 loader가 LevelException을 던진다.
Level loadLevelFile(String path) =>
    loadLevelFromJson(File(path).readAsStringSync(), source: path);

/// [dir]의 level_*.json 경로를 이름순으로.
List<String> allLevelPaths([String dir = kDefaultLevelsDir]) {
  final d = Directory(dir);
  if (!d.existsSync()) {
    throw ArgumentError('레벨 디렉터리 없음: $dir');
  }
  final files = d
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => RegExp(r'level_\d+\.json$').hasMatch(p))
      .toList()
    ..sort();
  return files;
}

/// meta.chapter == [chapter]인 레벨 경로만. 로드해 필터한다.
List<String> levelPathsForChapter(int chapter,
    [String dir = kDefaultLevelsDir]) {
  final out = <String>[];
  for (final p in allLevelPaths(dir)) {
    if (loadLevelFile(p).meta.chapter == chapter) out.add(p);
  }
  return out;
}

/// 결과 JSON을 [kDefaultOutDir]/level_NNN.json 형태로 기록한다.
void writeResultJson(String outDir, int levelId, Map<String, dynamic> json) {
  final d = Directory(outDir);
  if (!d.existsSync()) d.createSync(recursive: true);
  final name = 'level_${levelId.toString().padLeft(3, '0')}.json';
  File('$outDir/$name').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json));
}

// --- 프로비넌스 스탬프 (2026-07-20 위양성 포렌식 대응) ---
//
// mtime은 신뢰 불가임이 증명됐다(오래된 아카이브가 벌크 복원돼 fresh한 mtime으로 위장).
// 그래서 아카이브 정합은 **레벨 파일 내용 해시**로 판단한다: 스윕 시점의 레벨 내용과
// 소비(bake) 시점의 레벨 내용이 다르면 그 아카이브는 stale이므로 거부한다.

/// 레벨 파일 내용 해시 (16진 16자리). 순수 Dart FNV-1a 32비트를 두 시드로 돌려 이어붙인다.
/// 결정적·의존성 없음. 충돌 저항은 실수(우발적 내용 변경) 탐지 용도로 충분하다.
String levelContentHash(String path) =>
    contentHash(File(path).readAsStringSync());

/// [content] 문자열의 내용 해시 (파일 없이 검증·테스트용).
String contentHash(String content) {
  final bytes = utf8.encode(content);
  int fnv(int seed) {
    var h = seed;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x01000193) & 0xFFFFFFFF; // FNV prime, 32비트 마스킹(항상 양수)
    }
    return h;
  }

  final a = fnv(0x811C9DC5);
  final b = fnv(0x811C9DC5 ^ 0x5BD1E995);
  return a.toRadixString(16).padLeft(8, '0') +
      b.toRadixString(16).padLeft(8, '0');
}

/// 현재 git HEAD SHA (짧게 실패 허용 — 없으면 null). 스윕 1회당 한 번만 호출 권장.
String? currentGitSha() {
  try {
    final r = Process.runSync('git', ['rev-parse', 'HEAD']);
    if (r.exitCode == 0) return (r.stdout as String).trim();
  } catch (_) {
    // git 미설치·비-레포 등 — 프로비넌스에서 git_sha만 생략한다.
  }
  return null;
}

/// 결과 [json]에 프로비넌스(레벨 내용 해시·스윕 시각·git SHA)를 박는다.
/// 소비자(bake_hints)는 이 [levelPath]의 현재 내용 해시와 대조해 stale을 거부한다.
void stampProvenance(Map<String, dynamic> json, String levelPath,
    {String? gitSha}) {
  json['provenance'] = {
    'level_hash': levelContentHash(levelPath),
    'swept_at': DateTime.now().toUtc().toIso8601String(),
    'git_sha': ?gitSha,
  };
}
