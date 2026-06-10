import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/widgets/top_banner.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/pos_provider.dart';

const _uuid = Uuid();

// ─── 개점 처리 전체화면 페이지 (GoRouter용) ──────────────────────────────────
class OpenRegisterPage extends StatelessWidget {
  const OpenRegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('開店処理'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: SizedBox(
          width: 460,
          child: OpenRegisterSheet(),
        ),
      ),
    );
  }
}

// ─── 개점 시트 ────────────────────────────────────────────────────────────
class OpenRegisterSheet extends ConsumerStatefulWidget {
  const OpenRegisterSheet({super.key});

  @override
  ConsumerState<OpenRegisterSheet> createState() => _OpenRegisterSheetState();
}

class _OpenRegisterSheetState extends ConsumerState<OpenRegisterSheet> {
  int _openingCash = 0;
  bool _saving = false;
  String? _selectedStaffId;

  void _input(String k) {
    setState(() {
      if (k == '⌫') {
        final s = _openingCash.toString();
        _openingCash = s.length <= 1 ? 0 : int.parse(s.substring(0, s.length - 1));
      } else if (k == '000') {
        final next = int.tryParse('${_openingCash}000') ?? _openingCash;
        if (next <= 9999999) _openingCash = next;
      } else {
        final next = int.tryParse('$_openingCash$k') ?? _openingCash;
        if (next <= 9999999) _openingCash = next;
      }
    });
  }

