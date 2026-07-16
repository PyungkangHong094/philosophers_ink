import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/ink_budget.dart';
import 'package:philosophers_ink/gameplay/ink_controller.dart';
import 'package:philosophers_ink/sim/materials.dart';

void main() {
  group('선택 상태', () {
    test('기본 선택 = 첫 노출 잉크', () {
      final c = InkController(InkBudget(chalk: 100, frost: 50));
      expect(c.selected, InkType.chalk);
      expect(c.selectedMaterial, Material.wall);
    });

    test('석필 숨김이면 첫 노출(서리) 선택', () {
      final c = InkController(InkBudget(frost: 50));
      expect(c.selected, InkType.frost);
      expect(c.selectedMaterial, Material.coldLine);
    });

    test('노출 잉크 없으면 선택 null, 그리기 불가', () {
      final c = InkController(InkBudget());
      expect(c.selected, isNull);
      expect(c.selectedMaterial, isNull);
      expect(c.canDraw, isFalse);
    });

    test('select는 숨김 잉크 무시, 실제 변경 시에만 notify', () {
      final c = InkController(InkBudget(chalk: 100, frost: 50));
      var notes = 0;
      c.addListener(() => notes++);

      c.select(InkType.heat); // 숨김 → 무시
      expect(c.selected, InkType.chalk);
      expect(notes, 0);

      c.select(InkType.frost); // 변경
      expect(c.selected, InkType.frost);
      expect(notes, 1);

      c.select(InkType.frost); // 동일 → 무시
      expect(notes, 1);
    });
  });

  group('배치 게이트·차감', () {
    test('canDraw는 선택 잉크 잔량>0을 반영', () {
      final c = InkController(InkBudget(chalk: 3));
      expect(c.canDraw, isTrue);
      c.chargePlaced(3);
      expect(c.canDraw, isFalse, reason: '고갈되면 그리기 불가');
    });

    test('chargePlaced는 실제 배치 수를 사후 차감(cap) + notify', () {
      final c = InkController(InkBudget(chalk: 5));
      var notes = 0;
      c.addListener(() => notes++);

      expect(c.chargePlaced(8), 5, reason: '잔량 한도로 클램프');
      expect(c.budget.remaining(InkType.chalk), 0);
      expect(notes, 1);

      expect(c.chargePlaced(3), 0, reason: '바닥 → 0 차감');
      expect(notes, 1, reason: '0 차감은 notify 안 함');
    });

    test('선택 없으면 차감 경로가 모두 무동작', () {
      final c = InkController(InkBudget());
      expect(c.chargePlaced(5), 0);
      expect(c.selectedRemaining, 0);
    });

    test('selectedRemaining은 선택 잉크 잔량을 반영 (extendStroke maxCells용)', () {
      final c = InkController(InkBudget(chalk: 100, frost: 20));
      expect(c.selectedRemaining, 100);
      c.chargePlaced(30);
      expect(c.selectedRemaining, 70);
      c.select(InkType.frost);
      expect(c.selectedRemaining, 20);
    });
  });

  group('reset 재시작 안전', () {
    test('예산·선택 복원 + notify', () {
      final c = InkController(InkBudget(chalk: 100, frost: 50));
      c.select(InkType.frost);
      c.chargePlaced(40);
      var notes = 0;
      c.addListener(() => notes++);

      c.reset();
      expect(c.budget.remaining(InkType.chalk), 100);
      expect(c.budget.remaining(InkType.frost), 50);
      expect(c.selected, InkType.chalk, reason: '첫 노출 잉크로 복귀');
      expect(notes, 1);
    });

    test('3회 연속 재시작 동일 상태', () {
      final c = InkController(InkBudget(chalk: 100, heat: 40));
      List<Object?> runOnce() {
        c.reset();
        c.select(InkType.heat);
        c.chargePlaced(25);
        return [
          c.selected,
          c.budget.remaining(InkType.chalk),
          c.budget.remaining(InkType.heat),
        ];
      }

      final r1 = runOnce();
      final r2 = runOnce();
      final r3 = runOnce();
      expect(r2, r1);
      expect(r3, r1);
    });
  });
}
