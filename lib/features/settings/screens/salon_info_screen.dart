import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/back_guard_provider.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── Provider ─────────────────────────────────────────────────────────────
final _salonSettingProvider = StreamProvider<SalonSetting?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.salonSettings)..where((t) => t.id.equals(1)))
      .watchSingleOrNull();
});

// ─── Screen ───────────────────────────────────────────────────────────────
class SalonInfoScreen extends ConsumerWidget {
  const SalonInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_salonSettingProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,title: const Text('サロン基本情報')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (salon) => salon == null
            ? const Center(child: Text('設定データがありません'))
            : _SalonInfoForm(salon: salon),
      ),
    );
  }
}

class _SalonInfoForm extends ConsumerStatefulWidget {
  const _SalonInfoForm({required this.salon});
  final SalonSetting salon;

  @override
  ConsumerState<_SalonInfoForm> createState() => _SalonInfoFormState();
}

class _SalonInfoFormState extends ConsumerState<_SalonInfoForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nameJpCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _invoiceCtrl;
  late final TextEditingController _receiptFooterCtrl;
  bool _saving = false;
  bool _dirty = false;

  void _markDirty() {
    if (!_dirty) {
      setState(() => _dirty = true);
      ref.read(hasUnsavedChangesProvider.notifier).state = true;
    }
  }

  @override
  void initState() {
    super.initState();
    final s = widget.salon;
    _nameCtrl = TextEditingController(text: s.salonName);
    _nameJpCtrl = TextEditingController(text: s.salonNameJp ?? '');
    _phoneCtrl = TextEditingController(text: s.phone ?? '');
    _addressCtrl = TextEditingController(text: s.address ?? '');
    _emailCtrl = TextEditingController(text: s.email ?? '');
    _invoiceCtrl = TextEditingController(text: s.invoiceRegistrationNo ?? '');
    _receiptFooterCtrl = TextEditingController(text: s.receiptFooter ?? '');
    for (final ctrl in [_nameCtrl, _nameJpCtrl, _phoneCtrl, _addressCtrl, _emailCtrl, _invoiceCtrl, _receiptFooterCtrl]) {
      ctrl.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameJpCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _emailCtrl.dispose();
    _invoiceCtrl.dispose();
    _receiptFooterCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showTopBanner(context, 'サロン名を入力してください',
          color: AppColors.error, icon: Icons.error_outline);
      return;
    }
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await (db.update(db.salonSettings)..where((t) => t.id.equals(1))).write(
        SalonSettingsCompanion(
          salonName: Value(_nameCtrl.text.trim()),
          salonNameJp: Value(
              _nameJpCtrl.text.trim().isEmpty ? null : _nameJpCtrl.text.trim()),
          phone: Value(
              _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
          address: Value(_addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim()),
          email: Value(
              _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim()),
          invoiceRegistrationNo: Value(_invoiceCtrl.text.trim().isEmpty
              ? null
              : _invoiceCtrl.text.trim()),
          receiptFooter: Value(_receiptFooterCtrl.text.trim().isEmpty
              ? null
              : _receiptFooterCtrl.text.trim()),
        ),
      );
      if (mounted) {
        setState(() => _dirty = false);
        ref.read(hasUnsavedChangesProvider.notifier).state = false;
        showTopBanner(context, '保存しました',
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(icon: Icons.store_outlined, title: 'サロン名'),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'サロン名 *',
              hintText: 'My Salon',
              prefixIcon: Icon(Icons.store_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameJpCtrl,
            decoration: const InputDecoration(
              labelText: 'サロン名（日本語）',
              hintText: 'マイサロン',
              prefixIcon: Icon(Icons.translate_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(icon: Icons.contact_phone_outlined, title: '連絡先'),
          const SizedBox(height: 10),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '電話番号',
              hintText: '03-1234-5678',
              prefixIcon: Icon(Icons.phone_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'メールアドレス',
              hintText: 'salon@example.com',
              prefixIcon: Icon(Icons.email_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '住所',
              hintText: '東京都渋谷区...',
              prefixIcon: Icon(Icons.location_on_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(
              icon: Icons.receipt_long_outlined, title: '適格請求書・レシート'),
          const SizedBox(height: 10),
          TextField(
            controller: _invoiceCtrl,
            decoration: const InputDecoration(
              labelText: '適格請求書番号（インボイス登録番号）',
              hintText: 'T1234567890123',
              prefixIcon: Icon(Icons.numbers_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _receiptFooterCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'レシートフッター',
              hintText: 'またのご来店をお待ちしております',
              prefixIcon: Icon(Icons.notes_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? '保存中...' : '保存'),
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── セクションヘッダー ──────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(title,
            style: AppTextStyles.label.copyWith(color: AppColors.primary)),
      ],
    );
  }
}
