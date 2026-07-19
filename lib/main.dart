import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 세로 고정 (GDD 1장) — 세로 전용 셸/HUD가 가로에서 깨지지 않게 잠근다.
  // 네이티브 매니페스트에서도 세로만 허용(iOS Info.plist·Android screenOrientation).
  SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
  );
  runApp(const InkApp());
}
