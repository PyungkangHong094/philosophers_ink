import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/render/world_painter.dart';

/// P2-1 회귀: update()가 비동기 변환 중 dispose되면 (a) dispose된 ChangeNotifier에
/// notify하지 않고, (b) 디코드한 이미지를 누수시키지 않으며, (c) throw 없이 조용히 종료해야 한다.
///
/// 이미지 디코드(dart:ui)는 실제 엔진 비동기 콜백을 쓰므로 tester.runAsync 안에서 돈다.
void main() {
  testWidgets('정상 update는 이미지를 생성한다', (tester) async {
    await tester.runAsync(() async {
      final src = WorldImageSource(width: 4, height: 4);
      addTearDown(src.dispose);
      await src.update(Uint8List(4 * 4 * 4)); // RGBA 0으로 채운 4x4
      expect(src.image, isNotNull);
      expect(src.image!.width, 4);
      expect(src.image!.height, 4);
    });
  });

  testWidgets('인플라이트 update 중 dispose되면 throw 없이 종료하고 이미지를 남기지 않는다',
      (tester) async {
    await tester.runAsync(() async {
      final src = WorldImageSource(width: 4, height: 4);
      // 변환 시작(첫 await에서 suspend) 직후 dispose로 레이스를 강제한다.
      final inflight = src.update(Uint8List(4 * 4 * 4));
      src.dispose();
      // 재개 시 _disposed 가드로 조용히 끝나야 한다 — 예외가 나면 이 await가 재던진다.
      await inflight;
      expect(src.image, isNull, reason: 'dispose 후 이미지를 보유하지 않는다');
    });
  });

  testWidgets('dispose 후 update 호출은 아무 것도 하지 않는다 (진입 가드)', (tester) async {
    await tester.runAsync(() async {
      final src = WorldImageSource(width: 4, height: 4);
      src.dispose();
      await src.update(Uint8List(4 * 4 * 4)); // 진입 가드로 즉시 반환, throw 없음
      expect(src.image, isNull);
    });
  });
}
