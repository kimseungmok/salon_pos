import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/widgets/top_banner.dart';
import '../../../shared/theme/app_theme.dart';
import '../../pos/screens/refund_screen.dart';
import '../providers/transactions_provider.dart';

// ─── 결제 수단 레이블 ─────────────────────────────────────────────────────
const _methodLabel = {
  'cash': '現金',
  'ic_emoney': 'IC・電子マネー',
  'credit_card': 'クレジット',
  'qr_code': 'QRコード',
  'point': 'ポイント',
  'voucher': '回数券',
  'bank_transfer': '振込',
};

const _methodColors = {
  'cash': Color(0xFF4CAF50),
  'ic_emoney': Color(0xFF2196F3),
  'credit_card': Color(0xFFFF9800),
  'qr_code': Color(0xFF9C27B0),
  'point': Color(0xFFE91E63),
  'voucher': Color(0xFF009688),
  'bank_transfer': Color(0xFF607D8B),
};

// ─── 메인 화면 ────────────────────────────────────────────────────────────
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _currencyFmt = NumberFormat('#,###', 'ja_JP');
  final _dateFmt = DateFormat('MM/dd HH:mm');
  final _searchCtrl = TextEditingController();
  TransactionItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      ref.read(transactionFilterProvider.notifier).update(
            (f) => q.isEmpty ? f.copyWith(clearSearch: true) : f.copyWith(searchQuery: q),
          );
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final summaryAsync = ref.watch(transactionSummaryProvider);
    final listAsync = ref.watch(transactionListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: AppColors.textSecondary,
          onPressed: () => context.pop(),
        ),
        title: Text('取引一覧',
            style: AppTextStyles.h4.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          _CsvExportBtn(listAsync: listAsync),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppColors.border),
        ),
      ),
      body: Row(
        children: [
          // ── 메인 영역 ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── 검색바 ──────────────────────────────────────────────
                Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: TextField(
                            controller: _searchCtrl,
                            style: AppTextStyles.body2.copyWith(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '取引番号・金額・顧客名・担当者を検索...',
                              hintStyle: AppTextStyles.caption.copyWith(color: AppColors.textDisabled),
                              prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close, size: 14),
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        _searchCtrl.clear();
                                        ref.read(transactionFilterProvider.notifier)
                                            .update((f) => f.copyWith(clearSearch: true));
                                      },
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                              filled: true,
                              fillColor: AppColors.background,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ── 상단 필터 바 ────────────────────────────────────────
                _FilterBar(filter: filter),
                // ── 요약 카드 ────────────────────────────────────────────
                summaryAsync.when(
                  loading: () => const _SummaryShimmer(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (s) => _SummaryRow(summary: s),
                ),
                // ── 거래 목록 ────────────────────────────────────────────
                Expanded(
                  child: listAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('エラー: $e',
                          style: const TextStyle(color: AppColors.error)),
                    ),
                    data: (items) {
                      if (items.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.receipt_long_outlined,
                                  size: 56, color: AppColors.border),
                              const SizedBox(height: 12),
                              Text('取引データがありません',
                                  style: AppTextStyles.body1.copyWith(
                                      color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty)
                                Text('「${filter.searchQuery}」に一致する取引はありません',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textDisabled))
                              else
                                Text('${filter.startDate} 〜 ${filter.endDate}',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textDisabled)),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) => _TransactionCard(
                          item: items[i],
                          currencyFmt: _currencyFmt,
                          dateFmt: _dateFmt,
                          isSelected: _selectedItem?.id == items[i].id,
                          onTap: () => setState(() {
                            _selectedItem = (_selectedItem?.id == items[i].id)
                                ? null
                                : items[i];
                          }),
                          onRefund: () => _openRefund(context, items[i]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // ── 거래 상세 패널 ──────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: _selectedItem != null ? 300 : 0,
            child: _selectedItem != null
                ? _DetailPanel(
                    key: ValueKey(_selectedItem!.id),
                    item: _selectedItem!,
                    currencyFmt: _currencyFmt,
                    dateFmt: _dateFmt,
                    onClose: () => setState(() => _selectedItem = null),
                    onRefund: () => _openRefund(context, _selectedItem!),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  void _openRefund(BuildContext context, TransactionItem item) {
    if (!item.isCompleted && !item.isPartialRefund) {
      showTopBanner(context, '返金できない取引です（${_statusLabel(item.status)}）',
          color: AppColors.warning, icon: Icons.warning_amber_outlined);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RefundScreen(saleId: item.id)),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed': return '完了';
      case 'partial_refund': return '一部返金';
      case 'refunded': return '返金済';
      case 'voided': return '無効';
      default: return status;
    }
  }
}

// ─── 필터 바 ─────────────────────────────────────────────────────────────
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});
  final TransactionFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(transactionStaffListProvider);

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border:
            Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // 날짜 범위 버튼
          _FilterChipBtn(
            icon: Icons.date_range_outlined,
            label: '${filter.startDate.substring(5)} 〜 ${filter.endDate.substring(5)}',
            active: true,
            onTap: () => _showDatePicker(context, ref, filter),
          ),
          const SizedBox(width: 6),

          // 상태 필터
          _FilterChipBtn(
            icon: Icons.radio_button_checked,
            label: _statusLabel(filter.status),
            active: filter.status != null,
            onTap: () => _showStatusMenu(context, ref, filter),
          ),
          const SizedBox(width: 6),

          // 결제 수단 필터
          _FilterChipBtn(
            icon: Icons.credit_card_outlined,
            label: _methodLabel[filter.payMethod] ?? '全決済',
            active: filter.payMethod != null,
            onTap: () => _showMethodMenu(context, ref, filter),
          ),
          const SizedBox(width: 6),

          // 담당자 필터
          staffAsync.when(
            data: (staffList) => _FilterChipBtn(
              icon: Icons.content_cut,
              label: staffList.where((s) => s.id == filter.staffId).firstOrNull?.name ?? '全担当',
              active: filter.staffId != null,
              onTap: () => _showStaffMenu(context, ref, filter, staffList),
            ),
            loading: () => const SizedBox(width: 60, height: 28),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const Spacer(),

          // 정렬
          _FilterChipBtn(
            icon: Icons.sort,
            label: _sortLabel(filter.sort),
            active: false,
            onTap: () => _showSortMenu(context, ref, filter),
          ),

          // 필터 초기화 버튼 (활성 필터 있을 때만)
          if (filter.staffId != null || filter.status != null || filter.payMethod != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => ref.read(transactionFilterProvider.notifier).update(
                    (f) => f.copyWith(clearStaff: true, status: 'all', payMethod: 'all'),
                  ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close, size: 12, color: AppColors.error),
                    const SizedBox(width: 3),
                    Text('絞込解除', style: AppTextStyles.caption.copyWith(color: AppColors.error, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'completed': return '完了';
      case 'partial_refund': return '一部返金';
      case 'refunded': return '返金済';
      case 'voided': return '無効';
      default: return '全ステータス';
    }
  }

  String _sortLabel(String sort) {
    switch (sort) {
      case 'date_asc': return '日時 ↑';
      case 'amount_desc': return '金額 ↓';
      case 'amount_asc': return '金額 ↑';
      default: return '日時 ↓';
    }
  }

  Future<void> _showDatePicker(
      BuildContext context, WidgetRef ref, TransactionFilter filter) async {
    final start = DateTime.parse(filter.startDate);
    final end = DateTime.parse(filter.endDate);
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: start, end: end),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (range != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      ref.read(transactionFilterProvider.notifier).update((f) => f.copyWith(
            startDate: fmt.format(range.start),
            endDate: fmt.format(range.end),
          ));
    }
  }

  void _showStatusMenu(
      BuildContext context, WidgetRef ref, TransactionFilter filter) {
    final items = [
      ('all', '全ステータス'),
      ('completed', '完了'),
      ('partial_refund', '一部返金'),
      ('refunded', '返金済'),
      ('voided', '無効'),
    ];
    _showMenuOptions(context, items, filter.status ?? 'all', (v) {
      ref.read(transactionFilterProvider.notifier)
          .update((f) => f.copyWith(status: v == 'all' ? null : v));
    });
  }

  void _showMethodMenu(
      BuildContext context, WidgetRef ref, TransactionFilter filter) {
    final items = [
      ('all', '全決済方法'),
      ...(_methodLabel.entries.map((e) => (e.key, e.value))),
    ];
    _showMenuOptions(context, items, filter.payMethod ?? 'all', (v) {
      ref.read(transactionFilterProvider.notifier)
          .update((f) => f.copyWith(payMethod: v == 'all' ? null : v));
    });
  }

  void _showStaffMenu(
      BuildContext context, WidgetRef ref, TransactionFilter filter,
      List<StaffItem> staffList) {
    final items = <(String, String)>[
      ('all', '全担当者'),
      ...staffList.map((s) => (s.id, s.name)),
    ];
    _showMenuOptions(context, items, filter.staffId ?? 'all', (v) {
      ref.read(transactionFilterProvider.notifier)
          .update((f) => f.copyWith(staffId: v == 'all' ? null : v, clearStaff: v == 'all'));
    });
  }

  void _showSortMenu(
      BuildContext context, WidgetRef ref, TransactionFilter filter) {
    final items = [
      ('date_desc', '日時 新しい順'),
      ('date_asc', '日時 古い順'),
      ('amount_desc', '金額 高い順'),
      ('amount_asc', '金額 低い順'),
    ];
    _showMenuOptions(context, items, filter.sort, (v) {
      ref.read(transactionFilterProvider.notifier)
          .update((f) => f.copyWith(sort: v));
    });
  }

  void _showMenuOptions(BuildContext context, List<(String, String)> items,
      String current, ValueChanged<String> onSelect) {
    final RenderBox btn = context.findRenderObject() as RenderBox;
    final offset = btn.localToGlobal(Offset.zero);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          offset.dx, offset.dy + btn.size.height, offset.dx + 200, 0),
      items: items
          .map((e) => PopupMenuItem(
                value: e.$1,
                child: Row(
                  children: [
                    if (e.$1 == current)
                      const Icon(Icons.check, size: 16, color: AppColors.primary)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(e.$2, style: AppTextStyles.body2),
                  ],
                ),
              ))
          .toList(),
    ).then((v) {
      if (v != null) onSelect(v);
    });
  }
}

