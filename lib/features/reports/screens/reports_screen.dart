import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/top_banner.dart';
import '../providers/reports_provider.dart';
// ignore: unused_import
import 'dart:math' show min;

// ─── 결제 수단 라벨/아이콘 ────────────────────────────────────────────────
const _methodLabels = {
  'cash': '現金',
  'credit': 'クレジット',
  'ic_card': 'IC・電子マネー',
  'qr': 'QRコード',
  'gift_card': 'ギフトカード',
  'bank_transfer': '銀行振込',
  'points': 'ポイント',
};

const _methodColors = [
  Color(0xFF0064FF),
  Color(0xFF00B746),
  Color(0xFFFF6B35),
  Color(0xFF9B5CDB),
  Color(0xFFFF4E8C),
  Color(0xFF00BFAE),
  Color(0xFFFFB300),
];

// ─── 메인 화면 ────────────────────────────────────────────────────────────
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    (label: '今日', range: _RangeType.today),
    (label: '今週', range: _RangeType.week),
    (label: '今月', range: _RangeType.month),
    (label: '先月', range: _RangeType.lastMonth),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) {
          final t = _tabs[_tabController.index];
          ref.read(reportRangeProvider.notifier).state = switch (t.range) {
            _RangeType.today => ReportRange.forToday(),
            _RangeType.week => ReportRange.forWeek(),
            _RangeType.month => ReportRange.forMonth(),
            _RangeType.lastMonth => ReportRange.forLastMonth(),
          };
        }
      });
    // 초기 탭 = 今月
    _tabController.index = 2;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(reportRangeProvider);
    final summaryAsync = ref.watch(salesSummaryProvider(range));
    final trendAsync = ref.watch(monthlyTrendProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 헤더 (탭 + 기간 + CSV) ────────────────────────────────────
          _DashboardHeader(
            tabController: _tabController,
            tabs: _tabs,
            range: range,
          ),
          // ── 본문 ───────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(salesSummaryProvider(range));
                ref.invalidate(monthlyTrendProvider);
                ref.invalidate(todayRevenueProvider);
                await ref.read(salesSummaryProvider(range).future);
              },
              color: AppColors.primary,
              child: summaryAsync.when(
                data: (summary) => _DashboardBody(
                  summary: summary,
                  trendAsync: trendAsync,
                  range: range,
                ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, st) => ListView(
                  children: [
                    SizedBox(
                      height: 300,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: AppColors.error),
                            const SizedBox(height: 12),
                            Text('$e',
                                style: AppTextStyles.body2.copyWith(
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RangeType { today, week, month, lastMonth }

// ─── 헤더 ─────────────────────────────────────────────────────────────────
class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({
    required this.tabController,
    required this.tabs,
    required this.range,
  });

  final TabController tabController;
  final List<({String label, _RangeType range})> tabs;
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // 상단 제목 + 기간 텍스트 + CSV
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
            child: Row(
              children: [
                Text('売上ダッシュボード',
                    style: AppTextStyles.h3
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${range.startStr} 〜 ${range.endStr}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const Spacer(),
                // 거래 내역 버튼
                TextButton.icon(
                  onPressed: () => context.push(AppRoutes.transactions),
                  icon: const Icon(Icons.receipt_long_outlined, size: 15),
                  label: const Text('取引一覧'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    textStyle: AppTextStyles.caption
                        .copyWith(fontWeight: FontWeight.w600),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                  ),
                ),
                const SizedBox(width: 4),
                _SummaryTextCopyButton(range: range),
                const SizedBox(width: 4),
                _CsvExportButton(range: range),
              ],
            ),
          ),
          // 탭바
          TabBar(
            controller: tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle:
                AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
            unselectedLabelStyle: AppTextStyles.body2,
            indicatorColor: AppColors.primary,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.label,
            isScrollable: false,
            tabs: tabs.map((t) => Tab(text: t.label)).toList(),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

// ─── 본문 2컬럼 레이아웃 ──────────────────────────────────────────────────
class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.summary,
    required this.trendAsync,
    required this.range,
  });

  final SalesSummary summary;
  final AsyncValue<List<MonthlyTrend>> trendAsync;
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 데이터가 없을 때 빈 상태 화면
    if (summary.totalCount == 0 && summary.prevRevenue == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined, size: 64, color: AppColors.border),
            const SizedBox(height: 16),
            Text('この期間の売上データがありません',
                style: AppTextStyles.body1
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Text(
              '${range.startStr} 〜 ${range.endStr}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textDisabled),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 왼쪽 패널 (고정 360px) ─────────────────────────────────────
        SizedBox(
          width: 360,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _KpiGrid(summary: summary),
              const SizedBox(height: 14),
              _TaxSummaryCard(summary: summary),
              const SizedBox(height: 14),
              _KpiTargetCard(range: range),
              const SizedBox(height: 14),
              _MomComparisonCard(summary: summary),
              const SizedBox(height: 14),
              _PaymentMethodCard(summary: summary),
              const SizedBox(height: 14),
              _CustomerInsightCard(summary: summary),
              const SizedBox(height: 14),
              _PointSummaryCard(summary: summary),
              const SizedBox(height: 14),
              _BreakdownCard(summary: summary),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.border),
        // ── 오른쪽 패널 (확장) ──────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 시간대별 매출 (오늘 탭에서만)
              if (range.period == ReportPeriod.today &&
                  summary.revenueByHour.isNotEmpty) ...[
                _SectionCard(
                  title: '時間帯別売上',
                  icon: Icons.access_time_outlined,
                  child: _HourlyBarChart(data: summary.revenueByHour),
                ),
                const SizedBox(height: 14),
              ],
              // 날짜별 추이 (오늘 이외)
              if (range.period != ReportPeriod.today &&
                  summary.revenueByDay.isNotEmpty) ...[
                _SectionCard(
                  title: '日別売上推移',
                  icon: Icons.bar_chart_outlined,
                  child: _DailyBarChart(data: summary.revenueByDay, range: range),
                ),
                const SizedBox(height: 14),
              ],
              // 월간 추이 라인 차트
              trendAsync.when(
                data: (trend) => trend.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          _SectionCard(
                            title: '月別売上推移（過去6ヶ月）',
                            icon: Icons.show_chart_outlined,
                            child: _MonthlyLineChart(trends: trend),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // 고객 세그먼트 분석
              ref.watch(customerSegmentProvider(range)).when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (seg) => seg.totalCount == 0
                    ? const SizedBox.shrink()
                    : Column(
                        children: [
                          _SectionCard(
                            title: '顧客セグメント',
                            icon: Icons.people_outline,
                            child: _CustomerSegmentCard(segment: seg),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
              ),
              // 스태프별 매출
              if (summary.staffRevenues.isNotEmpty) ...[
                _SectionCard(
                  title: 'スタッフ別売上',
                  icon: Icons.person_outline,
                  child: _StaffRevenueList(
                    staffRevenues: summary.staffRevenues,
                    total: summary.totalRevenue,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              // 결제 수단별
              if (summary.revenueByMethod.isNotEmpty) ...[
                _SectionCard(
                  title: '支払方法別',
                  icon: Icons.payment_outlined,
                  child: _PaymentMethodCard(summary: summary),
                ),
                const SizedBox(height: 14),
              ],
              // 인기 메뉴 TOP10
              if (summary.topMenus.isNotEmpty) ...[
                _SectionCard(
                  title: 'メニュー別売上 TOP10',
                  icon: Icons.format_list_numbered_outlined,
                  child: _TopMenuList(menus: summary.topMenus),
                ),
                const SizedBox(height: 14),
              ],
              // 최근 거래 내역
              if (summary.recentSales.isNotEmpty) ...[
                _SectionCard(
                  title: '最近の取引',
                  icon: Icons.receipt_long_outlined,
                  child: _RecentSalesList(sales: summary.recentSales),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── KPI 그리드 (2x3) ────────────────────────────────────────────────────
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final growthRevenue = summary.revenueGrowth;
    final growthCount = summary.countGrowth;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: '売上合計',
                value: '¥${_fmtNum(summary.totalRevenue)}',
                growth: growthRevenue,
                color: AppColors.primary,
                icon: Icons.attach_money,
                large: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: '純売上（返金控除）',
                value: '¥${_fmtNum(summary.netRevenue)}',
                color: const Color(0xFF00B746),
                icon: Icons.account_balance_wallet_outlined,
                large: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: '件数',
                value: '${summary.totalCount}件',
                growth: growthCount,
                color: const Color(0xFF9B5CDB),
                icon: Icons.receipt_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: '客単価',
                value: '¥${_fmtNum(summary.avgSale)}',
                color: const Color(0xFFFF6B35),
                icon: Icons.person_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: '返金合計',
                value: summary.refundAmount > 0
                    ? '- ¥${_fmtNum(summary.refundAmount)}'
                    : '¥0',
                color: AppColors.error,
                icon: Icons.undo_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: '値引き合計',
                value: summary.totalDiscount > 0
                    ? '- ¥${_fmtNum(summary.totalDiscount)}'
                    : '¥0',
                color: AppColors.warning,
                icon: Icons.local_offer_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.growth,
    this.large = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final double? growth;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final isUp = (growth ?? 0) >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: (large ? AppTextStyles.h3 : AppTextStyles.h4).copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (growth != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  isUp ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 11,
                  color: isUp ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 2),
                Text(
                  '${growth!.abs().toStringAsFixed(1)}% 前比',
                  style: AppTextStyles.caption.copyWith(
                    color: isUp ? AppColors.success : AppColors.error,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 결제 수단 도넛 차트 ──────────────────────────────────────────────────
class _PaymentMethodCard extends StatefulWidget {
  const _PaymentMethodCard({required this.summary});
  final SalesSummary summary;

  @override
  State<_PaymentMethodCard> createState() => _PaymentMethodCardState();
}

class _PaymentMethodCardState extends State<_PaymentMethodCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final data = widget.summary.revenueByMethod;
    if (data.isEmpty) return const SizedBox.shrink();

    final total = data.values.fold(0, (a, b) => a + b);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _SectionCard(
      title: '支払い方法',
      icon: Icons.credit_card_outlined,
      child: Row(
        children: [
          // 도넛 차트
          SizedBox(
            width: 110,
            height: 110,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 32,
                pieTouchData: PieTouchData(
                  touchCallback: (event, resp) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          resp == null ||
                          resp.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex =
                          resp.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sections: entries.asMap().entries.map((e) {
                  final i = e.key;
                  final entry = e.value;
                  final color = _methodColors[i % _methodColors.length];
                  final isTouched = i == _touchedIndex;
                  final pct = total > 0 ? entry.value / total * 100 : 0.0;
                  return PieChartSectionData(
                    value: entry.value.toDouble(),
                    color: color,
                    radius: isTouched ? 22 : 18,
                    title: isTouched ? '${pct.toStringAsFixed(1)}%' : '',
                    titleStyle: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 범례
          Expanded(
            child: Column(
              children: entries.asMap().entries.map((e) {
                final i = e.key;
                final entry = e.value;
                final color = _methodColors[i % _methodColors.length];
                final pct = total > 0
                    ? (entry.value / total * 100).toStringAsFixed(1)
                    : '0.0';
                final label =
                    _methodLabels[entry.key] ?? entry.key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          label,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: AppTextStyles.caption
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 고객 인사이트 카드 ───────────────────────────────────────────────────
class _CustomerInsightCard extends StatelessWidget {
  const _CustomerInsightCard({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final total =
        summary.newCustomerCount + summary.returningCustomerCount;
    if (total == 0) return const SizedBox.shrink();

    final newPct = total > 0 ? summary.newCustomerCount / total : 0.0;

    return _SectionCard(
      title: '顧客インサイト',
      icon: Icons.people_outline,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _InsightChip(
                  label: '新規',
                  count: summary.newCustomerCount,
                  total: total,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsightChip(
                  label: 'リピーター',
                  count: summary.returningCustomerCount,
                  total: total,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 비율 바
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: newPct,
              minHeight: 8,
              backgroundColor: AppColors.success.withAlpha(50),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '新規 ${(newPct * 100).toStringAsFixed(1)}%',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary, fontSize: 10),
              ),
              Text(
                'リピーター ${((1 - newPct) * 100).toStringAsFixed(1)}%',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.success, fontSize: 10),
              ),
            ],
          ),
          // 휴면 고객 표시
          if (summary.dormantCustomerCount > 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text(
                    '休眠顧客（90日以上）: ${summary.dormantCustomerCount}人',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.warning, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });
  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(color: color),
          ),
          const SizedBox(height: 4),
          Text(
            '$count人',
            style:
                AppTextStyles.h4.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// ─── 前月比較カード ───────────────────────────────────────────────────────
class _MomComparisonCard extends StatelessWidget {
  const _MomComparisonCard({required this.summary});
  final SalesSummary summary;

  String _fmt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasPrev = summary.prevRevenue > 0;
    final revDiff = summary.totalRevenue - summary.prevRevenue;
    final cntDiff = summary.totalCount - summary.prevCount;
    final revPct = summary.revenueGrowth;
    final cntPct = summary.countGrowth;
    final isRevUp = revDiff >= 0;
    final isCntUp = cntDiff >= 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.compare_arrows_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('前月比較',
                  style: AppTextStyles.label
                      .copyWith(color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasPrev) ...[
            Text('前月データがありません',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
          ] else ...[
            // 売上比較
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('売上',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        '¥${_fmt(summary.totalRevenue)}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isRevUp
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 13,
                            color: isRevUp
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '¥${_fmt(revDiff.abs())} (${revPct.abs().toStringAsFixed(1)}%)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isRevUp
                                    ? AppColors.success
                                    : AppColors.error),
                          ),
                        ],
                      ),
                      Text('前月: ¥${_fmt(summary.prevRevenue)}',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textDisabled)),
                    ],
                  ),
                ),
                Container(
                    width: 1, height: 64, color: AppColors.border),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('来店数',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        '${summary.totalCount}件',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            isCntUp
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 13,
                            color: isCntUp
                                ? AppColors.success
                                : AppColors.error,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${cntDiff.abs()}件 (${cntPct.abs().toStringAsFixed(1)}%)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isCntUp
                                    ? AppColors.success
                                    : AppColors.error),
                          ),
                        ],
                      ),
                      Text('前月: ${summary.prevCount}件',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textDisabled)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 進捗バー
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: summary.prevRevenue > 0
                    ? (summary.totalRevenue / summary.prevRevenue)
                        .clamp(0.0, 2.0) /
                        2.0
                    : 0,
                minHeight: 6,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isRevUp ? AppColors.success : AppColors.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 포인트 요약 ──────────────────────────────────────────────────────────
class _PointSummaryCard extends StatelessWidget {
  const _PointSummaryCard({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.pointEarned == 0 && summary.pointUsed == 0) {
      return const SizedBox.shrink();
    }
    return _SectionCard(
      title: 'ポイント',
      icon: Icons.stars_outlined,
      child: Row(
        children: [
          Expanded(
            child: _PointChip(
              label: '付与',
              value: summary.pointEarned,
              color: const Color(0xFFFFB300),
              icon: Icons.add_circle_outline,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PointChip(
              label: '利用',
              value: summary.pointUsed,
              color: const Color(0xFF9B5CDB),
              icon: Icons.remove_circle_outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _PointChip extends StatelessWidget {
  const _PointChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTextStyles.caption.copyWith(color: color)),
              Text('${_fmtNum(value)}pt',
                  style: AppTextStyles.h4
                      .copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 내역 테이블 ──────────────────────────────────────────────────────────
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '内訳',
      icon: Icons.table_chart_outlined,
      child: Column(
        children: [
          _BreakdownRow('税込売上合計', '¥${_fmtNum(summary.totalRevenue)}',
              bold: true, color: AppColors.primary),
          _BreakdownRow(
              'うち消費税(10%+8%)', '¥${_fmtNum(summary.totalTax)}'),
          _BreakdownRow(
              '値引き', '- ¥${_fmtNum(summary.totalDiscount)}',
              color: AppColors.error),
          _BreakdownRow(
              '返金', '- ¥${_fmtNum(summary.refundAmount)}',
              color: AppColors.error),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: AppColors.border),
          ),
          _BreakdownRow('純売上', '¥${_fmtNum(summary.netRevenue)}',
              bold: true),
          _BreakdownRow('取引件数', '${summary.totalCount}件'),
          _BreakdownRow('客単価', '¥${_fmtNum(summary.avgSale)}'),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow(this.label, this.value,
      {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTextStyles.body2
                  .copyWith(color: AppColors.textSecondary)),
          Text(
            value,
            style: AppTextStyles.body2.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 시간대별 바 차트 ─────────────────────────────────────────────────────
class _HourlyBarChart extends StatelessWidget {
  const _HourlyBarChart({required this.data});
  final Map<int, int> data;

  @override
  Widget build(BuildContext context) {
    final maxVal =
        data.values.isEmpty ? 1.0 : data.values.reduce((a, b) => a > b ? a : b).toDouble();
    // 데이터 범위 기반으로 표시 시간 동적 계산 (데이터 없으면 8~22 기본)
    final dataKeys = data.keys;
    final startH = dataKeys.isEmpty ? 8 : dataKeys.reduce((a, b) => a < b ? a : b).clamp(0, 8);
    final endH = dataKeys.isEmpty ? 22 : dataKeys.reduce((a, b) => a > b ? a : b).clamp(22, 23);

    return SizedBox(
      height: 160,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.2,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final h = v.toInt();
                  if (h < startH || h > endH) return const SizedBox.shrink();
                  // 너무 많으면 짝수만 표시
                  final range = endH - startH;
                  if (range > 12 && h % 2 != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '$h',
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 9,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
                reservedSize: 18,
              ),
            ),
          ),
          barGroups: List.generate(endH - startH + 1, (i) {
            final h = startH + i;
            final val = (data[h] ?? 0).toDouble();
            final isMax = val == maxVal && val > 0;
            return BarChartGroupData(
              x: h,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color:
                      isMax ? AppColors.primary : AppColors.primary.withAlpha(100),
                  width: 14,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            );
          }),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${group.x}時\n¥${_fmtNum(rod.toY.toInt())}',
                  AppTextStyles.caption.copyWith(
                      color: Colors.white, height: 1.5),
                );
              },
              getTooltipColor: (_) => AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 날짜별 바 차트 ───────────────────────────────────────────────────────
class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({required this.data, required this.range});
  final Map<String, int> data;
  final ReportRange range;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final sorted = data.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxVal = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 170,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.2,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, meta) {
                  if (v == 0) return const SizedBox.shrink();
                  return Text(
                    _fmtK(v.toInt()),
                    style: AppTextStyles.caption.copyWith(
                        fontSize: 9, color: AppColors.textSecondary),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  final day = sorted[i].key.substring(8); // DD
                  // 너무 많으면 일부만
                  if (sorted.length > 20 && i % 5 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      day,
                      style: AppTextStyles.caption.copyWith(
                          fontSize: 9, color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: sorted.asMap().entries.map((e) {
            final val = e.value.value.toDouble();
            final isMax = val == maxVal && val > 0;
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: val,
                  color:
                      isMax ? AppColors.primary : AppColors.primary.withAlpha(110),
                  width: sorted.length > 20 ? 8 : 14,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                ),
              ],
            );
          }).toList(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final entry = sorted[group.x];
                return BarTooltipItem(
                  '${entry.key.substring(5)}\n¥${_fmtNum(rod.toY.toInt())}',
                  AppTextStyles.caption.copyWith(
                      color: Colors.white, height: 1.5),
                );
              },
              getTooltipColor: (_) => AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 월간 추이 라인 차트 ──────────────────────────────────────────────────
class _MonthlyLineChart extends StatelessWidget {
  const _MonthlyLineChart({required this.trends});
  final List<MonthlyTrend> trends;

  @override
  Widget build(BuildContext context) {
    if (trends.isEmpty) return const SizedBox.shrink();
    final maxVal = trends.map((e) => e.revenue).reduce((a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxVal * 1.3,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.border,
              strokeWidth: 1,
              dashArray: [4, 4],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, meta) {
                  if (v == 0) return const SizedBox.shrink();
                  return Text(
                    _fmtK(v.toInt()),
                    style: AppTextStyles.caption.copyWith(
                        fontSize: 9, color: AppColors.textSecondary),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= trends.length) {
                    return const SizedBox.shrink();
                  }
                  // "MM月" 표시
                  final month = trends[i].yearMonth.substring(5);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${int.parse(month)}月',
                      style: AppTextStyles.caption.copyWith(
                          fontSize: 10, color: AppColors.textSecondary),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: trends.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value.revenue.toDouble());
              }).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: AppColors.primary,
              barWidth: 2.5,
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primary.withAlpha(30),
              ),
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) =>
                    FlDotCirclePainter(
                  radius: 4,
                  color: AppColors.primary,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final i = s.x.toInt();
                return LineTooltipItem(
                  '${trends[i].yearMonth}\n¥${_fmtNum(s.y.toInt())}',
                  AppTextStyles.caption.copyWith(
                      color: Colors.white, height: 1.5),
                );
              }).toList(),
              getTooltipColor: (_) => AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 스태프별 매출 ────────────────────────────────────────────────────────
class _StaffRevenueList extends StatelessWidget {
  const _StaffRevenueList(
      {required this.staffRevenues, required this.total});
  final List<StaffRevenue> staffRevenues;
  final int total;

  static const _staffColors = AppColors.staffColors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: staffRevenues.asMap().entries.map((e) {
        final i = e.key;
        final s = e.value;
        final pct = total > 0 ? (s.revenue / total * 100) : 0.0;
        final color = _staffColors[i % _staffColors.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // 순위
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}',
                  style: AppTextStyles.body2.copyWith(
                    color: i == 0 ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: i == 0 ? FontWeight.w700 : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withAlpha(30),
                child: Text(
                  s.staffName.isNotEmpty
                      ? String.fromCharCode(s.staffName.runes.first)
                      : '?',
                  style: AppTextStyles.label.copyWith(color: color),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(s.staffName,
                              style: AppTextStyles.body2.copyWith(
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '¥${_fmtNum(s.revenue)}  (${pct.toStringAsFixed(1)}%)',
                          style: AppTextStyles.body2
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total > 0 ? s.revenue / total : 0,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text('${s.count}件',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── 인기 메뉴 TOP10 ──────────────────────────────────────────────────────
class _TopMenuList extends StatelessWidget {
  const _TopMenuList({required this.menus});
  final List<TopMenuItem> menus;

  @override
  Widget build(BuildContext context) {
    final maxRev = menus.isEmpty ? 1 : menus.first.revenue;
    final totalRev = menus.fold<int>(0, (sum, m) => sum + m.revenue);
    return Column(
      children: menus.asMap().entries.map((e) {
        final i = e.key;
        final m = e.value;
        final ratio = maxRev > 0 ? m.revenue / maxRev : 0.0;
        final pct = totalRev > 0 ? (m.revenue / totalRev * 100).round() : 0;
        final isTop3 = i < 3;
        final medal = ['🥇', '🥈', '🥉'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: isTop3
                    ? Text(medal[i],
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center)
                    : Text(
                        '${i + 1}',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(m.name,
                              style: AppTextStyles.body2.copyWith(
                                  fontWeight: isTop3
                                      ? FontWeight.w600
                                      : FontWeight.normal),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '¥${_fmtNum(m.revenue)}',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        backgroundColor: AppColors.border,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isTop3
                              ? AppColors.primary
                              : AppColors.primary.withAlpha(140),
                        ),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text('${m.count}回',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary)),
                        const Spacer(),
                        Text('$pct%',
                            style: AppTextStyles.caption.copyWith(
                                color: isTop3
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                fontWeight: isTop3
                                    ? FontWeight.w600
                                    : FontWeight.normal)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── 최근 거래 내역 ───────────────────────────────────────────────────────
class _RecentSalesList extends StatelessWidget {
  const _RecentSalesList({required this.sales});
  final List<RecentSale> sales;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: sales.map((s) => _RecentSaleTile(sale: s)).toList(),
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  const _RecentSaleTile({required this.sale});
  final RecentSale sale;

  static const _statusColors = {
    'completed': AppColors.success,
    'partial_refund': AppColors.warning,
    'voided': AppColors.error,
  };
  static const _statusLabels = {
    'completed': '完了',
    'partial_refund': '一部返金',
    'voided': '無効',
  };
  static const _methodIcons = {
    'cash': Icons.money,
    'credit': Icons.credit_card,
    'ic_card': Icons.contactless,
    'qr': Icons.qr_code,
    'gift_card': Icons.card_giftcard,
    'bank_transfer': Icons.account_balance,
  };

  @override
  Widget build(BuildContext context) {
    final color =
        _statusColors[sale.status] ?? AppColors.textSecondary;
    final statusLabel =
        _statusLabels[sale.status] ?? sale.status;
    final methodIcon =
        _methodIcons[sale.primaryMethod] ?? Icons.payment;
    final timeStr =
        DateFormat('HH:mm').format(sale.createdAt);

    return InkWell(
      onTap: () => context.push(AppRoutes.transactions),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // 결제 수단 아이콘
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(methodIcon, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          // 고객 + 스태프
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.customerName,
                  style: AppTextStyles.body2
                      .copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${sale.staffName} · ${sale.saleNo}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 금액 + 상태 + 시간
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '¥${_fmtNum(sale.amount)}',
                style: AppTextStyles.body2
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTextStyles.caption.copyWith(
                          color: color, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    timeStr,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ─── 섹션 카드 ────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.h4
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─── CSV 내보내기 버튼 ────────────────────────────────────────────────────
class _CsvExportButton extends ConsumerStatefulWidget {
  const _CsvExportButton({required this.range});
  final ReportRange range;

  @override
  ConsumerState<_CsvExportButton> createState() => _CsvExportButtonState();
}

class _CsvExportButtonState extends ConsumerState<_CsvExportButton> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final summary =
          ref.read(salesSummaryProvider(widget.range)).valueOrNull;
      if (summary == null) {
        if (mounted) {
          showTopBanner(context, 'データ読み込み中です。しばらくお待ちください。',
              color: AppColors.primary, icon: Icons.hourglass_top_rounded);
        }
        return;
      }

      final csv = _buildCsv(summary, widget.range);
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now();
      final fname =
          'salon_report_${widget.range.startStr}_${widget.range.endStr}_'
          '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$fname');
      await file.writeAsString('﻿$csv'); // BOM 추가 (Excel 호환)

      if (mounted) {
        showTopBanner(
          context,
          '$fname を書類フォルダに保存しました',
          color: AppColors.success,
          icon: Icons.check_circle_outline,
          actionLabel: '開く',
          onAction: () => Process.run('open', [file.path]),
        );
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エクスポートエラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _buildCsv(SalesSummary s, ReportRange range) {
    final buf = StringBuffer();

    buf.writeln('# サマリー');
    buf.writeln('期間,${range.startStr} 〜 ${range.endStr}');
    buf.writeln('売上合計,${s.totalRevenue}');
    buf.writeln('純売上,${s.netRevenue}');
    buf.writeln('件数,${s.totalCount}');
    buf.writeln('客単価,${s.avgSale}');
    buf.writeln('消費税,${s.totalTax}');
    buf.writeln('値引き合計,${s.totalDiscount}');
    buf.writeln('返金合計,${s.refundAmount}');
    buf.writeln('ポイント付与,${s.pointEarned}');
    buf.writeln('ポイント利用,${s.pointUsed}');
    buf.writeln();

    if (s.revenueByMethod.isNotEmpty) {
      buf.writeln('# 支払い方法別');
      buf.writeln('方法,金額');
      for (final e in s.revenueByMethod.entries) {
        buf.writeln('${_methodLabels[e.key] ?? e.key},${e.value}');
      }
      buf.writeln();
    }

    if (s.revenueByDay.isNotEmpty) {
      buf.writeln('# 日別売上');
      buf.writeln('日付,売上');
      final sorted = s.revenueByDay.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      for (final e in sorted) buf.writeln('${e.key},${e.value}');
      buf.writeln();
    }

    if (s.topMenus.isNotEmpty) {
      buf.writeln('# メニュー別売上');
      buf.writeln('メニュー名,件数,売上');
      for (final m in s.topMenus) {
        buf.writeln('"${m.name}",${m.count},${m.revenue}');
      }
      buf.writeln();
    }

    if (s.staffRevenues.isNotEmpty) {
      buf.writeln('# スタッフ別売上');
      buf.writeln('スタッフ名,件数,売上');
      for (final st in s.staffRevenues) {
        buf.writeln('"${st.staffName}",${st.count},${st.revenue}');
      }
    }

    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return _exporting
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : TextButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.download_outlined, size: 16),
            label: const Text('CSV'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              textStyle: AppTextStyles.body2,
            ),
          );
  }
}

// ─── 유틸 ─────────────────────────────────────────────────────────────────
String _fmtNum(int n) {
  if (n >= 1000000) {
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
  if (n >= 1000) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
  return n.toString();
}

String _fmtK(int n) {
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(0)}万';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
  return n.toString();
}

// ─── 세금 집계 카드 (적격청구서 대응) ──────────────────────────────────────
class _TaxSummaryCard extends StatelessWidget {
  const _TaxSummaryCard({required this.summary});
  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasData = summary.totalTax > 0 ||
        summary.taxableAmount10 > 0 ||
        summary.taxableAmount8 > 0;

    return _SectionCard(
      title: '消費税集計（インボイス対応）',
      icon: Icons.receipt_outlined,
      child: hasData
          ? Column(
              children: [
                _TaxRow(
                  label: '課税売上 (10%)',
                  taxable: summary.taxableAmount10,
                  tax: summary.taxAmount10,
                  color: const Color(0xFF0064FF),
                ),
                const SizedBox(height: 8),
                _TaxRow(
                  label: '軽減課税 (8%)',
                  taxable: summary.taxableAmount8,
                  tax: summary.taxAmount8,
                  color: const Color(0xFF00B746),
                ),
                const Divider(height: 16, color: AppColors.border),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('消費税合計',
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary)),
                          Text('¥${_fmtNum(summary.totalTax)}',
                              style: const TextStyle(
                                fontFamily: 'NotoSansJP',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              )),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('税込売上合計',
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary)),
                          Text('¥${_fmtNum(summary.totalRevenue)}',
                              style: const TextStyle(
                                fontFamily: 'NotoSansJP',
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('税データがありません',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary)),
            ),
    );
  }
}

class _TaxRow extends StatelessWidget {
  const _TaxRow({
    required this.label,
    required this.taxable,
    required this.tax,
    required this.color,
  });
  final String label;
  final int taxable;
  final int tax;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(8),
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.caption.copyWith(
                        color: color, fontWeight: FontWeight.w600)),
                Text('課税標準: ¥${_fmtNum(taxable)}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary, fontSize: 10)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('税額',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary, fontSize: 9)),
              Text('¥${_fmtNum(tax)}',
                  style: TextStyle(
                    fontFamily: 'NotoSansJP',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── KPI 목표 달성률 카드 ─────────────────────────────────────────────────
class _KpiTargetCard extends ConsumerWidget {
  const _KpiTargetCard({required this.range});
  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpiAsync = ref.watch(kpiProgressProvider(range));

    return _SectionCard(
      title: 'KPI目標達成率',
      icon: Icons.flag_outlined,
      child: kpiAsync.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) => const SizedBox.shrink(),
        data: (kpis) {
          if (kpis.isEmpty) {
            return Column(
              children: [
                Text('今月のKPI目標が設定されていません',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text('設定 → KPI目標 から入力できます',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.textDisabled, fontSize: 10)),
              ],
            );
          }
          return Column(
            children: kpis
                .map((k) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _KpiProgressRow(kpi: k),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}

class _KpiProgressRow extends StatelessWidget {
  const _KpiProgressRow({required this.kpi});
  final KpiProgress kpi;

  @override
  Widget build(BuildContext context) {
    final color = kpi.achieved
        ? AppColors.success
        : kpi.progress > 0.7
            ? AppColors.warning
            : AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(kpi.label,
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ),
            Text(
              '${kpi.percentage}%',
              style: TextStyle(
                fontFamily: 'NotoSansJP',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            if (kpi.achieved)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child:
                    Icon(Icons.check_circle, size: 14, color: AppColors.success),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: kpi.progress.clamp(0.0, 1.0),
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '実績: ${kpi.unit == '円' ? '¥${_fmtNum(kpi.actualValue)}' : '${kpi.actualValue}${kpi.unit}'}',
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary, fontSize: 10),
            ),
            Text(
              '目標: ${kpi.unit == '円' ? '¥${_fmtNum(kpi.targetValue)}' : '${kpi.targetValue}${kpi.unit}'}',
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.textDisabled, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── サマリーテキストコピーボタン ─────────────────────────────────────────────
class _SummaryTextCopyButton extends ConsumerStatefulWidget {
  const _SummaryTextCopyButton({required this.range});
  final ReportRange range;

  @override
  ConsumerState<_SummaryTextCopyButton> createState() =>
      _SummaryTextCopyButtonState();
}

class _SummaryTextCopyButtonState
    extends ConsumerState<_SummaryTextCopyButton> {
  bool _copying = false;

  Future<void> _copy() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final summary =
          await ref.read(salesSummaryProvider(widget.range).future);
      final now = DateTime.now();
      final buf = StringBuffer();
      buf.writeln('【売上レポート】${widget.range.period.name}');
      buf.writeln('売上合計: ¥${_fmtNum(summary.totalRevenue)}');
      buf.writeln('件数: ${summary.totalCount}件');
      buf.writeln('客単価: ¥${_fmtNum(summary.avgSale)}');
      buf.writeln('純売上: ¥${_fmtNum(summary.netRevenue)}');
      if (summary.refundAmount > 0) {
        buf.writeln('返金: -¥${_fmtNum(summary.refundAmount)}');
      }
      if (summary.totalDiscount > 0) {
        buf.writeln('値引き: -¥${_fmtNum(summary.totalDiscount)}');
      }
      buf.writeln(
          '作成: ${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}');
      await Clipboard.setData(ClipboardData(text: buf.toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('サマリーをコピーしました'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('コピーに失敗しました'),
              duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _copying
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.content_copy_outlined, size: 18),
      tooltip: 'サマリーをコピー',
      onPressed: _copying ? null : _copy,
    );
  }
}

// ─── 고객 세그먼트 카드 ────────────────────────────────────────────────────
class _CustomerSegmentCard extends StatelessWidget {
  const _CustomerSegmentCard({required this.segment});
  final CustomerSegment segment;

  @override
  Widget build(BuildContext context) {
    final total = segment.totalCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // 세그먼트 바
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 20,
            child: Row(
              children: [
                if (segment.newCount > 0)
                  Flexible(
                    flex: segment.newCount,
                    child: Container(color: const Color(0xFF3B82F6)),
                  ),
                if (segment.returningCount > 0)
                  Flexible(
                    flex: segment.returningCount,
                    child: Container(color: const Color(0xFF10B981)),
                  ),
                if (segment.vipCount > 0)
                  Flexible(
                    flex: segment.vipCount,
                    child: Container(color: const Color(0xFFF59E0B)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 범례
        Row(
          children: [
            _SegmentLegend(
              color: const Color(0xFF3B82F6),
              label: '新規',
              count: segment.newCount,
              total: total,
            ),
            const SizedBox(width: 16),
            _SegmentLegend(
              color: const Color(0xFF10B981),
              label: '既存',
              count: segment.returningCount,
              total: total,
            ),
            const SizedBox(width: 16),
            _SegmentLegend(
              color: const Color(0xFFF59E0B),
              label: 'VIP',
              count: segment.vipCount,
              total: total,
            ),
            const Spacer(),
            Text('合計: $total名',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}


class _SegmentLegend extends StatelessWidget {
  const _SegmentLegend({
    required this.color,
    required this.label,
    required this.count,
    required this.total,
  });
  final Color color;
  final String label;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total * 100;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text('$label: $count名 (${pct.toStringAsFixed(0)}%)',
            style: AppTextStyles.caption),
      ],
    );
  }
}
