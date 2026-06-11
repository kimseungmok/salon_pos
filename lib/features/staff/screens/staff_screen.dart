import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/staff_provider.dart';

// ─── 스태프별 이달 예약 건수 ─────────────────────────────────────────────────
final _staffMonthlyAptCountProvider =
    StreamProvider.family<int, String>((ref, staffId) {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final prefix = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-';
  return (db.select(db.appointments)
        ..where((t) =>
            t.staffId.equals(staffId) &
            t.startAt.like('$prefix%') &
            t.status.isNotIn(['cancelled'])))
      .watch()
      .map((list) => list.length);
});

// ─── 스태프별 이달 매출 ───────────────────────────────────────────────────
final _staffMonthlyRevenueProvider =
    FutureProvider.family<int, String>((ref, staffId) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final yearMonth = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}';
  final sales = await (db.select(db.sales)
        ..where((t) =>
            t.staffId.equals(staffId) &
            t.saleDate.like('$yearMonth%') &
            t.status.isIn(['completed', 'partial_refund'])))
      .get();
  return sales.fold<int>(0, (s, e) => s + e.totalAmount);
});

// ─── スタッフ管理 메인 화면 ────────────────────────────────────────────────
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(staffListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('スタッフ管理'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text('スタッフ追加'),
              onPressed: () => _openForm(context, ref, null),
            ),
          ),
        ],
      ),
      body: staffAsync.when(
        data: (list) => list.isEmpty
            ? _EmptyState(onAdd: () => _openForm(context, ref, null))
            : _StaffGrid(staffList: list),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  void _openForm(BuildContext ctx, WidgetRef ref, StaffData? existing) {
    Future.microtask(() {
      if (!ctx.mounted) return;
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(ctx),
          child: _StaffFormSheet(existing: existing),
        ),
      );
    });
  }
}

// ─── 그리드 목록 ──────────────────────────────────────────────────────────
class _StaffGrid extends ConsumerWidget {
  const _StaffGrid({required this.staffList});
  final List<StaffData> staffList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: staffList
            .map((s) => _StaffCard(
                  staff: s,
                  onTap: () => _openForm(context, ref, s),
                ))
            .toList(),
      ),
    );
  }

  void _openForm(BuildContext ctx, WidgetRef ref, StaffData staff) {
    Future.microtask(() {
      if (!ctx.mounted) return;
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(ctx),
          child: _StaffFormSheet(existing: staff),
        ),
      );
    });
  }
}

