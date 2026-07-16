import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/ink.dart';
import 'package:philosophers_ink/gameplay/ink_budget.dart';

void main() {
  group('InkBudget 차감 정확성 — 부분 배치 cap 모델 (GDD 4.2)', () {
    test('chargeAvailable은 잔량 한도 내 실제 차감량 반환', () {
      final b = InkBudget(chalk: 50);
      expect(b.chargeAvailable(InkType.chalk, 20), 20);
      expect(b.remaining(InkType.chalk), 30);
      // 잔량(30)보다 큰 요청(100) → 30만 차감하고 30 반환 (cap), 음수 없음.
      expect(b.chargeAvailable(InkType.chalk, 100), 30);
      expect(b.remaining(InkType.chalk), 0);
      // 바닥난 뒤 추가 요청 → 0 차감.
      expect(b.chargeAvailable(InkType.chalk, 10), 0);
      expect(b.remaining(InkType.chalk), 0);
    });

    test('여유 있는 요청은 요청량 전부 차감 (배치 셀 수와 일치)', () {
      final b = InkBudget(chalk: 100);
      expect(b.chargeAvailable(InkType.chalk, 30), 30);
      expect(b.remaining(InkType.chalk), 70);
    });

    test('0/음수 요청은 무동작', () {
      final b = InkBudget(chalk: 10);
      expect(b.chargeAvailable(InkType.chalk, 0), 0);
      expect(b.chargeAvailable(InkType.chalk, -5), 0);
      expect(b.remaining(InkType.chalk), 10);
    });
  });

  group('예산 부족 시 cap (부분 배치)', () {
    test('잔량 초과 요청은 잔량만큼만 차감하고 그 지점에서 멈춘다', () {
      final b = InkBudget(chalk: 40);
      // 잔량 40에 41 요청 → 40 차감(cap), 41째는 안 칠해짐.
      expect(b.chargeAvailable(InkType.chalk, 41), 40);
      expect(b.remaining(InkType.chalk), 0);
      // 이후 요청은 0 배치.
      expect(b.chargeAvailable(InkType.chalk, 1), 0);
    });

    test('canAfford는 여력만 보고, 차감하지 않는다 (질의)', () {
      final b = InkBudget(chalk: 5);
      expect(b.canAfford(InkType.chalk, 5), isTrue);
      expect(b.canAfford(InkType.chalk, 6), isFalse);
      expect(b.remaining(InkType.chalk), 5, reason: 'canAfford는 부작용 없음');
    });
  });

  group('삭제 시 미반환 (GDD 4.2)', () {
    test('잔량을 늘리는 경로는 reset뿐 — 차감 후 저절로 복원되지 않는다', () {
      final b = InkBudget(chalk: 100);
      b.chargeAvailable(InkType.chalk, 60);
      // 스트로크 삭제는 GameState의 몫이고, 예산에는 반환 API가 없다.
      expect(b.remaining(InkType.chalk), 40);
      expect(b.remaining(InkType.chalk), 40);
      b.chargeAvailable(InkType.chalk, 40);
      expect(b.remaining(InkType.chalk), 0);
    });
  });

  group('예산 0 숨김 상태 (GDD 4.2)', () {
    test('초기 예산 0 → isHidden, canAfford false, cap 청구 0, visibleInks 제외', () {
      final b = InkBudget(chalk: 100); // heat/frost 미지정 → 0
      expect(b.isHidden(InkType.heat), isTrue);
      expect(b.isHidden(InkType.frost), isTrue);
      expect(b.isHidden(InkType.chalk), isFalse);
      expect(b.canAfford(InkType.heat, 1), isFalse);
      expect(b.chargeAvailable(InkType.heat, 1), 0);
      expect(b.fraction(InkType.heat), 0.0);
      expect(b.visibleInks, [InkType.chalk]);
    });

    test('숨김(초기 0)과 고갈(사용 후 0)을 구분', () {
      final b = InkBudget(chalk: 10, heat: 0);
      b.chargeAvailable(InkType.chalk, 10);
      expect(b.isHidden(InkType.chalk), isFalse);
      expect(b.isDepleted(InkType.chalk), isTrue, reason: '썼다가 바닥남');
      expect(b.isHidden(InkType.heat), isTrue);
      expect(b.isDepleted(InkType.heat), isFalse, reason: '처음부터 없음');
    });

    test('음수 예산은 0(숨김)으로 클램프', () {
      final b = InkBudget(chalk: -5);
      expect(b.isHidden(InkType.chalk), isTrue);
      expect(b.initial(InkType.chalk), 0);
    });
  });

  group('게이지·비율', () {
    test('fraction은 잔량/초기, 차감에 따라 감소', () {
      final b = InkBudget(frost: 200);
      expect(b.fraction(InkType.frost), 1.0);
      b.chargeAvailable(InkType.frost, 50);
      expect(b.fraction(InkType.frost), closeTo(0.75, 1e-9));
      b.chargeAvailable(InkType.frost, 150);
      expect(b.fraction(InkType.frost), 0.0);
    });
  });

  group('reset 재시작 안전 (GDD 10.5)', () {
    test('reset은 잔량을 초기 예산으로 복원', () {
      final b = InkBudget(chalk: 100, heat: 50);
      b.chargeAvailable(InkType.chalk, 80);
      b.chargeAvailable(InkType.heat, 50);
      b.reset();
      expect(b.remaining(InkType.chalk), 100);
      expect(b.remaining(InkType.heat), 50);
    });

    test('3회 연속 재시작 동일 동작 — 같은 차감 시퀀스는 같은 잔량', () {
      final b = InkBudget(chalk: 100, heat: 50, frost: 30);
      List<int> runOnce() {
        b.reset();
        b.chargeAvailable(InkType.chalk, 33);
        b.chargeAvailable(InkType.heat, 999); // cap → 50
        b.chargeAvailable(InkType.frost, 10);
        return [
          b.remaining(InkType.chalk),
          b.remaining(InkType.heat),
          b.remaining(InkType.frost),
        ];
      }

      final r1 = runOnce();
      final r2 = runOnce();
      final r3 = runOnce();
      expect(r1, [67, 0, 20]);
      expect(r2, r1);
      expect(r3, r1);
    });
  });

  group('fromMap (M2 로더용)', () {
    test('예산 키를 읽고 누락 키는 0', () {
      final b = InkBudget.fromMap({'chalk': 84, 'heat': 30});
      expect(b.initial(InkType.chalk), 84);
      expect(b.initial(InkType.heat), 30);
      expect(b.isHidden(InkType.frost), isTrue);
    });
  });

  group('InkType ↔ 물질/키 매핑', () {
    test('잉크는 정적 물질로 매핑, 키 왕복', () {
      expect(InkType.chalk.budgetKey, 'chalk');
      expect(inkTypeFromKey('frost'), InkType.frost);
      expect(inkTypeFromKey('nope'), isNull);
    });
  });
}
