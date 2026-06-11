import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

// ─── 마지막 담당자 기억 Provider ──────────────────────────────────────────
const _kLastStaffId = 'pos_last_staff_id';

final lastStaffProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLastStaffId);
});

Future<void> saveLastStaff(String staffId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastStaffId, staffId);
}

const _uuid = Uuid();

// ─── 레지스터 세션 ────────────────────────────────────────────────────────
final activeSessionProvider = StreamProvider<RegisterSession?>((ref) {
  final db = ref.watch(databaseProvider);
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return (db.select(db.registerSessions)
        ..where((t) => t.status.equals('open'))
        ..where((t) => t.openAt.like('$today%')))
      .watchSingleOrNull();
});

// ─── 메뉴 카테고리 목록 ───────────────────────────────────────────────────
final menuCategoriesProvider = StreamProvider<List<MenuCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menuCategories)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── 선택된 카테고리의 메뉴 목록 (활성만 — 通常表示用) ────────────────────
final menusByCategoryProvider =
    StreamProvider.family<List<MenusData>, String>((ref, categoryId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menus)
        ..where((t) => t.categoryId.equals(categoryId))
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── 선택된 카테고리의 메뉴 목록 (전체 — 編集モード用) ────────────────────
final menusByCategoryAllProvider =
    StreamProvider.family<List<MenusData>, String>((ref, categoryId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menus)
        ..where((t) => t.categoryId.equals(categoryId))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── お気に入りメニュー (isFavorite = true) ───────────────────────────────
final favoritesMenusProvider = StreamProvider<List<MenusData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menus)
        ..where((t) => t.isFavorite.equals(true))
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── 活性スタッフ ──────────────────────────────────────────────────────────
final activeStaffProvider = StreamProvider<List<StaffData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.staff)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

// ─── POS 주문 상태 ────────────────────────────────────────────────────────
class PosOrderItem {
  final String id;
  final String refId; // menu.id or product.id
  final String itemType; // menu | product
  final String name;
  final int unitPrice;
  final int qty;
  final String taxType; // 10 | 8 | exempt
  final String? staffId;
  final String? staffName;
  final int discountAmount; // 아이템 레벨 할인 (엔화)

  const PosOrderItem({
    required this.id,
    required this.refId,
    required this.itemType,
    required this.name,
    required this.unitPrice,
    required this.qty,
    this.taxType = '10',
    this.staffId,
    this.staffName,
    this.discountAmount = 0,
  });

  int get total => (unitPrice * qty - discountAmount).clamp(0, 999999999);

  PosOrderItem copyWith({
    int? qty,
    String? staffId,
    String? staffName,
    int? unitPrice,
    int? discountAmount,
  }) =>
      PosOrderItem(
        id: id,
        refId: refId,
        itemType: itemType,
        name: name,
        unitPrice: unitPrice ?? this.unitPrice,
        qty: qty ?? this.qty,
        taxType: taxType,
        staffId: staffId ?? this.staffId,
        staffName: staffName ?? this.staffName,
        discountAmount: discountAmount ?? this.discountAmount,
      );
}

class PosState {
  final List<PosOrderItem> items;
  final String? customerId;
  final String? customerName;
  final String? selectedStaffId;
  final int manualDiscountAmount; // 수동 할인금액
  final int pointUsed;
  final int tipAmount;
  final String? appointmentId;
  final String? notes; // 売上メモ

  const PosState({
    this.items = const [],
    this.customerId,
    this.customerName,
    this.selectedStaffId,
    this.manualDiscountAmount = 0,
    this.pointUsed = 0,
    this.tipAmount = 0,
    this.appointmentId,
    this.notes,
  });

  // ─── 계산 ──────────────────────────────────────────────────────────────
  // 아이템 할인 포함된 소계
  int get subtotal => items.fold(0, (s, i) => s + i.total);

  // 10% 과세 품목 합계 (세포함)
  int get taxable10Total => items
      .where((i) => i.taxType == '10')
      .fold(0, (s, i) => s + i.total);

  // 8% 과세 품목 합계 (세포함)
  int get taxable8Total => items
      .where((i) => i.taxType == '8')
      .fold(0, (s, i) => s + i.total);

  int get exemptTotal => items
      .where((i) => i.taxType == 'exempt')
      .fold(0, (s, i) => s + i.total);

  // 세별도 기준액
  int get taxableAmount10 => (taxable10Total / 1.10).round();
  int get taxableAmount8 => (taxable8Total / 1.08).round();

