import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../core/widgets/top_banner.dart';

// ─── Data class ──────────────────────────────────────────────────────────────

class _CreditAccountWithCustomer {
  final CreditAccount account;
  final Customer customer;

  const _CreditAccountWithCustomer(this.account, this.customer);
}

// ─── Providers ───────────────────────────────────────────────────────────────

final _creditAccountsProvider =
    StreamProvider<List<_CreditAccountWithCustomer>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .select(db.creditAccounts)
      .join([
        innerJoin(
            db.customers, db.customers.id.equalsExp(db.creditAccounts.customerId))
      ])
      .watch()
      .map((rows) => rows.map((row) {
            return _CreditAccountWithCustomer(
              row.readTable(db.creditAccounts),
              row.readTable(db.customers),
            );
          }).toList()
            ..sort((a, b) => b.account.balance.compareTo(a.account.balance)));
});

final _txProvider = StreamProvider.family<List<CreditTransaction>, String>((ref, accountId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.creditTransactions)
        ..where((t) => t.accountId.equals(accountId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(30))
      .watch();
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class CreditManagementScreen extends ConsumerWidget {
  const CreditManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(_creditAccountsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('掛け売り管理'),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (accounts) {
          final activeAccounts =
              accounts.where((a) => a.account.balance > 0).toList();
          final totalBalance =
              activeAccounts.fold(0, (s, a) => s + a.account.balance);

          return Column(
            children: [
              // 요약 헤더
              if (accounts.isNotEmpty)
                Container(
                  color: AppColors.surface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    children: [
                      _StatChip(
                        label: '掛け売り顧客',
                        value: '${accounts.length}名',
                        color: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 12),
                      _StatChip(
                        label: '未収合計',
                        value: '¥${_fmt(totalBalance)}',
                        color: AppColors.error,
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),

              // 목록
              Expanded(
                child: accounts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                size: 64,
                                color: AppColors.textSecondary
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            const Text('掛け売り顧客がいません',
                                style: TextStyle(
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: 8),
                            const Text(
                              '会計画面で「掛け売り」決済を選択すると\nここに顧客が追加されます',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: accounts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _AccountCard(
                          item: accounts[i],
                          onTap: () => _showDetail(ctx, ref, accounts[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDetail(
      BuildContext context, WidgetRef ref, _CreditAccountWithCustomer item) {
    showDialog(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: _AccountDetailSheet(item: item),
        ),
      ),
    );
  }
}

// ─── Account Card ─────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.item, required this.onTap});
  final _CreditAccountWithCustomer item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSuspended = item.account.status == 'suspended';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSuspended
              ? Colors.grey.withValues(alpha: 0.2)
              : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                radius: 22,
                child: Text(
                  item.customer.name.isNotEmpty
                      ? item.customer.name[0]
                      : '?',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(item.customer.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        if (isSuspended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('停止中',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.customer.phone ?? '',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '¥${_fmt(item.account.balance)}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: item.account.balance > 0
                          ? AppColors.error
                          : AppColors.success,
                    ),
                  ),
                  const Text('未収',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Account Detail Sheet ─────────────────────────────────────────────────────

class _AccountDetailSheet extends ConsumerStatefulWidget {
  const _AccountDetailSheet({required this.item});
  final _CreditAccountWithCustomer item;

  @override
  ConsumerState<_AccountDetailSheet> createState() =>
      _AccountDetailSheetState();
}

class _AccountDetailSheetState extends ConsumerState<_AccountDetailSheet> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _processing = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _recordPayment() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showTopBanner(context, '金額を正しく入力してください',
          icon: Icons.warning_rounded, color: AppColors.error);
      return;
    }

    setState(() => _processing = true);
    try {
      final db = ref.read(databaseProvider);
      final account = widget.item.account;
      final newBalance = (account.balance - amount).clamp(0, account.balance);

      await db.transaction(() async {
        // 거래 이력 기록
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
        // 잔액 업데이트
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
    final txAsync = ref.watch(_txProvider(widget.item.account.id));

    return SizedBox(
      width: 560,
      height: 480,
      child: Column(
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.item.customer.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(widget.item.customer.phone ?? '',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '¥${_fmt(widget.item.account.balance)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: widget.item.account.balance > 0
                            ? AppColors.error
                            : AppColors.success,
                      ),
                    ),
                    const Text('未収残高',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
          ),
          const Divider(height: 1),

          // 수납 폼
          if (widget.item.account.balance > 0)
            Container(
              padding: const EdgeInsets.all(16),
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
                  SizedBox(
                    width: 80,
                    child: ElevatedButton(
                      onPressed: _processing ? null : _recordPayment,
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
                  ),
                ],
              ),
            ),
          const Divider(height: 1),

          // 거래 이력
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: const [
                Text('取引履歴',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: txAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('エラー: $e')),
              data: (txList) {
                if (txList.isEmpty) {
                  return const Center(
                      child: Text('履歴がありません',
                          style: TextStyle(color: AppColors.textSecondary)));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  itemCount: txList.length,
                  itemBuilder: (ctx, i) => _TxRow(tx: txList[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});
  final CreditTransaction tx;

  @override
  Widget build(BuildContext context) {
    final isCharge = tx.txType == 'charge';
    final isPayment = tx.txType == 'payment';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCharge
                  ? AppColors.error.withValues(alpha: 0.1)
                  : isPayment
                      ? AppColors.success.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCharge
                  ? Icons.arrow_upward_rounded
                  : isPayment
                      ? Icons.arrow_downward_rounded
                      : Icons.tune,
              size: 16,
              color: isCharge
                  ? AppColors.error
                  : isPayment
                      ? AppColors.success
                      : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCharge
                      ? '掛け売り発生'
                      : isPayment
                          ? '収納'
                          : '手動調整',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (tx.notes != null && tx.notes!.isNotEmpty)
                  Text(tx.notes!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${tx.amount > 0 ? '+' : ''}¥${_fmt(tx.amount.abs())}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: tx.amount > 0 ? AppColors.error : AppColors.success,
                ),
              ),
              Text(
                _shortDate(tx.createdAt),
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(5, 16) : iso;
    }
  }
}

// ─── Stat Chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

String _fmt(int v) => v.abs().toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
