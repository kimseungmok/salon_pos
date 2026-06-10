import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/database_provider.dart';

// ─── 거래 내역 필터 ────────────────────────────────────────────────────────
class TransactionFilter {
  final String startDate;   // YYYY-MM-DD
  final String endDate;     // YYYY-MM-DD
  final String? staffId;
  final String? payMethod;  // 'all' or method key
  final String? status;     // 'all' | 'completed' | 'partial_refund' | 'refunded' | 'voided'
  final String sort;        // 'date_desc' | 'date_asc' | 'amount_desc' | 'amount_asc'
  final String? searchQuery; // 取引番号 or 金額 検索

  const TransactionFilter({
    required this.startDate,
    required this.endDate,
    this.staffId,
    this.payMethod,
    this.status,
    this.sort = 'date_desc',
    this.searchQuery,
  });

  TransactionFilter copyWith({
    String? startDate,
    String? endDate,
    String? staffId,
    String? payMethod,
    String? status,
    String? sort,
    String? searchQuery,
    bool clearSearch = false,
    bool clearStaff = false,
  }) {
    return TransactionFilter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      staffId: clearStaff ? null : staffId ?? this.staffId,
      payMethod: payMethod ?? this.payMethod,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      searchQuery: clearSearch ? null : searchQuery ?? this.searchQuery,
    );
  }
}

// ─── 거래 내역 데이터 모델 ─────────────────────────────────────────────────
class TransactionItem {
  final String id;
  final String saleNo;
  final String saleDate;
  final DateTime createdAt;
  final String staffId;
  final String staffName;
  final String? customerId;
  final String? customerName;
  final int totalAmount;
  final int taxAmount;
  final int discountAmount;
  final String status;
  final List<String> methods;     // 결제 수단 목록
  final List<String> menuNames;   // 시술 목록

  const TransactionItem({
    required this.id,
    required this.saleNo,
    required this.saleDate,
    required this.createdAt,
    required this.staffId,
    required this.staffName,
    this.customerId,
    this.customerName,
    required this.totalAmount,
    required this.taxAmount,
    required this.discountAmount,
    required this.status,
    required this.methods,
    required this.menuNames,
  });

  bool get isRefunded => status == 'refunded';
  bool get isPartialRefund => status == 'partial_refund';
  bool get isVoided => status == 'voided';
  bool get isCompleted => status == 'completed' || status == 'partial_refund';
}

// ─── 스태프 목록 Provider (거래 이력 필터용) ───────────────────────────────
class StaffItem {
  final String id;
  final String name;
  const StaffItem({required this.id, required this.name});
}

final transactionStaffListProvider = FutureProvider<List<StaffItem>>((ref) async {
  final db = ref.watch(databaseProvider);
  final staffList = await db.select(db.staff).get();
  return staffList.map((s) => StaffItem(id: s.id, name: s.name)).toList();
});

// ─── Filter Provider ───────────────────────────────────────────────────────
final transactionFilterProvider = StateProvider<TransactionFilter>((ref) {
  final now = DateTime.now();
  final startDate =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
  final endDate =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return TransactionFilter(startDate: startDate, endDate: endDate);
});

