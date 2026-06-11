import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../core/widgets/top_banner.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final _plansProvider = StreamProvider<List<MembershipPlan>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.membershipPlans)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .watch();
});

// ─── Screen ──────────────────────────────────────────────────────────────────

class PrepaidPlanScreen extends ConsumerWidget {
  const PrepaidPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(_plansProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('回数券・プリペイドプラン'),
        backgroundColor: AppColors.surface,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => _showPlanSheet(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新規追加'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (plans) {
          if (plans.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_membership_outlined,
                      size: 64, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text('プランがありません',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _showPlanSheet(context, ref, null),
                    child: const Text('最初のプランを作成'),
                  ),
                ],
              ),
            );
          }

          final sessionPlans = plans.where((p) => p.planType == 'session').toList();
          final amountPlans = plans.where((p) => p.planType == 'amount').toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (sessionPlans.isNotEmpty) ...[
                _SectionLabel(label: '回数券（施術回数）', icon: Icons.repeat_outlined),
                const SizedBox(height: 8),
                ...sessionPlans.map((p) => _PlanCard(
                      plan: p,
                      onEdit: () => _showPlanSheet(context, ref, p),
                      onToggle: () => _toggleActive(context, ref, p),
                      onDelete: () => _confirmDelete(context, ref, p),
                    )),
                const SizedBox(height: 20),
              ],
              if (amountPlans.isNotEmpty) ...[
                _SectionLabel(label: 'プリペイド（金額）', icon: Icons.account_balance_wallet_outlined),
                const SizedBox(height: 8),
                ...amountPlans.map((p) => _PlanCard(
                      plan: p,
                      onEdit: () => _showPlanSheet(context, ref, p),
                      onToggle: () => _toggleActive(context, ref, p),
                      onDelete: () => _confirmDelete(context, ref, p),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showPlanSheet(BuildContext context, WidgetRef ref, MembershipPlan? plan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _PlanFormSheet(plan: plan),
      ),
    );
  }

  Future<void> _toggleActive(BuildContext context, WidgetRef ref, MembershipPlan plan) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.membershipPlans)..where((t) => t.id.equals(plan.id)))
        .write(MembershipPlansCompanion(isActive: Value(!plan.isActive)));
    if (context.mounted) {
      showTopBanner(
        context,
        plan.isActive ? '${plan.name} を無効にしました' : '${plan.name} を有効にしました',
        icon: Icons.check_circle_outline,
        color: AppColors.success,
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, MembershipPlan plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${plan.name}」を削除しますか？\n既存の顧客データには影響しません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final db = ref.read(databaseProvider);
      await (db.delete(db.membershipPlans)..where((t) => t.id.equals(plan.id))).go();
      if (context.mounted) {
        showTopBanner(context, '削除しました', icon: Icons.delete_outline, color: AppColors.error);
      }
    }
  }
}

// ─── Plan Card ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final MembershipPlan plan;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isSession = plan.planType == 'session';
    final color = isSession ? const Color(0xFF6366F1) : const Color(0xFF0EA5E9);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: plan.isActive
              ? color.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Opacity(
        opacity: plan.isActive ? 1.0 : 0.6,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSession ? Icons.repeat_outlined : Icons.account_balance_wallet_outlined,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(plan.name,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        if (!plan.isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('無効',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '¥${_fmt(plan.price)}',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: color),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _subtitle(plan),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (plan.discountRate > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('${plan.discountRate}% OFF',
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    if (plan.description != null && plan.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(plan.description!,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'toggle') onToggle();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('編集')),
                  PopupMenuItem(
                      value: 'toggle',
                      child: Text(plan.isActive ? '無効にする' : '有効にする')),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Text('削除', style: TextStyle(color: AppColors.error))),
                ],
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(MembershipPlan plan) {
    if (plan.planType == 'session') {
      return '${plan.totalSessions ?? "?"}回';
    } else {
      return '残高 ¥${_fmt(plan.totalAmount ?? 0)}';
    }
  }

  String _fmt(int v) {
    // 3자리마다 콤마
    return v.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                letterSpacing: 0.3)),
      ],
    );
  }
}

// ─── Plan Form Sheet ──────────────────────────────────────────────────────────