class _FilterChipBtn extends StatelessWidget {
  const _FilterChipBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryLight : AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppColors.primary.withAlpha(80) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(label,
                style: AppTextStyles.caption.copyWith(
                    color: active ? AppColors.primary : AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
            const SizedBox(width: 2),
            Icon(Icons.expand_more, size: 12,
                color: active ? AppColors.primary : AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─── 요약 행 ──────────────────────────────────────────────────────────────
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});
  final TransactionSummary summary;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,###', 'ja_JP');
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border:
            Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SummaryItem(
              label: '売上合計',
              value: '¥${fmt.format(summary.totalRevenue)}',
              color: AppColors.primary),
          const _SDivider(),
          _SummaryItem(
              label: '件数',
              value: '${summary.completedCount}件',
              color: AppColors.textPrimary),
          const _SDivider(),
          _SummaryItem(
              label: '消費税',
              value: '¥${fmt.format(summary.totalTax)}',
              color: AppColors.textSecondary),
          const _SDivider(),
          _SummaryItem(
              label: '割引合計',
              value: summary.totalDiscount > 0
                  ? '-¥${fmt.format(summary.totalDiscount)}'
                  : '¥0',
              color: summary.totalDiscount > 0
                  ? AppColors.warning
                  : AppColors.textSecondary),
          const _SDivider(),
          _SummaryItem(
              label: '返金',
              value: '${summary.refundedCount}件',
              color: summary.refundedCount > 0
                  ? AppColors.error
                  : AppColors.textSecondary),
          const _SDivider(),
          _SummaryItem(
              label: '無効',
              value: '${summary.voidedCount}件',
              color: summary.voidedCount > 0
                  ? AppColors.textSecondary
                  : AppColors.textDisabled),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: TextStyle(
                fontFamily: 'NotoSansJP',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              )),
          Text(label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 9,
              )),
        ],
      ),
    );
  }
}

