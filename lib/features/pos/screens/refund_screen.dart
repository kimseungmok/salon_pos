import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/pos_provider.dart';

const _uuid = Uuid();

// ─── 返金手段定義 ──────────────────────────────────────────────────────────
class _RefundMethod {
  const _RefundMethod(this.key, this.label, this.icon, this.color);
  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

const _refundMethods = [
  _RefundMethod('cash', '現金返金', Icons.payments_outlined, Color(0xFF22C55E)),
  _RefundMethod('credit_card', 'カード返金', Icons.credit_card, Color(0xFF6366F1)),
  _RefundMethod('bank_transfer', '銀行振込', Icons.account_balance_outlined, Color(0xFF8D6E63)),
];

// 返金理由アイコン
const _reasonIcons = <String, IconData>{
  '顧客都合': Icons.person_outline,
  'サービス不満足': Icons.sentiment_dissatisfied_outlined,
  '施術ミス': Icons.content_cut,
  '二重請求': Icons.receipt_long_outlined,
  'その他': Icons.more_horiz,
};

String _methodLabel(String key) {
  const m = {
    'cash': '現金',
    'credit_card': 'クレジット',
    'ic_card': 'IC・電子マネー',
    'qr': 'QRコード',
    'gift_card': 'ギフトカード',
    'bank_transfer': '銀行振込',
  };
  return m[key] ?? key;
}

IconData _methodIcon(String key) {
  const icons = {
    'cash': Icons.payments_outlined,
    'credit_card': Icons.credit_card,
    'ic_card': Icons.contactless_outlined,
    'qr': Icons.qr_code_scanner,
    'gift_card': Icons.card_giftcard_outlined,
    'bank_transfer': Icons.account_balance_outlined,
  };
  return icons[key] ?? Icons.payment;
}

// ─── 払い戻し画面 ──────────────────────────────────────────────────────────
class RefundScreen extends ConsumerStatefulWidget {
  const RefundScreen({super.key, required this.saleId});
  final String saleId;

  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  final Map<String, int> _selectedQty = {};
  String _reason = '顧客都合';
  String _refundMethod = 'cash';
  bool _processing = false;

