import 'package:drift/drift.dart';

// ─── 레지스터 세션 (개점/마감) ─────────────────────────────────────────────
class RegisterSessions extends Table {
  TextColumn get id => text()();
  TextColumn get sessionNo => text()();
  TextColumn get openedBy => text()(); // staff_id
  TextColumn get closedBy => text().nullable()();
  TextColumn get openAt => text()();
  TextColumn get closeAt => text().nullable()();
  IntColumn get openingCash => integer().withDefault(const Constant(0))();
  IntColumn get closingCash => integer().nullable()();
  IntColumn get expectedCash => integer().nullable()(); // 계산상 기대 현금
  IntColumn get cashDifference => integer().nullable()(); // 오차
  TextColumn get status => text().withDefault(const Constant('open'))(); // open|closed
  TextColumn get closeNotes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 현금 입출금 ──────────────────────────────────────────────────────────
class CashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get staffId => text()();
  TextColumn get movementType => text()(); // cash_in|cash_out|petty_cash
  IntColumn get amount => integer()();
  TextColumn get reason => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 할인 ────────────────────────────────────────────────────────────────
class Discounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get discountType => text()(); // percent|amount
  IntColumn get value => integer()(); // % 또는 금액
  TextColumn get applicableTo => text().withDefault(const Constant('all'))(); // all|menu|product
  TextColumn get validFrom => text().nullable()();
  TextColumn get validTo => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 쿠폰 ────────────────────────────────────────────────────────────────
class Coupons extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().withLength(max: 30)();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get discountType => text()(); // percent|amount
  IntColumn get value => integer()();
  IntColumn get minPurchase => integer().withDefault(const Constant(0))();
  IntColumn get maxUses => integer().nullable()(); // 전체 사용 한도
  IntColumn get usedCount => integer().withDefault(const Constant(0))();
  TextColumn get issuedTo => text().nullable()(); // NULL=공용
  TextColumn get validFrom => text().nullable()();
  TextColumn get validTo => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 쿠폰 사용 이력 ───────────────────────────────────────────────────────
class CouponUsage extends Table {
  TextColumn get id => text()();
  TextColumn get couponId => text()();
  TextColumn get customerId => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get usedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 판매 ────────────────────────────────────────────────────────────────
class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get saleNo => text()(); // S{date}-{device}-{seq}
  TextColumn get sessionId => text()();
  TextColumn get appointmentId => text().nullable()();
  TextColumn get customerId => text().nullable()();
  TextColumn get staffId => text()(); // 주담당
  TextColumn get saleDate => text()(); // YYYY-MM-DD
  IntColumn get subtotal => integer()(); // 세전 합계
  IntColumn get discountAmount => integer().withDefault(const Constant(0))();
  IntColumn get taxableAmount10 => integer().withDefault(const Constant(0))(); // 10% 과세 기준액
  IntColumn get taxableAmount8 => integer().withDefault(const Constant(0))(); // 8% 과세 기준액
  IntColumn get taxAmount10 => integer().withDefault(const Constant(0))();
  IntColumn get taxAmount8 => integer().withDefault(const Constant(0))();
  IntColumn get taxExemptAmount => integer().withDefault(const Constant(0))();
  IntColumn get pointUsed => integer().withDefault(const Constant(0))();
  IntColumn get pointEarned => integer().withDefault(const Constant(0))();
  IntColumn get tipAmount => integer().withDefault(const Constant(0))();
  IntColumn get totalAmount => integer()(); // 최종 결제 금액
  TextColumn get status => text().withDefault(const Constant('completed'))(); // completed|refunded|partial_refund|voided
  TextColumn get notes => text().nullable()();
  TextColumn get receiptNo => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 판매 아이템 ──────────────────────────────────────────────────────────
class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get itemType => text()(); // menu|product|membership|gift_card
  TextColumn get refId => text().nullable()(); // 원본 ID
  TextColumn get staffId => text().nullable()();
  TextColumn get itemName => text()(); // 스냅샷
  IntColumn get unitPrice => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  IntColumn get discountAmount => integer().withDefault(const Constant(0))();
  TextColumn get discountType => text().nullable()(); // percent|amount (아이템 할인 방식)
  IntColumn get discountValue => integer().withDefault(const Constant(0))(); // 할인 입력값
  IntColumn get totalPrice => integer()(); // (unitPrice * qty) - discount
  TextColumn get taxType => text().withDefault(const Constant('10'))(); // 10|8|exempt
  TextColumn get selectedOptions => text().nullable()(); // JSON
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 판매 할인 적용 ───────────────────────────────────────────────────────
class SaleDiscounts extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get discountId => text().nullable()();
  TextColumn get couponId => text().nullable()();
  TextColumn get discountName => text()(); // 스냅샷
  TextColumn get discountType => text()(); // percent|amount
  IntColumn get value => integer()();
  IntColumn get appliedAmount => integer()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 결제 (복합 결제 지원) ────────────────────────────────────────────────
class SalePayments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get method => text()(); // cash|credit_card|debit_card|ic_card|qr|point|gift_card|membership|bank_transfer|other
  IntColumn get amount => integer()();
  TextColumn get giftCardId => text().nullable()();
  TextColumn get membershipId => text().nullable()();
  TextColumn get creditAccountId => text().nullable()(); // 掛け売り
  TextColumn get cardBrand => text().nullable()(); // visa|mastercard|jcb|amex
  TextColumn get cardLast4 => text().nullable()();
  TextColumn get approvalNo => text().nullable()(); // 승인번호
  TextColumn get terminalId => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 환불 ────────────────────────────────────────────────────────────────
class Refunds extends Table {
  TextColumn get id => text()();
  TextColumn get originalSaleId => text()();
  TextColumn get staffId => text()();
  TextColumn get refundNo => text()();
  TextColumn get refundType => text()(); // full|partial
  IntColumn get refundAmount => integer()();
  TextColumn get reason => text()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 환불 아이템 ──────────────────────────────────────────────────────────
class RefundItems extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text()();
  TextColumn get saleItemId => text()();
  IntColumn get quantity => integer()();
  IntColumn get refundAmount => integer()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 환불 결제 ────────────────────────────────────────────────────────────
class RefundPayments extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text()();
  TextColumn get method => text()();
  IntColumn get amount => integer()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 판매 드래프트 (작업 복구) ────────────────────────────────────────────
class DraftSales extends Table {
  TextColumn get id => text().withDefault(const Constant('current'))();
  TextColumn get data => text()(); // JSON
  TextColumn get savedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
