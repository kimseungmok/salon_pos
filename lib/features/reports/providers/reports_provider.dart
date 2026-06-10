import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

// ─── 기간 선택 ────────────────────────────────────────────────────────────
enum ReportPeriod { today, week, month, lastMonth, custom }

class ReportRange {
  final DateTime start;
  final DateTime end;
  final ReportPeriod period;

  const ReportRange({
    required this.start,
    required this.end,
    required this.period,
  });

  static ReportRange forToday() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return ReportRange(start: start, end: now, period: ReportPeriod.today);
  }

  static ReportRange forWeek() {
    final now = DateTime.now();
    final weekday = now.weekday % 7;
    final start = DateTime(now.year, now.month, now.day - weekday);
    return ReportRange(start: start, end: now, period: ReportPeriod.week);
  }

  static ReportRange forMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    return ReportRange(start: start, end: now, period: ReportPeriod.month);
  }

  static ReportRange forLastMonth() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final lastOfLastMonth =
        firstOfThisMonth.subtract(const Duration(days: 1));
    final start = DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
    return ReportRange(
        start: start, end: lastOfLastMonth, period: ReportPeriod.lastMonth);
  }

  // 전일/전주/전월 비교용 동일 기간 범위
  ReportRange get previous {
    switch (period) {
      case ReportPeriod.today:
        // 어제 같은 시간대
        return ReportRange(
          start: start.subtract(const Duration(days: 1)),
          end: end.subtract(const Duration(days: 1)),
          period: period,
        );
      case ReportPeriod.week:
        // 지난주
        return ReportRange(
          start: start.subtract(const Duration(days: 7)),
          end: end.subtract(const Duration(days: 7)),
          period: period,
        );
      case ReportPeriod.month:
        // 지난달 같은 날짜
        final prevMonth = DateTime(start.year, start.month - 1, 1);
        final prevEnd = DateTime(start.year, start.month, 0); // 지난달 말일
        return ReportRange(start: prevMonth, end: prevEnd, period: period);
      case ReportPeriod.lastMonth:
        // 2달 전
        final twoMonthsAgo = DateTime(start.year, start.month - 1, 1);
        final prevEnd = DateTime(start.year, start.month, 0);
        return ReportRange(start: twoMonthsAgo, end: prevEnd, period: period);
      case ReportPeriod.custom:
        final diff = end.difference(start);
        return ReportRange(
          start: start.subtract(diff + const Duration(days: 1)),
          end: start.subtract(const Duration(days: 1)),
          period: period,
        );
    }
  }

  String get startStr => _fmtDate(start);
  String get endStr => _fmtDate(end);

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final reportRangeProvider = StateProvider<ReportRange>(
  (_) => ReportRange.forMonth(),
);

// ─── 메인 매출 요약 ───────────────────────────────────────────────────────
class SalesSummary {
  final int totalRevenue;
  final int totalCount;
  final int avgSale;
  final int totalTax;
  final int taxAmount10; // 10% 소비세
  final int taxAmount8;  // 8% 경감세율
  final int taxableAmount10; // 10% 과세 기준액
  final int taxableAmount8;  // 8% 과세 기준액
  final int totalDiscount;
  final int refundAmount;
  final int netRevenue;
  final int pointEarned;
  final int pointUsed;
  final int newCustomerCount;
  final int returningCustomerCount;
  final int dormantCustomerCount; // 90일 이상 미방문
  // 비교 기간 (전일/전월 대비)
  final int prevRevenue;
  final int prevCount;
  // 시간대별 매출 (0~23)
  final Map<int, int> revenueByHour;
  // 날짜별 매출 YYYY-MM-DD → amount
  final Map<String, int> revenueByDay;
  // 결제 수단별 금액
  final Map<String, int> revenueByMethod;
  // 인기 메뉴 TOP10
  final List<TopMenuItem> topMenus;
  // 스태프별 매출
  final List<StaffRevenue> staffRevenues;
  // 최근 거래 내역
  final List<RecentSale> recentSales;

