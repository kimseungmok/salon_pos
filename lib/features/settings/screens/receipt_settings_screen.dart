import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import 'loyalty_settings_screen.dart' show salonSettingsProvider;

// ─── レシート設定 画面 ────────────────────────────────────────────────────
class ReceiptSettingsScreen extends ConsumerStatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  ConsumerState<ReceiptSettingsScreen> createState() =>
      _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState
    extends ConsumerState<ReceiptSettingsScreen> {
  final _nameCtrl = TextEditingController();
  final _nameJpCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _invoiceNoCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  bool _dirty = false;
  bool _saving = false;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameJpCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _invoiceNoCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  void _initFromSettings(SalonSetting s) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = s.salonName;
    _nameJpCtrl.text = s.salonNameJp ?? '';
    _phoneCtrl.text = s.phone ?? '';
    _addressCtrl.text = s.address ?? '';
    _invoiceNoCtrl.text = s.invoiceRegistrationNo ?? '';
    _footerCtrl.text = s.receiptFooter ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(salonSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('レシート設定'),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('保存'),
              ),
            ),
        ],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (settings) {
          if (settings != null) _initFromSettings(settings);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ─ 店舗情報 ─────────────────────────────────────────────────
              _SectionCard(
                icon: Icons.store_outlined,
                title: '店舗情報',
                subtitle: 'レシートに印字される店舗情報',
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      _Field(
                        ctrl: _nameCtrl,
                        label: '店舗名 *',
                        hint: 'Salon Example',
                        onChanged: (_) => setState(() => _dirty = true),
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        ctrl: _nameJpCtrl,
                        label: '店舗名（日本語）',
                        hint: 'サロン例',
                        onChanged: (_) => setState(() => _dirty = true),
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        ctrl: _phoneCtrl,
                        label: '電話番号',
                        hint: '03-0000-0000',
                        onChanged: (_) => setState(() => _dirty = true),
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        ctrl: _addressCtrl,
                        label: '住所',
                        hint: '東京都渋谷区...',
                        onChanged: (_) => setState(() => _dirty = true),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ─ 適格請求書 ────────────────────────────────────────────────
              _SectionCard(
                icon: Icons.receipt_long_outlined,
                title: '適格請求書（インボイス）',
                subtitle: '登録番号を入力するとレシートに印字されます',
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _Field(
                    ctrl: _invoiceNoCtrl,
                    label: '登録番号',
                    hint: 'T0000000000000',
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ─ フッター ──────────────────────────────────────────────────
              _SectionCard(
                icon: Icons.text_fields_outlined,
                title: 'フッターメッセージ',
                subtitle: 'レシート最下部に印字するメッセージ',
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _Field(
                    ctrl: _footerCtrl,
                    label: 'フッター',
                    hint: 'またのご来店をお待ちしております',
                    maxLines: 3,
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
              ),

              // ─ プレビュー ────────────────────────────────────────────────
              const SizedBox(height: 12),
              _SectionCard(
                icon: Icons.preview_outlined,
                title: 'レシートプレビュー',
                subtitle: '印字イメージ（実際とは異なる場合があります）',
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'サロン名',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        if (_nameJpCtrl.text.isNotEmpty)
                          Text(_nameJpCtrl.text,
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.center),
                        if (_phoneCtrl.text.isNotEmpty)
                          Text('TEL: ${_phoneCtrl.text}',
                              style: const TextStyle(fontSize: 11),
                              textAlign: TextAlign.center),
                        if (_addressCtrl.text.isNotEmpty)
                          Text(_addressCtrl.text,
                              style: const TextStyle(fontSize: 11),
                              textAlign: TextAlign.center),
                        const Divider(height: 16),
                        const Text('─── 施術内容 ───',
                            style: TextStyle(fontSize: 11)),
                        const SizedBox(height: 4),
                        const Text('カット            ¥5,000',
                            style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
                        const Text('カラー            ¥8,000',
                            style: TextStyle(fontSize: 12, fontFamily: 'monospace')),
                        const Divider(height: 16),
                        const Text('合計            ¥13,000',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                fontFamily: 'monospace')),
                        if (_invoiceNoCtrl.text.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('登録番号: ${_invoiceNoCtrl.text}',
                              style: const TextStyle(fontSize: 10)),
                        ],
                        if (_footerCtrl.text.isNotEmpty) ...[
                          const Divider(height: 16),
                          Text(_footerCtrl.text,
                              style: const TextStyle(fontSize: 11),
                              textAlign: TextAlign.center),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await (db.update(db.salonSettings)..where((t) => t.id.equals(1))).write(
        SalonSettingsCompanion(
          salonName: Value(_nameCtrl.text.trim()),
          salonNameJp: Value(_nameJpCtrl.text.trim().isEmpty ? null : _nameJpCtrl.text.trim()),
          phone: Value(_phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
          address: Value(_addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim()),
          invoiceRegistrationNo: Value(_invoiceNoCtrl.text.trim().isEmpty ? null : _invoiceNoCtrl.text.trim()),
          receiptFooter: Value(_footerCtrl.text.trim().isEmpty ? null : _footerCtrl.text.trim()),
        ),
      );
      if (mounted) {
        setState(() => _dirty = false);
        showTopBanner(context, '設定を保存しました',
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

class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
  });
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.h4),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
