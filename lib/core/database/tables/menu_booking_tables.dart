import 'package:drift/drift.dart';

// ─── 메뉴 카테고리 ────────────────────────────────────────────────────────
class MenuCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  TextColumn get color => text().withDefault(const Constant('#0064FF'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 메뉴 ────────────────────────────────────────────────────────────────
class Menus extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get nameJp => text().withLength(max: 100).nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get price => integer()();
  IntColumn get durationMin => integer().withDefault(const Constant(60))(); // 시술 시간(분)
  IntColumn get bufferMin => integer().withDefault(const Constant(0))(); // 버퍼(정리) 시간 — 스태프 사용불가
  IntColumn get processingMin => integer().withDefault(const Constant(0))(); // 발색 등 처리 대기 — 스태프 이석 가능
  TextColumn get taxType => text().withDefault(const Constant('10'))(); // 10|8|exempt
  TextColumn get color => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get posSlot => integer().nullable()(); // POSグリッド位置: row*5+col、null=自動配置
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  BoolColumn get isAvailableOnline => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 스태프별 메뉴 가격 ───────────────────────────────────────────────────
class MenuStaffPrices extends Table {
  TextColumn get id => text()();
  TextColumn get menuId => text()();
  TextColumn get staffId => text()();
  IntColumn get price => integer()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 메뉴 옵션 그룹 ───────────────────────────────────────────────────────
class MenuOptionGroups extends Table {
  TextColumn get id => text()();
  TextColumn get menuId => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  TextColumn get selectionType => text().withDefault(const Constant('single'))(); // single|multiple
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 메뉴 옵션 ────────────────────────────────────────────────────────────
class MenuOptions extends Table {
  TextColumn get id => text()();
  TextColumn get groupId => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  IntColumn get additionalPrice => integer().withDefault(const Constant(0))();
  IntColumn get additionalMinutes => integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 리소스 (의자/룸/기기) ────────────────────────────────────────────────
class Resources extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get resourceType => text().withDefault(const Constant('chair'))(); // chair|room|equipment
  IntColumn get capacity => integer().withDefault(const Constant(1))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 리소스-메뉴 연결 ─────────────────────────────────────────────────────
class ResourceMenuLinks extends Table {
  TextColumn get resourceId => text()();
  TextColumn get menuId => text()();

  @override
  Set<Column> get primaryKey => {resourceId, menuId};
}

// ─── 예약 ────────────────────────────────────────────────────────────────
class Appointments extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().nullable()();
  TextColumn get staffId => text()();
  TextColumn get resourceId => text().nullable()();
  TextColumn get startAt => text()(); // ISO8601
  TextColumn get endAt => text()();
  TextColumn get actualStartAt => text().nullable()(); // 실제 시작
  TextColumn get actualEndAt => text().nullable()(); // 실제 종료
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending|confirmed|in_progress|completed|cancelled|no_show
  TextColumn get source => text().withDefault(const Constant('staff'))(); // staff|online|phone|walk_in
  TextColumn get color => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get reminderSentAt => text().nullable()();
  TextColumn get saleId => text().nullable()();
  BoolColumn get isFirstVisit => boolean().withDefault(const Constant(false))();
  TextColumn get repeatGroupId => text().nullable()(); // 반복 예약 그룹
  TextColumn get repeatRule => text().nullable()(); // JSON {frequency,interval,endDate}
  BoolColumn get isRepeatParent => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 예약 메뉴 ────────────────────────────────────────────────────────────
class AppointmentMenus extends Table {
  TextColumn get id => text()();
  TextColumn get appointmentId => text()();
  TextColumn get menuId => text()();
  TextColumn get staffId => text().nullable()(); // 담당 스태프 (다수 가능)
  TextColumn get menuName => text()(); // 스냅샷
  IntColumn get price => integer()();
  IntColumn get durationMin => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get selectedOptions => text().nullable()(); // JSON [{optionId, name, additionalPrice}]
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 대기 명단 ────────────────────────────────────────────────────────────
class Waitlist extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get staffId => text().nullable()();
  TextColumn get preferredDate => text()(); // YYYY-MM-DD
  TextColumn get preferredTimeFrom => text().nullable()(); // HH:MM
  TextColumn get preferredTimeTo => text().nullable()();
  TextColumn get menuId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('waiting'))(); // waiting|offered|booked|cancelled
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 예약 드래프트 (작업 복구) ────────────────────────────────────────────
class DraftAppointments extends Table {
  TextColumn get id => text().withDefault(const Constant('current'))();
  TextColumn get data => text()(); // JSON
  TextColumn get savedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
