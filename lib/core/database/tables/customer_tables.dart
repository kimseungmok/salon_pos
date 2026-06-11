import 'package:drift/drift.dart';

// ─── 고객 ────────────────────────────────────────────────────────────────
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get customerNo => text().withLength(max: 20).nullable()();
  TextColumn get name => text().withLength(max: 50)();
  TextColumn get nameKana => text().withLength(max: 50).nullable()();
  TextColumn get gender => text().nullable()(); // male|female|other
  TextColumn get birthDate => text().nullable()(); // YYYY-MM-DD
  TextColumn get phone => text().withLength(max: 20).nullable()();
  TextColumn get email => text().withLength(max: 100).nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get assignedStaffId => text().nullable()();
  IntColumn get pointBalance => integer().withDefault(const Constant(0))();
  IntColumn get totalVisits => integer().withDefault(const Constant(0))();
  IntColumn get totalSpent => integer().withDefault(const Constant(0))();
  TextColumn get lastVisitDate => text().nullable()();
  TextColumn get firstVisitDate => text().nullable()();
  BoolColumn get isVip => boolean().withDefault(const Constant(false))();
  BoolColumn get cautionFlag => boolean().withDefault(const Constant(false))(); // 요주의
  TextColumn get cautionNote => text().nullable()();
  TextColumn get allergies => text().nullable()(); // JSON 배열
  BoolColumn get patchTestDone => boolean().withDefault(const Constant(false))();
  TextColumn get patchTestDate => text().nullable()();
  TextColumn get hairType => text().nullable()(); // 모질 메모
  TextColumn get skinType => text().nullable()();
  TextColumn get referralSource => text().nullable()(); // 소개경로
  TextColumn get referredBy => text().nullable()(); // 소개 고객 ID
  TextColumn get lineId => text().nullable()();
  TextColumn get instagramId => text().nullable()();
  TextColumn get notes => text().nullable()();
  BoolColumn get dmOptIn => boolean().withDefault(const Constant(true))();
  IntColumn get noShowCount => integer().withDefault(const Constant(0))();
  IntColumn get cancelCount => integer().withDefault(const Constant(0))();
  TextColumn get loyaltyTierId => text().nullable()(); // → loyalty_tiers.id
  IntColumn get loyaltyPointsTotal => integer().withDefault(const Constant(0))(); // 누적 적립 (티어 계산용)
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 고객 태그 ────────────────────────────────────────────────────────────
class CustomerTags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 30)();
  TextColumn get color => text().withDefault(const Constant('#8B95A1'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 고객-태그 연결 ───────────────────────────────────────────────────────
class CustomerTagLinks extends Table {
  TextColumn get customerId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {customerId, tagId};
}

// ─── 시술 기록 (카르테) ───────────────────────────────────────────────────
class TreatmentRecords extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get staffId => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get appointmentId => text().nullable()();
  TextColumn get treatmentDate => text()(); // YYYY-MM-DD
  TextColumn get menuNames => text().nullable()(); // 시술명 요약
  TextColumn get colorRecipe => text().nullable()(); // JSON {brand,color,ratio,developer}
  TextColumn get permRecipe => text().nullable()(); // JSON
  TextColumn get conditionBefore => text().nullable()(); // 시술 전 상태
  TextColumn get conditionAfter => text().nullable()(); // 시술 후 상태
  TextColumn get nextVisitMenu => text().nullable()(); // 다음 방문 제안
  IntColumn get nextVisitDays => integer().nullable()(); // 다음 방문 권장 일수
  TextColumn get photos => text().nullable()(); // JSON 배열 [url, ...]
  TextColumn get privateNotes => text().nullable()(); // 스태프 전용 메모
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 회원권 플랜 ──────────────────────────────────────────────────────────
class MembershipPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(max: 100)();
  TextColumn get description => text().nullable()();
  TextColumn get planType => text().withDefault(const Constant('session'))(); // session|period|amount
  IntColumn get price => integer()();
  IntColumn get totalSessions => integer().nullable()(); // session형
  IntColumn get validDays => integer().nullable()(); // period형
  IntColumn get totalAmount => integer().nullable()(); // amount형 (선불금액)
  TextColumn get applicableMenuIds => text().nullable()(); // JSON 배열
  IntColumn get discountRate => integer().withDefault(const Constant(0))(); // %
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 고객 회원권 ──────────────────────────────────────────────────────────
class CustomerMemberships extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get planId => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  IntColumn get totalSessions => integer().nullable()();
  IntColumn get usedSessions => integer().withDefault(const Constant(0))();
  IntColumn get remainingAmount => integer().nullable()(); // amount형
  TextColumn get status => text().withDefault(const Constant('active'))(); // active|expired|suspended|cancelled
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 회원권 사용 이력 ─────────────────────────────────────────────────────
class MembershipUsage extends Table {
  TextColumn get id => text()();
  TextColumn get membershipId => text()();
  TextColumn get customerId => text()();
  TextColumn get saleId => text().nullable()();
  IntColumn get sessionsUsed => integer().withDefault(const Constant(1))();
  IntColumn get amountUsed => integer().withDefault(const Constant(0))();
  TextColumn get usedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 포인트 이력 ──────────────────────────────────────────────────────────
class PointHistory extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get changeType => text()(); // earn|use|expire|adjust|gift_card
  IntColumn get changeAmount => integer()(); // +적립 / -사용
  IntColumn get balanceAfter => integer()();
  TextColumn get expireDate => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 기프트 카드 ──────────────────────────────────────────────────────────
class GiftCards extends Table {
  TextColumn get id => text()();
  TextColumn get cardNo => text().withLength(max: 20)();
  IntColumn get originalAmount => integer()();
  IntColumn get remainingAmount => integer()();
  TextColumn get purchasedBy => text().nullable()(); // 구매 고객 ID
  TextColumn get issuedTo => text().nullable()(); // 수령 고객 ID
  TextColumn get saleId => text().nullable()(); // 구매 판매 ID
  TextColumn get expireDate => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // active|used|expired|cancelled
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 기프트 카드 거래 ─────────────────────────────────────────────────────
class GiftCardTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text()();
  TextColumn get saleId => text().nullable()();
  TextColumn get transactionType => text()(); // purchase|use|refund
  IntColumn get amount => integer()();
  IntColumn get balanceAfter => integer()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 외상 계정 (掛け売り) ─────────────────────────────────────────────────
class CreditAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text()();
  IntColumn get balance => integer().withDefault(const Constant(0))(); // 미수금 (양수 = 고객이 갚아야 할 금액)
  IntColumn get creditLimit => integer().withDefault(const Constant(0))(); // 한도 (0=무제한)
  TextColumn get status => text().withDefault(const Constant('active'))(); // active|suspended
  TextColumn get notes => text().nullable()();
  TextColumn get updatedAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}

// ─── 외상 거래 이력 ───────────────────────────────────────────────────────
class CreditTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()(); // → credit_accounts.id
  TextColumn get customerId => text()();
  TextColumn get txType => text()(); // charge(외상발생)|payment(수납)|adjust(수동조정)
  IntColumn get amount => integer()(); // 양수 = 외상증가, 음수 = 수납/감소
  IntColumn get balanceAfter => integer()();
  TextColumn get saleId => text().nullable()(); // 연결 매출
  TextColumn get staffId => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text().withDefault(const CustomExpression("(datetime('now','localtime'))"))();

  @override
  Set<Column> get primaryKey => {id};
}