// ─── 거래 목록 Provider ────────────────────────────────────────────────────
final transactionListProvider =
    FutureProvider<List<TransactionItem>>((ref) async {
  final db = ref.watch(databaseProvider);
  final filter = ref.watch(transactionFilterProvider);

  // 스태프명 맵
  final staffList = await db.select(db.staff).get();
  final staffNames = {for (final s in staffList) s.id: s.name};

  // 고객명 맵 (간단하게 별도 조회)
  final customerList = await db.select(db.customers).get();
  final customerNames = {for (final c in customerList) c.id: c.name};

  // 판매 조회 (status 필터 포함)
  final salesQuery = db.select(db.sales)
    ..where((t) => t.saleDate.isBetweenValues(filter.startDate, filter.endDate));

  if (filter.staffId != null && filter.staffId!.isNotEmpty) {
    salesQuery.where((t) => t.staffId.equals(filter.staffId!));
  }

  final allowedStatuses = filter.status == null || filter.status == 'all'
      ? ['completed', 'partial_refund', 'refunded', 'voided']
      : [filter.status!];
  salesQuery.where((t) => t.status.isIn(allowedStatuses));

  var sales = await salesQuery.get();

  // 결제 수단 맵
  final saleIds = sales.map((s) => s.id).toList();
  final payMap = <String, List<String>>{};
  if (saleIds.isNotEmpty) {
    final payments = await (db.select(db.salePayments)
          ..where((t) => t.saleId.isIn(saleIds)))
        .get();
    for (final p in payments) {
      payMap.putIfAbsent(p.saleId, () => []).add(p.method);
    }
  }

  // 결제 수단 필터
  if (filter.payMethod != null && filter.payMethod != 'all') {
    sales = sales
        .where((s) => (payMap[s.id] ?? []).contains(filter.payMethod))
        .toList();
  }

  // 시술 메뉴 맵 (검색 필터보다 먼저 빌드)
  final menuMap = <String, List<String>>{};
  if (saleIds.isNotEmpty) {
    final items = await (db.select(db.saleItems)
          ..where((t) => t.saleId.isIn(saleIds)))
        .get();
    for (final item in items) {
      menuMap.putIfAbsent(item.saleId, () => []).add(item.itemName);
    }
  }

  // 검색 필터 (取引番号 or 금액 or 고객명 or 담당자 or 메뉴명)
  if (filter.searchQuery != null && filter.searchQuery!.trim().isNotEmpty) {
    final q = filter.searchQuery!.trim().toLowerCase();
    final amtQ = int.tryParse(q.replaceAll(',', '').replaceAll('¥', ''));
    sales = sales.where((s) {
      if (s.saleNo.toLowerCase().contains(q)) return true;
      if (amtQ != null && s.totalAmount == amtQ) return true;
      final cName = s.customerId != null
          ? (customerNames[s.customerId] ?? '').toLowerCase()
          : '';
      if (cName.contains(q)) return true;
      final staffName = (staffNames[s.staffId] ?? '').toLowerCase();
      if (staffName.contains(q)) return true;
      // 메뉴명 검색
      final menus = menuMap[s.id] ?? [];
      if (menus.any((m) => m.toLowerCase().contains(q))) return true;
      return false;
    }).toList();
  }

  // 정렬
  List<TransactionItem> result = sales.map((s) {
    return TransactionItem(
      id: s.id,
      saleNo: s.saleNo,
      saleDate: s.saleDate,
      createdAt: DateTime.parse(s.createdAt),
      staffId: s.staffId,
      staffName: staffNames[s.staffId] ?? '-',
      customerId: s.customerId,
      customerName: s.customerId != null ? customerNames[s.customerId] : null,
      totalAmount: s.totalAmount,
      taxAmount: s.taxAmount10 + s.taxAmount8,
      discountAmount: s.discountAmount,
      status: s.status,
      methods: payMap[s.id] ?? [],
      menuNames: menuMap[s.id] ?? [],
    );
  }).toList();

  switch (filter.sort) {
    case 'date_asc':
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      break;
    case 'amount_desc':
      result.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      break;
    case 'amount_asc':
      result.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
      break;
    case 'date_desc':
    default:
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      break;
  }

  return result;
});

// ─── 거래 내역 요약 Provider ────────────────────────────────────────────────
class TransactionSummary {
  final int totalRevenue;
  final int totalCount;
  final int completedCount;
  final int refundedCount;
  final int voidedCount;
  final int totalTax;
  final int totalDiscount;

  const TransactionSummary({
    required this.totalRevenue,
    required this.totalCount,
    required this.completedCount,
    required this.refundedCount,
    required this.voidedCount,
    required this.totalTax,
    required this.totalDiscount,
  });
}

final transactionSummaryProvider =
    FutureProvider<TransactionSummary>((ref) async {
  final items = await ref.watch(transactionListProvider.future);
  return TransactionSummary(
    totalRevenue: items
        .where((i) => i.isCompleted)
        .fold(0, (s, e) => s + e.totalAmount),
    totalCount: items.length,
    completedCount: items.where((i) => i.isCompleted).length,
    refundedCount: items.where((i) => i.isRefunded).length,
    voidedCount: items.where((i) => i.isVoided).length,
    totalTax:
        items.where((i) => i.isCompleted).fold(0, (s, e) => s + e.taxAmount),
    totalDiscount: items
        .where((i) => i.isCompleted)
        .fold(0, (s, e) => s + e.discountAmount),
  );
});
