import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── Provider ─────────────────────────────────────────────────────────────
final loyaltyTiersProvider = StreamProvider<List<LoyaltyTier>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.loyaltyTiers)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── ロイヤルティランク管理画面 ─────────────────────────────────────────────
class LoyaltyTiersScreen extends ConsumerWidget {
  const LoyaltyTiersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersAsync = ref.watch(loyaltyTiersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('会員ランク管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'ランク追加',
            onPressed: () => _showForm(context, null),
          ),
        ],
      ),
      body: tiersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (tiers) {
          if (tiers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.loyalty_outlined,
                      size: 56, color: AppColors.textDisabled),
                  const SizedBox(height: 16),
                  Text('会員ランクがありません',
                      style: AppTextStyles.body1
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text('ブロンズ・シルバー・ゴールド・プラチナなど\n累計支出に応じた自動ランクアップを設定',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showForm(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('最初のランクを作成'),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              // 説明バナー
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                      color: AppColors.primary.withAlpha(40)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '顧客の累計支出額に応じて自動でランクが付与されます。\nポイント倍率・割引率はランクごとに設定できます。',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: tiers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TierCard(
                    tier: tiers[i],
                    onEdit: () => _showForm(context, tiers[i]),
                    onDelete: () =>
                        _confirmDelete(context, ref, tiers[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, LoyaltyTier tier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ランクを削除'),
        content: Text('「${tier.nameJp ?? tier.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      final db = ref.read(databaseProvider);
      await (db.delete(db.loyaltyTiers)
            ..where((t) => t.id.equals(tier.id)))
          .go();
    }
  }

  void _showForm(BuildContext context, LoyaltyTier? tier) {
    showDialog(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(width: 580, child: _TierFormSheet(tier: tier)),
        ),
      ),
    );
  }
}

// ─── ランクカード ──────────────────────────────────────────────────────────
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.onEdit,
    required this.onDelete,
  });
  final LoyaltyTier tier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color _parseColor(String hex) {
    try {
      final v = hex.replaceFirst('#', '');
      return Color(int.parse('FF$v', radix: 16));
    } catch (_) {
      return AppColors.warning;
    }
  }

  String _fmtAmount(int n) {
    if (n == 0) return '¥0〜';
    final s = n.toString();
    final buf = StringBuffer('¥');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    buf.write('〜');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(tier.color);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            shape: BoxShape.circle,
            border: Border.all(color: color.withAlpha(80)),
          ),
          child: Center(
            child: Icon(Icons.military_tech_outlined,
                color: color, size: 22),
          ),
        ),
        title: Row(
          children: [
            Text(
              tier.nameJp ?? tier.name,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _fmtAmount(tier.minAmount),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 12,
            children: [
              _Badge(
                  icon: Icons.stars_outlined,
                  label: 'ポイント×${tier.pointRateMultiplier}',
                  color: AppColors.warning),
              if (tier.discountRate > 0)
                _Badge(
                    icon: Icons.discount_outlined,
                    label: '${tier.discountRate}%割引',
                    color: AppColors.success),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              size: 18, color: AppColors.textSecondary),
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('編集')),
            const PopupMenuItem(
              value: 'delete',
              child:
                  Text('削除', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─── ランクフォームシート ─────────────────────────────────────────────────
class _TierFormSheet extends ConsumerStatefulWidget {
  const _TierFormSheet({this.tier});
  final LoyaltyTier? tier;

  @override
  ConsumerState<_TierFormSheet> createState() => _TierFormSheetState();
}

class _TierFormSheetState extends ConsumerState<_TierFormSheet> {
  final _nameCtrl = TextEditingController();
  final _nameJpCtrl = TextEditingController();
  final _minAmountCtrl = TextEditingController();
  int _pointMultiplier = 1;
  int _discountRate = 0;
  String _colorHex = '#CD7F32'; // Bronze

  final _presetColors = const [
    ('#CD7F32', 'ブロンズ'),
    ('#C0C0C0', 'シルバー'),
    ('#FFD700', 'ゴールド'),
    ('#E5E4E2', 'プラチナ'),
    ('#6366F1', 'インディゴ'),
    ('#EC4899', 'ピンク'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.tier != null) {
      final t = widget.tier!;
      _nameCtrl.text = t.name;
      _nameJpCtrl.text = t.nameJp ?? '';
      _minAmountCtrl.text = t.minAmount.toString();
      _pointMultiplier = t.pointRateMultiplier;
      _discountRate = t.discountRate;
      _colorHex = t.color;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameJpCtrl.dispose();
    _minAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    const uuid = Uuid();
    final minAmount =
        int.tryParse(_minAmountCtrl.text.replaceAll(',', '')) ?? 0;

    if (widget.tier == null) {
      // 既存件数をsortOrderに
      final count =
          await db.select(db.loyaltyTiers).get().then((l) => l.length);
      await db.into(db.loyaltyTiers).insert(LoyaltyTiersCompanion.insert(
        id: uuid.v4(),
        name: _nameCtrl.text.trim(),
        nameJp: Value(_nameJpCtrl.text.trim().isEmpty
            ? null
            : _nameJpCtrl.text.trim()),
        minAmount: Value(minAmount),
        pointRateMultiplier: Value(_pointMultiplier),
        discountRate: Value(_discountRate),
        color: Value(_colorHex),
        sortOrder: Value(count),
      ));
    } else {
      await (db.update(db.loyaltyTiers)
            ..where((t) => t.id.equals(widget.tier!.id)))
          .write(LoyaltyTiersCompanion(
        name: Value(_nameCtrl.text.trim()),
        nameJp: Value(_nameJpCtrl.text.trim().isEmpty
            ? null
            : _nameJpCtrl.text.trim()),
        minAmount: Value(minAmount),
        pointRateMultiplier: Value(_pointMultiplier),
        discountRate: Value(_discountRate),
        color: Value(_colorHex),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  Color _parseColor(String hex) {
    try {
      final v = hex.replaceFirst('#', '');
      return Color(int.parse('FF$v', radix: 16));
    } catch (_) {
      return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = _parseColor(_colorHex);

    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  widget.tier == null ? 'ランク追加' : 'ランク編集',
                  style: AppTextStyles.h3,
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ランク名
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ランク名（英語）', style: AppTextStyles.label),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _nameCtrl,
                              decoration: InputDecoration(
                                hintText: 'Bronze',
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ランク名（日本語）', style: AppTextStyles.label),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _nameJpCtrl,
                              decoration: InputDecoration(
                                hintText: 'ブロンズ',
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // カラー選択
                  Text('ランクカラー', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: _presetColors.map((c) {
                      final color = _parseColor(c.$1);
                      final selected = _colorHex == c.$1;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _colorHex = c.$1),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(
                                    color: Colors.black, width: 2)
                                : Border.all(
                                    color: color.withAlpha(80)),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                        color: color.withAlpha(100),
                                        blurRadius: 6)
                                  ]
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 20)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 最低累計支出
                  Text('適用条件（累計支出）', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _minAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      prefixText: '¥',
                      hintText: '50000',
                      helperText: 'この金額以上の累計支出でランクが付与されます',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ポイント倍率
                  Row(
                    children: [
                      Text('ポイント倍率', style: AppTextStyles.label),
                      const Spacer(),
                      Text('×$_pointMultiplier',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selectedColor)),
                    ],
                  ),
                  TextFormField(
                    initialValue: _pointMultiplier > 0 ? _pointMultiplier.toString() : '',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '1',
                      suffixText: '倍',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() {
                      _pointMultiplier = int.tryParse(v.trim()) ?? 1;
                      if (_pointMultiplier < 1) _pointMultiplier = 1;
                      if (_pointMultiplier > 10) _pointMultiplier = 10;
                    }),
                  ),
                  const SizedBox(height: 16),

                  // 割引率
                  Row(
                    children: [
                      Text('メンバー割引率', style: AppTextStyles.label),
                      const Spacer(),
                      Text('$_discountRate%',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selectedColor)),
                    ],
                  ),
                  TextFormField(
                    initialValue: _discountRate > 0 ? _discountRate.toString() : '',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: '%',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() {
                      _discountRate = int.tryParse(v.trim()) ?? 0;
                      if (_discountRate < 0) _discountRate = 0;
                      if (_discountRate > 30) _discountRate = 30;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
    );
  }
}
