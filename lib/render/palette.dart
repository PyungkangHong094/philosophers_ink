import 'dart:typed_data';

import '../sim/materials.dart';

/// 물질 ID → RGBA 룩업 테이블 + 그리드→RGBA 버퍼 변환 (GDD 10.3).
///
/// 중앙 물질 테이블(materials.dart)의 argb 색을 256엔트리 LUT로 펼쳐두고,
/// 매 프레임 그리드 셀 배열을 RGBA8888 버퍼로 변환한다. 변환은 예산 ~1ms.
class Palette {
  /// 256 * 4 바이트. [id*4 + {0:R,1:G,2:B,3:A}].
  final Uint8List lut;

  Palette() : lut = _buildLut();

  static Uint8List _buildLut() {
    final lut = Uint8List(256 * 4);
    for (final p in kMaterialTable) {
      final base = p.id.index * 4;
      final argb = p.argb;
      lut[base] = (argb >> 16) & 0xFF; // R
      lut[base + 1] = (argb >> 8) & 0xFF; // G
      lut[base + 2] = argb & 0xFF; // B
      lut[base + 3] = (argb >> 24) & 0xFF; // A
    }
    return lut;
  }

  /// 그리드 셀 배열 → RGBA8888 버퍼. [rgba]는 재사용 버퍼 (길이 = cells.length*4).
  void writeRgba(Uint8List cells, Uint8List rgba) {
    for (var i = 0; i < cells.length; i++) {
      final src = cells[i] * 4;
      final dst = i * 4;
      rgba[dst] = lut[src];
      rgba[dst + 1] = lut[src + 1];
      rgba[dst + 2] = lut[src + 2];
      rgba[dst + 3] = lut[src + 3];
    }
  }
}
