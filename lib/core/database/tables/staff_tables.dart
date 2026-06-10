import 'package:drift/drift.dart';

// ─── 스태프 ───────────────────────────────────────────────────────────────
class Staff extends Table {
  TextColumn get id => text()();
  TextColumn get staffNo => text().withLength(max: 20).nullable()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameKana => text().withLength(max: 50).nullable()();
  TextColumn get role => text().withDefault(const Constant('stylist'))(); // owner|manager|stylist|assistant|reception
  TextColumn get color => text().withDefault(const Constant('#0064FF'))();
  TextColumn get phone => text().withLength(max: 20).nullable()();
  TextColumn get email => text().withLength(max: 100).nullable()();
  TextColumn get birthDate => text().nullable()();
  TextColumn get hireDate => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get pin => text().withLength(min: 4, max: 4).nullable()(); // 4자리 PIN
  TextColumn get salaryType => text().withDefault(const Constant('monthly'))(); // monthly|hourly|daily
  IntColumn get baseSalary => integer().withDefault(const Constant(0))();
  IntColumn get hourlyRate => integer().withDefault(const Constant(0))();
  IntColumn get commissionRate => integer().withDefault(const Constant(0))(); // 기본 커미션 %
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 스태프 메뉴 커미션 ───────────────────────────────────────────────────
class StaffMenuCommissions extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();
  TextColumn get menuId => text()();
  IntColumn get commissionRate => integer()(); // %
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 커미션 구간 ──────────────────────────────────────────────────────────
class StaffCommissionTiers extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();
  IntColumn get tierOrder => integer()();
  IntColumn get fromAmount => integer()();
  IntColumn get toAmount => integer().nullable()(); // NULL = 상한없음
  IntColumn get rate => integer()(); // %
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 시프트 패턴 ──────────────────────────────────────────────────────────
class ShiftPatterns extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get startTime => text()(); // HH:MM
  TextColumn get endTime => text()();
  IntColumn get breakMinutes => integer().withDefault(const Constant(60))();
  TextColumn get color => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 시프트 (예정) ────────────────────────────────────────────────────────
class Shifts extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();
  TextColumn get shiftDate => text()(); // YYYY-MM-DD
  TextColumn get patternId => text().nullable()();
  TextColumn get startTime => text()(); // HH:MM
  TextColumn get endTime => text()();
  IntColumn get breakMinutes => integer().withDefault(const Constant(60))();
  TextColumn get status => text().withDefault(const Constant('scheduled'))(); // scheduled|off|holiday
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 출퇴근 (실제) ────────────────────────────────────────────────────────
class Attendance extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();
  TextColumn get workDate => text()(); // YYYY-MM-DD
  TextColumn get clockIn => text().nullable()();
  TextColumn get clockOut => text().nullable()();
  IntColumn get breakMinutes => integer().withDefault(const Constant(0))();
  IntColumn get actualWorkMinutes => integer().withDefault(const Constant(0))();
  IntColumn get overtimeMinutes => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 급여 기간 ────────────────────────────────────────────────────────────
class PayrollPeriods extends Table {
  TextColumn get id => text()();
  TextColumn get periodStart => text()(); // YYYY-MM-DD
  TextColumn get periodEnd => text()();
  TextColumn get payDate => text()();
  TextColumn get status => text().withDefault(const Constant('open'))(); // open|closed|paid
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 급여 ────────────────────────────────────────────────────────────────
class Payroll extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();
  TextColumn get periodId => text()();
  IntColumn get basePay => integer().withDefault(const Constant(0))();
  IntColumn get commissionPay => integer().withDefault(const Constant(0))();
  IntColumn get overtimePay => integer().withDefault(const Constant(0))();
  IntColumn get allowances => integer().withDefault(const Constant(0))();
  IntColumn get deductions => integer().withDefault(const Constant(0))(); // 사회보험 등
  IntColumn get incomeTax => integer().withDefault(const Constant(0))();
  IntColumn get netPay => integer().withDefault(const Constant(0))();
  IntColumn get totalSalesAmount => integer().withDefault(const Constant(0))();
  IntColumn get workDays => integer().withDefault(const Constant(0))();
  IntColumn get workHours => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