  Future<void> _openRegister() async {
    if (_selectedStaffId == null) {
      showTopBanner(context, '担当者を選択してください',
          icon: Icons.person_outline);
      return;
    }
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now();
      final sessionNo =
          'S${now.toIso8601String().substring(0, 10).replaceAll('-', '')}-${now.millisecondsSinceEpoch % 10000}';
      await db.into(db.registerSessions).insert(
            RegisterSessionsCompanion.insert(
              id: _uuid.v4(),
              sessionNo: sessionNo,
              openedBy: _selectedStaffId!,
              openAt: now.toIso8601String(),
              openingCash: Value(_openingCash),
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffList = ref.watch(activeStaffProvider).valueOrNull ?? [];
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', '⌫'];

    return Column(
      children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text('開店処理', style: AppTextStyles.h3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 담당자 선택
                Text('担当者', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: staffList.map((s) {
                    final isSelected = _selectedStaffId == s.id;
                    final color = Color(int.tryParse(s.color.replaceFirst('#', '0xFF')) ?? 0xFF0064FF);
                    return GestureDetector(
                      onTap: () => setState(() => _selectedStaffId = s.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? color.withAlpha(30) : AppColors.background,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(
                            color: isSelected ? color : AppColors.border,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: color,
                              child: Text(s.name.substring(0, 1),
                                  style: const TextStyle(fontSize: 11, color: Colors.white)),
                            ),
                            const SizedBox(width: 6),
                            Text(s.name,
                                style: AppTextStyles.body2.copyWith(
                                    color: isSelected ? color : AppColors.textPrimary)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                // 시재 입력
                Text('開店時レジ金額', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('¥${_fmtN(_openingCash)}', style: AppTextStyles.price),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 숫자 패드
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 2.2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: keys.map((k) {
                    final isDelete = k == '⌫';
                    return Material(
                      color: isDelete ? AppColors.errorLight : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _input(k),
                        child: Center(
                          child: Text(k,
                              style: isDelete
                                  ? AppTextStyles.h3.copyWith(color: AppColors.error)
                                  : AppTextStyles.h3),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _openRegister,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('開店する (¥${_fmtN(_openingCash)})', style: AppTextStyles.button),
                ),
                const SizedBox(height: 8),
              ],
            ),
          )),
        ],
      );
  }
}

// ─── 마감 시트 ────────────────────────────────────────────────────────────
class CloseRegisterSheet extends ConsumerStatefulWidget {
  const CloseRegisterSheet({super.key, required this.session});
  final RegisterSession session;

  @override
  ConsumerState<CloseRegisterSheet> createState() => _CloseRegisterSheetState();
}

class _CloseRegisterSheetState extends ConsumerState<CloseRegisterSheet> {
  int _closingCash = 0;
  bool _saving = false;

  void _input(String k) {
    setState(() {
      if (k == '⌫') {
        final s = _closingCash.toString();
        _closingCash = s.length <= 1 ? 0 : int.parse(s.substring(0, s.length - 1));
      } else if (k == '000') {
        final next = int.tryParse('${_closingCash}000') ?? _closingCash;
        if (next <= 9999999) _closingCash = next;
      } else {
        final next = int.tryParse('$_closingCash$k') ?? _closingCash;
        if (next <= 9999999) _closingCash = next;
      }
    });
  }

  Future<void> _closeRegister() async {
    // 이중 확인 다이얼로그 (실수 방지)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.store_outlined,
                      color: AppColors.warning, size: 24),
                ),
                const SizedBox(height: 16),
                Text('閉店処理を実行しますか？',
                    style: AppTextStyles.h4, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('レジ金額 ¥${_fmtN(_closingCash)} で閉店します。\nこの操作は取り消せません。',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.textSecondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 46)),
                        child: const Text('キャンセル'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          minimumSize: const Size(0, 46),
                        ),
                        child: const Text('閉店する',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final summary = await (db.select(db.dailySummaries)
            ..where((t) => t.id.equals(widget.session.openAt.substring(0, 10))))
          .getSingleOrNull();
      final cashSales = summary?.cashTotal ?? 0;
      final expected = widget.session.openingCash + cashSales;
      final diff = _closingCash - expected;

      await (db.update(db.registerSessions)
            ..where((t) => t.id.equals(widget.session.id)))
          .write(RegisterSessionsCompanion(
        closedBy: Value(widget.session.openedBy),
        closeAt: Value(DateTime.now().toIso8601String()),
        closingCash: Value(_closingCash),
        expectedCash: Value(expected),
        cashDifference: Value(diff),
        status: const Value('closed'),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', '⌫'];

    return Column(
      children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Text('閉店処理', style: AppTextStyles.h3),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─ 当日売上サマリー ─────────────────────────────────────────
                _DailySummaryCard(date: widget.session.openAt.substring(0, 10)),
                const SizedBox(height: 16),
                Text('閉店時レジ金額', style: AppTextStyles.label.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('¥${_fmtN(_closingCash)}', style: AppTextStyles.price),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 2.2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: keys.map((k) {
                    final isDelete = k == '⌫';
                    return Material(
                      color: isDelete ? AppColors.errorLight : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _input(k),
                        child: Center(
                          child: Text(k,
                              style: isDelete
                                  ? AppTextStyles.h3.copyWith(color: AppColors.error)
                                  : AppTextStyles.h3),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _closeRegister,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                  icon: const Icon(Icons.store_outlined),
                  label: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('閉店する'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          )),
        ],
      );
  }
}

// ─── 当日売上サマリーカード ────────────────────────────────────────────────
class _DailySummaryCard extends ConsumerWidget {
  const _DailySummaryCard({required this.date});
  final String date; // YYYY-MM-DD

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final summaryFuture = (db.select(db.dailySummaries)
          ..where((t) => t.id.equals(date)))
        .getSingleOrNull();

    return FutureBuilder<DailySummary?>(
      future: summaryFuture,
      builder: (ctx, snap) {
        final s = snap.data;
        if (s == null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Text('本日の売上データなし',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary)),
          );
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withAlpha(8),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.primary.withAlpha(40)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.today_outlined,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text('本日の売上サマリー',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SummaryItem(
                        label: '売上合計',
                        value: '¥${_fmtN(s.netSales)}',
                        bold: true),
                  ),
                  Expanded(
                    child: _SummaryItem(
                        label: '件数', value: '${s.saleCount}件'),
                  ),
                  Expanded(
                    child: _SummaryItem(
                        label: '客数', value: '${s.customerCount}人'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SummaryItem(
                        label: '現金',
                        value: '¥${_fmtN(s.cashTotal)}',
                        color: const Color(0xFF00B746)),
                  ),
                  Expanded(
                    child: _SummaryItem(
                        label: 'カード',
                        value: '¥${_fmtN(s.cardTotal)}',
                        color: AppColors.primary),
                  ),
                  Expanded(
                    child: _SummaryItem(
                        label: 'その他',
                        value: '¥${_fmtN(s.otherTotal)}',
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem(
      {required this.label, required this.value, this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTextStyles.caption
                .copyWith(color: AppColors.textSecondary, fontSize: 10)),
        const SizedBox(height: 2),
        Text(value,
            style: AppTextStyles.body2.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color: color,
            )),
      ],
    );
  }
}

String _fmtN(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