  const SalesSummary({
    required this.totalRevenue,
    required this.totalCount,
    required this.avgSale,
    required this.totalTax,
    this.taxAmount10 = 0,
    this.taxAmount8 = 0,
    this.taxableAmount10 = 0,
    this.taxableAmount8 = 0,
    required this.totalDiscount,
    required this.refundAmount,
    required this.netRevenue,
    required this.pointEarned,
    required this.pointUsed,
    required this.newCustomerCount,
    required this.returningCustomerCount,
    this.dormantCustomerCount = 0,
    required this.prevRevenue,
    required this.prevCount,
    required this.revenueByHour,
    required this.revenueByDay,
    required this.revenueByMethod,
    required this.topMenus,
    required this.staffRevenues,
    required this.recentSales,
  });

  static const empty = SalesSummary(
    totalRevenue: 0,
    totalCount: 0,
    avgSale: 0,
    totalTax: 0,
    taxAmount10: 0,
    taxAmount8: 0,
    taxableAmount10: 0,
    taxableAmount8: 0,
    totalDiscount: 0,
    refundAmount: 0,
    netRevenue: 0,
    pointEarned: 0,
    pointUsed: 0,
    newCustomerCount: 0,
    returningCustomerCount: 0,
    dormantCustomerCount: 0,
    prevRevenue: 0,
    prevCount: 0,
    revenueByHour: {},
    revenueByDay: {},
    revenueByMethod: {},
    topMenus: [],
    staffRevenues: [],
    recentSales: [],
  );

  // 전일/전월 대비 성장률 (%)
  double get revenueGrowth {
    if (prevRevenue == 0) return 0;
    return (totalRevenue - prevRevenue) / prevRevenue * 100;
  }

  double get countGrowth {
    if (prevCount == 0) return 0;
    return (totalCount - prevCount) / prevCount * 100;
  }

  // 신규고객 비율
  double get newCustomerRatio {
    final total = newCustomerCount + returningCustomerCount;
    if (total == 0) return 0;
    return newCustomerCount / total;
  }
}

class TopMenuItem {
  final String name;
  final int count;
  final int revenue;

  const TopMenuItem({
    required this.name,
    required this.count,
    required this.revenue,
  });
}

class StaffRevenue {
  final String staffId;
  final String staffName;
  final int revenue;
  final int count;

  const StaffRevenue({
    required this.staffId,
    required this.staffName,
    required this.revenue,
    required this.count,
  });
}

class RecentSale {
  final String id;
  final String saleNo;
  final String staffName;
  final String customerName;
  final int amount;
  final String status;
  final DateTime createdAt;
  final String primaryMethod;

  const RecentSale({
    required this.id,
    required this.saleNo,
    required this.staffName,
    required this.customerName,
    required this.amount,
    required this.status,
    required this.createdAt,
    required this.primaryMethod,
  });
}

