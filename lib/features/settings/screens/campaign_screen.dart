import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── キャンペーン一覧 Provider ──────────────────────────────────────────────
final _campaignsProvider = StreamProvider<List<Campaign>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.campaigns)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();
});

// ─── メッセージテンプレート一覧 Provider ────────────────────────────────────
final _templatesForCampaignProvider =
    StreamProvider<List<MessageTemplate>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.messageTemplates)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

// ─── キャンペーン管理画面 ───────────────────────────────────────────────────
class CampaignScreen extends ConsumerWidget {
  const CampaignScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(_campaignsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settings),
        ),
        title: const Text('キャンペーン管理'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showForm(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新規作成'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                textStyle: AppTextStyles.label
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: campaignsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (campaigns) => campaigns.isEmpty
            ? _EmptyState(onTap: () => _showForm(context, ref, null))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: campaigns.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _CampaignCard(
                  campaign: campaigns[i],
                  onEdit: () => _showForm(context, ref, campaigns[i]),
                  onDelete: () => _delete(context, ref, campaigns[i]),
                ),
              ),
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, Campaign? campaign) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 520,
          child: _CampaignFormSheet(campaign: campaign),
        ),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, Campaign campaign) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${campaign.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      final db = ref.read(databaseProvider);
      await (db.delete(db.campaigns)
            ..where((t) => t.id.equals(campaign.id)))
          .go();
    }
  }
}

// ─── キャンペーンカード ──────────────────────────────────────────────────────
class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.onEdit,
    required this.onDelete,
  });
  final Campaign campaign;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = _statusInfo(campaign.status);
    final segmentLabel = _segmentLabel(campaign.targetSegment);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(campaign.name,
                      style: AppTextStyles.h4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.group_outlined,
                    size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(segmentLabel,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(width: 16),
                if (campaign.targetCount > 0) ...[
                  const Icon(Icons.people_outline,
                      size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('${campaign.targetCount}名',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary)),
                  const SizedBox(width: 16),
                ],
                if (campaign.sentAt != null) ...[
                  const Icon(Icons.send_outlined,
                      size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    campaign.sentAt!.substring(0, 10),
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('編集'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(fontSize: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('削除'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    textStyle: const TextStyle(fontSize: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusInfo(String status) {
    switch (status) {
      case 'draft':
        return (AppColors.textSecondary, '下書き');
      case 'scheduled':
        return (const Color(0xFFFFB300), '予約済み');
      case 'sending':
        return (AppColors.primary, '送信中');
      case 'sent':
        return (const Color(0xFF4CAF50), '送信完了');
      case 'cancelled':
        return (AppColors.error, 'キャンセル');
      default:
        return (AppColors.textSecondary, status);
    }
  }

  String _segmentLabel(String segment) {
    switch (segment) {
      case 'all':
        return '全顧客';
      case 'vip':
        return 'VIP顧客';
      case 'new':
        return '新規顧客';
      case 'lost':
        return '休眠顧客';
      case 'birthday':
        return '誕生日月顧客';
      case 'custom':
        return 'カスタム';
      default:
        return segment;
    }
  }
}

// ─── キャンペーンフォーム ────────────────────────────────────────────────────
class _CampaignFormSheet extends ConsumerStatefulWidget {
  const _CampaignFormSheet({this.campaign});
  final Campaign? campaign;

  @override
  ConsumerState<_CampaignFormSheet> createState() =>
      _CampaignFormSheetState();
}

class _CampaignFormSheetState extends ConsumerState<_CampaignFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl =
      TextEditingController(text: widget.campaign?.name ?? '');
  String _segment = 'all';
  String? _templateId;
  String _status = 'draft';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.campaign != null) {
      _segment = widget.campaign!.targetSegment;
      _templateId = widget.campaign!.templateId;
      _status = widget.campaign!.status;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(_templatesForCampaignProvider);
    final isNew = widget.campaign == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ヘッダー
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text(isNew ? 'キャンペーン新規作成' : 'キャンペーン編集',
                  style: AppTextStyles.h3),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
        // フォーム
        Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // キャンペーン名
                _Label('キャンペーン名'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    hintText: '例: 6月特別キャンペーン',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '名前を入力してください' : null,
                ),
                const SizedBox(height: 16),

                // 対象セグメント
                _Label('対象顧客'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _segment,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('全顧客')),
                    DropdownMenuItem(value: 'vip', child: Text('VIP顧客')),
                    DropdownMenuItem(value: 'new', child: Text('新規顧客（初回来店1ヶ月以内）')),
                    DropdownMenuItem(value: 'lost', child: Text('休眠顧客（90日以上未来店）')),
                    DropdownMenuItem(value: 'birthday', child: Text('誕生日月顧客')),
                  ],
                  onChanged: (v) => setState(() => _segment = v ?? 'all'),
                ),
                const SizedBox(height: 16),

                // テンプレート
                _Label('メッセージテンプレート'),
                const SizedBox(height: 6),
                templatesAsync.when(
                  data: (templates) => DropdownButtonFormField<String?>(
                    value: _templateId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    hint: const Text('テンプレートを選択'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— 未設定 —')),
                      ...templates.map((t) => DropdownMenuItem(
                            value: t.id,
                            child: Text(t.name,
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setState(() => _templateId = v),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e',
                      style: const TextStyle(color: AppColors.error)),
                ),
                const SizedBox(height: 16),

                // ステータス
                _Label('ステータス'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: ['draft', 'scheduled', 'sent'].map((s) {
                    final label = switch (s) {
                      'draft' => '下書き',
                      'scheduled' => '予約済み',
                      _ => '送信完了',
                    };
                    return ChoiceChip(
                      label: Text(label),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                      selectedColor: AppColors.primaryLight,
                      labelStyle: TextStyle(
                        color: _status == s
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: _status == s
                            ? FontWeight.w700
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // 保存ボタン
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      textStyle: AppTextStyles.label
                          .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final name = _nameCtrl.text.trim();
      if (widget.campaign == null) {
        // 新規
        await db.into(db.campaigns).insert(CampaignsCompanion.insert(
          id: const Uuid().v4(),
          name: name,
          templateId: _templateId ?? '',
          targetSegment: _segment,
          status: Value(_status),
        ));
      } else {
        // 更新
        await (db.update(db.campaigns)
              ..where((t) => t.id.equals(widget.campaign!.id)))
            .write(CampaignsCompanion(
          name: Value(name),
          templateId: Value(_templateId ?? ''),
          targetSegment: Value(_segment),
          status: Value(_status),
        ));
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── ラベル ──────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTextStyles.label.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      );
}

// ─── 空状態 ──────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.campaign_outlined,
              size: 64, color: AppColors.border),
          const SizedBox(height: 16),
          Text('キャンペーンはまだありません',
              style: AppTextStyles.h4
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            'VIP顧客や休眠顧客向けのキャンペーンを\n作成して、売上アップにつなげましょう。',
            textAlign: TextAlign.center,
            style: AppTextStyles.body2
                .copyWith(color: AppColors.textDisabled),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add),
            label: const Text('最初のキャンペーンを作成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
