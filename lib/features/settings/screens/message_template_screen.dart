import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── Provider ─────────────────────────────────────────────────────────────
final _allTemplatesProvider = StreamProvider<List<MessageTemplate>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.messageTemplates)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

// ─── 메인 화면 ────────────────────────────────────────────────────────────
class MessageTemplateScreen extends ConsumerWidget {
  const MessageTemplateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_allTemplatesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('メッセージテンプレート'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditSheet(context, ref, null),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (templates) => templates.isEmpty
            ? _buildEmpty(context, ref)
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: templates.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) =>
                    _TemplateTile(template: templates[i], onEdit: (t) => _showEditSheet(context, ref, t)),
              ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chat_bubble_outline,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          const Text('テンプレートがありません',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _showEditSheet(context, ref, null),
            icon: const Icon(Icons.add),
            label: const Text('テンプレートを追加'),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, MessageTemplate? tmpl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TemplateEditSheet(template: tmpl),
    );
  }
}

// ─── 템플릿 타일 ──────────────────────────────────────────────────────────
class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.template, required this.onEdit});
  final MessageTemplate template;
  final ValueChanged<MessageTemplate> onEdit;

  String _typeLabel(String type) => switch (type) {
        'reminder' => 'リマインダー',
        'followup' => 'フォロー',
        'birthday' => 'お誕生日',
        'reactivation' => '再来店',
        'campaign' => 'キャンペーン',
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: template.isActive
              ? AppColors.primaryLight
              : AppColors.border.withAlpha(60),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.chat_bubble_outline,
          color: template.isActive
              ? AppColors.primary
              : AppColors.textSecondary,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(template.name,
                style: AppTextStyles.body2
                    .copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _typeLabel(template.templateType),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          template.body,
          style:
              AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined,
            size: 18, color: AppColors.textSecondary),
        onPressed: () => onEdit(template),
      ),
      onTap: () => onEdit(template),
    );
  }
}

// ─── 편집 시트 ────────────────────────────────────────────────────────────
class _TemplateEditSheet extends ConsumerStatefulWidget {
  const _TemplateEditSheet({this.template});
  final MessageTemplate? template;

  @override
  ConsumerState<_TemplateEditSheet> createState() =>
      _TemplateEditSheetState();
}

class _TemplateEditSheetState extends ConsumerState<_TemplateEditSheet> {
  late final _nameCtrl =
      TextEditingController(text: widget.template?.name ?? '');
  late final _bodyCtrl =
      TextEditingController(text: widget.template?.body ?? '');
  late String _type =
      widget.template?.templateType ?? 'reminder';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (name.isEmpty || body.isEmpty) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      if (widget.template == null) {
        await db.into(db.messageTemplates).insert(
              MessageTemplatesCompanion.insert(
                id: const Uuid().v4(),
                name: name,
                templateType: _type,
                channel: 'line',
                body: body,
              ),
            );
      } else {
        await (db.update(db.messageTemplates)
              ..where((t) => t.id.equals(widget.template!.id)))
            .write(MessageTemplatesCompanion(
          name: Value(name),
          templateType: Value(_type),
          body: Value(body),
        ));
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('テンプレートを削除'),
        content: Text('「${widget.template!.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.messageTemplates)
          ..where((t) => t.id.equals(widget.template!.id)))
        .go();
    if (mounted) Navigator.pop(context);
  }

  static const _typeOptions = [
    ('reminder', 'リマインダー'),
    ('followup', 'フォロー'),
    ('birthday', 'お誕生日'),
    ('reactivation', '再来店'),
    ('campaign', 'キャンペーン'),
  ];

  static const _variables = [
    '{{customer_name}}',
    '{{date}}',
    '{{time}}',
    '{{staff_name}}',
    '{{days_since}}',
  ];

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
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
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
            child: Row(
              children: [
                Text(isEdit ? 'テンプレート編集' : 'テンプレート追加',
                    style: AppTextStyles.h4),
                const Spacer(),
                if (isEdit)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: AppColors.error, size: 20),
                    onPressed: _delete,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // テンプレート名
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'テンプレート名 *',
                      hintText: 'ご予約リマインダー',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // タイプ
                  Text('種別',
                      style: AppTextStyles.label
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _typeOptions.map((opt) {
                      final selected = _type == opt.$1;
                      return ChoiceChip(
                        label: Text(opt.$2),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _type = opt.$1),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // 変数ガイド
                  Text('使用できる変数',
                      style: AppTextStyles.label
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _variables
                        .map(
                          (v) => GestureDetector(
                            onTap: () {
                              final pos =
                                  _bodyCtrl.selection.base.offset;
                              if (pos < 0) {
                                _bodyCtrl.text += v;
                              } else {
                                final text = _bodyCtrl.text;
                                _bodyCtrl.text = text.substring(0, pos) +
                                    v +
                                    text.substring(pos);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F4FF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.primary.withAlpha(60)),
                              ),
                              child: Text(v,
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.primary,
                                    fontFamily: 'monospace',
                                  )),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  // 본문
                  TextField(
                    controller: _bodyCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'メッセージ本文 *',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(isEdit ? '保存' : '追加'),
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
}
