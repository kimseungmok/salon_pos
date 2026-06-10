import 'package:drift/drift.dart';

// ─── 경비 카테고리 ────────────────────────────────────────────────────────
class ExpenseCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  TextColumn get accountCode => text().nullable()(); // 勘定科目
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 경비 ────────────────────────────────────────────────────────────────
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  TextColumn get staffId => text().nullable()(); // 담당자
  TextColumn get expenseDate => text()(); // YYYY-MM-DD
  IntColumn get amount => integer()();
  TextColumn get taxType => text().withDefault(const Constant('10'))(); // 10|8|exempt
  TextColumn get description => text()();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))(); // cash|card|bank
  TextColumn get receiptUrl => text().nullable()(); // 영수증 사진
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 일별 집계 (캐시) ─────────────────────────────────────────────────────
class DailySummaries extends Table {
  TextColumn get id => text()(); // YYYY-MM-DD
  TextColumn get summaryDate => text()();
  IntColumn get totalSales => integer().withDefault(const Constant(0))();
  IntColumn get totalRefunds => integer().withDefault(const Constant(0))();
  IntColumn get netSales => integer().withDefault(const Constant(0))();
  IntColumn get menuSales => integer().withDefault(const Constant(0))();
  IntColumn get productSales => integer().withDefault(const Constant(0))();
  IntColumn get taxAmount10 => integer().withDefault(const Constant(0))();
  IntColumn get taxAmount8 => integer().withDefault(const Constant(0))();
  IntColumn get cashTotal => integer().withDefault(const Constant(0))();
  IntColumn get cardTotal => integer().withDefault(const Constant(0))();
  IntColumn get otherTotal => integer().withDefault(const Constant(0))();
  IntColumn get customerCount => integer().withDefault(const Constant(0))();
  IntColumn get newCustomerCount => integer().withDefault(const Constant(0))();
  IntColumn get saleCount => integer().withDefault(const Constant(0))();
  IntColumn get expenses => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 월별 집계 (캐시 + P&L) ───────────────────────────────────────────────
class MonthlySummaries extends Table {
  TextColumn get id => text()(); // YYYY-MM
  TextColumn get yearMonth => text()();
  IntColumn get totalSales => integer().withDefault(const Constant(0))();
  IntColumn get totalRefunds => integer().withDefault(const Constant(0))();
  IntColumn get netSales => integer().withDefault(const Constant(0))();
  IntColumn get menuSales => integer().withDefault(const Constant(0))();
  IntColumn get productSales => integer().withDefault(const Constant(0))();
  IntColumn get totalCogs => integer().withDefault(const Constant(0))(); // 매출원가
  IntColumn get grossProfit => integer().withDefault(const Constant(0))();
  IntColumn get totalExpenses => integer().withDefault(const Constant(0))();
  IntColumn get laborCost => integer().withDefault(const Constant(0))(); // 인건비
  IntColumn get operatingProfit => integer().withDefault(const Constant(0))();
  IntColumn get taxAmount => integer().withDefault(const Constant(0))();
  IntColumn get netProfit => integer().withDefault(const Constant(0))();
  IntColumn get customerCount => integer().withDefault(const Constant(0))();
  IntColumn get newCustomerCount => integer().withDefault(const Constant(0))();
  IntColumn get repeatCustomerCount => integer().withDefault(const Constant(0))();
  IntColumn get avgSalesPerCustomer => integer().withDefault(const Constant(0))();
  IntColumn get saleCount => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 연별 집계 ────────────────────────────────────────────────────────────
class YearlySummaries extends Table {
  TextColumn get id => text()(); // YYYY
  TextColumn get year => text()();
  IntColumn get totalSales => integer().withDefault(const Constant(0))();
  IntColumn get netSales => integer().withDefault(const Constant(0))();
  IntColumn get grossProfit => integer().withDefault(const Constant(0))();
  IntColumn get totalExpenses => integer().withDefault(const Constant(0))();
  IntColumn get netProfit => integer().withDefault(const Constant(0))();
  IntColumn get customerCount => integer().withDefault(const Constant(0))();
  IntColumn get newCustomerCount => integer().withDefault(const Constant(0))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 세무 기간 (消費税申告) ───────────────────────────────────────────────
class TaxPeriods extends Table {
  TextColumn get id => text()();
  TextColumn get periodName => text()(); // 예: 2024年第1四半期
  TextColumn get startDate => text()();
  TextColumn get endDate => text()();
  TextColumn get periodType => text()(); // monthly|quarterly|annual
  IntColumn get taxableAmount10 => integer().withDefault(const Constant(0))();
  IntColumn get taxableAmount8 => integer().withDefault(const Constant(0))();
  IntColumn get taxCollected10 => integer().withDefault(const Constant(0))();
  IntColumn get taxCollected8 => integer().withDefault(const Constant(0))();
  IntColumn get inputTax => integer().withDefault(const Constant(0))(); // 仕入税額
  IntColumn get taxDue => integer().withDefault(const Constant(0))(); // 納付税額
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft|filed|paid
  TextColumn get filedAt => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── KPI 목표 ─────────────────────────────────────────────────────────────
class KpiTargets extends Table {
  TextColumn get id => text()();
  TextColumn get yearMonth => text()(); // YYYY-MM
  TextColumn get staffId => text().nullable()(); // NULL = 전체 매장
  TextColumn get targetType => text()(); // sales|customer_count|new_customer|repeat_rate|avg_unit
  IntColumn get targetValue => integer()();
  IntColumn get actualValue => integer().withDefault(const Constant(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