// ─── 메인 Provider ────────────────────────────────────────────────────────
final salesSummaryProvider =
    FutureProvider.family<SalesSummary, ReportRange>((ref, range) async {
  final db = ref.watch(databaseProvider);

  // 현재 기간 매출
  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(range.startStr, range.endStr) &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();

  // 이전 기간 매출 (비교용)
  final prev = range.previous;
  final prevSales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(prev.startStr, prev.endStr) &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();

  final prevRevenue = prevSales.fold(0, (s, e) => s + e.totalAmount);

  if (sales.isEmpty) {
    return SalesSummary(
      totalRevenue: 0,
      totalCount: 0,
      avgSale: 0,
      totalTax: 0,
      totalDiscount: 0,
      refundAmount: 0,
      netRevenue: 0,
      pointEarned: 0,
      pointUsed: 0,
      newCustomerCount: 0,
      returningCustomerCount: 0,
      prevRevenue: prevRevenue,
      prevCount: prevSales.length,
      revenueByHour: {},
      revenueByDay: {},
      revenueByMethod: {},
      topMenus: [],
      staffRevenues: [],
      recentSales: [],
    );
  }

  final totalRevenue = sales.fold(0, (s, e) => s + e.totalAmount);
  final tax10 = sales.fold(0, (s, e) => s + e.taxAmount10);
  final tax8 = sales.fold(0, (s, e) => s + e.taxAmount8);
  final totalTax = tax10 + tax8;
  final taxable10 = sales.fold(0, (s, e) => s + e.taxableAmount10);
  final taxable8 = sales.fold(0, (s, e) => s + e.taxableAmount8);
  final totalDiscount = sales.fold(0, (s, e) => s + e.discountAmount);
  final pointEarned = sales.fold(0, (s, e) => s + e.pointEarned);
  final pointUsed = sales.fold(0, (s, e) => s + e.pointUsed);

  final saleIds = sales.map((s) => s.id).toList();

  // 환불 합계: 기간 내 created_at 기준으로 독립적으로 집계
  // (refunded 상태 판매도 포함하기 위해 saleIds 기반 아닌 날짜 기반)
  final allPeriodSales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(range.startStr, range.endStr)))
      .get();
  final allPeriodSaleIds = allPeriodSales.map((s) => s.id).toList();
  final refunds = allPeriodSaleIds.isEmpty
      ? <Refund>[]
      : await (db.select(db.refunds)
              ..where((t) => t.originalSaleId.isIn(allPeriodSaleIds) &
                  t.status.equals('completed')))
          .get();
  final refundAmount = refunds.fold(0, (s, e) => s + e.refundAmount);

  // 시간대별 매출 (created_at 기준)
  final revenueByHour = <int, int>{};
  for (final s in sales) {
    final h = DateTime.parse(s.createdAt).hour;
    revenueByHour[h] = (revenueByHour[h] ?? 0) + s.totalAmount;
  }

  // 날짜별 매출
  final revenueByDay = <String, int>{};
  for (final s in sales) {
    revenueByDay[s.saleDate] =
        (revenueByDay[s.saleDate] ?? 0) + s.totalAmount;
  }

  // 결제 수단별 매출
  final payments = saleIds.isEmpty
      ? <SalePayment>[]
      : await (db.select(db.salePayments)
              ..where((t) => t.saleId.isIn(saleIds)))
          .get();
  final revenueByMethod = <String, int>{};
  for (final p in payments) {
    revenueByMethod[p.method] =
        (revenueByMethod[p.method] ?? 0) + p.amount;
  }

  // 메뉴 집계
  final items = saleIds.isEmpty
      ? <SaleItem>[]
      : await (db.select(db.saleItems)
              ..where((t) =>
                  t.saleId.isIn(saleIds) & t.itemType.equals('menu')))
          .get();

  final menuMap = <String, (int, int)>{};
  for (final item in items) {
    final prev2 = menuMap[item.itemName] ?? (0, 0);
    menuMap[item.itemName] =
        (prev2.$1 + item.quantity, prev2.$2 + item.totalPrice);
  }
  final topMenus = menuMap.entries
      .map((e) =>
          TopMenuItem(name: e.key, count: e.value.$1, revenue: e.value.$2))
      .toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  // 스태프별 매출
  final staffRevMap = <String, (int, int)>{};
  for (final s in sales) {
    final prev2 = staffRevMap[s.staffId] ?? (0, 0);
    staffRevMap[s.staffId] = (prev2.$1 + s.totalAmount, prev2.$2 + 1);
  }
  final staffList = await (db.select(db.staff)
        ..where((t) => t.id.isIn(staffRevMap.keys.toList())))
      .get();
  final staffNames = {for (final s in staffList) s.id: s.name};
  final staffRevenues = staffRevMap.entries
      .map((e) => StaffRevenue(
            staffId: e.key,
            staffName: staffNames[e.key] ?? e.key,
            revenue: e.value.$1,
            count: e.value.$2,
          ))
      .toList()
    ..sort((a, b) => b.revenue.compareTo(a.revenue));

  // 신규 vs 재방문 고객
  final customerIds =
      sales.where((s) => s.customerId != null).map((s) => s.customerId!).toSet();
  int newCustomerCount = 0;
  int returningCustomerCount = 0;
  if (customerIds.isNotEmpty) {
    final customers = await (db.select(db.customers)
          ..where((t) => t.id.isIn(customerIds.toList())))
        .get();
    for (final c in customers) {
      final firstVisitInRange = c.firstVisitDate != null &&
          c.firstVisitDate!.compareTo(range.startStr) >= 0;
      if (firstVisitInRange) {
        newCustomerCount++;
      } else {
        returningCustomerCount++;
      }
    }
  }

  // 휴면 고객 수 (90일 이상 미방문)
  final dormantThreshold = DateTime.now()
      .subtract(const Duration(days: 90))
      .toIso8601String()
      .substring(0, 10);
  final dormantCustomerCount = await (db.select(db.customers)
        ..where((t) =>
            t.isDeleted.equals(false) &
            (t.lastVisitDate.isSmallerOrEqualValue(dormantThreshold) |
                t.lastVisitDate.isNull())))
      .get()
      .then((list) => list.length);

  // 최근 거래 20건
  final recentSalesRaw = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(range.startStr, range.endStr) &
            t.status.isIn(['completed', 'partial_refund', 'voided']))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(20))
      .get();

  final recentStaffIds =
      recentSalesRaw.map((s) => s.staffId).toSet().toList();
  final recentStaffList = recentStaffIds.isEmpty
      ? <StaffData>[]
      : await (db.select(db.staff)
              ..where((t) => t.id.isIn(recentStaffIds)))
          .get();
  final recentStaffMap = {for (final s in recentStaffList) s.id: s.name};

  final recentCustomerIds = recentSalesRaw
      .where((s) => s.customerId != null)
      .map((s) => s.customerId!)
      .toSet()
      .toList();
  final recentCustomerList = recentCustomerIds.isEmpty
      ? <Customer>[]
      : await (db.select(db.customers)
              ..where((t) => t.id.isIn(recentCustomerIds)))
          .get();
  final recentCustomerMap = {for (final c in recentCustomerList) c.id: c.name};

  // 결제수단 맵 (최근 거래용)
  final recentSaleIds = recentSalesRaw.map((s) => s.id).toList();
  final recentPayments = recentSaleIds.isEmpty
      ? <SalePayment>[]
      : await (db.select(db.salePayments)
              ..where((t) => t.saleId.isIn(recentSaleIds)))
          .get();
  final primaryMethodMap = <String, String>{};
  for (final p in recentPayments) {
    primaryMethodMap.putIfAbsent(p.saleId, () => p.method);
  }

  final recentSales = recentSalesRaw.map((s) {
    return RecentSale(
      id: s.id,
      saleNo: s.saleNo,
      staffName: recentStaffMap[s.staffId] ?? '-',
      customerName: s.customerId != null
          ? (recentCustomerMap[s.customerId!] ?? 'お客様')
          : 'お客様',
      amount: s.totalAmount,
      status: s.status,
      createdAt: DateTime.parse(s.createdAt),
      primaryMethod: primaryMethodMap[s.id] ?? 'cash',
    );
  }).toList();

  return SalesSummary(
    totalRevenue: totalRevenue,
    totalCount: sales.length,
    avgSale: sales.isEmpty ? 0 : totalRevenue ~/ sales.length,
    totalTax: totalTax,
    taxAmount10: tax10,
    taxAmount8: tax8,
    taxableAmount10: taxable10,
    taxableAmount8: taxable8,
    totalDiscount: totalDiscount,
    refundAmount: refundAmount,
    netRevenue: totalRevenue - refundAmount,
    pointEarned: pointEarned,
    pointUsed: pointUsed,
    newCustomerCount: newCustomerCount,
    returningCustomerCount: returningCustomerCount,
    dormantCustomerCount: dormantCustomerCount,
    prevRevenue: prevRevenue,
    prevCount: prevSales.length,
    revenueByHour: revenueByHour,
    revenueByDay: revenueByDay,
    revenueByMethod: revenueByMethod,
    topMenus: topMenus.take(10).toList(),
    staffRevenues: staffRevenues,
    recentSales: recentSales,
  );
});

