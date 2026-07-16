/// 인앱 레벨 에디터의 편집 버퍼 (디버그 전용, GDD 10.6). 순수 Dart.
///
/// [Level]은 불변이므로, 에디터는 이 가변 문서에 방출구·플라스크·지형을 쌓고
/// [build]로 검증된 [Level]을 만든 뒤 [exportJson]으로 직렬화한다. 파일 쓰기(디스크)는
/// 이 계층 밖(에디터 UI + 주입형 sink)에서 처리해 I/O 비의존·테스트 가능하게 둔다.
///
/// 왕복 계약: fromLevel → (편집) → build → exportJson → loadLevelFromJson 이 무손실.
library;

import '../level_model.dart';
import '../loader.dart';
import '../serializer.dart';
import '../validator.dart';

class EditorDocument {
  LevelMeta meta;
  int background;
  final List<EmitterSpec> emitters;
  final List<FlaskSpec> flasks;
  final List<TerrainRect> terrain;
  final List<GimmickSpec> gimmicks;
  final Map<InkType, int> inkBudget;
  StarThresholds? starThresholds;

  EditorDocument({
    required this.meta,
    required this.background,
    List<EmitterSpec>? emitters,
    List<FlaskSpec>? flasks,
    List<TerrainRect>? terrain,
    List<GimmickSpec>? gimmicks,
    Map<InkType, int>? inkBudget,
    this.starThresholds,
  })  : emitters = emitters ?? [],
        flasks = flasks ?? [],
        terrain = terrain ?? [],
        gimmicks = gimmicks ?? [],
        inkBudget = inkBudget ??
            {InkType.chalk: 0, InkType.heat: 0, InkType.frost: 0};

  /// 빈 문서 (새 레벨 저작 시작). 챕터 1 기본값.
  factory EditorDocument.blank({int id = 0}) => EditorDocument(
        meta: LevelMeta(id: id, name: '새 레벨', chapter: 1, difficulty: 1),
        background: 0xFF1D1418,
      );

  /// 기존 레벨을 편집용으로 연다 (리스트를 복사해 원본 불변 유지).
  factory EditorDocument.fromLevel(Level level) => EditorDocument(
        meta: level.meta,
        background: level.background,
        emitters: List.of(level.emitters),
        flasks: List.of(level.flasks),
        terrain: List.of(level.terrain),
        gimmicks: List.of(level.gimmicks),
        inkBudget: Map.of(level.inkBudget),
        starThresholds: level.starThresholds,
      );

  void addEmitter(EmitterSpec e) => emitters.add(e);
  void addFlask(FlaskSpec f) => flasks.add(f);
  void addTerrain(TerrainRect t) => terrain.add(t);

  void removeEmitterAt(int i) => emitters.removeAt(i);
  void removeFlaskAt(int i) => flasks.removeAt(i);
  void removeTerrainAt(int i) => terrain.removeAt(i);

  void setInkBudget(InkType type, int budget) => inkBudget[type] = budget;

  /// 현재 상태로 [Level]을 만든다. **검증을 통과해야** 반환 — 실패 시 [LevelException].
  /// 에디터가 이 예외를 잡아 저작자에게 문제를 노출한다(조용한 저장 금지).
  Level build({String source = 'editor'}) {
    final level = Level(
      meta: meta,
      background: background,
      emitters: List.of(emitters),
      flasks: List.of(flasks),
      terrain: List.of(terrain),
      gimmicks: List.of(gimmicks),
      inkBudget: Map.of(inkBudget),
      starThresholds: starThresholds,
    );
    validateLevel(level, source: source);
    return level;
  }

  /// 검증된 레벨을 JSON 문자열로 익스포트 (파일 쓰기는 호출자 몫).
  String exportJson({String source = 'editor'}) => serializeLevel(build(source: source));

  /// 익스포트 JSON을 다시 로드해 왕복이 성립하는지 자체 확인 (에디터 저장 전 무결성).
  Level reloadExported({String source = 'editor'}) =>
      loadLevelFromJson(exportJson(source: source), source: source);
}