  // 세액
  int get taxAmount10 => taxable10Total - taxableAmount10;
  int get taxAmount8 => taxable8Total - taxableAmount8;
  int get totalTax => taxAmount10 + taxAmount8;

  int get discountTotal => manualDiscountAmount;

  int get grandTotal =>
      (subtotal - discountTotal - pointUsed).clamp(0, 999999999);

  PosState copyWith({
    List<PosOrderItem>? items,
    String? customerId,
    String? customerName,
    String? selectedStaffId,
    int? manualDiscountAmount,
    int? pointUsed,
    int? tipAmount,
    String? appointmentId,
    String? notes,
    bool clearCustomer = false,
    bool clearStaff = false,
    bool clearNotes = false,
  }) =>
      PosState(
        items: items ?? this.items,
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        customerName:
            clearCustomer ? null : (customerName ?? this.customerName),
        selectedStaffId: clearStaff ? null : (selectedStaffId ?? this.selectedStaffId),
        manualDiscountAmount:
            manualDiscountAmount ?? this.manualDiscountAmount,
        pointUsed: pointUsed ?? this.pointUsed,
        tipAmount: tipAmount ?? this.tipAmount,
        appointmentId: appointmentId ?? this.appointmentId,
        notes: clearNotes ? null : (notes ?? this.notes),
      );
}

// ─── POS 노티파이어 ───────────────────────────────────────────────────────
class PosNotifier extends Notifier<PosState> {
  @override
  PosState build() => const PosState();

  AppDatabase get _db => ref.read(databaseProvider);

