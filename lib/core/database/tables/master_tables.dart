import 'package:drift/drift.dart';

// ─── 매장 설정 (단일 레코드 id=1) ──────────────────────────────────────────
class SalonSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get salonName => text().withLength(max: 100)();
  TextColumn get salonNameJp => text().withLength(max: 100).nullable()();
  TextColumn get phone => text().withLength(max: 20).nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get email => text().withLength(max: 100).nullable()();
  TextColumn get invoiceRegistrationNo => text().withLength(max: 20).nullable()(); // 適格請求書番号
  TextColumn get logoUrl => text().nullable()();
  IntColumn get taxRate10 => integer().withDefault(const Constant(10))();
  IntColumn get taxRate8 => integer().withDefault(const Constant(8))();
  TextColumn get currency => text().withDefault(const Constant('JPY'))();
  TextColumn get timezone => text().withDefault(const Constant('Asia/Tokyo'))();
  IntColumn get businessHourStart => integer().withDefault(const Constant(9))();
  IntColumn get businessHourEnd => integer().withDefault(const Constant(20))();
  IntColumn get slotMinutes => integer().withDefault(const Constant(15))();
  IntColumn get cancelBufferMinutes => integer().withDefault(const Constant(60))();
  BoolColumn get pointEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get pointRatePercent => integer().withDefault(const Constant(1))();
  IntColumn get pointExpireDays => integer().withDefault(const Constant(365))();
  TextColumn get receiptFooter => text().nullable()();
  TextColumn get deviceCode => text().withDefault(const Constant('A'))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 앱 버전 ──────────────────────────────────────────────────────────────
class AppVersions extends Table {
  TextColumn get id => text()();
  TextColumn get version => text().withLength(max: 20)();
  IntColumn get buildNumber => integer()();
  TextColumn get releaseNote => text().nullable()();
  TextColumn get releaseDate => text()();
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 프린터 설정 ──────────────────────────────────────────────────────────
class PrinterSettings extends Table {
  TextColumn get id => text()();
  TextColumn get printerName => text().withLength(max: 100)();
  TextColumn get printerType => text().withDefault(const Constant('receipt'))();
  TextColumn get connectionType => text().withDefault(const Constant('bluetooth'))();
  TextColumn get address => text().nullable()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 감사 로그 ────────────────────────────────────────────────────────────
class AuditLogs extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text().nullable()();
  TextColumn get action => text()(); // create|update|delete|login|logout
  TextColumn get targetTable => text()();
  TextColumn get recordId => text().nullable()();
  TextColumn get oldValues => text().nullable()(); // JSON
  TextColumn get newValues => text().nullable()(); // JSON
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
