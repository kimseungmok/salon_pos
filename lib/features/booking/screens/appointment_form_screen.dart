import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/database/app_database.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../pos/providers/pos_provider.dart';

const _uuid = Uuid();

class AppointmentFormScreen extends ConsumerStatefulWidget {
  const AppointmentFormScreen({
    super.key,
    this.appointmentId,
    this.initialStartAt,
    this.initialStaffId,
    this.initialCustomerId,
    this.initialCustomerName,
  });
  final String? appointmentId; // null = 신규
  final DateTime? initialStartAt;
  final String? initialStaffId;
  final String? initialCustomerId;
  final String? initialCustomerName;

  @override
  ConsumerState<AppointmentFormScreen> createState() => _AppointmentFormScreenState();
}

class _AppointmentFormScreenState extends ConsumerState<AppointmentFormScreen> {
  final _noteCtrl = TextEditingController();

  String? _customerId;
  String? _customerName;
  String? _staffId;
  late DateTime _startAt;
  int _durationMin = 60;
  List<MenusData> _selectedMenus = [];
  bool _saving = false;
  bool _loading = true;

  // 반복 예약
  String _repeatType = 'none'; // none / weekly / biweekly / monthly
  int _repeatCount = 4; // 총 몇 회(본인 포함)

  @override
  void initState() {
    super.initState();
    // 다음 30분 단위 정각으로 스냅
    final now = DateTime.now();
    final snapped = _snapToNext30(now);
    _startAt = widget.initialStartAt ?? snapped;
    _staffId = widget.initialStaffId;
    _customerId = widget.initialCustomerId;
    _customerName = widget.initialCustomerName;
    if (widget.appointmentId != null) {
      _loadExisting();
    } else {
      setState(() => _loading = false);
    }
  }

  /// 현재 시각 기준 다음 30분 단위로 올림
  DateTime _snapToNext30(DateTime dt) {
    final minute = dt.minute;
    final addMin = minute == 0 ? 0 : (30 - minute % 30) % 30 == 0 ? 30 : (30 - minute % 30);
    return dt.add(Duration(minutes: addMin)).copyWith(second: 0, millisecond: 0);
  }