class _SDivider extends StatelessWidget {
  const _SDivider();
  @override
  Widget build(BuildContext context) {
    return Container(width: 0.5, height: 28, color: AppColors.border);
  }
}

class _SummaryShimmer extends StatelessWidget {
  const _SummaryShimmer();
  @override
  Widget build(BuildContext context) {
    return Container(height: 52, color: AppColors.surface);
  }
}

// ─── 거래 카드 ────────────────────────────────────────────────────────────
class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.item,
    required this.currencyFmt,
    required this.dateFmt,
    required this.isSelected,
    required this.onTap,
    required this.onRefund,
  });
  final TransactionItem item;
  final NumberFormat currencyFmt;
  final DateFormat dateFmt;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onRefund;

  Color get _statusColor {
    if (item.isVoided) return AppColors.textDisabled;
    if (item.isRefunded) return AppColors.error;
    if (item.isPartialRefund) return AppColors.warning;
    return AppColors.success;
  }

  String get _statusLabel {
    if (item.isVoided) return '無効';
    if (item.isRefunded) return '返金済';
    if (item.isPartialRefund) return '一部返金';
    return '完了';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryLight
              : item.isVoided
                  ? AppColors.background
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 0.5,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.primary.withAlpha(20), blurRadius: 6, offset: const Offset(0, 2))]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7.5),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 상태 컬러 바
                Container(width: 3, color: _statusColor),
                // 카드 내용
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 왼쪽: 번호/날짜
                        Expanded(
                          flex: 3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.saleNo,
                                      style: AppTextStyles.caption.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        fontFamily: 'monospace',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _statusColor.withAlpha(20),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _statusLabel,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: _statusColor,
                                        fontFamily: 'NotoSansJP',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                dateFmt.format(item.createdAt),
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ),

                        // 가운데: 고객/스태프/시술
                        Expanded(
                          flex: 4,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person_outline,
                                      size: 11, color: AppColors.textSecondary),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: GestureDetector(
                                      onTap: item.customerId != null
                                          ? () => context.push('/customers/${item.customerId}')
                                          : null,
                                      child: Text(
                                        item.customerName ?? '一般顧客',
                                        style: AppTextStyles.caption.copyWith(
                                          color: item.customerId != null
                                              ? AppColors.primary
                                              : AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          decoration: item.customerId != null
                                              ? TextDecoration.underline
                                              : null,
                                          decorationColor: AppColors.primary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.content_cut,
                                      size: 10, color: AppColors.textSecondary),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      item.staffName,
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 10),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              if (item.menuNames.isNotEmpty)
                                Text(
                                  item.menuNames.join('・'),
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary, fontSize: 9),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),

                        // 오른쪽: 금액/결제수단/환불 버튼
                        Expanded(
                          flex: 3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                item.isVoided
                                    ? '-'
                                    : '¥${currencyFmt.format(item.totalAmount)}',
                                style: TextStyle(
                                  fontFamily: 'NotoSansJP',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: item.isVoided
                                      ? AppColors.textDisabled
                                      : AppColors.textPrimary,
                                  decoration: item.isRefunded
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 3,
                                children: item.methods.map((m) {
                                  final color =
                                      _methodColors[m] ?? AppColors.textSecondary;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: color.withAlpha(20),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      _methodLabel[m] ?? m,
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                        fontFamily: 'NotoSansJP',
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              // 빠른 환불 버튼 (완료 상태만)
                              if (item.isCompleted || item.isPartialRefund) ...[
                                const SizedBox(height: 5),
                                GestureDetector(
                                  onTap: onRefund,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorLight,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.error.withAlpha(60)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.keyboard_return, size: 10, color: AppColors.error),
                                        const SizedBox(width: 3),
                                        Text('返金',
                                            style: AppTextStyles.caption.copyWith(
                                                color: AppColors.error,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 거래 상세 패널 ───────────────────────────────────────────────────────
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({
    super.key,
    required this.item,
    required this.currencyFmt,
    required this.dateFmt,
    required this.onClose,
    required this.onRefund,
  });
  final TransactionItem item;
  final NumberFormat currencyFmt;
  final DateFormat dateFmt;
  final VoidCallback onClose;
  final VoidCallback onRefund;

  Color get _statusColor {
    if (item.isVoided) return AppColors.textDisabled;
    if (item.isRefunded) return AppColors.error;
    if (item.isPartialRefund) return AppColors.warning;
    return AppColors.success;
  }

  String get _statusLabel {
    if (item.isVoided) return '無効';
    if (item.isRefunded) return '返金済';
    if (item.isPartialRefund) return '一部返金';
    return '完了';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_statusLabel,
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'NotoSansJP')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.saleNo,
                      style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: AppColors.textSecondary,
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // ── 상세 정보 ──────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 날짜
                  _DetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: '日時',
                    value: DateFormat('yyyy/MM/dd HH:mm').format(item.createdAt),
                  ),
                  const SizedBox(height: 10),

                  // 고객
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: '顧客',
                    value: item.customerName ?? '一般顧客',
                  ),
                  const SizedBox(height: 10),

                  // 담당자
                  _DetailRow(
                    icon: Icons.content_cut,
                    label: '担当者',
                    value: item.staffName,
                  ),
                  const SizedBox(height: 16),

                  // 시술 목록
                  if (item.menuNames.isNotEmpty) ...[
                    Text('施術内容',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...item.menuNames.map((name) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.circle, size: 4, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name, style: AppTextStyles.body2.copyWith(fontSize: 12))),
                            ],
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],

                  // 결제 수단
                  Text('決済方法',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: item.methods.map((m) {
                      final color = _methodColors[m] ?? AppColors.textSecondary;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(60)),
                        ),
                        child: Text(_methodLabel[m] ?? m,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600,
                                color: color, fontFamily: 'NotoSansJP')),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 금액 내역
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _AmountRow(
                      label: '小計',
                      value: '¥${currencyFmt.format(item.totalAmount - item.taxAmount + item.discountAmount)}'),
                  if (item.discountAmount > 0) ...[
                    const SizedBox(height: 6),
                    _AmountRow(
                        label: '割引',
                        value: '-¥${currencyFmt.format(item.discountAmount)}',
                        color: AppColors.warning),
                  ],
                  const SizedBox(height: 6),
                  _AmountRow(
                      label: '消費税',
                      value: '¥${currencyFmt.format(item.taxAmount)}',
                      color: AppColors.textSecondary),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  _AmountRow(
                    label: '合計',
                    value: item.isVoided ? '-' : '¥${currencyFmt.format(item.totalAmount)}',
                    isBold: true,
                    color: item.isVoided
                        ? AppColors.textDisabled
                        : AppColors.textPrimary,
                  ),
                ],
              ),
            ),
          ),

          // ── 액션 버튼 ──────────────────────────────────────────────────
          if (item.isCompleted || item.isPartialRefund) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: onRefund,
                  icon: const Icon(Icons.keyboard_return, size: 16, color: AppColors.error),
                  label: const Text('返金処理',
                      style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label,
            style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    this.color,
    this.isBold = false,
  });
  final String label;
  final String value;
  final Color? color;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: isBold ? 12 : 11)),
        const Spacer(),
        Text(value,
            style: TextStyle(
              fontFamily: 'NotoSansJP',
              fontSize: isBold ? 15 : 12,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: color ?? AppColors.textPrimary,
            )),
      ],
    );
  }
}

