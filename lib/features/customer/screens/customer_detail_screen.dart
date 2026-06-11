import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../settings/screens/loyalty_tiers_screen.dart' show loyaltyTiersProvider;

// ─── Provider ─────────────────────────────────────────────────────────────
final customerDetailProvider = StreamProvider.family<Customer?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.customers)..where((t) => t.id.equals(id))).watchSingleOrNull();
});

final customerTreatmentRecordsProvider =
    StreamProvider.family<List<TreatmentRecord>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.treatmentRecords)
        ..where((t) => t.customerId.equals(customerId))
        ..orderBy([(t) => OrderingTerm.desc(t.treatmentDate)]))
      .watch();
});

// 고객별 예약 목록
final customerAppointmentsProvider =
    StreamProvider.family<List<Appointment>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.appointments)
        ..where((t) => t.customerId.equals(customerId))
        ..orderBy([(t) => OrderingTerm.desc(t.startAt)])
        ..limit(50))
      .watch();
});

final customerSalesProvider =
    StreamProvider.family<List<Sale>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.sales)
        ..where((t) => t.customerId.equals(customerId))
        ..where((t) => t.status.equals('completed'))
        ..orderBy([(t) => OrderingTerm.desc(t.saleDate)])
        ..limit(50))
      .watch();
});

// 소개인 고객 이름 조회
final referredByCustomerProvider =
    FutureProvider.family<Customer?, String>((ref, id) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.customers)..where((t) => t.id.equals(id)))
      .getSingleOrNull();
});

// 来店履歴 + 메뉴명 맵 (saleId → menuNames)
// 고객 자주 이용 메뉴 Top3
final customerTopMenusProvider =
    FutureProvider.family<List<MapEntry<String, int>>, String>((ref, customerId) async {
  final db = ref.watch(databaseProvider);
  final sales = await (db.select(db.sales)
        ..where((t) => t.customerId.equals(customerId))
        ..where((t) => t.status.equals('completed')))
      .get();
  if (sales.isEmpty) return [];
  final saleIds = sales.map((s) => s.id).toList();
  final items = await (db.select(db.saleItems)
        ..where((t) => t.saleId.isIn(saleIds)))
      .get();
  final counts = <String, int>{};
  for (final item in items) {
    counts[item.itemName] = (counts[item.itemName] ?? 0) + 1;
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(3).toList();
});

// 最近6ヶ月の月別来店回数 (チャート用) — 単一クエリで集計
final customerMonthlyVisitsProvider =
    FutureProvider.family<List<int>, String>((ref, customerId) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
  final startDate =
      '${sixMonthsAgo.year.toString().padLeft(4, '0')}-${sixMonthsAgo.month.toString().padLeft(2, '0')}-01';
  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.customerId.equals(customerId) &
            t.saleDate.isBiggerOrEqualValue(startDate) &
            t.status.equals('completed')))
      .get();
  final counts = List.filled(6, 0);
  for (final sale in sales) {
    if (sale.saleDate.length >= 7) {
      final parts = sale.saleDate.substring(0, 7).split('-');
      if (parts.length == 2) {
        final y = int.tryParse(parts[0]) ?? 0;
        final m = int.tryParse(parts[1]) ?? 0;
        for (int i = 0; i < 6; i++) {
          final month = DateTime(now.year, now.month - (5 - i));
          if (month.year == y && month.month == m) {
            counts[i]++;
            break;
          }
        }
      }
    }
  }
  return counts;
});

// スタッフアラート (注意フラグ別色分け)
final staffAlertsProvider =
    StreamProvider.family<List<StaffAlert>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.staffAlerts)
        ..where((t) => t.customerId.equals(customerId) & t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

final customerSaleMenuMapProvider =
    FutureProvider.family<Map<String, String>, String>((ref, customerId) async {
  final db = ref.watch(databaseProvider);
  final sales = await (db.select(db.sales)
        ..where((t) => t.customerId.equals(customerId))
        ..where((t) => t.status.equals('completed'))
        ..limit(50))
      .get();
  final saleIds = sales.map((s) => s.id).toList();
  if (saleIds.isEmpty) return {};
  final items = await (db.select(db.saleItems)
        ..where((t) => t.saleId.isIn(saleIds)))
      .get();
  final menuMap = <String, List<String>>{};
  for (final item in items) {
    menuMap.putIfAbsent(item.saleId, () => []).add(item.itemName);
  }
  return {for (final e in menuMap.entries) e.key: e.value.join('・')};
});

// ─── 고객 상세 화면 ──────────────────────────────────────────────────────
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen(
      {super.key, required this.customerId, this.initialTab = 0});
  final String customerId;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerDetailProvider(customerId));

    return customerAsync.when(
      data: (customer) => customer == null
          ? Scaffold(appBar: AppBar(
        automaticallyImplyLeading: false,title: const Text('顧客詳細')),
              body: const Center(child: Text('顧客が見つかりません')))
          : _CustomerDetailBody(customer: customer, initialTab: initialTab),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
    );
  }
}

class _CustomerDetailBody extends ConsumerWidget {
  const _CustomerDetailBody({required this.customer, this.initialTab = 0});
  final Customer customer;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 7,
      initialIndex: initialTab,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
        automaticallyImplyLeading: false,
          title: Text(customer.name),
          actions: [
            // VIP 토글
            IconButton(
              icon: Icon(
                customer.isVip ? Icons.star : Icons.star_border,
                color: customer.isVip ? const Color(0xFFF59E0B) : null,
              ),
              tooltip: customer.isVip ? 'VIP解除' : 'VIPに設定',
              onPressed: () => _toggleVip(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'メッセージテンプレート',
              onPressed: () => _showMessageSheet(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _showEditSheet(context, ref),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '基本情報'),
              Tab(text: 'カルテ'),
              Tab(text: '来店履歴'),
              Tab(text: '予約履歴'),
              Tab(text: 'ポイント'),
              Tab(text: '回数券'),
              Tab(text: '掛け売り'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _BasicInfoTab(customer: customer),
            _KarteTab(customerId: customer.id),
            _VisitHistoryTab(customerId: customer.id),
            _AppointmentsTab(customerId: customer.id),
            _PointHistoryTab(customerId: customer.id, pointBalance: customer.pointBalance),
            _MembershipTab(customerId: customer.id),
            _CreditTab(customerId: customer.id, customerName: customer.name),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVip(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.customers)..where((t) => t.id.equals(customer.id)))
        .write(CustomersCompanion(isVip: Value(!customer.isVip)));
  }

  void _showMessageSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MessageTemplateSheet(customer: customer),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCustomerSheet(customer: customer),
    );
  }
}

// ─── 기본 정보 탭 ─────────────────────────────────────────────────────────
class _BasicInfoTab extends ConsumerWidget {
  const _BasicInfoTab({required this.customer});
  final Customer customer;

