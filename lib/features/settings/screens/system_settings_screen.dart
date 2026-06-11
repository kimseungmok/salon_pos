import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/app_settings_provider.dart';

// ─── サロン設定 provider ────────────────────────────────────────────────────
final _salonSettingsProvider = StreamProvider<SalonSetting?>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.salonSettings)..where((t) => t.id.equals(1)))
      .watchSingleOrNull();
});

class SystemSettingsScreen extends ConsumerWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,title: const Text('システム設定')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─ 予約表示時間 ────────────────────────────────────────────────
            _SectionCard(
              icon: Icons.access_time_outlined,
              title: '予約表示時間',
              subtitle: '予約管理カレンダーに表示する時間帯を設定します',
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _CalendarHoursSelector(settings: settings),
              ),
            ),
            const SizedBox(height: 12),
            // ─ 営業時間・スロット設定 ─────────────────────────────────────
            ref.watch(_salonSettingsProvider).when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (salon) => salon == null
                  ? const SizedBox.shrink()
                  : _SectionCard(
                      icon: Icons.schedule_outlined,
                      title: '営業時間・予約スロット',
                      subtitle: '営業開始・終了時間と予約枠の単位を設定します',
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _BusinessHoursSelector(salon: salon),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            // ─ 文字サイズ ─────────────────────────────────────────────────
            _SectionCard(
              icon: Icons.text_fields_outlined,
              title: '文字サイズ',
              subtitle: 'アプリ全体の文字サイズを調整します',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  // 프리뷰 텍스트
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(settings.textScale),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('プレビュー', style: AppTextStyles.h4),
                          const SizedBox(height: 4),
                          Text('田中 麻衣 — フルカラー', style: AppTextStyles.body2),
                          const SizedBox(height: 2),
                          Text('10:15〜11:45 ／ 90分', style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<double>(
                    segments: const [
                      ButtonSegment(value: 0.85, label: Text('小')),
                      ButtonSegment(value: 0.90, label: Text('90%')),
                      ButtonSegment(value: 0.95, label: Text('95%')),
                      ButtonSegment(value: 1.00, label: Text('標準')),
                      ButtonSegment(value: 1.05, label: Text('105%')),
                      ButtonSegment(value: 1.10, label: Text('110%')),
                      ButtonSegment(value: 1.15, label: Text('大')),
                    ],
                    selected: {_nearestScale(settings.textScale)},
                    onSelectionChanged: (s) => ref
                        .read(appSettingsProvider.notifier)
                        .setTextScale(s.first),
                  ),
                  const SizedBox(height: 8),
                  // 현재 값 표시 + 리셋 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '現在: ${(settings.textScale * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(appSettingsProvider.notifier)
                            .setTextScale(1.0),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                        ),
                        child: const Text('リセット', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
            // ─ バックアップ ───────────────────────────────────────────────
            _SectionCard(
              icon: Icons.backup_outlined,
              title: 'データバックアップ',
              subtitle: 'データベースファイルをバックアップフォルダにコピーします',
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _BackupSection(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _nearestScale(double current) {
    const steps = [0.85, 0.90, 0.95, 1.00, 1.05, 1.10, 1.15];
    return steps.reduce((a, b) => (a - current).abs() < (b - current).abs() ? a : b);
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
                width: 32,
                height: 32,
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

// ─── 캘린더 시간 범위 선택기 ──────────────────────────────────────────────
class _CalendarHoursSelector extends ConsumerWidget {
  const _CalendarHoursSelector({required this.settings});
  final AppSettings settings;

  static final _hours = List.generate(25, (i) => i); // 0 ~ 24

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = settings.calendarStartHour;
    final end = settings.calendarEndHour;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 시간 프리뷰 바
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: LayoutBuilder(builder: (ctx, box) {
            final totalHours = 24;
            final startRatio = start / totalHours;
            final endRatio = end / totalHours;
            return Stack(
              children: [
                // 선택된 시간대 표시
                Positioned(
                  left: box.maxWidth * startRatio,
                  width: box.maxWidth * (endRatio - startRatio),
                  top: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(40),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '$start:00 〜 $end:00  (${end - start}時間)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 16),
        // 시작 / 종료 시간 드롭다운
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('開始時間',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  _HourDropdown(
                    value: start,
                    hours: _hours.where((h) => h <= end - 1).toList(),
                    onChanged: (v) => ref
                        .read(appSettingsProvider.notifier)
                        .setCalendarHours(v, end),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Text('〜',
                style: TextStyle(
                    fontSize: 18, color: AppColors.textSecondary)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('終了時間',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  _HourDropdown(
                    value: end,
                    hours: _hours.where((h) => h >= start + 1).toList(),
                    onChanged: (v) => ref
                        .read(appSettingsProvider.notifier)
                        .setCalendarHours(start, v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '※ 設定変更は即時反映されます',
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

// ─── 영업시간·슬롯 설정 위젯 ──────────────────────────────────────────────
class _BusinessHoursSelector extends ConsumerWidget {
  const _BusinessHoursSelector({required this.salon});
  final SalonSetting salon;

  static const _slotOptions = [15, 30, 60];

  Future<void> _save(WidgetRef ref,
      {int? openHour, int? closeHour, int? slot}) async {
    final db = ref.read(databaseProvider);
    final newOpen = (openHour ?? salon.businessHourStart).clamp(0, 22);
    final newClose = (closeHour ?? salon.businessHourEnd).clamp(newOpen + 1, 24);
    final newSlot = slot ?? salon.slotMinutes;
    await (db.update(db.salonSettings)..where((t) => t.id.equals(1))).write(
      SalonSettingsCompanion(
        businessHourStart: Value(newOpen),
        businessHourEnd: Value(newClose),
        slotMinutes: Value(newSlot),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = salon.businessHourStart;
    final close = salon.businessHourEnd;
    final slot = salon.slotMinutes;
    final hours = List.generate(25, (i) => i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 時間バー
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: LayoutBuilder(builder: (ctx, box) {
            final startRatio = open / 24;
            final endRatio = close / 24;
            return Stack(children: [
              Positioned(
                left: box.maxWidth * startRatio,
                width: box.maxWidth * (endRatio - startRatio),
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withAlpha(40),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '$open:00 〜 $close:00  (${close - open}時間)',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ),
                ),
              ),
            ]);
          }),
        ),
        const SizedBox(height: 16),
        // 시간 드롭다운
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('開店時間',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  _HourDropdown(
                    value: open,
                    hours: hours.where((h) => h <= close - 1).toList(),
                    onChanged: (v) => _save(ref, openHour: v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            const Text('〜',
                style: TextStyle(fontSize: 18, color: AppColors.textSecondary)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('閉店時間',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  _HourDropdown(
                    value: close,
                    hours: hours.where((h) => h >= open + 1).toList(),
                    onChanged: (v) => _save(ref, closeHour: v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 슬롯 단위
        const Text('予約スロット単位',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: _slotOptions.map((m) {
            final selected = slot == m;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${m}分'),
                selected: selected,
                onSelected: (_) => _save(ref, slot: m),
                selectedColor: AppColors.primary.withAlpha(30),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : AppColors.border),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        const Text('※ 予約枠の単位は予約フォームの時間選択に反映されます',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _HourDropdown extends StatelessWidget {
  const _HourDropdown({
    required this.value,
    required this.hours,
    required this.onChanged,
  });
  final int value;
  final List<int> hours;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: hours.contains(value) ? value : hours.first,
          isExpanded: true,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
          dropdownColor: AppColors.surface,
          items: hours
              .map((h) => DropdownMenuItem(
                    value: h,
                    child: Text('$h:00'),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ─── バックアップセクション ────────────────────────────────────────────────
class _BackupSection extends StatefulWidget {
  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _backing = false;
  String? _lastBackupTime;

  Future<void> _backup() async {
    setState(() => _backing = true);
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(appDocDir.path, 'salon_pos.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        _showSnack('データベースファイルが見つかりません');
        return;
      }
      final backupDir = Directory(p.join(appDocDir.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}';
      await dbFile.copy(p.join(backupDir.path, 'salon_pos_$stamp.db'));
      setState(() {
        _lastBackupTime =
            '${now.year}/${now.month}/${now.day} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      });
      _showSnack('バックアップ完了: salon_pos_$stamp.db', success: true);
    } catch (e) {
      _showSnack('バックアップ失敗: $e');
    } finally {
      if (mounted) setState(() => _backing = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.success : AppColors.error,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastBackupTime != null) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  '最終バックアップ: $_lastBackupTime',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.success),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          'バックアップ先: ~/Documents/backups/',
          style: AppTextStyles.caption
              .copyWith(color: AppColors.textDisabled),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _backing ? null : _backup,
            icon: _backing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.backup_outlined, size: 18),
            label: Text(_backing ? 'バックアップ中...' : '今すぐバックアップ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
