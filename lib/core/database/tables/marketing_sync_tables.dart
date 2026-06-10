import 'package:drift/drift.dart';

// ─── 메시지 템플릿 ────────────────────────────────────────────────────────
class MessageTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get templateType => text()(); // reminder|followup|birthday|campaign|reactivation
  TextColumn get channel => text()(); // line|sms|email|push
  TextColumn get subject => text().nullable()();
  TextColumn get body => text()(); // 변수: {{customer_name}}, {{date}} 등
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 캠페인 ───────────────────────────────────────────────────────────────
class Campaigns extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get templateId => text()();
  TextColumn get targetSegment => text()(); // all|vip|new|lost|birthday|custom
  TextColumn get targetCondition => text().nullable()(); // JSON 필터 조건
  TextColumn get scheduleAt => text().nullable()(); // null = 즉시
  TextColumn get sentAt => text().nullable()();
  IntColumn get targetCount => integer().withDefault(const Constant(0))();
  IntColumn get sentCount => integer().withDefault(const Constant(0))();
  IntColumn get openCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft|scheduled|sending|sent|cancelled
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 메시지 발송 로그 ─────────────────────────────────────────────────────
class MessageLogs extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get campaignId => text().nullable()();
  TextColumn get templateId => text().nullable()();
  TextColumn get channel => text()();
  TextColumn get content => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('sent'))(); // pending|sent|delivered|failed
  TextColumn get sentAt => text().nullable()();
  TextColumn get openedAt => text().nullable()();
  TextColumn get errorMessage => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 자동화 규칙 ──────────────────────────────────────────────────────────
class AutomationRules extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get trigger => text()(); // after_visit|before_appointment|birthday|no_visit_90d
  IntColumn get delayHours => integer().withDefault(const Constant(0))();
  TextColumn get templateId => text()();
  TextColumn get channel => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 동기화 큐 ────────────────────────────────────────────────────────────
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get operation => text()(); // create|update|delete
  TextColumn get targetTable => text()();
  TextColumn get recordId => text()();
  TextColumn get data => text()(); // JSON 페이로드
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending|processing|synced|conflict|failed
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get priority => integer().withDefault(const Constant(5))(); // 1=최우선
  TextColumn get conflictData => text().nullable()(); // 서버 데이터
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get processedAt => text().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 기기 등록 ────────────────────────────────────────────────────────────
class Devices extends Table {
  TextColumn get id => text()();
  TextColumn get deviceName => text().withLength(max: 20)(); // A, B, C... (sale_no prefix)
  TextColumn get deviceType => text()(); // ipad|mac|web
  TextColumn get osVersion => text().nullable()();
  TextColumn get appVersion => text().nullable()();
  TextColumn get lastSyncAt => text().nullable()();
  TextColumn get lastActiveAt => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
