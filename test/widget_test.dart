/// 앱 부트스트랩 스모크 — InkApp이 뜨고 타이틀 화면에 도달한다.
///
/// 부팅은 SharedPreferences + 레벨 카탈로그 로드(비동기)를 거치므로 고정 시간 pump로
/// 퓨처를 흘려보낸다. 타이틀 애니메이션이 반복되므로 pumpAndSettle 금지.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/audio/audio_service.dart';
import 'package:philosophers_ink/ui/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('앱이 부팅되어 타이틀 로고를 그린다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // 오디오는 무음 주입 — 헤드리스 테스트에서 SoLoud FFI를 건드리지 않는다.
    await tester.pumpWidget(
      const InkApp(audioOverride: SilentAudioService()),
    );

    // 부팅 퓨처(prefs·카탈로그) 해소 대기.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('INK'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