// ─── 월간 추이 Provider (최근 6개월) ─────────────────────────────────────
class MonthlyTrend {
  final String yearMonth; // YYYY-MM
  final int revenue;
  final int count;

  const MonthlyTrend({
    required this.yearMonth,
    required this.revenue,
    required this.count,
  });
}

final monthlyTrendProvider =
    FutureProvider<List<MonthlyTrend>>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();

  final months = List.generate(6, (i) {
    final m = DateTime(now.year, now.month - i, 1);
    return '${m.year}-${m.month.toString().padLeft(2, '0')}';
  }).reversed.toList();

  final result = <MonthlyTrend>[];
  for (final ym in months) {
    final startStr = '$ym-01';
    final endStr =
        '$ym-${_daysInMonth(int.parse(ym.substring(0, 4)), int.parse(ym.substring(5, 7))).toString().padLeft(2, '0')}';

    final sales = await (db.select(db.sales)
          ..where((t) =>
              t.saleDate.isBetweenValues(startStr, endStr) &
              t.status.isIn(['completed', 'partial_refund'])))
        .get();

    result.add(MonthlyTrend(
      yearMonth: ym,
      revenue: sales.fold(0, (s, e) => s + e.totalAmount),
      count: sales.length,
    ));
  }
  return result;
});