// ─── 스태프 카드 ──────────────────────────────────────────────────────────
class _StaffCard extends ConsumerWidget {
  const _StaffCard({required this.staff, required this.onTap});
  final StaffData staff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _parseColor(staff.color);
    final aptCountAsync = ref.watch(_staffMonthlyAptCountProvider(staff.id));
    final aptCount = aptCountAsync.valueOrNull ?? 0;
    final revenueAsync = ref.watch(_staffMonthlyRevenueProvider(staff.id));
    final revenue = revenueAsync.valueOrNull ?? 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withAlpha(40),
                  child: Text(
                    _firstChar(staff.name),
                    style: AppTextStyles.h3.copyWith(color: color),
                  ),
                ),
                const Spacer(),
                // 이달 예약 건수 뱃지
                if (aptCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$aptCount件',
                      style: AppTextStyles.caption.copyWith(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              staff.name,
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (staff.nameKana != null && staff.nameKana!.isNotEmpty)
              Text(
                staff.nameKana!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 6),
            _RoleBadge(role: staff.role),
            // 이달 매출 표시
            if (revenue > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.attach_money,
                        size: 11, color: color.withAlpha(180)),
                    const SizedBox(width: 2),
                    Text(
                      '¥${_fmtNum(revenue)}',
                      style: AppTextStyles.caption.copyWith(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            // 입사일 표시
            if (staff.hireDate != null && staff.hireDate!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 10, color: AppColors.textSecondary),
                    const SizedBox(width: 3),
                    Text(
                      staff.hireDate!,
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        roleLabel(role),
        style: AppTextStyles.caption
            .copyWith(color: AppColors.textSecondary, fontSize: 10),
      ),
    );
  }
}

// ─── 스태프 추가/수정 폼 시트 ─────────────────────────────────────────────
class _StaffFormSheet extends ConsumerStatefulWidget {
  const _StaffFormSheet({this.existing});
  final StaffData? existing;

  @override
  ConsumerState<_StaffFormSheet> createState() => _StaffFormSheetState();
}

class _StaffFormSheetState extends ConsumerState<_StaffFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  late final _kanaCtrl = TextEditingController(text: widget.existing?.nameKana ?? '');
  late final _phoneCtrl = TextEditingController(text: widget.existing?.phone ?? '');
  late final _emailCtrl = TextEditingController(text: widget.existing?.email ?? '');
  late final _hireDateCtrl = TextEditingController(text: widget.existing?.hireDate ?? '');
  late final _pinCtrl = TextEditingController(text: widget.existing?.pin ?? '');
  late final _notesCtrl = TextEditingController(text: widget.existing?.notes ?? '');
  late String _role = widget.existing?.role ?? 'stylist';
  late String _color = widget.existing?.color ?? staffColorOptions[0];
  bool _saving = false;

  bool get isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kanaCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _hireDateCtrl.dispose();
    _pinCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ハンドル
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ヘッダー
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Text(
                  isEdit ? 'スタッフ編集' : 'スタッフ追加',
                  style: AppTextStyles.h3
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (isEdit)
                  TextButton(
                    onPressed: _confirmDelete,
                    child: Text('削除',
                        style: TextStyle(color: AppColors.error)),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(),
          // フォーム
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 색상 선택
                      _label('アバターカラー'),
                      const SizedBox(height: 8),
                      _ColorPicker(
                        selected: _color,
                        onChanged: (c) => setState(() => _color = c),
                      ),
                      const SizedBox(height: 16),
                      // 이름
                      Row(children: [
                        Expanded(
                          child: _Field(
                            ctrl: _nameCtrl,
                            label: '名前 *',
                            hint: '山田 花子',
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? '必須項目です' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                            ctrl: _kanaCtrl,
                            label: 'フリガナ',
                            hint: 'ヤマダ ハナコ',
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // 역할
                      _label('役割'),
                      const SizedBox(height: 8),
                      _RoleSelector(
                        selected: _role,
                        onChanged: (r) => setState(() => _role = r),
                      ),
                      const SizedBox(height: 12),
                      // 연락처
                      Row(children: [
                        Expanded(
                          child: _Field(
                            ctrl: _phoneCtrl,
                            label: '電話番号',
                            hint: '090-0000-0000',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                            ctrl: _emailCtrl,
                            label: 'メール',
                            hint: 'staff@salon.jp',
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // 입사일 + PIN
                      Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label('入社日'),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _hireDateCtrl,
                                readOnly: true,
                                decoration: InputDecoration(
                                  hintText: 'YYYY-MM-DD',
                                  suffixIcon: _hireDateCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 16),
                                          onPressed: () =>
                                              setState(() => _hireDateCtrl.clear()),
                                        )
                                      : const Icon(Icons.calendar_month_outlined,
                                          size: 16),
                                ),
                                onTap: () async {
                                  DateTime initial = DateTime.now();
                                  if (_hireDateCtrl.text.isNotEmpty) {
                                    initial = DateTime.tryParse(_hireDateCtrl.text) ??
                                        DateTime.now();
                                  }
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: initial,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _hireDateCtrl.text =
                                          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                            ctrl: _pinCtrl,
                            label: 'PINコード (4桁)',
                            hint: '1234',
                            maxLength: 4,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              if (v.length != 4 ||
                                  int.tryParse(v) == null) {
                                return '4桁の数字を入力';
                              }
                              return null;
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // 메모
                      _Field(
                        ctrl: _notesCtrl,
                        label: 'メモ',
                        hint: '備考など',
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 저장 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? '変更を保存' : 'スタッフを追加'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      if (isEdit) {
        await ref.read(staffNotifierProvider.notifier).updateStaff(
              widget.existing!.id,
              StaffCompanion(
                name: Value(_nameCtrl.text.trim()),
                nameKana: Value(
                    _kanaCtrl.text.trim().isEmpty ? null : _kanaCtrl.text.trim()),
                role: Value(_role),
                color: Value(_color),
                phone: Value(
                    _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
                email: Value(
                    _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim()),
                hireDate: Value(
                    _hireDateCtrl.text.trim().isEmpty ? null : _hireDateCtrl.text.trim()),
                pin: Value(
                    _pinCtrl.text.trim().isEmpty ? null : _pinCtrl.text.trim()),
                notes: Value(
                    _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
                updatedAt: Value(now),
              ),
            );
      } else {
        await ref.read(staffNotifierProvider.notifier).addStaff(
              StaffCompanion(
                id: Value(newStaffId()),
                name: Value(_nameCtrl.text.trim()),
                nameKana: Value(
                    _kanaCtrl.text.trim().isEmpty ? null : _kanaCtrl.text.trim()),
                role: Value(_role),
                color: Value(_color),
                phone: Value(
                    _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
                email: Value(
                    _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim()),
                hireDate: Value(
                    _hireDateCtrl.text.trim().isEmpty ? null : _hireDateCtrl.text.trim()),
                pin: Value(
                    _pinCtrl.text.trim().isEmpty ? null : _pinCtrl.text.trim()),
                notes: Value(
                    _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('スタッフを削除'),
        content: Text('「${widget.existing!.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(staffNotifierProvider.notifier)
                  .deactivateStaff(widget.existing!.id);
              if (mounted) Navigator.pop(context);
            },
            child: Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

// ─── 역할 선택기 ──────────────────────────────────────────────────────────
class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: staffRoles.map((r) {
        final isSelected = r.$1 == selected;
        return FilterChip(
          label: Text(r.$2),
          selected: isSelected,
          onSelected: (_) => onChanged(r.$1),
          showCheckmark: false,
          selectedColor: AppColors.primary.withAlpha(30),
          labelStyle: AppTextStyles.caption.copyWith(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontWeight:
                isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}

// ─── 색상 선택기 ──────────────────────────────────────────────────────────
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: staffColorOptions.map((hex) {
        final color = _parseColor(hex);
        final isSelected = hex == selected;
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: AppColors.textPrimary, width: 2.5)
                  : Border.all(color: Colors.transparent, width: 2.5),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: color.withAlpha(120),
                          blurRadius: 6,
                          spreadRadius: 1)
                    ]
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        );
      }).toList(),
    );
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_outline, size: 72, color: AppColors.border),
          const SizedBox(height: 12),
          Text(
            'スタッフがまだいません',
            style: AppTextStyles.body1
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('最初のスタッフを追加'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

// ─── 공통 텍스트 필드 ────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.validator,
  });
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

// ─── 유틸 ─────────────────────────────────────────────────────────────────
Widget _label(String text) => Text(
      text,
      style: AppTextStyles.label
          .copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
    );

Color _parseColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return AppColors.primary;
  }
}

String _firstChar(String s) =>
    s.isEmpty ? '?' : String.fromCharCode(s.runes.first);

String _fmtNum(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