// ─── 거래 이력 CSV 내보내기 버튼 ─────────────────────────────────────────
class _CsvExportBtn extends ConsumerStatefulWidget {
  const _CsvExportBtn({required this.listAsync});
  final AsyncValue<List<TransactionItem>> listAsync;

  @override
  ConsumerState<_CsvExportBtn> createState() => _CsvExportBtnState();
}

class _CsvExportBtnState extends ConsumerState<_CsvExportBtn> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    final items = widget.listAsync.valueOrNull;
    if (items == null || items.isEmpty) {
      showTopBanner(context, '書き出すデータがありません',
          color: AppColors.primary, icon: Icons.info_outline);
      return;
    }
    setState(() => _exporting = true);
    try {
      final buf = StringBuffer();
      buf.writeln('取引番号,日付,顧客名,担当者,施術メニュー,支払方法,金額,ステータス');
      for (final t in items) {
        final methodsStr = t.methods
            .map((m) => _methodLabel[m] ?? m)
            .join(' / ');
        buf.writeln(
          '"${t.saleNo}",'
          '"${t.saleDate}",'
          '"${t.customerName ?? ''}",'
          '"${t.staffName}",'
          '"${t.menuNames.join('・')}",'
          '"$methodsStr",'
          '${t.totalAmount},'
          '"${t.status}"',
        );
      }
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now();
      final fname =
          'transactions_${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}_'
          '${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}.csv';
      final file = File('${dir.path}/$fname');
      await file.writeAsString('﻿${buf.toString()}');
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

  @override
  Widget build(BuildContext context) {
    return _exporting
        ? const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2))
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
