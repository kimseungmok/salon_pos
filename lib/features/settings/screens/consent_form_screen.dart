import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── Provider ─────────────────────────────────────────────────────────────
final consentFormsProvider = StreamProvider<List<ConsentFormTemplate>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.consentFormTemplates)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── 施術同意書テンプレート管理 ─────────────────────────────────────────────
class ConsentFormScreen extends ConsumerWidget {
  const ConsentFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formsAsync = ref.watch(consentFormsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('施術同意書テンプレート'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'テンプレート追加',
            onPressed: () => _showForm(context, null),
          ),
        ],
      ),
      body: formsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (forms) {
          if (forms.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_outlined,
                      size: 56, color: AppColors.textDisabled),
                  const SizedBox(height: 16),
                  Text('同意書テンプレートがありません',
                      style: AppTextStyles.body1
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text('パーマ・カラーなど施術別の同意書を\n作成・管理できます',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showForm(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('最初のテンプレートを作成'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: forms.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ConsentFormCard(
              form: forms[i],
              onEdit: () => _showForm(context, forms[i]),
              onCopy: () => _copyContent(context, forms[i]),
              onDelete: () => _confirmDelete(context, ref, forms[i]),
            ),
          );
        },
      ),
    );
  }

  void _copyContent(BuildContext context, ConsentFormTemplate form) {
    Clipboard.setData(ClipboardData(text: form.content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${form.name}」の内容をコピーしました'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ConsentFormTemplate form) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('テンプレートを削除'),
        content: Text('「${form.name}」を削除しますか？'),
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
      await (db.update(db.consentFormTemplates)
            ..where((t) => t.id.equals(form.id)))
          .write(const ConsentFormTemplatesCompanion(isActive: Value(false)));
    }
  }

  void _showForm(BuildContext context, ConsentFormTemplate? form) {
    showDialog(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(width: 580, child: _ConsentFormSheet(form: form)),
        ),
      ),
    );
  }
}

// ─── 同意書カード ──────────────────────────────────────────────────────────
class _ConsentFormCard extends StatelessWidget {
  const _ConsentFormCard({
    required this.form,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
  });
  final ConsentFormTemplate form;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  String _typeLabel(String type) {
    switch (type) {
      case 'consent': return '同意書';
      case 'consultation': return 'カウンセリング';
      case 'questionnaire': return 'アンケート';
      default: return type;
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'consent': return AppColors.error;
      case 'consultation': return AppColors.primary;
      case 'questionnaire': return AppColors.warning;
      default: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(form.formType);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.description_outlined, color: color, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(form.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_typeLabel(form.formType),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            form.content.length > 60
                ? '${form.content.substring(0, 60)}…'
                : form.content,
            style: AppTextStyles.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy_outlined,
                  size: 18, color: AppColors.textSecondary),
              tooltip: '内容をコピー',
              onPressed: onCopy,
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
                  child:
                      Text('削除', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 同意書フォームシート ─────────────────────────────────────────────────
class _ConsentFormSheet extends ConsumerStatefulWidget {
  const _ConsentFormSheet({this.form});
  final ConsentFormTemplate? form;

  @override
  ConsumerState<_ConsentFormSheet> createState() => _ConsentFormSheetState();
}

class _ConsentFormSheetState extends ConsumerState<_ConsentFormSheet> {
  final _nameCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _formType = 'consent';

  final _types = const [
    ('consent', '同意書'),
    ('consultation', 'カウンセリング'),
    ('questionnaire', 'アンケート'),
  ];

  // デフォルトテンプレート
  static const _templates = {
    'consent': '''【施術同意書】

私は以下の施術を受けるにあたり、下記の事項を理解し同意いたします。

■ 施術内容:
■ 使用薬剤:

【確認事項】
□ アレルギーや過敏症がないことを確認しました
□ 施術のリスクについて説明を受け理解しました
□ 施術後のケア方法について説明を受けました

【免責事項】
施術による効果には個人差があります。
体調不良などが生じた場合は速やかにスタッフにお申し出ください。

お客様署名: ________________　　日付: 　　年　　月　　日''',
    'consultation': '''【カウンセリングシート】

本日はどのような施術をご希望ですか？

■ ご要望:

■ アレルギー・敏感症状: □ なし  □ あり（詳細:　　　　）

■ 過去の施術履歴:

■ 頭皮・髪の状態:
□ 普通  □ 乾燥  □ 脂性  □ 敏感  □ ダメージ

■ スタイルのご希望（雑誌等の切り抜きがあればお持ちください）:''',
    'questionnaire': '''【お客様アンケート】

本日のサービスについてお聞かせください。

Q1. 本日のご来店のきっかけは？
□ インターネット  □ SNS  □ ご紹介  □ 看板  □ その他

Q2. サービスへのご満足度は？
□ 大変満足  □ 満足  □ 普通  □ 不満  □ 大変不満

Q3. スタッフの対応はいかがでしたか？
□ 大変良い  □ 良い  □ 普通  □ 改善が必要

Q4. また利用したいですか？
□ はい  □ おそらく  □ 未定  □ いいえ

ご意見・ご感想:''',
  };

  @override
  void initState() {
    super.initState();
    if (widget.form != null) {
      _nameCtrl.text = widget.form!.name;
      _contentCtrl.text = widget.form!.content;
      _formType = widget.form!.formType;
    } else {
      _contentCtrl.text = _templates['consent']!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final db = ref.read(databaseProvider);
    const uuid = Uuid();
    if (widget.form == null) {
      final count =
          await db.select(db.consentFormTemplates).get().then((l) => l.length);
      await db
          .into(db.consentFormTemplates)
          .insert(ConsentFormTemplatesCompanion.insert(
            id: uuid.v4(),
            name: _nameCtrl.text.trim(),
            content: _contentCtrl.text.trim(),
            formType: Value(_formType),
            sortOrder: Value(count),
          ));
    } else {
      await (db.update(db.consentFormTemplates)
            ..where((t) => t.id.equals(widget.form!.id)))
          .write(ConsentFormTemplatesCompanion(
        name: Value(_nameCtrl.text.trim()),
        content: Value(_contentCtrl.text.trim()),
        formType: Value(_formType),
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  widget.form == null ? 'テンプレート追加' : 'テンプレート編集',
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
                  // タイプ
                  Text('種別', style: AppTextStyles.label),
                  const SizedBox(height: 8),
                  Row(
                    children: _types.map((t) {
                      final selected = _formType == t.$1;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t.$2),
                          selected: selected,
                          selectedColor: AppColors.primary.withAlpha(40),
                          onSelected: (_) {
                            setState(() {
                              _formType = t.$1;
                              if (widget.form == null &&
                                  _templates.containsKey(t.$1)) {
                                _contentCtrl.text = _templates[t.$1]!;
                              }
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // 名前
                  Text('テンプレート名', style: AppTextStyles.label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: '例: パーマ施術同意書',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 内容
                  Row(
                    children: [
                      Text('内容', style: AppTextStyles.label),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 14),
                        label: const Text('コピー',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _contentCtrl.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('コピーしました'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _contentCtrl,
                    maxLines: 18,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.all(12),
                      hintText: '同意書の内容を入力...',
                    ),
                    style: const TextStyle(
                        fontSize: 13, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ),
        ],
    );
  }
}