  static String _calcVisitCycle(Customer c) {
    if (c.totalVisits < 2 ||
        c.firstVisitDate == null ||
        c.lastVisitDate == null) return '-';
    final first = DateTime.tryParse(c.firstVisitDate!);
    final last = DateTime.tryParse(c.lastVisitDate!);
    if (first == null || last == null) return '-';
    final totalDays = last.difference(first).inDays;
    if (totalDays <= 0) return '-';
    final avgDays = (totalDays / (c.totalVisits - 1)).round();
    if (avgDays < 14) return '${avgDays}日';
    if (avgDays < 60) return '${(avgDays / 7).round()}週間';
    return '${(avgDays / 30).round()}ヶ月';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 앞으로 있는 예약 (오늘 이후)
    final upcomingAsync = ref.watch(customerAppointmentsProvider(customer.id));
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final upcoming = upcomingAsync.valueOrNull
        ?.where((a) =>
            a.startAt.compareTo(today) >= 0 &&
            a.status != 'cancelled' &&
            a.status != 'no_show')
        .take(3)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 통계 카드
          Row(
            children: [
              _StatCard('来店回数', '${customer.totalVisits}回', Icons.celebration_outlined, AppColors.primary),
              const SizedBox(width: 12),
              _StatCard('累計売上', '¥${_fmt(customer.totalSpent)}', Icons.monetization_on_outlined, AppColors.success),
              const SizedBox(width: 12),
              _StatCard('平均単価',
                  customer.totalVisits > 0
                      ? '¥${_fmt((customer.totalSpent / customer.totalVisits).round())}'
                      : '-',
                  Icons.trending_up_outlined, AppColors.alertInfo),
              const SizedBox(width: 12),
              _StatCard('来店サイクル', _calcVisitCycle(customer), Icons.loop_outlined, const Color(0xFF6366F1)),
              const SizedBox(width: 12),
              _StatCard('保有ポイント', '${_fmt(customer.pointBalance)}pt', Icons.stars_outlined, AppColors.warning),
            ],
          ),
          const SizedBox(height: 8),
          // 会員ランクバッジ
          ref.watch(loyaltyTiersProvider).whenData((tiers) {
            if (tiers.isEmpty) return const SizedBox.shrink();
            // 累計支出に応じた最高ランクを計算
            final sorted = [...tiers]
              ..sort((a, b) => b.minAmount.compareTo(a.minAmount));
            final tier = sorted.firstWhere(
              (t) => customer.totalSpent >= t.minAmount,
              orElse: () => sorted.last,
            );
            if (customer.totalSpent < sorted.last.minAmount) {
              return const SizedBox.shrink();
            }
            Color rankColor;
            try {
              final v = tier.color.replaceFirst('#', '');
              rankColor = Color(int.parse('FF$v', radix: 16));
            } catch (_) {
              rankColor = AppColors.warning;
            }
            // 次ランクまでの進捗
            final nextTierIdx = sorted.indexWhere((t) => t.minAmount > customer.totalSpent);
            final nextTier = nextTierIdx >= 0 ? sorted[nextTierIdx] : null;
            // 進捗は逆順リストなので注意: 現ランクはsorted[nextTierIdx-1]
            final progress = nextTier != null && nextTierIdx > 0
                ? (customer.totalSpent - tier.minAmount) /
                    (nextTier.minAmount - tier.minAmount).toDouble()
                : 1.0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: rankColor.withAlpha(15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: rankColor.withAlpha(60)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.military_tech_outlined, color: rankColor, size: 18),
                      const SizedBox(width: 6),
                      Text(tier.nameJp ?? tier.name,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: rankColor)),
                      if (tier.pointRateMultiplier > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('ポイント×${tier.pointRateMultiplier}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                      if (tier.discountRate > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.success.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('${tier.discountRate}%割引',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                      const Spacer(),
                      if (nextTier != null)
                        Text(
                          '次: ¥${_fmt(nextTier.minAmount - customer.totalSpent)}で${nextTier.nameJp ?? nextTier.name}',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                  if (nextTier != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: rankColor.withAlpha(30),
                        valueColor: AlwaysStoppedAnimation(rankColor),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).value ?? const SizedBox.shrink(),
          const SizedBox(height: 8),
          // 자주 이용 메뉴 Top3
          ref.watch(customerTopMenusProvider(customer.id)).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (tops) => tops.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF10B981).withAlpha(60)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.favorite_border, size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        Text('よく利用するメニュー',
                            style: AppTextStyles.caption.copyWith(
                                color: const Color(0xFF10B981),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: tops
                                .asMap()
                                .entries
                                .map((e) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: const Color(0xFF10B981).withAlpha(80)),
                                      ),
                                      child: Text(
                                        '${e.key + 1}. ${e.value.key}(${e.value.value}回)',
                                        style: const TextStyle(
                                            fontSize: 11, color: Color(0xFF10B981)),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          // 月別来店グラフ (最近6ヶ月)
          ref.watch(customerMonthlyVisitsProvider(customer.id)).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (counts) {
              // 全て0なら表示しない
              if (counts.every((c) => c == 0)) return const SizedBox.shrink();
              return _MonthlyVisitChart(counts: counts);
            },
          ),
          const SizedBox(height: 12),
          // 기본 정보 카드
          _InfoCard(children: [
            _InfoRow(Icons.person_outline, '名前', '${customer.name}${customer.nameKana != null ? ' (${customer.nameKana})' : ''}'),
            if (customer.gender != null)
              _InfoRow(Icons.wc_outlined, '性別', customer.gender == 'male' ? '男性' : customer.gender == 'female' ? '女性' : 'その他'),
            if (customer.birthDate != null)
              _BirthdayRow(birthDate: customer.birthDate!),
            if (customer.phone != null)
              _InfoRow(Icons.phone_outlined, '電話', customer.phone!),
            if (customer.email != null)
              _InfoRow(Icons.email_outlined, 'メール', customer.email!),
            if (customer.address != null)
              _InfoRow(Icons.home_outlined, '住所', customer.address!),
            if (customer.firstVisitDate != null)
              _InfoRow(Icons.calendar_today_outlined, '初来店', customer.firstVisitDate!),
            if (customer.lastVisitDate != null)
              _InfoRow(Icons.history, '前回来店', customer.lastVisitDate!),
            if (customer.referralSource != null)
              _InfoRow(Icons.campaign_outlined, '来店経路', customer.referralSource!),
            if (customer.referredBy != null)
              _ReferredByRow(customerId: customer.referredBy!),
          ]),
          // 주의 사항 (인라인 편집)
          const SizedBox(height: 12),
          _CautionEditCard(customer: customer),
          const SizedBox(height: 12),
          _InlineNotesCard(customer: customer),
          const SizedBox(height: 12),
          _StaffAlertsCard(customerId: customer.id),
          // 다음 예약 표시
          if (upcoming != null && upcoming.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.primary.withAlpha(60)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.event_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('今後の予約',
                            style: AppTextStyles.label
                                .copyWith(color: AppColors.primary)),
                      ],
                    ),
                  ),
                  ...upcoming.map((apt) {
                    final start = DateTime.parse(apt.startAt);
                    final dateStr =
                        '${start.month}月${start.day}日 ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
                    return Padding(
                      padding:
                          const EdgeInsets.fromLTRB(14, 0, 14, 10),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 6, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(dateStr,
                              style: AppTextStyles.body2.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 카르테 탭 ────────────────────────────────────────────────────────────
class _KarteTab extends ConsumerStatefulWidget {
  const _KarteTab({required this.customerId});
  final String customerId;

  @override
  ConsumerState<_KarteTab> createState() => _KarteTabState();
}

class _KarteTabState extends ConsumerState<_KarteTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync =
        ref.watch(customerTreatmentRecordsProvider(widget.customerId));

    return Stack(
      children: [
        Column(
          children: [
            // 검색바
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'カルテを検索 (日付・メニュー・カラーレシピ)',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _query = '');
                                },
                              )
                            : null,
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // カルテ一括コピー
                  recordsAsync.maybeWhen(
                    data: (records) => records.isEmpty
                        ? const SizedBox.shrink()
                        : Tooltip(
                            message: 'カルテ全件コピー',
                            child: IconButton(
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              onPressed: () => _copyAllKarte(context, records),
                              color: AppColors.textSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: recordsAsync.when(
                data: (records) {
                  final filtered = _query.isEmpty
                      ? records
                      : records.where((r) {
                          final q = _query;
                          return (r.treatmentDate.toLowerCase().contains(q)) ||
                              (r.menuNames?.toLowerCase().contains(q) ?? false) ||
                              (r.colorRecipe?.toLowerCase().contains(q) ?? false) ||
                              (r.privateNotes?.toLowerCase().contains(q) ?? false) ||
                              (r.conditionBefore?.toLowerCase().contains(q) ?? false) ||
                              (r.conditionAfter?.toLowerCase().contains(q) ?? false);
                        }).toList();

                  if (records.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.article_outlined,
                              size: 48, color: AppColors.textDisabled),
                          const SizedBox(height: 12),
                          const Text('カルテがありません',
                              style: TextStyle(
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _showAddKarte(context),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('カルテを追加'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        '「$_query」に一致するカルテはありません',
                        style: AppTextStyles.body2.copyWith(
                            color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) =>
                        _KarteCard(record: filtered[i]),
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'karte_add',
            onPressed: () => _showAddKarte(context),
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _copyAllKarte(BuildContext context, List<TreatmentRecord> records) async {
    final buf = StringBuffer();
    buf.writeln('【カルテ一覧】 (${records.length}件)');
    buf.writeln('');
    for (final r in records) {
      buf.writeln('━━━ ${r.treatmentDate} ━━━');
      if (r.menuNames != null) buf.writeln('施術: ${r.menuNames}');
      if (r.colorRecipe != null) buf.writeln('レシピ: ${r.colorRecipe}');
      if (r.conditionBefore != null) buf.writeln('施術前: ${r.conditionBefore}');
      if (r.conditionAfter != null) buf.writeln('施術後: ${r.conditionAfter}');
      if (r.privateNotes != null) buf.writeln('メモ: ${r.privateNotes}');
      buf.writeln('');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${records.length}件のカルテをコピーしました'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  void _showAddKarte(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _KarteFormSheet(customerId: widget.customerId),
      ),
    );
  }
}

class _KarteCard extends StatelessWidget {
  const _KarteCard({required this.record});
  final TreatmentRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(record.treatmentDate, style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
              if (record.menuNames != null)
                Text(record.menuNames!, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (record.colorRecipe != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.palette_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text('カラーレシピ: ${record.colorRecipe}', style: AppTextStyles.caption),
                ],
              ),
            ),
          ],
          if (record.conditionBefore != null || record.conditionAfter != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (record.conditionBefore != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withAlpha(30),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('前', style: AppTextStyles.caption.copyWith(
                              color: AppColors.warning, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(record.conditionBefore!, style: AppTextStyles.caption)),
                      ],
                    ),
                  ],
                  if (record.conditionBefore != null && record.conditionAfter != null)
                    const SizedBox(height: 4),
                  if (record.conditionAfter != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.success.withAlpha(30),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('後', style: AppTextStyles.caption.copyWith(
                              color: AppColors.success, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(record.conditionAfter!, style: AppTextStyles.caption)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (record.nextVisitMenu != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('次回提案: ${record.nextVisitMenu}',
                      style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                  if (record.nextVisitDays != null) ...[
                    const Spacer(),
                    Text('${record.nextVisitDays}日後',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ],
          if (record.privateNotes != null) ...[
            const SizedBox(height: 8),
            _KarteNotesWithTags(notes: record.privateNotes!),
          ],
        ],
      ),
    );
  }
}

// ─── カルテ タグ+メモ 表示 ──────────────────────────────────────────────────
class _KarteNotesWithTags extends StatelessWidget {
  const _KarteNotesWithTags({required this.notes});
  final String notes;

  @override
  Widget build(BuildContext context) {
    // #tag 파싱
    final lines = notes.split('\n');
    final tags = <String>[];
    final memoLines = <String>[];
    for (final line in lines) {
      final tagMatches = RegExp(r'#(\S+)').allMatches(line).map((m) => m.group(1)!).toList();
      if (tagMatches.isNotEmpty && line.trim().startsWith('#')) {
        tags.addAll(tagMatches);
      } else {
        memoLines.add(line);
      }
    }
    final memoText = memoLines.join('\n').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withAlpha(60)),
                      ),
                      child: Text('#$t',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500)),
                    ))
                .toList(),
          ),
          if (memoText.isNotEmpty) const SizedBox(height: 4),
        ],
        if (memoText.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, size: 13, color: AppColors.textDisabled),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(memoText,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic))),
            ],
          ),
      ],
    );
  }
}

// ─── 내원 이력 탭 ─────────────────────────────────────────────────────────
class _VisitHistoryTab extends ConsumerWidget {
  const _VisitHistoryTab({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(customerSalesProvider(customerId));
    final menuMapAsync = ref.watch(customerSaleMenuMapProvider(customerId));
    final menuMap = menuMapAsync.valueOrNull ?? {};

    return salesAsync.when(
      data: (sales) => sales.isEmpty
          ? const Center(child: Text('来店履歴がありません', style: TextStyle(color: AppColors.textSecondary)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: sales.length,
              separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = sales[i];
                final menus = menuMap[s.id];
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.saleDate,
                                style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            if (menus != null && menus.isNotEmpty)
                              Text(menus,
                                  style: AppTextStyles.body2.copyWith(
                                      fontSize: 12, color: AppColors.textPrimary)),
                            const SizedBox(height: 2),
                            Text(s.saleNo,
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary, fontSize: 10,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('¥${_fmt(s.totalAmount)}',
                              style: AppTextStyles.priceSmall.copyWith(
                                  color: AppColors.primary, fontSize: 14)),
                          if (s.pointEarned > 0)
                            Text('+${s.pointEarned}pt',
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.success)),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

// ─── 予約履歴 탭 ─────────────────────────────────────────────────────────
class _AppointmentsTab extends ConsumerWidget {
  const _AppointmentsTab({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aptsAsync = ref.watch(customerAppointmentsProvider(customerId));

    return aptsAsync.when(
      data: (apts) {
        if (apts.isEmpty) {
          return const Center(
            child: Text('予約履歴がありません',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: apts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _AppointmentHistoryCard(apt: apts[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _AppointmentHistoryCard extends ConsumerWidget {
  const _AppointmentHistoryCard({required this.apt});
  final Appointment apt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final start = DateTime.parse(apt.startAt);
    final end = DateTime.parse(apt.endAt);
    final durationMin = end.difference(start).inMinutes;

    final statusColor = _statusColor(apt.status);
    final statusLabel = _statusLabel(apt.status);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        (db.select(db.appointmentMenus)
              ..where((t) => t.appointmentId.equals(apt.id))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get(),
        apt.staffId.isNotEmpty
            ? (db.select(db.staff)..where((t) => t.id.equals(apt.staffId)))
                .getSingleOrNull()
            : Future.value(null),
      ]),
      builder: (_, snap) {
        final menus = snap.data != null
            ? (snap.data![0] as List).cast<AppointmentMenusData>()
            : <AppointmentMenusData>[];
        final staff = snap.data?[1] as StaffData?;
        final menuText = menus.isEmpty
            ? apt.status == 'cancelled' ? 'キャンセル済み' : '（メニューなし）'
            : menus.map((m) => m.menuName).join(' / ');

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: apt.status == 'cancelled'
                    ? AppColors.border
                    : statusColor.withAlpha(80)),
          ),
          child: Row(
            children: [
              // 날짜 열
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${start.month}/${start.day}',
                    style: AppTextStyles.h4.copyWith(
                        color: apt.status == 'cancelled'
                            ? AppColors.textSecondary
                            : AppColors.textPrimary),
                  ),
                  Text(
                    '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // 내용 열
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(menuText,
                        style: AppTextStyles.body2.copyWith(
                            fontWeight: FontWeight.w600,
                            color: apt.status == 'cancelled'
                                ? AppColors.textSecondary
                                : AppColors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(children: [
                      if (staff != null) ...[
                        const Icon(Icons.person_outline,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text(staff.name,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                      ],
                      const Icon(Icons.timer_outlined,
                          size: 11, color: AppColors.textSecondary),
                      const SizedBox(width: 3),
                      Text('${durationMin}分',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                    ]),
                  ],
                ),
              ),
              // 상태 뱃지
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withAlpha(60)),
                ),
                child: Text(statusLabel,
                    style: AppTextStyles.caption.copyWith(
                        color: statusColor, fontSize: 10)),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'confirmed' => AppColors.primary,
      'completed' => AppColors.success,
      'in_progress' => AppColors.warning,
      'cancelled' || 'no_show' => AppColors.error,
      _ => AppColors.textSecondary,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'pending' => '仮予約',
      'confirmed' => '確定',
      'in_progress' => '施術中',
      'completed' => '完了',
      'cancelled' => 'キャンセル',
      'no_show' => '無断欠席',
      _ => status,
    };
  }
}

// ─── 포인트 이력 탭 ──────────────────────────────────────────────────────
final _pointHistoryProvider =
    StreamProvider.family<List<PointHistoryData>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.pointHistory)
        ..where((t) => t.customerId.equals(customerId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(100))
      .watch();
});

class _PointHistoryTab extends ConsumerStatefulWidget {
  const _PointHistoryTab({required this.customerId, required this.pointBalance});
  final String customerId;
  final int pointBalance;

  @override
  ConsumerState<_PointHistoryTab> createState() => _PointHistoryTabState();
}

class _PointHistoryTabState extends ConsumerState<_PointHistoryTab> {
  Future<void> _showAdjustDialog() async {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String type = 'earn'; // earn / use / expire
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('ポイント手動調整'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 조작 타입
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'earn', label: Text('付与')),
                  ButtonSegment(value: 'use', label: Text('利用')),
                  ButtonSegment(value: 'expire', label: Text('失効')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setLocal(() => type = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ポイント数',
                  suffixText: 'pt',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'メモ（任意）',
                  hintText: '手動調整の理由など',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final amt = int.tryParse(amtCtrl.text.trim()) ?? 0;
    if (amt <= 0) return;

    final db = ref.read(databaseProvider);
    final now = DateTime.now().toIso8601String();
    final delta = type == 'earn' ? amt : -amt;

    final cust = await (db.select(db.customers)
          ..where((t) => t.id.equals(widget.customerId)))
        .getSingleOrNull();
    final currentBalance = cust?.pointBalance ?? 0;
    final newBalance = (currentBalance + delta).clamp(0, 9999999);

    await db.into(db.pointHistory).insert(PointHistoryCompanion.insert(
      id: const Uuid().v4(),
      customerId: widget.customerId,
      changeType: type == 'earn' ? 'adjust' : type,
      changeAmount: delta,
      balanceAfter: newBalance,
      notes: Value(noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim()),
    ));
    if (cust != null) {
      await (db.update(db.customers)
            ..where((t) => t.id.equals(widget.customerId)))
          .write(CustomersCompanion(pointBalance: Value(newBalance)));
    }
    if (mounted) {
      showTopBanner(context,
          '${type == 'earn' ? '+$amt' : '-$amt'}pt を手動調整しました',
          icon: Icons.stars_outlined,
          color: type == 'earn' ? AppColors.success : AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final histAsync = ref.watch(_pointHistoryProvider(widget.customerId));

    return Stack(
      children: [
        histAsync.when(
          data: (list) => Column(
            children: [
              // 잔여 포인트 요약
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded, color: AppColors.warning, size: 20),
                    const SizedBox(width: 10),
                    Text('現在のポイント残高', style: AppTextStyles.body2),
                    const Spacer(),
                    Text(
                      '${widget.pointBalance} pt',
                      style: AppTextStyles.h3.copyWith(
                          color: AppColors.warning, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 이력 리스트
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text('ポイント履歴がありません',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 72),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, indent: 52),
                        itemBuilder: (_, i) => _PointHistoryTile(item: list[i]),
                      ),
              ),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        ),
        // 수동 조정 FAB
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.small(
            onPressed: _showAdjustDialog,
            tooltip: 'ポイント手動調整',
            backgroundColor: AppColors.warning,
            heroTag: 'point_adjust',
            child: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
          ),
        ),
      ],
    );
  }
}

class _PointHistoryTile extends StatelessWidget {
  const _PointHistoryTile({required this.item});
  final PointHistoryData item;

  static const _typeLabels = {
    'earn': '付与',
    'use': '利用',
    'expire': '失効',
    'adjust': '調整',
    'gift_card': 'ギフト',
  };
  static const _typeColors = {
    'earn': AppColors.success,
    'use': AppColors.primary,
    'expire': AppColors.error,
    'adjust': AppColors.warning,
    'gift_card': Color(0xFF9B5CDB),
  };

  @override
  Widget build(BuildContext context) {
    final isPositive = item.changeAmount > 0;
    final color = _typeColors[item.changeType] ?? AppColors.textSecondary;
    final label = _typeLabels[item.changeType] ?? item.changeType;
    final dateStr = item.createdAt.length >= 10 ? item.createdAt.substring(0, 10) : item.createdAt;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            isPositive ? '+' : '−',
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontSize: 10)),
          ),
          const SizedBox(width: 8),
          if (item.notes != null)
            Expanded(
              child: Text(item.notes!, style: AppTextStyles.caption, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
      subtitle: Text(dateStr, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isPositive ? '+' : ''}${item.changeAmount} pt',
            style: AppTextStyles.body2.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            '残 ${item.balanceAfter} pt',
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─── 고객 수정 시트 ───────────────────────────────────────────────────────
class _EditCustomerSheet extends ConsumerStatefulWidget {
  const _EditCustomerSheet({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_EditCustomerSheet> createState() => _EditCustomerSheetState();
}

class _EditCustomerSheetState extends ConsumerState<_EditCustomerSheet> {
  late final _nameCtrl = TextEditingController(text: widget.customer.name);
  late final _kanaCtrl = TextEditingController(text: widget.customer.nameKana ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.customer.phone ?? '');
  late final _emailCtrl = TextEditingController(text: widget.customer.email ?? '');
  late final _birthCtrl = TextEditingController(text: widget.customer.birthDate ?? '');
  late final _allergiesCtrl = TextEditingController(text: widget.customer.allergies ?? '');
  late final _cautionNoteCtrl = TextEditingController(text: widget.customer.cautionNote ?? '');
  late final _noteCtrl = TextEditingController(text: widget.customer.notes ?? '');
  late String? _gender = widget.customer.gender;
  late bool _cautionFlag = widget.customer.cautionFlag;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kanaCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _birthCtrl.dispose();
    _allergiesCtrl.dispose();
    _cautionNoteCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text('顧客情報編集', style: AppTextStyles.h4),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                children: [
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '名前 *')),
                  const SizedBox(height: 12),
                  TextField(controller: _kanaCtrl, decoration: const InputDecoration(labelText: 'フリガナ')),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: '電話番号'), keyboardType: TextInputType.phone)),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'メール'), keyboardType: TextInputType.emailAddress)),
                  ]),
                  const SizedBox(height: 12),
                  // 생년월일 DatePicker 필드
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _birthCtrl,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: '生年月日',
                            hintText: 'YYYY-MM-DD',
                            suffixIcon: _birthCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () => setState(() => _birthCtrl.clear()),
                                  )
                                : const Icon(Icons.cake_outlined, size: 18),
                          ),
                          onTap: () async {
                            DateTime initial = DateTime(1990, 1, 1);
                            if (_birthCtrl.text.isNotEmpty) {
                              try { initial = DateTime.parse(_birthCtrl.text); } catch (_) {}
                            }
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initial,
                              firstDate: DateTime(1920),
                              lastDate: DateTime.now(),
                              locale: const Locale('ja'),
                            );
                            if (picked != null) {
                              setState(() {
                                _birthCtrl.text =
                                    '${picked.year.toString().padLeft(4, '0')}-'
                                    '${picked.month.toString().padLeft(2, '0')}-'
                                    '${picked.day.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('性別', style: AppTextStyles.body2),
                      const SizedBox(width: 16),
                      ...['male', 'female', 'other'].map((g) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(g == 'male' ? '男性' : g == 'female' ? '女性' : 'その他'),
                          selected: _gender == g,
                          onSelected: (v) => setState(() => _gender = v ? g : null),
                        ),
                      )),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  // 주의 사항 섹션
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                      const SizedBox(width: 6),
                      Text('注意事項', style: AppTextStyles.body2.copyWith(
                          color: AppColors.error, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Switch(
                        value: _cautionFlag,
                        activeColor: AppColors.error,
                        onChanged: (v) => setState(() => _cautionFlag = v),
                      ),
                    ],
                  ),
                  if (_cautionFlag) ...[
                    const SizedBox(height: 8),
                    TextField(controller: _cautionNoteCtrl, maxLines: 2,
                        decoration: const InputDecoration(labelText: '注意内容', hintText: '施術上の注意点など')),
                    const SizedBox(height: 8),
                    TextField(controller: _allergiesCtrl,
                        decoration: const InputDecoration(labelText: 'アレルギー', hintText: '薬剤アレルギーなど')),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _noteCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'メモ')),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await (db.update(db.customers)..where((t) => t.id.equals(widget.customer.id)))
          .write(CustomersCompanion(
        name: Value(_nameCtrl.text.trim()),
        nameKana: Value(_kanaCtrl.text.trim().isEmpty ? null : _kanaCtrl.text.trim()),
        phone: Value(_phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
        email: Value(_emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim()),
        birthDate: Value(_birthCtrl.text.trim().isEmpty ? null : _birthCtrl.text.trim()),
        allergies: Value(_allergiesCtrl.text.trim().isEmpty ? null : _allergiesCtrl.text.trim()),
        cautionNote: Value(_cautionNoteCtrl.text.trim().isEmpty ? null : _cautionNoteCtrl.text.trim()),
        cautionFlag: Value(_cautionFlag),
        notes: Value(_noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()),
        gender: Value(_gender),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
        setState(() => _saving = false);
      }
    }
  }
}

// ─── 공용 위젯 ────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(value, style: AppTextStyles.priceSmall.copyWith(color: color)),
            Text(label, style: AppTextStyles.caption),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: children.asMap().entries.map((e) => Column(
          children: [
            e.value,
            if (e.key < children.length - 1) const Divider(height: 1, indent: 44),
          ],
        )).toList(),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text(label, style: AppTextStyles.caption)),
          Expanded(child: Text(value, style: AppTextStyles.body2)),
        ],
      ),
    );
  }
}

// ─── 생일 행 (나이 + D-day 포함) ──────────────────────────────────────────
class _BirthdayRow extends StatelessWidget {
  const _BirthdayRow({required this.birthDate});
  final String birthDate; // YYYY-MM-DD

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    DateTime? dob;
    try { dob = DateTime.parse(birthDate); } catch (_) {}

    int? age;
    int? daysUntil;
    bool isTodayBirthday = false;

    if (dob != null) {
      // 나이 계산
      age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      // 올해 생일
      final thisYearBirthday = DateTime(now.year, dob.month, dob.day);
      final diff = thisYearBirthday.difference(DateTime(now.year, now.month, now.day)).inDays;
      if (diff == 0) {
        isTodayBirthday = true;
        daysUntil = 0;
      } else if (diff > 0) {
        daysUntil = diff;
      } else {
        // 내년 생일
        final nextYearBirthday = DateTime(now.year + 1, dob.month, dob.day);
        daysUntil = nextYearBirthday.difference(DateTime(now.year, now.month, now.day)).inDays;
      }
    }

    final ddayText = daysUntil == null
        ? ''
        : isTodayBirthday
            ? '🎂 今日!'
            : 'あと${daysUntil}日';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.cake_outlined, size: 18,
              color: isTodayBirthday ? const Color(0xFFFF4E8C) : AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(width: 80, child: Text('生年月日', style: AppTextStyles.caption)),
          Expanded(
            child: Row(
              children: [
                Text(birthDate, style: AppTextStyles.body2),
                if (age != null) ...[
                  const SizedBox(width: 8),
                  Text('($age歳)', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
                const Spacer(),
                if (daysUntil != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isTodayBirthday
                          ? const Color(0xFFFF4E8C).withAlpha(20)
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTodayBirthday
                            ? const Color(0xFFFF4E8C).withAlpha(80)
                            : AppColors.primary.withAlpha(60),
                      ),
                    ),
                    child: Text(
                      ddayText,
                      style: AppTextStyles.caption.copyWith(
                        color: isTodayBirthday ? const Color(0xFFFF4E8C) : AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── カルテ追加フォーム ───────────────────────────────────────────────────
class _KarteFormSheet extends ConsumerStatefulWidget {
  const _KarteFormSheet({required this.customerId});
  final String customerId;

  @override
  ConsumerState<_KarteFormSheet> createState() => _KarteFormSheetState();
}

class _KarteFormSheetState extends ConsumerState<_KarteFormSheet> {
  final _dateCtrl = TextEditingController();
  final _menuCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _condBeforeCtrl = TextEditingController();
  final _condAfterCtrl = TextEditingController();
  final _nextMenuCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int _nextVisitDays = 28;
  bool _saving = false;
  final Set<String> _selectedTags = {};

  static const _presetTags = [
    'カット', 'カラー', 'パーマ', 'トリートメント',
    'ヘッドスパ', 'ストレート', 'ハイライト', 'ブリーチ',
    '敏感肌', 'アレルギー注意', '初回', 'リピート',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateCtrl.text =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _menuCtrl.dispose();
    _colorCtrl.dispose();
    _condBeforeCtrl.dispose();
    _condAfterCtrl.dispose();
    _nextMenuCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
          top: MediaQuery.of(context).size.height * 0.1),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // ハンドルバー
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text('カルテ記録', style: AppTextStyles.h3),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // フォーム
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 施術日
                  TextField(
                    controller: _dateCtrl,
                    decoration: const InputDecoration(
                      labelText: '施術日 *',
                      hintText: 'YYYY-MM-DD',
                      prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 施術メニュー
                  TextField(
                    controller: _menuCtrl,
                    decoration: const InputDecoration(
                      labelText: '施術メニュー',
                      hintText: 'カット、カラーなど',
                      prefixIcon: Icon(Icons.content_cut, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // カラーレシピ
                  TextField(
                    controller: _colorCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'カラーレシピ',
                      hintText: 'ブランド / 色番号 / 比率 / オキシ濃度',
                      prefixIcon: Icon(Icons.palette_outlined, size: 18),
                    ),
                  ),
                  // 전회 레시피 복제 버튼
                  _PrevRecipeHint(
                    customerId: widget.customerId,
                    colorCtrl: _colorCtrl,
                    onCopied: () => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  // 施術前の状態
                  TextField(
                    controller: _condBeforeCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '施術前の状態',
                      hintText: '毛髪・頭皮の状態など',
                      prefixIcon: Icon(Icons.info_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 施術後の状態
                  TextField(
                    controller: _condAfterCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: '施術後の状態',
                      hintText: '仕上がり・反応など',
                      prefixIcon: Icon(Icons.check_circle_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 次回提案メニュー
                  TextField(
                    controller: _nextMenuCtrl,
                    decoration: const InputDecoration(
                      labelText: '次回提案メニュー',
                      hintText: '次回おすすめメニュー',
                      prefixIcon: Icon(Icons.arrow_forward_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 次回来店目安
                  Row(
                    children: [
                      const Icon(Icons.event_repeat_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text('次回来店目安', style: AppTextStyles.body2),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _nextVisitDays,
                            style: AppTextStyles.body2,
                            items: [14, 21, 28, 42, 56, 90].map((d) =>
                              DropdownMenuItem(value: d, child: Text('$d日後'))).toList(),
                            onChanged: (v) { if (v != null) setState(() => _nextVisitDays = v); },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 施術タグ
                  Row(
                    children: [
                      const Icon(Icons.label_outline, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('施術タグ', style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _presetTags.map((tag) {
                      final sel = _selectedTags.contains(tag);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (sel) _selectedTags.remove(tag);
                          else _selectedTags.add(tag);
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel ? AppColors.primary.withAlpha(20) : AppColors.background,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: sel ? AppColors.primary : AppColors.border,
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            '#$tag',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                              color: sel ? AppColors.primary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // スタッフメモ
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'スタッフメモ（非公開）',
                      hintText: '施術上の注意・お客様の好みなど',
                      prefixIcon: Icon(Icons.lock_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 保存ボタン
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('カルテを保存'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final date = _dateCtrl.text.trim();
    if (date.isEmpty) {
      showTopBanner(context, '施術日を入力してください',
          color: AppColors.error, icon: Icons.error_outline);
      return;
    }
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      // 担当スタッフ (最初のアクティブスタッフ)
      final staffList = await (db.select(db.staff)
            ..where((t) => t.isActive.equals(true))
            ..limit(1))
          .get();
      final staffId = staffList.isNotEmpty ? staffList.first.id : 'unknown';

      await db.into(db.treatmentRecords).insert(TreatmentRecordsCompanion(
        id: Value(const Uuid().v4()),
        customerId: Value(widget.customerId),
        staffId: Value(staffId),
        treatmentDate: Value(date),
        menuNames: Value(_menuCtrl.text.trim().isEmpty ? null : _menuCtrl.text.trim()),
        colorRecipe: Value(_colorCtrl.text.trim().isEmpty ? null : _colorCtrl.text.trim()),
        conditionBefore: Value(_condBeforeCtrl.text.trim().isEmpty ? null : _condBeforeCtrl.text.trim()),
        conditionAfter: Value(_condAfterCtrl.text.trim().isEmpty ? null : _condAfterCtrl.text.trim()),
        nextVisitMenu: Value(_nextMenuCtrl.text.trim().isEmpty ? null : _nextMenuCtrl.text.trim()),
        nextVisitDays: Value(_nextVisitDays),
        privateNotes: Value(() {
          final tagStr = _selectedTags.isEmpty
              ? ''
              : _selectedTags.map((t) => '#$t').join(' ');
          final notes = _notesCtrl.text.trim();
          if (tagStr.isEmpty && notes.isEmpty) return null;
          if (tagStr.isEmpty) return notes;
          if (notes.isEmpty) return tagStr;
          return '$tagStr\n$notes';
        }()),
      ));
      if (mounted) {
        Navigator.pop(context);
        showTopBanner(context, 'カルテを保存しました',
            color: AppColors.success, icon: Icons.check_circle_outline);
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── 前回カラーレシピ複製ヒント ──────────────────────────────────────────────
class _PrevRecipeHint extends ConsumerWidget {
  const _PrevRecipeHint({
    required this.customerId,
    required this.colorCtrl,
    required this.onCopied,
  });
  final String customerId;
  final TextEditingController colorCtrl;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (colorCtrl.text.isNotEmpty) return const SizedBox.shrink();
    final async = ref.watch(customerTreatmentRecordsProvider(customerId));
    final lastRecipe = async.valueOrNull
        ?.where((r) => r.colorRecipe != null && r.colorRecipe!.isNotEmpty)
        .firstOrNull
        ?.colorRecipe;
    if (lastRecipe == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 2, bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          colorCtrl.text = lastRecipe;
          onCopied();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.copy_outlined, size: 12, color: AppColors.primary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '前回を複製: $lastRecipe',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 메시지 템플릿 시트 ───────────────────────────────────────────────────
final _messageTemplatesProvider = FutureProvider<List<MessageTemplate>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.messageTemplates)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
});

class _MessageTemplateSheet extends ConsumerWidget {
  const _MessageTemplateSheet({required this.customer});
  final Customer customer;

  String _resolve(String body) {
    final now = DateTime.now();
    final daysSince = customer.lastVisitDate != null
        ? now.difference(DateTime.parse(customer.lastVisitDate!)).inDays
        : 0;
    return body
        .replaceAll('{{customer_name}}', customer.name)
        .replaceAll('{{date}}', '${now.month}月${now.day}日')
        .replaceAll('{{time}}', '${now.hour.toString().padLeft(2, '0')}:00')
        .replaceAll('{{staff_name}}', 'スタッフ')
        .replaceAll('{{days_since}}', '$daysSince');
  }

  String _typeLabel(String type) {
    return switch (type) {
      'reminder' => 'リマインダー',
      'followup' => 'フォロー',
      'birthday' => 'お誕生日',
      'reactivation' => '再来店',
      'campaign' => 'キャンペーン',
      _ => type,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_messageTemplatesProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('メッセージテンプレート', style: AppTextStyles.h4),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (templates) => templates.isEmpty
                  ? const Center(child: Text('テンプレートがありません'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: templates.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (ctx, i) {
                        final t = templates[i];
                        final resolved = _resolve(t.body);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          title: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primaryLight,
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _typeLabel(t.templateType),
                                  style:
                                      AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(t.name,
                                    style: AppTextStyles.body2
                                        .copyWith(
                                            fontWeight:
                                                FontWeight.w600)),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              resolved,
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_outlined,
                                size: 18, color: AppColors.primary),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: resolved));
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(ctx)
                                    .showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '「${t.name}」をコピーしました'),
                                    duration:
                                        const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                          ),
                          onTap: () async {
                            await Clipboard.setData(
                                ClipboardData(text: resolved));
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('「${t.name}」をコピーしました'),
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 소개인 행 ────────────────────────────────────────────────────────────
class _ReferredByRow extends ConsumerWidget {
  const _ReferredByRow({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(referredByCustomerProvider(customerId));
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (referred) {
        if (referred == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              SizedBox(
                  width: 80,
                  child: Text('紹介者', style: AppTextStyles.caption)),
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      context.push('${AppRoutes.customers}/${referred.id}'),
                  child: Row(
                    children: [
                      Text(
                        referred.name,
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right,
                          size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── インラインメモカード ─────────────────────────────────────────────────
class _InlineNotesCard extends ConsumerStatefulWidget {
  const _InlineNotesCard({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_InlineNotesCard> createState() => _InlineNotesCardState();
}

class _InlineNotesCardState extends ConsumerState<_InlineNotesCard> {
  bool _editing = false;
  late final _ctrl =
      TextEditingController(text: widget.customer.notes ?? '');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.customers)
          ..where((t) => t.id.equals(widget.customer.id)))
        .write(CustomersCompanion(
      notes: Value(_ctrl.text.trim().isEmpty ? null : _ctrl.text.trim()),
    ));
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return _InfoCard(children: [
        Row(
          children: [
            const Icon(Icons.notes_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text('メモ',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'スタッフ内部メモを入力...',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            isDense: true,
            contentPadding: const EdgeInsets.all(10),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => setState(() {
                _ctrl.text = widget.customer.notes ?? '';
                _editing = false;
              }),
              child: const Text('キャンセル'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8)),
              child: const Text('保存'),
            ),
          ],
        ),
      ]);
    }

    // 표시 모드
    final hasNotes = widget.customer.notes != null &&
        widget.customer.notes!.isNotEmpty;
    return _InfoCard(children: [
      InkWell(
        onTap: () => setState(() => _editing = true),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              const Icon(Icons.notes_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('メモ',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasNotes ? widget.customer.notes! : 'タップして追加...',
                  style: TextStyle(
                    fontSize: 13,
                    color: hasNotes
                        ? AppColors.textPrimary
                        : AppColors.textDisabled,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                hasNotes ? Icons.edit_outlined : Icons.add,
                size: 15,
                color: AppColors.textDisabled,
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

// ─── 月別来店ミニグラフ ───────────────────────────────────────────────────
class _MonthlyVisitChart extends StatelessWidget {
  const _MonthlyVisitChart({required this.counts});
  final List<int> counts; // 6 elements, oldest first

  @override
  Widget build(BuildContext context) {
    final maxVal = counts.fold(0, (m, v) => v > m ? v : m);
    final now = DateTime.now();
    final monthLabels = List.generate(6, (i) {
      final m = DateTime(now.year, now.month - (5 - i));
      return '${m.month}月';
    });

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_outlined,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                '月別来店回数（最近6ヶ月）',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 60,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(6, (i) {
                final val = counts[i];
                final barHeight = maxVal == 0
                    ? 4.0
                    : (val / maxVal * 50).clamp(4.0, 50.0);
                final isCurrentMonth = i == 5;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (val > 0)
                        Text(
                          '$val',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isCurrentMonth
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isCurrentMonth
                                ? AppColors.primary
                                : AppColors.primary.withAlpha(80),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        monthLabels[i],
                        style: TextStyle(
                          fontSize: 10,
                          color: isCurrentMonth
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: isCurrentMonth
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 注意事項・アレルギー インライン編集 ──────────────────────────────────────
class _CautionEditCard extends ConsumerStatefulWidget {
  const _CautionEditCard({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_CautionEditCard> createState() => _CautionEditCardState();
}

class _CautionEditCardState extends ConsumerState<_CautionEditCard> {
  bool _editing = false;
  late TextEditingController _cautionCtrl;
  late TextEditingController _allergyCtrl;
  late bool _cautionFlag;

  @override
  void initState() {
    super.initState();
    _cautionCtrl = TextEditingController(text: widget.customer.cautionNote ?? '');
    _allergyCtrl = TextEditingController(text: widget.customer.allergies ?? '');
    _cautionFlag = widget.customer.cautionFlag;
  }

  @override
  void dispose() {
    _cautionCtrl.dispose();
    _allergyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(databaseProvider);
    await (db.update(db.customers)
          ..where((t) => t.id.equals(widget.customer.id)))
        .write(CustomersCompanion(
      cautionFlag: Value(_cautionFlag),
      cautionNote: Value(
          _cautionCtrl.text.trim().isEmpty ? null : _cautionCtrl.text.trim()),
      allergies: Value(
          _allergyCtrl.text.trim().isEmpty ? null : _allergyCtrl.text.trim()),
    ));
    setState(() => _editing = false);
  }

  bool get _hasData =>
      _cautionFlag ||
      widget.customer.cautionNote != null ||
      widget.customer.allergies != null;

  @override
  Widget build(BuildContext context) {
    // データなし & 非編集時は追加ボタン表示
    if (!_hasData && !_editing) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        ),
        icon: const Icon(Icons.warning_amber_outlined, size: 16),
        label: const Text('注意事項・アレルギーを追加', style: TextStyle(fontSize: 13)),
        onPressed: () => setState(() => _editing = true),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cautionFlag ? AppColors.errorLight : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: _cautionFlag
                ? AppColors.error.withAlpha(80)
                : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.error, size: 16),
              const SizedBox(width: 6),
              Text('注意事項・アレルギー',
                  style:
                      AppTextStyles.label.copyWith(color: AppColors.error)),
              const Spacer(),
              if (!_editing)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    _cautionCtrl.text = widget.customer.cautionNote ?? '';
                    _allergyCtrl.text = widget.customer.allergies ?? '';
                    _cautionFlag = widget.customer.cautionFlag;
                    setState(() => _editing = true);
                  },
                ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('注意フラグ', style: TextStyle(fontSize: 13)),
                const Spacer(),
                Switch(
                  value: _cautionFlag,
                  onChanged: (v) => setState(() => _cautionFlag = v),
                  activeColor: AppColors.error,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cautionCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '注意事項',
                hintText: 'スタッフへの注意事項...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _allergyCtrl,
              decoration: InputDecoration(
                labelText: 'アレルギー',
                hintText: 'ジアミン、パーマ液 など',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _editing = false),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                  ),
                  child: const Text('保存', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ] else ...[
            if (widget.customer.cautionNote != null) ...[
              const SizedBox(height: 6),
              Text(widget.customer.cautionNote!,
                  style: AppTextStyles.body2),
            ],
            if (widget.customer.allergies != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.local_pharmacy_outlined,
                      size: 13, color: AppColors.error),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'アレルギー: ${widget.customer.allergies}',
                      style: AppTextStyles.body2.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
            if (!widget.customer.cautionFlag &&
                widget.customer.cautionNote == null &&
                widget.customer.allergies == null)
              Text('データなし', style: AppTextStyles.caption),
          ],
        ],
      ),
    );
  }
}

// ─── スタッフアラートカード ──────────────────────────────────────────────────
class _StaffAlertsCard extends ConsumerStatefulWidget {
  const _StaffAlertsCard({required this.customerId});
  final String customerId;

  @override
  ConsumerState<_StaffAlertsCard> createState() => _StaffAlertsCardState();
}

class _StaffAlertsCardState extends ConsumerState<_StaffAlertsCard> {
  bool _isAdding = false;
  final _msgCtrl = TextEditingController();
  String _alertType = 'warning';

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _addAlert() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) return;
    final db = ref.read(databaseProvider);
    const uuid = Uuid();
    await db.into(db.staffAlerts).insert(StaffAlertsCompanion.insert(
      id: uuid.v4(),
      customerId: widget.customerId,
      alertType: Value(_alertType),
      message: msg,
    ));
    _msgCtrl.clear();
    setState(() => _isAdding = false);
  }

  Future<void> _dismiss(String alertId) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.staffAlerts)..where((t) => t.id.equals(alertId)))
        .write(const StaffAlertsCompanion(isActive: Value(false)));
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'danger': return AppColors.error;
      case 'warning': return AppColors.warning;
      default: return AppColors.alertInfo;
    }
  }

  Color _typeBg(String type) {
    switch (type) {
      case 'danger': return AppColors.errorLight;
      case 'warning': return const Color(0xFFFFFBEB);
      default: return const Color(0xFFEFF6FF);
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'danger': return Icons.dangerous_outlined;
      case 'warning': return Icons.warning_amber_rounded;
      default: return Icons.info_outline;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'danger': return '危険';
      case 'warning': return '注意';
      default: return '情報';
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(staffAlertsProvider(widget.customerId));

    return alertsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (alerts) {
        final hasAlerts = alerts.isNotEmpty;
        if (!hasAlerts && !_isAdding) {
          return OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.warning),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            icon: const Icon(Icons.add_alert_outlined, size: 16),
            label: const Text('スタッフへのアラートを追加', style: TextStyle(fontSize: 13)),
            onPressed: () => setState(() => _isAdding = true),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.warning.withAlpha(80)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ヘッダー
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.add_alert_outlined, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text('スタッフアラート',
                        style: AppTextStyles.label.copyWith(color: AppColors.warning)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add, size: 18),
                      color: AppColors.warning,
                      tooltip: 'アラート追加',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setState(() => _isAdding = true),
                    ),
                  ],
                ),
              ),
              // アラートリスト
              ...alerts.map((a) => Container(
                margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: _typeBg(a.alertType),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _typeColor(a.alertType).withAlpha(60)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_typeIcon(a.alertType), size: 15, color: _typeColor(a.alertType)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _typeColor(a.alertType).withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_typeLabel(a.alertType),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _typeColor(a.alertType))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(a.message,
                          style: const TextStyle(fontSize: 13, height: 1.4)),
                    ),
                    GestureDetector(
                      onTap: () => _dismiss(a.id),
                      child: Icon(Icons.close, size: 15,
                          color: AppColors.textSecondary.withAlpha(150)),
                    ),
                  ],
                ),
              )),
              // 追加フォーム
              if (_isAdding) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // タイプ選択
                      Row(
                        children: ['info', 'warning', 'danger'].map((t) =>
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_typeLabel(t),
                                  style: const TextStyle(fontSize: 12)),
                              selected: _alertType == t,
                              selectedColor: _typeColor(t).withAlpha(40),
                              onSelected: (_) => setState(() => _alertType = t),
                            ),
                          ),
                        ).toList(),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _msgCtrl,
                        decoration: InputDecoration(
                          hintText: 'アラート内容を入力...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          isDense: true,
                        ),
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13),
                        autofocus: true,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              _msgCtrl.clear();
                              setState(() => _isAdding = false);
                            },
                            child: const Text('キャンセル'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addAlert,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                            ),
                            child: const Text('追加', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else
                const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }
}

String _fmt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

// ─── 回数券・プリペイド タブ ──────────────────────────────────────────────

final _customerMembershipsProvider =
    StreamProvider.family<List<CustomerMembership>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.customerMemberships)
        ..where((t) => t.customerId.equals(customerId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

final _membershipPlanByIdProvider =
    FutureProvider.family<MembershipPlan?, String>((ref, planId) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.membershipPlans)..where((t) => t.id.equals(planId)))
      .getSingleOrNull();
});

class _MembershipTab extends ConsumerWidget {
  const _MembershipTab({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membershipsAsync = ref.watch(_customerMembershipsProvider(customerId));

    return membershipsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (memberships) {
        if (memberships.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.card_membership_outlined,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                const Text('回数券・プリペイドなし',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                const Text('会計画面で回数券・プリペイドを販売すると\nここに表示されます',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        final active = memberships
            .where((m) => m.status == 'active')
            .toList();
        final inactive = memberships
            .where((m) => m.status != 'active')
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active.isNotEmpty) ...[
              _MembershipSectionLabel(label: '有効', count: active.length),
              const SizedBox(height: 8),
              ...active.map((m) => _MembershipCard(membership: m)),
              const SizedBox(height: 16),
            ],
            if (inactive.isNotEmpty) ...[
              _MembershipSectionLabel(label: '終了・キャンセル', count: inactive.length),
              const SizedBox(height: 8),
              ...inactive.map((m) => _MembershipCard(membership: m, dimmed: true)),
            ],
          ],
        );
      },
    );
  }
}

class _MembershipSectionLabel extends StatelessWidget {
  const _MembershipSectionLabel({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(width: 6),
        Text('($count)',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _MembershipCard extends ConsumerWidget {
  const _MembershipCard({required this.membership, this.dimmed = false});
  final CustomerMembership membership;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(_membershipPlanByIdProvider(membership.planId));

    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: planAsync.when(
                      data: (plan) => Text(
                        plan?.name ?? membership.planId,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      loading: () => const Text('...'),
                      error: (_, __) => Text(membership.planId),
                    ),
                  ),
                  _StatusBadge(status: membership.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (membership.totalSessions != null) ...[
                    _InfoChip(
                      label: '残り',
                      value:
                          '${(membership.totalSessions! - membership.usedSessions)}/${membership.totalSessions}回',
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (membership.remainingAmount != null) ...[
                    _InfoChip(
                      label: '残高',
                      value: '¥${_fmt(membership.remainingAmount!)}',
                      color: const Color(0xFF0EA5E9),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (membership.endDate != null)
                    _InfoChip(
                      label: '有効期限',
                      value: membership.endDate!.length >= 10
                          ? membership.endDate!.substring(0, 10)
                          : membership.endDate!,
                      color: AppColors.textSecondary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    const labels = {
      'active': '有効',
      'expired': '期限切れ',
      'suspended': '停止',
      'cancelled': 'キャンセル',
    };
    const colors = {
      'active': AppColors.success,
      'expired': AppColors.textSecondary,
      'suspended': Colors.orange,
      'cancelled': AppColors.error,
    };
    final label = labels[status] ?? status;
    final color = colors[status] ?? AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
          Text(value,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ─── 掛け売り タブ ────────────────────────────────────────────────────────────

final _customerCreditAccountProvider =
    StreamProvider.family<CreditAccount?, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.creditAccounts)
        ..where((t) => t.customerId.equals(customerId)))
      .watchSingleOrNull();
});

final _customerCreditTxProvider =
    StreamProvider.family<List<CreditTransaction>, String>((ref, customerId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.creditTransactions)
        ..where((t) => t.customerId.equals(customerId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(50))
      .watch();
});

class _CreditTab extends ConsumerStatefulWidget {
  const _CreditTab({required this.customerId, required this.customerName});
  final String customerId;
  final String customerName;

  @override
  ConsumerState<_CreditTab> createState() => _CreditTabState();
}

class _CreditTabState extends ConsumerState<_CreditTab> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _processing = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _recordPayment(CreditAccount account) async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showTopBanner(context, '収納金額を入力してください',
          icon: Icons.warning_rounded, color: AppColors.error);
      return;
    }

    setState(() => _processing = true);
    try {
      final db = ref.read(databaseProvider);
      final newBalance = (account.balance - amount).clamp(0, account.balance);

      await db.transaction(() async {
        await db.into(db.creditTransactions).insert(
              CreditTransactionsCompanion(
                id: Value(const Uuid().v4()),
                accountId: Value(account.id),
                customerId: Value(account.customerId),
                txType: const Value('payment'),
                amount: Value(-amount),
                balanceAfter: Value(newBalance),
                notes: Value(_noteCtrl.text.trim().isEmpty
                    ? null
                    : _noteCtrl.text.trim()),
              ),
            );
        await (db.update(db.creditAccounts)
              ..where((t) => t.id.equals(account.id)))
            .write(CreditAccountsCompanion(balance: Value(newBalance)));
      });

      if (mounted) {
        _amountCtrl.clear();
        _noteCtrl.clear();
        showTopBanner(context, '¥${_fmt(amount)} を収納しました',
            icon: Icons.check_circle_outline, color: AppColors.success);
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync =
        ref.watch(_customerCreditAccountProvider(widget.customerId));
    final txAsync =
        ref.watch(_customerCreditTxProvider(widget.customerId));

    return accountAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (account) {
        if (account == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_outlined,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                const Text('掛け売り履歴なし',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                const Text('会計画面で「掛け売り」決済を選択すると\nここに表示されます',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          );
        }

        return Column(
          children: [
            // 잔액 헤더
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  const Text('未収残高', style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  Text(
                    '¥${_fmt(account.balance)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: account.balance > 0
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 수납 폼
            if (account.balance > 0)
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.error.withValues(alpha: 0.04),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '収納金額 (¥)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'メモ（任意）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed:
                          _processing ? null : () => _recordPayment(account),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      child: _processing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('収納'),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),

            // 이력
            Expanded(
              child: txAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (txList) {
                  if (txList.isEmpty) {
                    return const Center(
                        child: Text('取引履歴がありません',
                            style: TextStyle(color: AppColors.textSecondary)));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: txList.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 52),
                    itemBuilder: (ctx, i) => _CreditTxTile(tx: txList[i]),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CreditTxTile extends StatelessWidget {
  const _CreditTxTile({required this.tx});
  final CreditTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isCharge = tx.txType == 'charge';
    final isPayment = tx.txType == 'payment';
    final color = isCharge
        ? AppColors.error
        : isPayment
            ? AppColors.success
            : AppColors.warning;
    final label =
        isCharge ? '掛け売り' : isPayment ? '収納' : '調整';
    final dateStr = tx.createdAt.length >= 16
        ? tx.createdAt.substring(5, 16)
        : tx.createdAt;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isCharge
              ? Icons.arrow_upward_rounded
              : isPayment
                  ? Icons.arrow_downward_rounded
                  : Icons.tune,
          size: 16,
          color: color,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          if (tx.notes != null && tx.notes!.isNotEmpty)
            Expanded(
              child: Text(tx.notes!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
      subtitle: Text(dateStr,
          style:
              const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${tx.amount > 0 ? '+' : ''}¥${_fmt(tx.amount.abs())}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color),
          ),
          Text(
            '残 ¥${_fmt(tx.balanceAfter)}',
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