  Future<void> _loadExisting() async {
    final db = ref.read(databaseProvider);

    // 예약 기본 정보 로드
    final apt = await (db.select(db.appointments)
          ..where((t) => t.id.equals(widget.appointmentId!)))
        .getSingleOrNull();
    if (apt == null || !mounted) {
      setState(() => _loading = false);
      return;
    }

    // 고객명 조회
    String? customerName;
    if (apt.customerId != null) {
      // DB에서 직접 id로 조회
      final custResult = await (db.select(db.customers)
            ..where((t) => t.id.equals(apt.customerId!)))
          .getSingleOrNull();
      customerName = custResult?.name;
    }

    // 예약 메뉴 로드
    final menuLinks = await (db.select(db.appointmentMenus)
          ..where((t) => t.appointmentId.equals(widget.appointmentId!))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();

    // 메뉴 상세 조회
    final menus = <MenusData>[];
    for (final link in menuLinks) {
      final menu = await (db.select(db.menus)
            ..where((t) => t.id.equals(link.menuId)))
          .getSingleOrNull();
      if (menu != null) menus.add(menu);
    }

    final startDt = DateTime.tryParse(apt.startAt) ?? _startAt;
    final endDt = DateTime.tryParse(apt.endAt);

    if (!mounted) return;
    setState(() {
      _staffId = apt.staffId;
      _startAt = startDt;
      if (endDt != null) _durationMin = endDt.difference(startDt).inMinutes;
      _noteCtrl.text = apt.notes ?? '';
      _customerId = apt.customerId;
      _customerName = customerName;
      _selectedMenus = menus;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffList = ref.watch(activeStaffProvider).valueOrNull ?? [];

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.appointmentId == null ? '予約追加' : '予約編集'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存',
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ① 顧客 ──────────────────────────────────────────────────────
              InkWell(
                onTap: () => _showCustomerSearch(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 18,
                          color: _customerId != null
                              ? AppColors.primary
                              : AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(_customerId != null ? '顧客' : '顧客を選択',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _customerName ?? '',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_customerId != null)
                        GestureDetector(
                          onTap: () => setState(() {
                            _customerId = null;
                            _customerName = null;
                          }),
                          child: const Icon(Icons.close, size: 16,
                              color: AppColors.textSecondary),
                        )
                      else
                        const Icon(Icons.chevron_right, size: 16,
                            color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),

              // ② 担当スタッフ ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.people_outline, size: 18,
                        color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Text('担当',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: staffList.isEmpty
                          ? Text('スタッフ未登録',
                              style: AppTextStyles.caption
                                  .copyWith(color: AppColors.textSecondary))
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                spacing: 6,
                                children: staffList.map((s) {
                                  final isSelected = _staffId == s.id;
                                  final color = Color(int.tryParse(
                                          s.color.replaceFirst('#', '0xFF')) ??
                                      0xFF0064FF);
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _staffId = s.id),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 120),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? color.withAlpha(25)
                                            : AppColors.background,
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.full),
                                        border: Border.all(
                                            color: isSelected
                                                ? color
                                                : AppColors.border,
                                            width: isSelected ? 1.5 : 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 9,
                                            backgroundColor: color,
                                            child: Text(
                                                s.name.substring(0, 1),
                                                style: const TextStyle(
                                                    fontSize: 8,
                                                    color: Colors.white)),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(s.name,
                                              style: AppTextStyles.caption
                                                  .copyWith(
                                                      color: isSelected
                                                          ? color
                                                          : AppColors
                                                              .textPrimary,
                                                      fontWeight: isSelected
                                                          ? FontWeight.w600
                                                          : FontWeight.normal)),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ③ 日付・時間・所要時間 (한 row) ───────────────────────────────
              IntrinsicHeight(
                child: Row(
                  children: [
                    // 날짜
                    Expanded(
                      flex: 5,
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startAt,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            locale: const Locale('ja'),
                          );
                          if (picked != null) {
                            setState(() => _startAt = DateTime(
                                picked.year, picked.month, picked.day,
                                _startAt.hour, _startAt.minute));
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Text(
                                '${_startAt.month}/${_startAt.day}',
                                style: AppTextStyles.body2
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // 시간
                    Expanded(
                      flex: 4,
                      child: InkWell(
                        onTap: () => _showTimePicker(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Text(
                                '${_startAt.hour}:${_startAt.minute.toString().padLeft(2, '0')}',
                                style: AppTextStyles.body2
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    // 소요시간
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.timelapse_outlined,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: DropdownButton<int>(
                                value: _durationMin.clamp(30, 240),
                                underline: const SizedBox.shrink(),
                                isExpanded: true,
                                style: AppTextStyles.body2
                                    .copyWith(fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                                items: [30, 45, 60, 90, 120, 150, 180, 240]
                                    .map((v) => DropdownMenuItem(
                                        value: v, child: Text('$v分')))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _durationMin = v ?? 60),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ④ メニュー ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.spa_outlined, size: 18,
                        color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Text('メニュー',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary)),
                    const Spacer(),
                    // 前回メニューを使う (고객 선택 + 신규 + 메뉴 미선택 시)
                    if (_customerId != null &&
                        widget.appointmentId == null &&
                        _selectedMenus.isEmpty)
                      TextButton.icon(
                        onPressed: () => _loadPrevMenus(context),
                        icon: const Icon(Icons.history, size: 15),
                        label: const Text('前回を使う',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: AppColors.textSecondary),
                      ),
                    TextButton.icon(
                      onPressed: () => _showMenuPicker(context),
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('追加',
                          style: TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.primary),
                    ),
                  ],
                ),
              ),
              if (_selectedMenus.isEmpty)
                InkWell(
                  onTap: () => _showMenuPicker(context),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Text('メニューを選択してください',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    children: [
                      ..._selectedMenus.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(e.value.name,
                                      style: AppTextStyles.body2),
                                ),
                                Text(
                                  '¥${e.value.price}  ${e.value.durationMin}分',
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textSecondary),
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(
                                      () => _selectedMenus.removeAt(e.key)),
                                  child: const Icon(
                                      Icons.remove_circle_outline,
                                      color: AppColors.error,
                                      size: 18),
                                ),
                              ],
                            ),
                          )),
                      if (_selectedMenus.length > 1) ...[
                        const Divider(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '合計 ¥${_selectedMenus.fold(0, (s, m) => s + m.price)}  '
                              '${_selectedMenus.fold(0, (s, m) => s + m.durationMin)}分',
                              style: AppTextStyles.body2.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              const Divider(height: 1),

              // ⑤ メモ ────────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.notes_outlined, size: 18,
                        color: AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        style: AppTextStyles.body2,
                        decoration: InputDecoration(
                          hintText: 'メモ・ご要望など',
                          hintStyle: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary),
                          border: InputBorder.none,
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ⑥ 繰り返し予約 (신규 예약 시만) ────────────────────────────────
              if (widget.appointmentId == null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.repeat_outlined, size: 18,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Text('繰り返し予約', style: AppTextStyles.body2
                              .copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 반복 타입 칩 선택
                      Wrap(
                        spacing: 6,
                        children: [
                          _repeatChip('none', 'なし'),
                          _repeatChip('weekly', '毎週'),
                          _repeatChip('biweekly', '隔週'),
                          _repeatChip('monthly', '毎月'),
                        ],
                      ),
                      // 반복 횟수 (none 제외)
                      if (_repeatType != 'none') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text('合計回数: ', style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary)),
                            ...List.generate(5, (i) {
                              final n = (i + 2); // 2~6
                              final selected = _repeatCount == n;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(6),
                                  onTap: () => setState(() => _repeatCount = n),
                                  child: Container(
                                    width: 36, height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.background,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : AppColors.border,
                                      ),
                                    ),
                                    child: Text('${n}回',
                                        style: AppTextStyles.caption.copyWith(
                                          color: selected
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        )),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _repeatSummary(),
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

            ],
          ),
        ),
      ),
    );
  }

  Widget _repeatChip(String type, String label) {
    final selected = _repeatType == type;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _repeatType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: AppTextStyles.caption.copyWith(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            )),
      ),
    );
  }

  String _repeatSummary() {
    if (_repeatType == 'none') return '';
    final intervals = {
      'weekly': const Duration(days: 7),
      'biweekly': const Duration(days: 14),
      'monthly': null,
    };
    final dates = <String>[];
    DateTime cur = _startAt;
    for (int i = 0; i < _repeatCount; i++) {
      dates.add('${cur.month}/${cur.day}');
      if (i < _repeatCount - 1) {
        if (_repeatType == 'monthly') {
          cur = DateTime(cur.year, cur.month + 1, cur.day,
              cur.hour, cur.minute);
        } else {
          cur = cur.add(intervals[_repeatType]!);
        }
      }
    }
    return dates.join(' → ');
  }

  // ─── 前回のメニューを復元 ──────────────────────────────────────────────────
  Future<void> _loadPrevMenus(BuildContext ctx) async {
    if (_customerId == null) return;
    final db = ref.read(databaseProvider);
    // 고객의 가장 최근 예약 조회
    final prevApt = await (db.select(db.appointments)
          ..where((t) =>
              t.customerId.equals(_customerId!) &
              t.status.isNotIn(['cancelled']))
          ..orderBy([(t) => OrderingTerm.desc(t.startAt)])
          ..limit(1))
        .getSingleOrNull();
    if (prevApt == null) {
      if (ctx.mounted) {
        showTopBanner(ctx, '過去の予約が見つかりませんでした',
            icon: Icons.history, color: AppColors.textSecondary);
      }
      return;
    }
    // 해당 예약의 메뉴 조회
    final menuLinks = await (db.select(db.appointmentMenus)
          ..where((t) => t.appointmentId.equals(prevApt.id))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    final menus = <MenusData>[];
    for (final link in menuLinks) {
      final menu = await (db.select(db.menus)
            ..where((t) => t.id.equals(link.menuId)))
          .getSingleOrNull();
      if (menu != null) menus.add(menu);
    }
    if (menus.isEmpty) {
      if (ctx.mounted) {
        showTopBanner(ctx, '前回の予約にメニューがありません',
            icon: Icons.history, color: AppColors.textSecondary);
      }
      return;
    }
    setState(() {
      _selectedMenus = menus;
      _durationMin = menus.fold<int>(0, (s, m) => s + m.durationMin);
      if (_durationMin < 30) _durationMin = 30;
    });
    if (ctx.mounted) {
      showTopBanner(ctx, '前回のメニューを復元しました (${menus.length}件)',
          icon: Icons.check_circle_outline, color: AppColors.success);
    }
  }

  // ─── 고객 검색 다이얼로그 ─────────────────────────────────────────────────
  void _showCustomerSearch(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 480,
          height: 520,
          child: _CustomerSearchDialog(
            onSelected: (id, name) {
              setState(() {
                _customerId = id;
                _customerName = name;
              });
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  // ─── 메뉴 선택 다이얼로그 ─────────────────────────────────────────────────
  void _showMenuPicker(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 480,
          height: 520,
          child: _MenuPickerDialog(
            alreadySelected: _selectedMenus.map((m) => m.id).toSet(),
            onSelected: (menu) {
              setState(() {
                if (!_selectedMenus.any((m) => m.id == menu.id)) {
                  _selectedMenus = [..._selectedMenus, menu];
                  // 소요 시간 자동 합산
                  _durationMin = _selectedMenus
                      .fold<int>(0, (s, m) => s + m.durationMin);
                  if (_durationMin < 30) _durationMin = 30;
                }
              });
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  // ─── 시간 선택 다이얼로그 ─────────────────────────────────────────────────
  void _showTimePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _TimePickerDialog(
        initial: _startAt,
        onConfirm: (hour, minute) {
          setState(() => _startAt = DateTime(
              _startAt.year, _startAt.month, _startAt.day, hour, minute));
        },
      ),
    );
  }

  // ─── 저장 ─────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_staffId == null) {
      showTopBanner(context, '担当スタッフを選択してください',
          icon: Icons.person_outline);
      return;
    }
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final endAt = _startAt.add(Duration(minutes: _durationMin));

      if (widget.appointmentId == null) {
        // ── 신규 (반복 포함) ──────────────────────────────────────────
        final totalCount = _repeatType == 'none' ? 1 : _repeatCount;
        DateTime curStart = _startAt;
        for (int rep = 0; rep < totalCount; rep++) {
          final curEnd = curStart.add(Duration(minutes: _durationMin));
          final aptId = _uuid.v4();
          await db.into(db.appointments).insert(AppointmentsCompanion.insert(
            id: aptId,
            staffId: _staffId!,
            customerId: Value(_customerId),
            startAt: curStart.toIso8601String(),
            endAt: curEnd.toIso8601String(),
            status: const Value('confirmed'),
            notes: Value(_noteCtrl.text.isEmpty ? null : _noteCtrl.text),
          ));
          for (int i = 0; i < _selectedMenus.length; i++) {
            final m = _selectedMenus[i];
            await db.into(db.appointmentMenus).insert(
              AppointmentMenusCompanion.insert(
                id: _uuid.v4(),
                appointmentId: aptId,
                menuId: m.id,
                menuName: m.name,
                price: m.price,
                durationMin: m.durationMin,
                sortOrder: Value(i),
              ),
            );
          }
          // 다음 날짜 계산
          if (rep < totalCount - 1) {
            if (_repeatType == 'weekly') {
              curStart = curStart.add(const Duration(days: 7));
            } else if (_repeatType == 'biweekly') {
              curStart = curStart.add(const Duration(days: 14));
            } else if (_repeatType == 'monthly') {
              curStart = DateTime(curStart.year, curStart.month + 1,
                  curStart.day, curStart.hour, curStart.minute);
            }
          }
        }
      } else {
        // ── 수정 ───────────────────────────────────────────────────────
        await (db.update(db.appointments)
              ..where((t) => t.id.equals(widget.appointmentId!)))
            .write(AppointmentsCompanion(
          staffId: Value(_staffId!),
          customerId: Value(_customerId),
          startAt: Value(_startAt.toIso8601String()),
          endAt: Value(endAt.toIso8601String()),
          notes: Value(_noteCtrl.text.isEmpty ? null : _noteCtrl.text),
          updatedAt: Value(DateTime.now().toIso8601String()),
        ));
        // 기존 메뉴 전부 삭제 후 재삽입
        await (db.delete(db.appointmentMenus)
              ..where((t) => t.appointmentId.equals(widget.appointmentId!)))
            .go();
        for (int i = 0; i < _selectedMenus.length; i++) {
          final m = _selectedMenus[i];
          await db.into(db.appointmentMenus).insert(
            AppointmentMenusCompanion.insert(
              id: _uuid.v4(),
              appointmentId: widget.appointmentId!,
              menuId: m.id,
              menuName: m.name,
              price: m.price,
              durationMin: m.durationMin,
              sortOrder: Value(i),
            ),
          );
        }
      }

      if (mounted) {
        if (widget.appointmentId == null &&
            _repeatType != 'none' && _repeatCount > 1) {
          showTopBanner(context,
              '${_repeatCount}件の予約を登録しました',
              icon: Icons.repeat_outlined,
              color: AppColors.success);
          await Future.delayed(const Duration(milliseconds: 600));
        }
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, '保存エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
        setState(() => _saving = false);
      }
    }
  }
}

// ─── 고객 검색 다이얼로그 내용 ────────────────────────────────────────────
class _CustomerSearchDialog extends ConsumerStatefulWidget {
  const _CustomerSearchDialog({required this.onSelected});
  final void Function(String id, String name) onSelected;

  @override
  ConsumerState<_CustomerSearchDialog> createState() =>
      _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends ConsumerState<_CustomerSearchDialog> {
  final _ctrl = TextEditingController();
  List<Customer> _results = [];
  bool _searching = false;
  bool _creatingCustomer = false;

  @override
  void initState() {
    super.initState();
    _loadAll(); // 초기에 전체 목록 표시
  }

  Future<void> _loadAll() async {
    setState(() => _searching = true);
    final db = ref.read(databaseProvider);
    final res = await (db.select(db.customers)
          ..orderBy([(t) => OrderingTerm.desc(t.totalVisits)])
          ..limit(50))
        .get();
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) { _loadAll(); return; }
    setState(() => _searching = true);
    final db = ref.read(databaseProvider);
    final res = await db.searchCustomers(q);
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  Future<void> _showQuickCreateDialog(BuildContext context) async {
    if (_creatingCustomer) return;
    _creatingCustomer = true;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _QuickCreateDialog(initialName: _ctrl.text.trim()),
    );
    _creatingCustomer = false;

    if (result == null || !mounted) return;

    try {
      final db = ref.read(databaseProvider);
      final id = const Uuid().v4();
      await db.into(db.customers).insert(CustomersCompanion.insert(
        id: id,
        name: result['name']!,
        phone: Value(result['phone']!.isEmpty ? null : result['phone']),
        totalVisits: const Value(0),
        totalSpent: const Value(0),
        pointBalance: const Value(0),
        isVip: const Value(false),
      ));
      if (mounted) widget.onSelected(id, result['name']!);
    } catch (e) {
      if (mounted) {
        showTopBanner(context, '登録エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(children: [
            Text('顧客選択', style: AppTextStyles.h4),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showQuickCreateDialog(context),
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: const Text('新規登録'),
            ),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        // 검색
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '名前・カナ・電話番号で検索',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _search,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        // 목록
        Expanded(
          child: _searching
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person_search_outlined,
                              size: 48, color: AppColors.textDisabled),
                          const SizedBox(height: 8),
                          Text(
                            _ctrl.text.isEmpty
                                ? '顧客が登録されていません'
                                : '「${_ctrl.text}」で顧客が見つかりません',
                            style: AppTextStyles.caption,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () =>
                                _showQuickCreateDialog(context),
                            icon: const Icon(Icons.person_add_outlined,
                                size: 16),
                            label: Text(
                              _ctrl.text.trim().isEmpty
                                  ? '新規顧客を登録'
                                  : '「${_ctrl.text.trim()}」を新規登録',
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final c = _results[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c.isVip
                                ? AppColors.warningLight
                                : AppColors.primaryLight,
                            child: Text(
                              c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
                              style: TextStyle(
                                color: c.isVip
                                    ? AppColors.warning
                                    : AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          title: Row(children: [
                            Text(c.name,
                                style: AppTextStyles.body2
                                    .copyWith(fontWeight: FontWeight.w600)),
                            if (c.isVip) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('VIP',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.warning, fontSize: 10)),
                              ),
                            ],
                            if (c.cautionFlag || c.allergies != null) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: [
                                  if (c.cautionNote != null) '注意: ${c.cautionNote}',
                                  if (c.allergies != null) 'アレルギー: ${c.allergies}',
                                ].join('\n'),
                                child: const Icon(Icons.warning_amber_rounded,
                                    size: 14, color: AppColors.error),
                              ),
                            ],
                          ]),
                          subtitle: Row(children: [
                            if (c.nameKana != null)
                              Text(c.nameKana!, style: AppTextStyles.caption),
                            if (c.phone != null) ...[
                              const SizedBox(width: 8),
                              Text(c.phone!, style: AppTextStyles.caption),
                            ],
                          ]),
                          trailing: Text('${c.totalVisits}回',
                              style: AppTextStyles.caption),
                          onTap: () => widget.onSelected(c.id, c.name),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─── 메뉴 선택 다이얼로그 내용 ────────────────────────────────────────────
class _MenuPickerDialog extends ConsumerStatefulWidget {
  const _MenuPickerDialog(
      {required this.onSelected, required this.alreadySelected});
  final void Function(MenusData) onSelected;
  final Set<String> alreadySelected;

  @override
  ConsumerState<_MenuPickerDialog> createState() => _MenuPickerDialogState();
}

class _MenuPickerDialogState extends ConsumerState<_MenuPickerDialog> {
  final _ctrl = TextEditingController();
  List<MenusData> _results = [];

  Future<void> _search(String q) async {
    final db = ref.read(databaseProvider);
    final query = db.select(db.menus)..where((t) => t.isActive.equals(true));
    if (q.trim().isNotEmpty) query.where((t) => t.name.like('%$q%'));
    query.orderBy([(t) => OrderingTerm(expression: t.sortOrder)]);
    final res = await (query..limit(50)).get();
    if (mounted) setState(() => _results = res);
  }

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(children: [
            Text('メニュー選択', style: AppTextStyles.h4),
            const Spacer(),
            IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
          ]),
        ),
        // 검색
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'メニュー検索',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _search,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        // 목록
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text('メニューが登録されていません',
                      style: AppTextStyles.caption))
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16),
                  itemBuilder: (_, i) {
                    final m = _results[i];
                    final already = widget.alreadySelected.contains(m.id);
                    return ListTile(
                      title: Text(m.name,
                          style: AppTextStyles.body2.copyWith(
                              color: already
                                  ? AppColors.textDisabled
                                  : AppColors.textPrimary)),
                      subtitle: Text('${m.durationMin}分',
                          style: AppTextStyles.caption),
                      trailing: Text('¥${m.price}',
                          style: AppTextStyles.label.copyWith(
                              color: already
                                  ? AppColors.textDisabled
                                  : AppColors.primary)),
                      onTap: already
                          ? null
                          : () => widget.onSelected(m),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── 시간 선택 다이얼로그 ────────────────────────────────────────────────
class _TimePickerDialog extends StatefulWidget {
  const _TimePickerDialog({required this.initial, required this.onConfirm});
  final DateTime initial;
  final void Function(int hour, int minute) onConfirm;

  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('開始時間'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 시
          _SpinnerColumn(
            value: _hour,
            min: 0, max: 23,
            label: '時',
            onChanged: (v) => setState(() => _hour = v),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          ),
          // 분 (15분 단위)
          _SpinnerColumn(
            value: _minute,
            min: 0, max: 45,
            step: 15,
            label: '分',
            onChanged: (v) => setState(() => _minute = v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル')),
        FilledButton(
          onPressed: () {
            widget.onConfirm(_hour, _minute);
            Navigator.pop(context);
          },
          child: const Text('確定'),
        ),
      ],
    );
  }
}

class _SpinnerColumn extends StatelessWidget {
  const _SpinnerColumn({
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.onChanged,
    this.step = 1,
  });
  final int value;
  final int min;
  final int max;
  final int step;
  final String label;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 4),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up),
          onPressed: () {
            int next = value + step;
            if (next > max) next = min;
            onChanged(next);
          },
        ),
        Container(
          width: 60,
          alignment: Alignment.center,
          child: Text(value.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () {
            int prev = value - step;
            if (prev < min) prev = max;
            onChanged(prev);
          },
        ),
      ],
    );
  }
}

// ─── 新規顧客 クイック登録ダイアログ ───────────────────────────────────────────
class _QuickCreateDialog extends StatefulWidget {
  const _QuickCreateDialog({required this.initialName});
  final String initialName;

  @override
  State<_QuickCreateDialog> createState() => _QuickCreateDialogState();
}

class _QuickCreateDialogState extends State<_QuickCreateDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _phoneCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新規顧客を登録'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '氏名 *',
                hintText: '例: 田中 美咲',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '電話番号（任意）',
                hintText: '例: 090-0000-0000',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(context, {
              'name': name,
              'phone': _phoneCtrl.text.trim(),
            });
          },
          child: const Text('登録'),
        ),
      ],
    );
  }
}
