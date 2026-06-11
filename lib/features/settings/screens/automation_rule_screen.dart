import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── Providers ─────────────────────────────────────────────────────────────
final _rulesProvider = StreamProvider<List<AutomationRule>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.automationRules)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .watch();
});

final _templatesForRulesProvider =
    FutureProvider<List<MessageTemplate>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.messageTemplates)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
});

// ─── 自動化ルール画面 ────────────────────────────────────────────────────
class AutomationRuleScreen extends ConsumerWidget {
  const AutomationRuleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(_rulesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settings),
        ),
        title: const Text('自動化ルール'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'ルール追加',
            onPressed: () => _showForm(context, ref, null),
          ),
        ],
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (rules) {
          if (rules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome_outlined,
                      size: 56, color: AppColors.textDisabled),
                  const SizedBox(height: 16),
                  Text('自動化ルールがありません',
                      style: AppTextStyles.body1
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text('来店後・誕生日・長期未来店など\nトリガー別に自動メッセージを設定できます',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showForm(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('最初のルールを作成'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _RuleCard(
              rule: rules[i],
              onEdit: () => _showForm(context, ref, rules[i]),
              onToggle: () => _toggleActive(ref, rules[i]),
              onDelete: () => _confirmDelete(context, ref, rules[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleActive(WidgetRef ref, AutomationRule rule) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.automationRules)..where((t) => t.id.equals(rule.id)))
        .write(AutomationRulesCompanion(isActive: Value(!rule.isActive)));
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AutomationRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ルールを削除'),
        content: Text('「${rule.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('削除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      final db = ref.read(databaseProvider);
      await (db.delete(db.automationRules)
            ..where((t) => t.id.equals(rule.id)))
          .go();
    }
  }

  void _showForm(BuildContext context, WidgetRef ref, AutomationRule? rule) {
    showDialog(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(width: 580, child: _RuleFormSheet(rule: rule)),
        ),
      ),
    );
  }
}

// ─── ルールカード ──────────────────────────────────────────────────────────
class _RuleCard extends ConsumerWidget {
  const _RuleCard({
    required this.rule,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });
  final AutomationRule rule;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  String _triggerLabel(String trigger) {
    switch (trigger) {
      case 'after_visit': return '来店後';
      case 'before_appointment': return '予約前日';
      case 'birthday': return '誕生日当日';
      case 'no_visit_90d': return '90日未来店';
      default: return trigger;
    }
  }

  IconData _triggerIcon(String trigger) {
    switch (trigger) {
      case 'after_visit': return Icons.celebration_outlined;
      case 'before_appointment': return Icons.event_outlined;
      case 'birthday': return Icons.cake_outlined;
      case 'no_visit_90d': return Icons.hourglass_empty_outlined;
      default: return Icons.auto_awesome_outlined;
    }
  }

  Color _triggerColor(String trigger) {
    switch (trigger) {
      case 'after_visit': return AppColors.success;
      case 'before_appointment': return AppColors.primary;
      case 'birthday': return AppColors.warning;
      case 'no_visit_90d': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _triggerColor(rule.trigger);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: rule.isActive ? color.withAlpha(80) : AppColors.border,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Icon(_triggerIcon(rule.trigger), color: color, size: 20),
        ),
        title: Row(
          children: [
            Text(rule.name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_triggerLabel(rule.trigger),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(Icons.schedule, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                rule.delayHours == 0
                    ? 'トリガー直後'
                    : rule.delayHours < 24
                        ? '${rule.delayHours}時間後'
                        : '${rule.delayHours ~/ 24}日後',
                style: AppTextStyles.caption,
              ),
              const SizedBox(width: 12),
              Icon(Icons.send_outlined, size: 12, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(rule.channel.toUpperCase(),
                  style: AppTextStyles.caption),
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: rule.isActive,
              onChanged: (_) => onToggle(),
              activeColor: color,
            ),
            PopupMenuButton<String>(
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
                  child: Text('削除', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ルールフォームシート ──────────────────────────────────────────────────
class _RuleFormSheet extends ConsumerStatefulWidget {
  const _RuleFormSheet({this.rule});
  final AutomationRule? rule;

  @override
  ConsumerState<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends ConsumerState<_RuleFormSheet> {
  final _nameCtrl = TextEditingController();
  String _trigger = 'after_visit';
  int _delayHours = 24;
  String _channel = 'line';
  String? _templateId;
  bool _isActive = true;

  final _triggers = const [
    ('after_visit', '来店後'),
    ('before_appointment', '予約前日'),
    ('birthday', '誕生日当日'),
    ('no_visit_90d', '90日未来店'),
  ];

  final _channels = const [
    ('line', 'LINE'),
    ('sms', 'SMS'),
    ('email', 'メール'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.rule != null) {
      final r = widget.rule!;
      _nameCtrl.text = r.name;
      _trigger = r.trigger;
      _delayHours = r.delayHours;
      _channel = r.channel;
      _templateId = r.templateId;
      _isActive = r.isActive;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _templateId == null) return;
    final db = ref.read(databaseProvider);
    const uuid = Uuid();
    if (widget.rule == null) {
      await db.into(db.automationRules).insert(AutomationRulesCompanion.insert(
        id: uuid.v4(),
        name: _nameCtrl.text.trim(),
        trigger: _trigger,
        delayHours: Value(_delayHours),
        templateId: _templateId!,
        channel: _channel,
        isActive: Value(_isActive),
      ));
    } else {
      await (db.update(db.automationRules)
            ..where((t) => t.id.equals(widget.rule!.id)))
          .write(AutomationRulesCompanion(
        name: Value(_nameCtrl.text.trim()),
        trigger: Value(_trigger),
        delayHours: Value(_delayHours),
        templateId: Value(_templateId!),
        channel: Value(_channel),
        isActive: Value(_isActive),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(_templatesForRulesProvider);

    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  widget.rule == null ? '自動化ルール追加' : 'ルール編集',
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
                  // ルール名
                  Text('ルール名', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: '例: 来店後サンクスメッセージ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // トリガー
                  Text('トリガー', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _triggers.map((t) {
                      final selected = _trigger == t.$1;
                      return ChoiceChip(
                        label: Text(t.$2),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _trigger = t.$1),
                        selectedColor:
                            AppColors.primary.withAlpha(40),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // 遅延時間
                  Row(
                    children: [
                      Text('遅延時間', style: AppTextStyles.label),
                      const Spacer(),
                      Text(
                        _delayHours == 0
                            ? '即時'
                            : _delayHours < 24
                                ? '$_delayHours時間後'
                                : '${_delayHours ~/ 24}日後',
                        style: AppTextStyles.body2.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  TextFormField(
                    initialValue: _delayHours > 0 ? _delayHours.toString() : '',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '0',
                      suffixText: '時間',
                      helperText: '0〜168時間（7日）',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => setState(() {
                      _delayHours = int.tryParse(v.trim()) ?? 0;
                      if (_delayHours < 0) _delayHours = 0;
                      if (_delayHours > 168) _delayHours = 168;
                    }),
                  ),
                  const SizedBox(height: 20),

                  // チャンネル
                  Text('送信チャンネル', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _channels.map((c) {
                      final selected = _channel == c.$1;
                      return ChoiceChip(
                        label: Text(c.$2),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _channel = c.$1),
                        selectedColor:
                            AppColors.primary.withAlpha(40),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // テンプレート
                  Text('メッセージテンプレート', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  templatesAsync.when(
                    loading: () =>
                        const CircularProgressIndicator(),
                    error: (_, __) =>
                        const Text('テンプレートの読み込みに失敗'),
                    data: (templates) {
                      if (templates.isEmpty) {
                        return Text(
                          'テンプレートがありません。先に設定→メッセージテンプレートで作成してください。',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary),
                        );
                      }
                      return DropdownButtonFormField<String>(
                        value: _templateId,
                        hint: const Text('テンプレートを選択'),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        items: templates
                            .map((t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(t.name,
                                      overflow:
                                          TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _templateId = v),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // 有効/無効
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ルールを有効にする'),
                    subtitle: Text(
                      _isActive ? '自動送信が有効です' : '自動送信は停止中です',
                      style: AppTextStyles.caption,
                    ),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeColor: AppColors.success,
                  ),
                ],
              ),
            ),
          ),
        ],
    );
  }
}