int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

// ─── 오늘 매출 요약 Provider (앱바 실시간 표시용) ──────────────────────────
class TodayRevenueSummary {
  final int revenue;
  final int count;
  final int netRevenue;

  const TodayRevenueSummary({
    required this.revenue,
    required this.count,
    required this.netRevenue,
  });
}

final todayRevenueProvider = FutureProvider<TodayRevenueSummary>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final todayStr =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.equals(todayStr) &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();

  final revenue = sales.fold(0, (s, e) => s + e.totalAmount);
  final count = sales.length;

  // 환불 금액 (status 무관 기간 내 모든 판매 기준)
  final allTodaySales = await (db.select(db.sales)
        ..where((t) => t.saleDate.equals(todayStr)))
      .get();
  final allIds = allTodaySales.map((s) => s.id).toList();
  final refunds = allIds.isEmpty
      ? <dynamic>[]
      : await (db.select(db.refunds)
                ..where((t) =>
                    t.originalSaleId.isIn(allIds) &
                    t.status.equals('completed')))
            .get();
  final refundAmount = refunds.fold(0, (s, e) => s + (e.refundAmount as int));

  return TodayRevenueSummary(
    revenue: revenue,
    count: count,
    netRevenue: revenue - refundAmount,
  );
});

// ─── KPI 목표 달성률 Provider ──────────────────────────────────────────────
class KpiProgress {
  final String targetType;
  final String label;
  final int targetValue;
  final int actualValue;
  final String unit;

  const KpiProgress({
    required this.targetType,
    required this.label,
    required this.targetValue,
    required this.actualValue,
    required this.unit,
  });

  double get progress =>
      targetValue == 0 ? 0 : (actualValue / targetValue).clamp(0.0, 1.5);
  bool get achieved => actualValue >= targetValue;
  int get percentage =>
      targetValue == 0 ? 0 : (actualValue / targetValue * 100).round();
}