  static const _reasons = [
    '顧客都合',
    'サービス不満足',
    '施術ミス',
    '二重請求',
    'その他',
  ];

  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('払い戻し'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _processing ? null : () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<_RefundData>(
        future: _loadData(db),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData || snap.data!.sale == null) {
            return Center(
              child: Text('売上データの読み込みに失敗しました\n${snap.error}',
                  style: AppTextStyles.body2),
            );
          }
          return _buildBody(context, snap.data!);
        },
      ),
    );
  }

  Future<_RefundData> _loadData(AppDatabase db) async {
    final sale = await (db.select(db.sales)
          ..where((t) => t.id.equals(widget.saleId)))
        .getSingleOrNull();
    final items = await (db.select(db.saleItems)
          ..where((t) => t.saleId.equals(widget.saleId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    final payments = await (db.select(db.salePayments)
          ..where((t) => t.saleId.equals(widget.saleId)))
        .get();
    final existingRefunds = await (db.select(db.refunds)
          ..where((t) => t.originalSaleId.equals(widget.saleId)))
        .get();
    final existingRefundAmt =
        existingRefunds.fold(0, (s, r) => s + r.refundAmount);
    return _RefundData(
      sale: sale,
      items: items,
      payments: payments,
      alreadyRefunded: existingRefundAmt,
    );
  }

  Widget _buildBody(BuildContext context, _RefundData data) {
    final sale = data.sale!;
    final refundableMax = sale.totalAmount - data.alreadyRefunded;
    final selectedAmt = _selectedQty.entries.fold(0, (s, e) {
      final item = data.items.firstWhere(
          (i) => i.id == e.key,
          orElse: () => data.items.first);
      return s + (item.totalPrice * e.value ~/ item.quantity);
    });
    final isAllSelected =
        data.items.isNotEmpty &&
        data.items.every((i) => (_selectedQty[i.id] ?? 0) == i.quantity);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 左: 元の売上内容 ──────────────────────────────────────────────
        Expanded(
          flex: 3,
          child: Container(
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sale header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('売上 No. ${sale.saleNo}',
                              style: AppTextStyles.h4),
                          const Spacer(),
                          _StatusChip(status: sale.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${sale.saleDate}  合計 ¥${_fmt(sale.totalAmount)}',
                        style: AppTextStyles.body2
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      if (data.alreadyRefunded > 0)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.warningLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.warning),
                          ),
                          child: Text(
                            '既返金: ¥${_fmt(data.alreadyRefunded)}  '
                            '残返金可能: ¥${_fmt(refundableMax)}',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.warning),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Action bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Text('返金アイテムを選択',
                          style: AppTextStyles.label
                              .copyWith(color: AppColors.textSecondary)),
                      const Spacer(),
                      // 全額返金 quick button
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        child: ElevatedButton.icon(
                          onPressed: isAllSelected
                              ? null
                              : () => setState(() {
                                    for (final item in data.items) {
                                      _selectedQty[item.id] = item.quantity;
                                    }
                                  }),
                          icon: Icon(
                            isAllSelected
                                ? Icons.check_circle
                                : Icons.select_all,
                            size: 16,
                          ),
                          label: Text(isAllSelected ? '全選択済' : '全額返金'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isAllSelected
                                ? AppColors.success
                                : AppColors.error,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _selectedQty.isEmpty
                            ? null
                            : () => setState(() => _selectedQty.clear()),
                        child: const Text('解除'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Item list (card style)
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: data.items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final item = data.items[i];
                      final qty = _selectedQty[item.id] ?? 0;
                      return _RefundItemCard(
                        item: item,
                        selectedQty: qty,
                        isChecked: qty > 0,
                        onToggle: () => setState(() {
                          if (qty > 0) {
                            _selectedQty.remove(item.id);
                          } else {
                            _selectedQty[item.id] = item.quantity;
                          }
                        }),
                        onQtyChanged: (v) =>
                            setState(() => _selectedQty[item.id] = v),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        const VerticalDivider(width: 1, color: AppColors.border),

        // ── 右: 返金設定 ──────────────────────────────────────────────────
        SizedBox(
          width: 300,
          child: Container(
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── ヘッダー ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.keyboard_return,
                            color: AppColors.error, size: 15),
                      ),
                      const SizedBox(width: 10),
                      Text('返金設定', style: AppTextStyles.h4),
                    ],
                  ),
                ),

                // ── コンテンツ (固定, スクロールなし) ───────────────────
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 返金額 + 元の支払方法 合体カード
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedAmt > 0
                                ? AppColors.errorLight
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedAmt > 0
                                  ? AppColors.error.withOpacity(0.4)
                                  : AppColors.border,
                            ),
                          ),
                          child: Column(
                            children: [
                              // 返金額
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('返金額',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary)),
                                  Text(
                                    '¥${_fmt(selectedAmt)}',
                                    style: AppTextStyles.priceMedium.copyWith(
                                      color: selectedAmt > 0
                                          ? AppColors.error
                                          : AppColors.textDisabled,
                                    ),
                                  ),
                                ],
                              ),
                              // 元の支払方法 (payments > 0の場合のみ)
                              if (data.payments.isNotEmpty) ...[
                                const Divider(height: 12),
                                ...data.payments.map((p) => Row(
                                  children: [
                                    Icon(_methodIcon(p.method),
                                        size: 13, color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(_methodLabel(p.method),
                                        style: AppTextStyles.caption.copyWith(
                                            color: AppColors.textSecondary)),
                                    const Spacer(),
                                    Text('¥${_fmt(p.amount)}',
                                        style: AppTextStyles.caption.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textSecondary)),
                                  ],
                                )),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 返金方法 — 3ボタン横並び
                        Text('返金方法',
                            style: AppTextStyles.label
                                .copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Row(
                          children: _refundMethods.asMap().entries.map((e) {
                            final i = e.key;
                            final m = e.value;
                            final isSelected = _refundMethod == m.key;
                            return Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(right: i < _refundMethods.length - 1 ? 6 : 0),
                                child: GestureDetector(
                                  onTap: () => setState(() => _refundMethod = m.key),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? m.color.withOpacity(0.08)
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected ? m.color : AppColors.border,
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(m.icon,
                                            size: 18,
                                            color: isSelected
                                                ? m.color
                                                : AppColors.textSecondary),
                                        const SizedBox(height: 4),
                                        Text(
                                          m.key == 'cash' ? '現金'
                                              : m.key == 'credit_card' ? 'カード'
                                              : '振込',
                                          style: AppTextStyles.caption.copyWith(
                                            color: isSelected
                                                ? m.color
                                                : AppColors.textSecondary,
                                            fontWeight: isSelected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 16),

                        // 返金理由
                        Text('返金理由',
                            style: AppTextStyles.label
                                .copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _reasons
                              .map((r) => _ReasonChip(
                                    label: r,
                                    icon: _reasonIcons[r] ?? Icons.more_horiz,
                                    isSelected: _reason == r,
                                    onTap: () => setState(() => _reason = r),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── 返金ボタン (下部固定) ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (selectedAmt > 0 &&
                              selectedAmt <= refundableMax &&
                              !_processing)
                          ? () => _executeRefund(
                                context: context,
                                data: data,
                                refundAmount: selectedAmt,
                              )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedAmt > 0
                            ? AppColors.error
                            : AppColors.border,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _processing
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.keyboard_return,
                                    color: Colors.white, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  selectedAmt > 0
                                      ? '¥${_fmt(selectedAmt)} 返金する'
                                      : 'アイテムを選択してください',
                                  style: AppTextStyles.button.copyWith(
                                    color: Colors.white,
                                    fontSize: selectedAmt > 0 ? 15 : 13,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _executeRefund({
    required BuildContext context,
    required _RefundData data,
    required int refundAmount,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, minWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.keyboard_return,
                          color: AppColors.error, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Text('払い戻しを実行しますか？',
                        style: AppTextStyles.h4),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.errorLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text('返金額',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('¥${_fmt(refundAmount)}',
                          style: AppTextStyles.price.copyWith(
                              color: AppColors.error, fontSize: 28)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('理由: $_reason',
                        style: AppTextStyles.body2
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('この操作は取り消せません。',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.error),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50)),
                        child: const Text('キャンセル'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('返金する',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _processing = true);
    try {
      final db = ref.read(databaseProvider);
      final refundId = _uuid.v4();
      final staffList = await db.activeStaff;
      final staffId =
          staffList.isNotEmpty ? staffList.first.id : 'staff-default';
      final sale = data.sale!;

      final refundNo =
          'R${DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '')}'
          '-${refundId.substring(0, 6).toUpperCase()}';

      final isFullRefund = refundAmount >= sale.totalAmount;

      await db.transaction(() async {
        await db.into(db.refunds).insert(RefundsCompanion.insert(
          id: refundId,
          originalSaleId: widget.saleId,
          staffId: staffId,
          refundNo: refundNo,
          refundType: isFullRefund ? 'full' : 'partial',
          refundAmount: refundAmount,
          reason: _reason,
        ));

        for (final entry in _selectedQty.entries) {
          await db.into(db.refundItems).insert(RefundItemsCompanion.insert(
            id: _uuid.v4(),
            refundId: refundId,
            saleItemId: entry.key,
            quantity: entry.value,
            refundAmount:
                _itemRefundAmt(data.items, entry.key, entry.value),
          ));
        }

        await db.into(db.refundPayments).insert(
            RefundPaymentsCompanion.insert(
          id: _uuid.v4(),
          refundId: refundId,
          method: _refundMethod,
          amount: refundAmount,
        ));

        await (db.update(db.sales)
              ..where((t) => t.id.equals(widget.saleId)))
            .write(SalesCompanion(
          status: Value(isFullRefund ? 'refunded' : 'partial_refund'),
        ));
      });

      if (!mounted) return;
      final ctx2 = context;
      // 再注文選択フラグ
      bool reorder = false;
      await showDialog(
        context: ctx2,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) => Dialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64, height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.successLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 36, color: AppColors.success),
                    ),
                    const SizedBox(height: 16),
                    Text('返金完了', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    Text('¥${_fmt(refundAmount)} を返金しました',
                        style: AppTextStyles.body2),
                    const SizedBox(height: 4),
                    Text('返金番号: $refundNo',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 20),
                    // ── 再注文オプション ──────────────────────────────────
                    InkWell(
                      onTap: () => setDlgState(() => reorder = !reorder),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: reorder ? AppColors.primaryLight : AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: reorder ? AppColors.primary : AppColors.border,
                            width: reorder ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: reorder ? AppColors.primary : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: reorder ? AppColors.primary : AppColors.border,
                                  width: 1.5,
                                ),
                              ),
                              child: reorder
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('返金商品を新しい注文に追加',
                                      style: AppTextStyles.body2.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: reorder ? AppColors.primary : AppColors.textPrimary)),
                                  Text('レジ画面のカートに返金商品を再追加します',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 10)),
                                ],
                              ),
                            ),
                            const Icon(Icons.add_shopping_cart_outlined,
                                size: 18, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                        },
                        child: Text(reorder ? 'カートに追加して閉じる' : '閉じる'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // 再注文 ON の場合: 返金したアイテムをカートに追加
      if (reorder && mounted) {
        final posNotifier = ref.read(posProvider.notifier);
        for (final entry in _selectedQty.entries) {
          final item = data.items.firstWhere(
            (i) => i.id == entry.key,
            orElse: () => data.items.first,
          );
          posNotifier.addRawItem(
            name: item.itemName,
            unitPrice: item.unitPrice,
            qty: entry.value,
            taxType: item.taxType,
          );
        }
        if (mounted) {
          showTopBanner(
            context,
            '${_selectedQty.length}件の商品をカートに追加しました',
            color: AppColors.primary,
            icon: Icons.add_shopping_cart_outlined,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      showTopBanner(context, '返金エラー: $e',
          color: AppColors.error, icon: Icons.error_outline);
      setState(() => _processing = false);
    }
  }

  int _itemRefundAmt(List<SaleItem> items, String itemId, int qty) {
    final item = items.firstWhere((i) => i.id == itemId);
    return item.totalPrice * qty ~/ item.quantity;
  }
}

// ─── アイテム選択カード ────────────────────────────────────────────────────
class _RefundItemCard extends StatelessWidget {
  const _RefundItemCard({
    required this.item,
    required this.selectedQty,
    required this.isChecked,
    required this.onToggle,
    required this.onQtyChanged,
  });
  final SaleItem item;
  final int selectedQty;
  final bool isChecked;
  final VoidCallback onToggle;
  final void Function(int) onQtyChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isChecked ? AppColors.errorLight : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isChecked
              ? AppColors.error.withOpacity(0.5)
              : AppColors.border,
          width: isChecked ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Check circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isChecked ? AppColors.error : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isChecked ? AppColors.error : AppColors.border,
                    width: 2,
                  ),
                ),
                child: isChecked
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight:
                            isChecked ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (item.quantity > 1)
                      Text('×${item.quantity}',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),

              Text('¥${_fmt(item.totalPrice)}',
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isChecked
                        ? AppColors.error
                        : AppColors.textPrimary,
                  )),

              // 数量セレクタ (複数個かつ選択済み)
              if (isChecked && item.quantity > 1) ...[
                const SizedBox(width: 12),
                _QtySelector(
                  value: selectedQty,
                  max: item.quantity,
                  onChanged: onQtyChanged,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 返金理由チップ ────────────────────────────────────────────────────────
class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? AppColors.primary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.label.copyWith(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: isSelected
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 数量セレクタ ──────────────────────────────────────────────────────────
class _QtySelector extends StatelessWidget {
  const _QtySelector(
      {required this.value, required this.max, required this.onChanged});
  final int value;
  final int max;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Btn(
          icon: Icons.remove,
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$value',
              style: AppTextStyles.label
                  .copyWith(fontWeight: FontWeight.w700)),
        ),
        _Btn(
          icon: Icons.add,
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: active
              ? AppColors.background
              : AppColors.background.withOpacity(0.5),
          border: Border.all(
            color: active ? AppColors.border : AppColors.textDisabled,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 14,
            color: active
                ? AppColors.textSecondary
                : AppColors.textDisabled),
      ),
    );
  }
}

// ─── ステータスチップ ──────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'completed' => ('完了', AppColors.success),
      'refunded' => ('全額返金済', AppColors.error),
      'partial_refund' => ('一部返金', AppColors.warning),
      'voided' => ('無効', AppColors.textDisabled),
      _ => (status, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ─── データ ────────────────────────────────────────────────────────────────
class _RefundData {
  const _RefundData({
    required this.sale,
    required this.items,
    required this.payments,
    required this.alreadyRefunded,
  });
  final Sale? sale;
  final List<SaleItem> items;
  final List<SalePayment> payments;
  final int alreadyRefunded;
}

// ─── ユーティリティ ────────────────────────────────────────────────────────
String _fmt(int n) {
  if (n < 0) return '-${_fmt(-n)}';
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