  // 메뉴 추가
  void addMenu(MenusData menu, {String? staffId, String? staffName}) {
    final items = [...state.items];
    final idx = items.indexWhere(
        (e) => e.refId == menu.id && e.itemType == 'menu' && e.staffId == staffId);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(qty: items[idx].qty + 1);
    } else {
      items.add(PosOrderItem(
        id: _uuid.v4(),
        refId: menu.id,
        itemType: 'menu',
        name: menu.name,
        unitPrice: menu.price,
        qty: 1,
        taxType: menu.taxType,
        staffId: staffId,
        staffName: staffName,
      ));
    }
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 상품(물판) 추가
  void addProduct(Product product) {
    final items = [...state.items];
    final idx = items.indexWhere(
        (e) => e.refId == product.id && e.itemType == 'product');
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(qty: items[idx].qty + 1);
    } else {
      items.add(PosOrderItem(
        id: _uuid.v4(),
        refId: product.id,
        itemType: 'product',
        name: product.name,
        unitPrice: product.retailPrice > 0 ? product.retailPrice : product.costPrice,
        qty: 1,
        taxType: product.taxType,
      ));
    }
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // セットメニュー一括カート追加 (バンドルID + メニューリスト)
  void addBundle(MenuBundle bundle, List<MenusData> menus) {
    final items = [...state.items];
    // バンドルを1行で追加 (refId=bundleId, itemType='bundle')
    final existIdx = items.indexWhere(
        (e) => e.refId == bundle.id && e.itemType == 'bundle');
    if (existIdx >= 0) {
      items[existIdx] = items[existIdx].copyWith(qty: items[existIdx].qty + 1);
    } else {
      final bundlePrice = (bundle.bundlePrice ?? 0) > 0
          ? bundle.bundlePrice!
          : menus.fold<int>(0, (sum, m) => sum + m.price);
      final discounted = bundle.discountRate > 0
          ? (bundlePrice * (1 - bundle.discountRate / 100)).round()
          : bundlePrice;
      final menuNames = menus.map((m) => m.name).join('・');
      items.add(PosOrderItem(
        id: _uuid.v4(),
        refId: bundle.id,
        itemType: 'bundle',
        name: '【セット】${bundle.name}（$menuNames）',
        unitPrice: discounted,
        qty: 1,
        taxType: '10',
      ));
    }
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 수량 변경
  void updateQty(String itemId, int qty) {
    if (qty <= 0) {
      removeItem(itemId);
      return;
    }
    final items = state.items
        .map((e) => e.id == itemId ? e.copyWith(qty: qty) : e)
        .toList();
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 아이템 삭제
  void removeItem(String itemId) {
    final items = state.items.where((e) => e.id != itemId).toList();
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 전체 클리어
  void clear() {
    state = const PosState();
    _clearDraft();
  }

  // 아이템 복원 (Undo용)
  void restoreItem(PosOrderItem item) {
    final items = [...state.items, item];
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 여러 아이템 일괄 복원 (クリア Undo용)
  void restoreItems(List<PosOrderItem> items) {
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 返金後 再注文用: 이름/단가/수량/taxType 직접 지정
  void addRawItem({
    required String name,
    required int unitPrice,
    required int qty,
    String taxType = '10',
    String? staffId,
    String? staffName,
  }) {
    final items = [...state.items];
    final idx = items.indexWhere(
        (e) => e.name == name && e.unitPrice == unitPrice && e.staffId == staffId);
    if (idx >= 0) {
      items[idx] = items[idx].copyWith(qty: items[idx].qty + qty);
    } else {
      items.add(PosOrderItem(
        id: _uuid.v4(),
        refId: 'reorder-${_uuid.v4()}',
        itemType: 'menu',
        name: name,
        unitPrice: unitPrice,
        qty: qty,
        taxType: taxType,
        staffId: staffId,
        staffName: staffName,
      ));
    }
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 고객 설정
  void setCustomer(String id, String name) {
    state = state.copyWith(customerId: id, customerName: name);
    _saveDraft();
  }

  void clearCustomer() {
    state = state.copyWith(clearCustomer: true);
    _saveDraft();
  }

  // 담당 스태프 (마지막 선택 자동 저장)
  void setStaff(String? staffId) {
    if (staffId == null) {
      state = state.copyWith(clearStaff: true);
    } else {
      state = state.copyWith(selectedStaffId: staffId);
      saveLastStaff(staffId); // SharedPreferences에 저장
    }
  }

  // 아이템 레벨 할인
  void setItemDiscount(String itemId, int discountAmount) {
    final items = state.items.map((e) {
      if (e.id != itemId) return e;
      final maxDisc = e.unitPrice * e.qty;
      return e.copyWith(discountAmount: discountAmount.clamp(0, maxDisc));
    }).toList();
    state = state.copyWith(items: items);
    _saveDraft();
  }

  // 팁
  void setTip(int amount) {
    state = state.copyWith(tipAmount: amount.clamp(0, 99999));
  }

  // 할인
  void setDiscount(int amount) {
    state = state.copyWith(manualDiscountAmount: amount.clamp(0, state.subtotal));
  }

  // 포인트 사용
  void setPointUsed(int points) {
    state = state.copyWith(pointUsed: points.clamp(0, state.subtotal));
  }

  // 売上メモ
  void setNotes(String? notes) {
    final trimmed = notes?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      state = state.copyWith(clearNotes: true);
    } else {
      state = state.copyWith(notes: trimmed);
    }
    _saveDraft();
  }

  // 예약 연결
  void linkAppointment(String appointmentId) {
    state = state.copyWith(appointmentId: appointmentId);
  }

  // ─── 결제 완료 처리 ─────────────────────────────────────────────────────
  Future<String> completeSale({
    required String sessionId,
    required List<Map<String, dynamic>> payments, // [{method, amount, ...}]
  }) async {
    final s = state;
    final staffId = s.selectedStaffId ?? await _defaultStaffId();
    final saleId = _uuid.v4();
    final now = DateTime.now();
    final saleDate = now.toIso8601String().substring(0, 10);

    // 판매번호 생성
    final settings = await _db.settings;
    final deviceCode = settings?.deviceCode ?? 'A';
    final seq = await _nextSaleSeq(saleDate, deviceCode);
    final saleNo = 'S${saleDate.replaceAll('-', '')}-$deviceCode-${seq.toString().padLeft(4, '0')}';

    await _db.transaction(() async {
      // 1. sales 레코드
      await _db.into(_db.sales).insert(SalesCompanion.insert(
        id: saleId,
        saleNo: saleNo,
        sessionId: sessionId,
        appointmentId: Value(s.appointmentId),
        customerId: Value(s.customerId),
        staffId: staffId,
        saleDate: saleDate,
        subtotal: s.subtotal,
        discountAmount: Value(s.discountTotal),
        taxableAmount10: Value(s.taxableAmount10),
        taxableAmount8: Value(s.taxableAmount8),
        taxAmount10: Value(s.taxAmount10),
        taxAmount8: Value(s.taxAmount8),
        pointUsed: Value(s.pointUsed),
        pointEarned: Value(_calcPointEarned(s.grandTotal)),
        totalAmount: s.grandTotal,
        notes: Value(s.notes),
      ));

      // 2. sale_items
      for (final item in s.items) {
        await _db.into(_db.saleItems).insert(SaleItemsCompanion.insert(
          id: _uuid.v4(),
          saleId: saleId,
          itemType: item.itemType,
          refId: Value(item.refId),
          staffId: Value(item.staffId ?? staffId),
          itemName: item.name,
          unitPrice: item.unitPrice,
          quantity: Value(item.qty),
          totalPrice: item.total,
          taxType: Value(item.taxType),
        ));
      }

      // 3. sale_payments
      for (final p in payments) {
        await _db.into(_db.salePayments).insert(SalePaymentsCompanion.insert(
          id: _uuid.v4(),
          saleId: saleId,
          method: p['method'] as String,
          amount: p['amount'] as int,
          cardBrand: Value(p['cardBrand'] as String?),
          cardLast4: Value(p['cardLast4'] as String?),
          approvalNo: Value(p['approvalNo'] as String?),
          giftCardId: Value(p['giftCardId'] as String?),
          membershipId: Value(p['membershipId'] as String?),
          creditAccountId: Value(p['creditAccountId'] as String?),
        ));

        // 掛け売り 결제 — credit_accounts 잔액 증가 & 이력 기록
        if (p['method'] == 'credit' && s.customerId != null) {
          final chargeAmount = p['amount'] as int;
          final existingAccount = await (_db.select(_db.creditAccounts)
                ..where((t) => t.customerId.equals(s.customerId!)))
              .getSingleOrNull();

          final String accountId;
          final int newBalance;
          if (existingAccount != null) {
            accountId = existingAccount.id;
            newBalance = existingAccount.balance + chargeAmount;
            await (_db.update(_db.creditAccounts)
                  ..where((t) => t.id.equals(accountId)))
                .write(CreditAccountsCompanion(balance: Value(newBalance)));
          } else {
            accountId = _uuid.v4();
            newBalance = chargeAmount;
            await _db.into(_db.creditAccounts).insert(CreditAccountsCompanion.insert(
              id: accountId,
              customerId: s.customerId!,
              balance: Value(chargeAmount),
            ));
          }

          await _db.into(_db.creditTransactions).insert(
                CreditTransactionsCompanion.insert(
                  id: _uuid.v4(),
                  accountId: accountId,
                  customerId: s.customerId!,
                  txType: 'charge',
                  amount: chargeAmount,
                  balanceAfter: newBalance,
                  saleId: Value(saleId),
                  staffId: Value(staffId),
                ),
              );
        }
      }

      // 4. 포인트 적립/사용
      if (s.customerId != null) {
        final earned = _calcPointEarned(s.grandTotal);
        if (s.pointUsed > 0) {
          await _db.into(_db.pointHistory).insert(PointHistoryCompanion.insert(
            id: _uuid.v4(),
            customerId: s.customerId!,
            saleId: Value(saleId),
            changeType: 'use',
            changeAmount: -s.pointUsed,
            balanceAfter: await _getPointBalance(s.customerId!) - s.pointUsed,
          ));
          await (_db.update(_db.customers)
                ..where((t) => t.id.equals(s.customerId!)))
              .write(CustomersCompanion(
            pointBalance: Value(
                (await _getPointBalance(s.customerId!) - s.pointUsed).clamp(0, 999999)),
          ));
        }
        if (earned > 0) {
          final balBefore = await _getPointBalance(s.customerId!);
          final balAfter = balBefore + earned;
          await _db.into(_db.pointHistory).insert(PointHistoryCompanion.insert(
            id: _uuid.v4(),
            customerId: s.customerId!,
            saleId: Value(saleId),
            changeType: 'earn',
            changeAmount: earned,
            balanceAfter: balAfter,
          ));
          // 고객 통계 업데이트
          await (_db.update(_db.customers)
                ..where((t) => t.id.equals(s.customerId!)))
              .write(CustomersCompanion(
            pointBalance: Value(balAfter),
            totalVisits: Value(await _getVisitCount(s.customerId!) + 1),
            totalSpent: Value(await _getTotalSpent(s.customerId!) + s.grandTotal),
            lastVisitDate: Value(saleDate),
          ));
        }
      }

      // 5. 재고 차감 (메뉴 backbar 상품은 별도 처리 — 향후 구현)

      // 6. 일별 집계 업데이트
      await _updateDailySummary(saleDate, s.grandTotal,
          s.taxAmount10 + s.taxAmount8, s.customerId != null);

      // 7. 드래프트 클리어
      await _db.delete(_db.draftSales).go();
    });

    // 예약 상태 완료로 변경
    if (s.appointmentId != null) {
      await (_db.update(_db.appointments)
            ..where((t) => t.id.equals(s.appointmentId!)))
          .write(AppointmentsCompanion(
        status: const Value('completed'),
        saleId: Value(saleId),
      ));
    }

    state = const PosState();
    return saleId;
  }

  // ─── 헬퍼 ──────────────────────────────────────────────────────────────
  Future<String> _defaultStaffId() async {
    final list = await _db.activeStaff;
    return list.isNotEmpty ? list.first.id : 'staff-default';
  }

  Future<int> _nextSaleSeq(String date, String device) async {
    final result = await _db.customSelect(
      "SELECT COUNT(*) as cnt FROM sales WHERE sale_date = ? AND sale_no LIKE ?",
      variables: [Variable(date), Variable('S${date.replaceAll('-', '')}-$device-%')],
    ).getSingleOrNull();
    return (result?.read<int>('cnt') ?? 0) + 1;
  }

  int _calcPointEarned(int amount) {
    return (amount * 0.01).floor(); // 1%
  }

  Future<int> _getPointBalance(String customerId) async {
    final c = await (_db.select(_db.customers)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    return c?.pointBalance ?? 0;
  }

  Future<int> _getVisitCount(String customerId) async {
    final c = await (_db.select(_db.customers)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    return c?.totalVisits ?? 0;
  }

  Future<int> _getTotalSpent(String customerId) async {
    final c = await (_db.select(_db.customers)
          ..where((t) => t.id.equals(customerId)))
        .getSingleOrNull();
    return c?.totalSpent ?? 0;
  }

  Future<void> _updateDailySummary(
      String date, int saleAmount, int taxAmount, bool hasCustomer) async {
    final existing = await (_db.select(_db.dailySummaries)
          ..where((t) => t.id.equals(date)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.dailySummaries).insert(DailySummariesCompanion.insert(
        id: date,
        summaryDate: date,
        totalSales: Value(saleAmount),
        netSales: Value(saleAmount),
        taxAmount10: Value(taxAmount),
        customerCount: Value(hasCustomer ? 1 : 0),
        saleCount: Value(1),
      ));
    } else {
      await (_db.update(_db.dailySummaries)
            ..where((t) => t.id.equals(date)))
          .write(DailySummariesCompanion(
        totalSales: Value(existing.totalSales + saleAmount),
        netSales: Value(existing.netSales + saleAmount),
        taxAmount10: Value(existing.taxAmount10 + taxAmount),
        customerCount: Value(existing.customerCount + (hasCustomer ? 1 : 0)),
        saleCount: Value(existing.saleCount + 1),
      ));
    }
  }

  // 드래프트 저장 (debounce는 UI에서 처리)
  Future<void> _saveDraft() async {
    final data = jsonEncode({
      'items': state.items
          .map((i) => {
                'id': i.id,
                'refId': i.refId,
                'itemType': i.itemType,
                'name': i.name,
                'unitPrice': i.unitPrice,
                'qty': i.qty,
                'taxType': i.taxType,
                'staffId': i.staffId,
                'staffName': i.staffName,
              })
          .toList(),
      'customerId': state.customerId,
      'customerName': state.customerName,
      'selectedStaffId': state.selectedStaffId,
      'manualDiscountAmount': state.manualDiscountAmount,
      'pointUsed': state.pointUsed,
      'appointmentId': state.appointmentId,
      'notes': state.notes,
    });
    await _db.into(_db.draftSales).insertOnConflictUpdate(
      DraftSalesCompanion.insert(id: const Value('current'), data: data),
    );
  }

  Future<void> _clearDraft() async {
    await _db.delete(_db.draftSales).go();
  }

  // 드래프트 복구
  Future<void> loadDraft() async {
    final draft = await _db.currentDraftSale;
    if (draft == null) return;
    try {
      final json = jsonDecode(draft.data) as Map<String, dynamic>;
      final items = (json['items'] as List).map((i) {
        final m = i as Map<String, dynamic>;
        return PosOrderItem(
          id: m['id'] as String,
          refId: m['refId'] as String,
          itemType: m['itemType'] as String,
          name: m['name'] as String,
          unitPrice: m['unitPrice'] as int,
          qty: m['qty'] as int,
          taxType: m['taxType'] as String? ?? '10',
          staffId: m['staffId'] as String?,
          staffName: m['staffName'] as String?,
        );
      }).toList();
      state = PosState(
        items: items,
        customerId: json['customerId'] as String?,
        customerName: json['customerName'] as String?,
        selectedStaffId: json['selectedStaffId'] as String?,
        manualDiscountAmount: json['manualDiscountAmount'] as int? ?? 0,
        pointUsed: json['pointUsed'] as int? ?? 0,
        appointmentId: json['appointmentId'] as String?,
        notes: json['notes'] as String?,
      );
    } catch (_) {
      await _clearDraft();
    }
  }
}

final posProvider = NotifierProvider<PosNotifier, PosState>(PosNotifier.new);
