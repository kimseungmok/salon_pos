import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── KPI 목표 목록 Provider ────────────────────────────────────────────────
final kpiTargetListProvider = StreamProvider<List<KpiTarget>>((ref) {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final yearMonth =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';
  return (db.select(db.kpiTargets)
        ..where((t) => t.yearMonth.equals(yearMonth) & t.staffId.isNull())
        ..orderBy([(t) => OrderingTerm.asc(t.targetType)]))
      .watch();
});

// ─── KPI目標設定 화면 ─────────────────────────────────────────────────────
class KpiSettingsScreen extends ConsumerStatefulWidget {
  const KpiSettingsScreen({super.key});

  @override
  ConsumerState<KpiSettingsScreen> createState() => _KpiSettingsScreenState();
}

class _KpiSettingsScreenState extends ConsumerState<KpiSettingsScreen> {
  // 현재 月 (YYYY-MM)
  late String _yearMonth;
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _yearMonth = '${_year}-${_month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final kpisAsync = ref.watch(kpiTargetListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('KPI目標設定'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.bar_chart_outlined, size: 16),
            label: const Text('レポートで確認'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(context);
              context.go(AppRoutes.reports);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('目標を追加'),
              onPressed: () => _showAddDialog(context),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 月選択
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                    _month--;
                    if (_month < 1) { _month = 12; _year--; }
                    _yearMonth = '${_year}-${_month.toString().padLeft(2, '0')}';
                  }),
                ),
                Expanded(
                  child: Center(
                    child: Text('${_year}年${_month}月',
                        style: AppTextStyles.h4),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                    _month++;
                    if (_month > 12) { _month = 1; _year++; }
                    _yearMonth = '${_year}-${_month.toString().padLeft(2, '0')}';
                  }),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: kpisAsync.when(
              data: (kpis) => kpis.isEmpty
                  ? _EmptyState(onAdd: () => _showAddDialog(context))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: kpis.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _KpiTile(
                        kpi: kpis[i],
                        onEdit: () => _showAddDialog(context, existing: kpis[i]),
                        onDelete: () => _delete(kpis[i].id),
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context,
      {KpiTarget? existing}) async {
    await showDialog(
      context: context,
      builder: (_) => _KpiFormDialog(
        yearMonth: _yearMonth,
        existing: existing,
      ),
    );
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('目標を削除'),
        content: const Text('この目標を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final db = ref.read(databaseProvider);
      await (db.delete(db.kpiTargets)..where((t) => t.id.equals(id))).go();
      if (mounted) {
        showTopBanner(context, '目標を削除しました',
            color: AppColors.success, icon: Icons.check_circle_outline);
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    }
  }
}

// ─── KPI 타일 ─────────────────────────────────────────────────────────────
class _KpiTile extends StatelessWidget {
  const _KpiTile(
      {required this.kpi, required this.onEdit, required this.onDelete});
  final KpiTarget kpi;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _typeLabels = {
    'sales': '月間売上目標',
    'customer_count': '来店客数目標',
    'new_customer': '新規顧客目標',
    'repeat_rate': 'リピート率目標',
    'avg_unit': '客単価目標',
  };
  static const _typeUnits = {
    'sales': '¥',
    'customer_count': '人',
    'new_customer': '人',
    'repeat_rate': '%',
    'avg_unit': '¥',
  };
  static const _typeIcons = {
    'sales': Icons.monetization_on_outlined,
    'customer_count': Icons.people_outline,
    'new_customer': Icons.person_add_outlined,
    'repeat_rate': Icons.repeat_outlined,
    'avg_unit': Icons.trending_up_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final label = _typeLabels[kpi.targetType] ?? kpi.targetType;
    final unit = _typeUnits[kpi.targetType] ?? '';
    final icon = _typeIcons[kpi.targetType] ?? Icons.flag_outlined;
    final isYen = unit == '¥';
    final valueText = isYen ? '$unit${_fmt(kpi.targetValue)}' : '${_fmt(kpi.targetValue)}$unit';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        title: Text(label, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(valueText,
            style: AppTextStyles.body1.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w700)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
              color: AppColors.textSecondary,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
              color: AppColors.error,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── KPI 목표 추가/수정 다이얼로그 ───────────────────────────────────────
class _KpiFormDialog extends ConsumerStatefulWidget {
  const _KpiFormDialog({required this.yearMonth, this.existing});
  final String yearMonth;
  final KpiTarget? existing;

  @override
  ConsumerState<_KpiFormDialog> createState() => _KpiFormDialogState();
}

class _KpiFormDialogState extends ConsumerState<_KpiFormDialog> {
  final _valueCtrl = TextEditingController();
  String _targetType = 'sales';
  bool _saving = false;

  static const _types = [
    ('sales', '月間売上目標', '¥'),
    ('customer_count', '来店客数目標', '人'),
    ('new_customer', '新規顧客目標', '人'),
    ('repeat_rate', 'リピート率目標', '%'),
    ('avg_unit', '客単価目標', '¥'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _targetType = widget.existing!.targetType;
      _valueCtrl.text = widget.existing!.targetValue.toString();
    }
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unit = _types.firstWhere((t) => t.$1 == _targetType).$3;

    return AlertDialog(
      title: Text(widget.existing != null ? 'KPI目標を編集' : 'KPI目標を追加'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 목표 타입 선택
          DropdownButtonFormField<String>(
            value: _targetType,
            decoration: const InputDecoration(labelText: '目標の種類'),
            items: _types.map((t) => DropdownMenuItem(
                value: t.$1,
                child: Text(t.$2))).toList(),
            onChanged: (v) {
              if (v != null) setState(() => _targetType = v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _valueCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '目標値',
              prefixText: unit == '¥' ? unit : null,
              suffixText: unit != '¥' ? unit : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final value = int.tryParse(_valueCtrl.text.replaceAll(',', ''));
    if (value == null || value <= 0) {
      showTopBanner(context, '正しい目標値を入力してください',
          color: AppColors.error, icon: Icons.error_outline);
      return;
    }
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      if (widget.existing != null) {
        await (db.update(db.kpiTargets)
              ..where((t) => t.id.equals(widget.existing!.id)))
            .write(KpiTargetsCompanion(
          targetType: Value(_targetType),
          targetValue: Value(value),
        ));
      } else {
        await db.into(db.kpiTargets).insert(KpiTargetsCompanion.insert(
          id: const Uuid().v4(),
          yearMonth: widget.yearMonth,
          targetType: _targetType,
          targetValue: value,
        ));
      }
      if (mounted) {
        Navigator.pop(context);
        showTopBanner(context, 'KPI目標を保存しました',
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

// ─── 빈 상태 ─────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_outlined, size: 48, color: AppColors.border),
          const SizedBox(height: 16),
          Text('今月のKPI目標が設定されていません',
              style: AppTextStyles.body2
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('目標を追加'),
            onPressed: onAdd,
          ),
        ],
      ),
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
