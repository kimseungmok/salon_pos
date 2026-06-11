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
final salonSettingsProvider = StreamProvider<SalonSetting?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.salonSettings)..where((t) => t.id.equals(1))).watchSingleOrNull();
});

// ─── ポイント・会員設定 画面 ────────────────────────────────────────────────
class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  ConsumerState<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends ConsumerState<LoyaltySettingsScreen> {
  bool _pointEnabled = true;
  int _pointRatePercent = 1;
  int _pointExpireDays = 365;
  bool _dirty = false;
  bool _saving = false;
  bool _initialized = false;

  void _markDirty() {
    setState(() => _dirty = true);
    ref.read(hasUnsavedChangesProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(salonSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ポイント・会員設定'),
        actions: [
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('保存'),
              ),
            ),
        ],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (settings) {
          // 초기 로드 시 한 번만 상태 설정
          if (!_initialized && settings != null) {
            _initialized = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _pointEnabled = settings.pointEnabled;
                  _pointRatePercent = settings.pointRatePercent;
                  _pointExpireDays = settings.pointExpireDays;
                });
              }
            });
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ─ ポイント有効 ─────────────────────────────────────────────
              _SectionCard(
                icon: Icons.stars_outlined,
                title: 'ポイントプログラム',
                subtitle: '来店・お支払いでポイントを付与します',
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      const Text('ポイントを有効にする'),
                      const Spacer(),
                      Switch(
                        value: _pointEnabled,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() {
                          _pointEnabled = v;
                          _markDirty();
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ─ ポイント付与率 ────────────────────────────────────────────
              if (_pointEnabled) ...[
                _SectionCard(
                  icon: Icons.percent_outlined,
                  title: 'ポイント付与率',
                  subtitle: '税込支払い金額に対するポイント付与率',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text('¥1,000 あたり',
                              style: AppTextStyles.body2.copyWith(
                                  color: AppColors.textSecondary)),
                          const Spacer(),
                          _RateSelector(
                            value: _pointRatePercent,
                            onChanged: (v) => setState(() {
                              _pointRatePercent = v;
                              _markDirty();
                            }),
                          ),
                          const SizedBox(width: 6),
                          const Text('pt'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '例: ¥10,000 のお支払い → ${(_pointRatePercent * 10)} pt',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ─ 有効期限 ──────────────────────────────────────────────
                _SectionCard(
                  icon: Icons.timer_outlined,
                  title: 'ポイント有効期限',
                  subtitle: '最終獲得日から有効期限を設定します',
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      children: [
                        ...[90, 180, 365, 730, 0].map((days) {
                          final label = days == 0
                              ? '無期限'
                              : days < 365
                                  ? '$days日'
                                  : '${days ~/ 365}年';
                          return RadioListTile<int>(
                            title: Text(label),
                            value: days == 0 ? 36500 : days,
                            groupValue: _pointExpireDays,
                            activeColor: AppColors.primary,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) => setState(() {
                              _pointExpireDays = v!;
                              _markDirty();
                            }),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
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
          pointEnabled: Value(_pointEnabled),
          pointRatePercent: Value(_pointRatePercent),
          pointExpireDays: Value(_pointExpireDays),
        ),
      );
      if (mounted) {
        setState(() => _dirty = false);
        ref.read(hasUnsavedChangesProvider.notifier).state = false;
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

// ─── 비율 선택기 ──────────────────────────────────────────────────────────
class _RateSelector extends StatelessWidget {
  const _RateSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600),
          items: [1, 2, 3, 5, 10]
              .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}

// ─── 섹션 카드 ────────────────────────────────────────────────────────────
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
