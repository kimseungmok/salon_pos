import 'package:drift/drift.dart';

// ─── 즐겨찾기 메뉴 (POS 빠른 접근) ──────────────────────────────────────────
class FavoriteMenus extends Table {
  TextColumn get id => text()();
  TextColumn get menuId => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 번들/세트 메뉴 ───────────────────────────────────────────────────────
class MenuBundles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get nameJp => text().withLength(max: 100).nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get bundlePrice => integer().nullable()(); // null = 합산가격
  IntColumn get discountRate => integer().withDefault(const Constant(0))(); // % 할인
  BoolColumn get isParallel => boolean().withDefault(const Constant(false))(); // 동시 시술
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

class MenuBundleItems extends Table {
  TextColumn get id => text()();
  TextColumn get bundleId => text()();
  TextColumn get menuId => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 로열티 티어 ──────────────────────────────────────────────────────────
class LoyaltyTiers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)(); // ブロンズ/シルバー/ゴールド/プラチナ
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  IntColumn get minAmount => integer().withDefault(const Constant(0))(); // 누적 지출 기준
  IntColumn get pointRateMultiplier =>
      integer().withDefault(const Constant(1))(); // 포인트 적립 배율
  IntColumn get discountRate => integer().withDefault(const Constant(0))(); // 전용 할인 %
  TextColumn get benefits => text().nullable()(); // JSON 추가 혜택
  TextColumn get color =>
      text().withDefault(const Constant('#CD7F32'))(); // Bronze
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 스태프 알림 (고객별 — Fresha 참고) ─────────────────────────────────
class StaffAlerts extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get alertType =>
      text().withDefault(const Constant('info'))(); // info|warning|danger
  TextColumn get message => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdBy => text().nullable()(); // staff_id
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 동의서 템플릿 (일본 살롱 필수) ─────────────────────────────────────
class ConsentFormTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)(); // パーマ施術同意書
  TextColumn get content => text()(); // 동의서 본문
  TextColumn get formType =>
      text().withDefault(const Constant('consent'))(); // consent|consultation|questionnaire
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

class CustomerConsentForms extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get templateId => text()();
  TextColumn get signedAt => text().nullable()();
  TextColumn get signedData => text().nullable()(); // JSON 서명 데이터
  TextColumn get staffId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 블록 타임 타입 (Fresha 참고) ────────────────────────────────────────
class BlockedTimeTypes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)(); // 昼休み/清掃/ミーティング
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  TextColumn get iconName => text().nullable()(); // Material Icons name
  IntColumn get defaultMinutes => integer().withDefault(const Constant(30))();
  BoolColumn get isPaid => boolean().withDefault(const Constant(true))();
  TextColumn get color =>
      text().withDefault(const Constant('#8B95A1'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 블록 타임 (캘린더) ───────────────────────────────────────────────────
class BlockedTimes extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();
  TextColumn get typeId => text().nullable()(); // → blocked_time_types.id
  TextColumn get startAt => text()(); // ISO8601
  TextColumn get endAt => text()();
  TextColumn get description => text().nullable()();
  TextColumn get repeatRule => text().nullable()(); // JSON 반복 규칙
  TextColumn get repeatGroupId => text().nullable()();
  TextColumn get createdAt =>
      text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
