import 'package:drift/drift.dart';

// ─── 상품 카테고리 ────────────────────────────────────────────────────────
class ProductCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameJp => text().withLength(max: 50).nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 공급업체 ─────────────────────────────────────────────────────────────
class Suppliers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get contactName => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 상품 ────────────────────────────────────────────────────────────────
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get supplierId => text().nullable()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get nameJp => text().withLength(max: 100).nullable()();
  TextColumn get sku => text().withLength(max: 50).nullable()();
  TextColumn get barcode => text().withLength(max: 50).nullable()();
  TextColumn get productType => text().withDefault(const Constant('retail'))(); // retail|backbar|both
  IntColumn get retailPrice => integer().withDefault(const Constant(0))();
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  TextColumn get taxType => text().withDefault(const Constant('10'))(); // 10|8|exempt
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
  IntColumn get minStock => integer().withDefault(const Constant(0))(); // 임계값
  IntColumn get reorderPoint => integer().withDefault(const Constant(0))(); // 발주 트리거
  IntColumn get reorderQty => integer().withDefault(const Constant(0))(); // 발주 수량
  TextColumn get unit => text().withDefault(const Constant('個'))();
  TextColumn get storageLocation => text().nullable()(); // 보관 위치
  TextColumn get photoUrl => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 재고 이동 ────────────────────────────────────────────────────────────
class InventoryMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get movementType => text()(); // purchase|sale|adjustment|return|loss|transfer_in|transfer_out|initial|count_adjust
  IntColumn get quantity => integer()(); // + 증가 / - 감소
  IntColumn get stockAfter => integer()();
  IntColumn get unitCost => integer().withDefault(const Constant(0))();
  TextColumn get refId => text().nullable()(); // sale_id | purchase_order_id
  TextColumn get refType => text().nullable()(); // sale|purchase_order|adjustment
  TextColumn get staffId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 발주서 ───────────────────────────────────────────────────────────────
class PurchaseOrders extends Table {
  TextColumn get id => text()();
  TextColumn get poNo => text()();
  TextColumn get supplierId => text()();
  TextColumn get staffId => text()(); // 발주 담당
  TextColumn get orderDate => text()();
  TextColumn get expectedDate => text().nullable()();
  TextColumn get receivedDate => text().nullable()();
  IntColumn get totalAmount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft|ordered|partial|received|cancelled
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 발주 아이템 ──────────────────────────────────────────────────────────
class PurchaseOrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text()();
  TextColumn get productId => text()();
  TextColumn get productName => text()(); // 스냅샷
  IntColumn get orderedQty => integer()();
  IntColumn get receivedQty => integer().withDefault(const Constant(0))();
  IntColumn get unitCost => integer()();
  IntColumn get totalCost => integer()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 재고 실사 ────────────────────────────────────────────────────────────
class StockCounts extends Table {
  TextColumn get id => text()();
  TextColumn get countNo => text()();
  TextColumn get staffId => text()();
  TextColumn get countDate => text()();
  TextColumn get status => text().withDefault(const Constant('draft'))(); // draft|in_progress|completed
  TextColumn get notes => text().nullable()();
  TextColumn get completedAt => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 재고 실사 아이템 ─────────────────────────────────────────────────────
class StockCountItems extends Table {
  TextColumn get id => text()();
  TextColumn get countId => text()();
  TextColumn get productId => text()();
  IntColumn get systemQty => integer()(); // 시스템상 수량
  IntColumn get countedQty => integer().nullable()(); // 실제 실사 수량
  IntColumn get difference => integer().nullable()(); // 차이
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