class _PlanFormSheet extends ConsumerStatefulWidget {
  const _PlanFormSheet({this.plan});
  final MembershipPlan? plan;

  @override
  ConsumerState<_PlanFormSheet> createState() => _PlanFormSheetState();
}

class _PlanFormSheetState extends ConsumerState<_PlanFormSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _sessionsCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  String _planType = 'session';
  bool _saving = false;
  bool _nameError = false;
  bool _priceError = false;
  bool _detailError = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    if (p != null) {
      _nameCtrl.text = p.name;
      _descCtrl.text = p.description ?? '';
      _priceCtrl.text = p.price.toString();
      _planType = p.planType;
      _sessionsCtrl.text = p.totalSessions?.toString() ?? '';
      _amountCtrl.text = p.totalAmount?.toString() ?? '';
      _discountCtrl.text = p.discountRate > 0 ? p.discountRate.toString() : '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _sessionsCtrl.dispose();
    _amountCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text.trim());
    final sessions = int.tryParse(_sessionsCtrl.text.trim());
    final amount = int.tryParse(_amountCtrl.text.trim());
    final discount = int.tryParse(_discountCtrl.text.trim()) ?? 0;

    final nameErr = name.isEmpty;
    final priceErr = price == null || price < 0;
    final detailErr =
        (_planType == 'session' && sessions == null) ||
        (_planType == 'amount' && amount == null);

    if (nameErr || priceErr || detailErr) {
      setState(() {
        _nameError = nameErr;
        _priceError = priceErr;
        _detailError = detailErr;
      });
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final companion = MembershipPlansCompanion(
        id: widget.plan != null ? Value(widget.plan!.id) : Value(const Uuid().v4()),
        name: Value(name),
        description: Value(_descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim()),
        planType: Value(_planType),
        price: Value(price),
        totalSessions: Value(_planType == 'session' ? sessions : null),
        totalAmount: Value(_planType == 'amount' ? amount : null),
        discountRate: Value(discount.clamp(0, 100)),
        isActive: const Value(true),
      );

      if (widget.plan != null) {
        await (db.update(db.membershipPlans)
              ..where((t) => t.id.equals(widget.plan!.id)))
            .write(companion);
      } else {
        await db.into(db.membershipPlans).insert(companion);
      }

      if (mounted) Navigator.pop(context);
      if (mounted) {
        showTopBanner(
          context,
          widget.plan != null ? '更新しました' : 'プランを作成しました',
          icon: Icons.check_circle_outline,
          color: AppColors.success,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  widget.plan != null ? 'プランを編集' : '新規プランを作成',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 16),

            // プランタイプ
            const Text('プランタイプ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'session',
                    icon: Icon(Icons.repeat_outlined, size: 16),
                    label: Text('回数券')),
                ButtonSegment(
                    value: 'amount',
                    icon: Icon(Icons.account_balance_wallet_outlined, size: 16),
                    label: Text('プリペイド')),
              ],
              selected: {_planType},
              onSelectionChanged: (v) => setState(() {
                _planType = v.first;
                _detailError = false;
              }),
            ),
            const SizedBox(height: 16),

            // 프란 이름
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'プラン名 *',
                hintText: _planType == 'session' ? 'カラー10回券' : 'プリペイド ¥50,000',
                errorText: _nameError ? 'プラン名を入力してください' : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_nameError) setState(() => _nameError = false);
              },
            ),
            const SizedBox(height: 12),

            // 金額 + 回数/残高
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '販売価格 * (¥)',
                      errorText: _priceError ? '価格を入力' : null,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (_priceError) setState(() => _priceError = false);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _planType == 'session'
                      ? TextField(
                          controller: _sessionsCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: '施術回数 *',
                            suffixText: '回',
                            errorText: _detailError ? '回数を入力' : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (_detailError) setState(() => _detailError = false);
                          },
                        )
                      : TextField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'チャージ金額 * (¥)',
                            errorText: _detailError ? '金額を入力' : null,
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) {
                            if (_detailError) setState(() => _detailError = false);
                          },
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 할인율 + 설명
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '割引率 (%)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'メモ（任意）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(widget.plan != null ? '更新する' : 'プランを作成',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