final kpiProgressProvider =
    FutureProvider.family<List<KpiProgress>, ReportRange>(
        (ref, range) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final yearMonth =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';

  // 이 월의 KPI 목표 조회 (매장 전체)
  final targets = await (db.select(db.kpiTargets)
        ..where((t) =>
            t.yearMonth.equals(yearMonth) & t.staffId.isNull()))
      .get();

  if (targets.isEmpty) return [];

  // 실적 계산 (현재 range 기준)
  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(range.startStr, range.endStr) &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();

  final actualRevenue = sales.fold(0, (s, e) => s + e.totalAmount);
  final actualCount = sales.length;

  // 신규 고객수
  final customerIds =
      sales.map((s) => s.customerId).where((id) => id != null).toSet();
  int newCustomers = 0;
  for (final cid in customerIds) {
    final prevSales = await (db.select(db.sales)
          ..where((t) =>
              t.customerId.equals(cid!) &
              t.saleDate.isSmallerThanValue(range.startStr)))
        .get();
    if (prevSales.isEmpty) newCustomers++;
  }

  final labelMap = {
    'sales': '売上目標',
    'customer_count': '客数目標',
    'new_customer': '新規目標',
    'avg_unit': '客単価目標',
  };
  final unitMap = {
    'sales': '円',
    'customer_count': '件',
    'new_customer': '人',
    'avg_unit': '円',
  };

  return targets.map((t) {
    int actual;
    switch (t.targetType) {
      case 'sales':
        actual = actualRevenue;
        break;
      case 'customer_count':
        actual = actualCount;
        break;
      case 'new_customer':
        actual = newCustomers;
        break;
      case 'avg_unit':
        actual = sales.isEmpty ? 0 : actualRevenue ~/ sales.length;
        break;
      default:
        actual = 0;
    }

    return KpiProgress(
      targetType: t.targetType,
      label: labelMap[t.targetType] ?? t.targetType,
      targetValue: t.targetValue,
      actualValue: actual,
      unit: unitMap[t.targetType] ?? '',
    );
  }).toList();
});

// ─── 결제 수단별 집계 ─────────────────────────────────────────────────────
class PaymentMethodSummary {
  final String method;
  final int amount;
  final int count;
  const PaymentMethodSummary({
    required this.method,
    required this.amount,
    required this.count,
  });
}

final paymentMethodProvider =
    FutureProvider.family<List<PaymentMethodSummary>, ReportRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(range.startStr, range.endStr) &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();
  if (sales.isEmpty) return [];
  final saleIds = sales.map((s) => s.id).toList();
  final payments = await (db.select(db.salePayments)
        ..where((t) => t.saleId.isIn(saleIds)))
      .get();
  final methodMap = <String, (int, int)>{};
  for (final p in payments) {
    final m = p.method;
    final prev = methodMap[m] ?? (0, 0);
    methodMap[m] = (prev.$1 + p.amount, prev.$2 + 1);
  }
  final list = methodMap.entries
      .map((e) => PaymentMethodSummary(
            method: e.key,
            amount: e.value.$1,
            count: e.value.$2,
          ))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return list;
});

// ─── 고객 세그먼트 분석 ────────────────────────────────────────────────────
class CustomerSegment {
  final int newCount;      // 해당 기간 첫 방문
  final int returningCount; // 기존 고객
  final int vipCount;      // VIP 고객
  final int totalCount;

  const CustomerSegment({
    required this.newCount,
    required this.returningCount,
    required this.vipCount,
    required this.totalCount,
  });

  double get newRatio => totalCount == 0 ? 0 : newCount / totalCount;
  double get returningRatio => totalCount == 0 ? 0 : returningCount / totalCount;
  double get vipRatio => totalCount == 0 ? 0 : vipCount / totalCount;
}

final customerSegmentProvider =
    FutureProvider.family<CustomerSegment, ReportRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.saleDate.isBetweenValues(range.startStr, range.endStr) &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();

  final customerIds = sales
      .map((s) => s.customerId)
      .where((id) => id != null)
      .toSet()
      .cast<String>();

  int newCount = 0;
  int vipCount = 0;

  for (final cid in customerIds) {
    // 신규 여부
    final prevSales = await (db.select(db.sales)
          ..where((t) =>
              t.customerId.equals(cid) &
              t.saleDate.isSmallerThanValue(range.startStr) &
              t.status.isIn(['completed', 'partial_refund'])))
        .get();
    if (prevSales.isEmpty) newCount++;

    // VIP 여부
    final customer = await (db.select(db.customers)
          ..where((t) => t.id.equals(cid)))
        .getSingleOrNull();
    if (customer?.isVip == true) vipCount++;
  }

  final total = customerIds.length;
  return CustomerSegment(
    newCount: newCount,
    returningCount: total - newCount,
    vipCount: vipCount,
    totalCount: total,
  );
});
