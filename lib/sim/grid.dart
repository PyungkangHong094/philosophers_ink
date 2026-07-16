import 'dart:typed_data';

import 'materials.dart';

/// Uint8List 1개로 표현하는 논리 그리드 (GDD 10.2).
///
/// 셀당 물질 ID 1바이트. 순수 Dart (dart:typed_data만 의존).
class Grid {
  final int width;
  final int height;

  /// 행 우선(row-major) 저장. cells[y * width + x] = 물질 ID.
  final Uint8List cells;

  Grid(this.width, this.height) : cells = Uint8List(width * height);

  /// 셀 (x, y)의 선형 인덱스.
  int index(int x, int y) => y * width + x;

  /// 경계 밖 접근 방지용. 이동 규칙이 매 시도마다 호출한다.
  bool inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  /// 경계 검사 없는 읽기 — 호출자가 범위를 보장할 때만.
  int get(int x, int y) => cells[y * width + x];

  /// 경계 검사 없는 쓰기 — 호출자가 범위를 보장할 때만.
  void set(int x, int y, int id) => cells[y * width + x] = id;

  /// 전체를 EMPTY로. reset()에서 호출.
  void clear() => cells.fillRange(0, cells.length, Material.empty.index);

  /// 결정성 검증용 그리드 해시 (FNV-1a 32비트).
  /// 같은 셀 배열 → 같은 해시. 테스트가 이 값의 3회 동일성을 고정한다.
  int hash() {
    var h = 0x811C9DC5; // FNV offset basis
    for (var i = 0; i < cells.length; i++) {
      h ^= cells[i];
      h = (h * 0x01000193) & 0xFFFFFFFF; // FNV prime, 32비트 마스킹
    }
    return h;
  }
}
