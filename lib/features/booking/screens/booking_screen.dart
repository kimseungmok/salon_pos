import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../pos/providers/pos_provider.dart';
import '../../settings/providers/app_settings_provider.dart';
import '../providers/booking_provider.dart';
import 'appointment_form_screen.dart';

// ─── 캘린더 뷰 모드 ──────────────────────────────────────────────────────────
enum _ViewMode { day, week, month, list }

const _uuid = Uuid();

// ─── 캘린더 상수 (시간 범위는 설정에서 동적으로 변경 가능) ──────────────────
// _startHour / _endHour 는 파일 레벨 변수로 선언하여
// 설정 변경 시 앱 전체에 즉시 반영됨
int _startHour = 9;
int _endHour = 21;
const double _slotHeight = 64.0;   // 1시간 = 64px (1분 ≈ 1.067px)
// 일 단위 뷰 스태프 컬럼 폭: 5명이 뷰포트에 딱 맞도록 LayoutBuilder에서 동적 계산
// (_DayCalendarState._staffColWidth 인스턴스 변수로 관리)
const double _staffColWidthFallback = 100.0;
const double _timeColWidth = 52.0;
const double _headerHeight = 48.0;       // 날짜 헤더 (WeekBar, 주뷰 공통)
const double _dayStaffHeaderHeight = 36.0; // 일뷰 스태프 헤더

double _minToY(int minutes) => minutes * _slotHeight / 60;
int _yToMin(double y) => (y * 60 / _slotHeight).round();
double get _totalHeight => (_endHour - _startHour) * _slotHeight;
bool _dateIsToday(DateTime d) {
  final n = DateTime.now();
  return d.year == n.year && d.month == n.month && d.day == n.day;
}

// ─── 상태 필터 ────────────────────────────────────────────────────────────
const _statusFilters = [
  (null, '全て'),
  ('pending', '確認待ち'),
  ('confirmed', '確認済'),
  ('in_progress', '施術中'),
  ('no_show', 'ノーショー'),
];

// ─── 예약 상태 색상 ───────────────────────────────────────────────────────
const _statusColors = <String, Color>{
  'pending': Color(0xFFFFB300),
  'confirmed': Color(0xFF0064FF),
  'in_progress': Color(0xFF00B746),
  'completed': Color(0xFF8B95A1),
  'no_show': Color(0xFFF04452),
  'cancelled': Color(0xFFF04452),
};

Color _statusColor(String status) =>
    _statusColors[status] ?? AppColors.primary;

// ─── BookingScreen ────────────────────────────────────────────────────────
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  final _pageController = PageController(initialPage: 500);
  static const _basePage = 500;
  // 미니달력 탭 시 -1일 버그 방지: 기준일을 자정(midnight)으로 정규화
  static final _baseDate = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();
  String? _filterStatus;
  String? _filterStaffId;
  _ViewMode _viewMode = _ViewMode.day;
  // 주뷰에서 싱글클릭으로 포커싱된 날짜 (예약 추가 시 사용)
  DateTime? _weekFocusedDate;
  // 사이드패널에 표시할 날짜 (모든 뷰에서 포커싱 날짜 공유)
  late DateTime _sidebarDate = DateTime.now();

  DateTime _pageToDate(int page) =>
      _baseDate.add(Duration(days: page - _basePage));

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onDateChanged(DateTime d) {
    ref.read(selectedDateProvider.notifier).state = d;
    setState(() => _sidebarDate = d);
    if (_viewMode == _ViewMode.day) {
      final diff = d.difference(_baseDate).inDays;
      _pageController.jumpToPage(_basePage + diff);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    // 설정에서 시간 범위 읽어 전역 변수 업데이트
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    if (settings != null) {
      _startHour = settings.calendarStartHour;
      _endHour = settings.calendarEndHour;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─ 좌측 패널 (미니 달력 + 예약 리스트) ──────────────────────
          _LeftPanel(
            selectedDate: _sidebarDate,
            viewMode: _viewMode,
            onDateChanged: _onDateChanged,
            onAptTap: (det) => _showAptDetail(context, det),
            onFocusDateChanged: (d) => setState(() {
              _weekFocusedDate = d;
              // 미니달력 포커스 시 왼쪽 패널도 해당 날짜로 갱신
              if (d != null) _sidebarDate = d;
            }),
          ),

          // ─ 우측: 헤더 + 캘린더 ────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                _BookingHeader(
                  viewMode: _viewMode,
                  filterStatus: _filterStatus,
                  filterStaffId: _filterStaffId,
                  selectedDate: selectedDate,
                  onDateChanged: _onDateChanged,
                  onAddTap: () => _openForm(
                    context, null,
                    initialStartAt: _viewMode == _ViewMode.week
                        ? _weekFocusedDate
                        : null,
                  ),
                  onBlockTap: () => _showAddBlockDialog(
                    context,
                    _viewMode == _ViewMode.week && _weekFocusedDate != null
                        ? _weekFocusedDate!
                        : selectedDate,
                  ),
                  onFilterChanged: (s) => setState(() => _filterStatus = s),
                  onStaffFilterChanged: (s) => setState(() => _filterStaffId = s),
                  onViewModeChanged: (m) {
                    setState(() {
                      _viewMode = m;
                      _sidebarDate = selectedDate;
                    });
                  },
                ),
                // ─ 캘린더 본체 ───────────────────────────────────────
                Expanded(
                  child: switch (_viewMode) {
                    _ViewMode.day => PageView.builder(
                        controller: _pageController,
                        onPageChanged: (page) {
                          final date = _pageToDate(page);
                          ref.read(selectedDateProvider.notifier).state = date;
                          setState(() => _sidebarDate = date);
                        },
                        itemBuilder: (context, page) {
                          final date = _pageToDate(page);
                          return _DayCalendar(
                            date: date,
                            filterStatus: _filterStatus,
                            filterStaffId: _filterStaffId,
                            onEmptySlotTap: (dt, staffId) =>
                                _quickCreate(context, dt, staffId),
                          );
                        },
                      ),
                    _ViewMode.week => _WeekScrollView(
                        selectedDate: selectedDate,
                        filterStatus: _filterStatus,
                        filterStaffId: _filterStaffId,
                        focusedDate: _weekFocusedDate,
                        onDateChanged: _onDateChanged,
                        onSwitchToDay: (d) {
                          _onDateChanged(d);
                          setState(() {
                            _viewMode = _ViewMode.day;
                            _weekFocusedDate = null;
                          });
                        },
                        onFocusedDateChanged: (d) {
                          setState(() {
                            _weekFocusedDate = d;
                            if (d != null) _sidebarDate = d;
                          });
                        },
                      ),
                    _ViewMode.month => _MonthCalendar(
                        selectedDate: selectedDate,
                        onDateFocused: (d) => _onDateChanged(d),
                        filterStatus: _filterStatus,
                        filterStaffId: _filterStaffId,
                      ),
                    _ViewMode.list => _ListCalendar(
                        selectedDate: selectedDate,
                        filterStatus: _filterStatus,
                        filterStaffId: _filterStaffId,
                        onAptTap: (det) => _showAptDetail(context, det),
                      ),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAptDetail(BuildContext ctx, AppointmentDetail det) {
    Future.microtask(() {
      if (!ctx.mounted) return;
      showDialog(
        context: ctx,
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(80),
        useRootNavigator: true,
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(ctx),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
                horizontal: 80, vertical: 40),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            child: SizedBox(
              width: 420,
              child: _AppointmentDetailSheet(detail: det),
            ),
          ),
        ),
      );
    });
  }

  void _openForm(BuildContext ctx, String? appointmentId,
      {DateTime? initialStartAt}) {
    Navigator.push(
      ctx,
      MaterialPageRoute(
          builder: (_) => AppointmentFormScreen(
              appointmentId: appointmentId,
              initialStartAt: initialStartAt)),
    );
  }

  Future<void> _showAddBlockDialog(BuildContext ctx, DateTime date) async {
    await showDialog(
      context: ctx,
      builder: (_) => _AddBlockDialog(initialDate: date),
    );
  }

  Future<void> _quickCreate(
      BuildContext ctx, DateTime startAt, String staffId) async {
    await showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 100),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 400,
          child: _QuickCreateSheet(startAt: startAt, staffId: staffId),
        ),
      ),
    );
  }
}

// ─── 헤더 ─────────────────────────────────────────────────────────────────
class _BookingHeader extends StatelessWidget {
  const _BookingHeader({
    required this.viewMode,
    required this.filterStatus,
    required this.filterStaffId,
    required this.selectedDate,
    required this.onAddTap,
    required this.onBlockTap,
    required this.onFilterChanged,
    required this.onStaffFilterChanged,
    required this.onViewModeChanged,
    required this.onDateChanged,
  });

  final _ViewMode viewMode;
  final String? filterStatus;
  final String? filterStaffId;
  final DateTime selectedDate;
  final VoidCallback onAddTap;
  final VoidCallback onBlockTap;
  final ValueChanged<String?> onFilterChanged;
  final ValueChanged<String?> onStaffFilterChanged;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          // ─ 날짜 네비게이션 ─────────────────────────────────────
          _DateNav(
            selectedDate: selectedDate,
            viewMode: viewMode,
            onChanged: onDateChanged,
          ),
          const SizedBox(width: 10),
          // ─ 예약 추가 버튼 ──────────────────────────────────────
          ElevatedButton.icon(
            onPressed: onAddTap,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('予約追加'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
          ),
          const SizedBox(width: 6),
          // ─ 블록 타임 추가 ─────────────────────────────────────
          OutlinedButton.icon(
            onPressed: onBlockTap,
            icon: const Icon(Icons.block_outlined, size: 16),
            label: const Text('ブロック'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
            ),
          ),
          // ─ 今日 버튼 (오늘이 아닐 때만 표시) ───────────────────
          if (!_dateIsToday(selectedDate)) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: () => onDateChanged(DateTime.now()),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: const BorderSide(color: AppColors.primary),
              ),
              child: const Text('今日',
                  style: TextStyle(fontSize: 13, color: AppColors.primary)),
            ),
          ],
          const Spacer(),
          // ─ 담당자 필터 드롭다운 ────────────────────────────────
          _StaffDropdown(
              filterStaffId: filterStaffId, onChanged: onStaffFilterChanged),
          const SizedBox(width: 6),
          // ─ 상태 필터 드롭다운 ──────────────────────────────────
          _StatusDropdown(
              filterStatus: filterStatus, onChanged: onFilterChanged),
          const SizedBox(width: 8),
          // ─ 日/週/月/リスト 드롭다운 ─────────────────────────────
          _ViewModeDropdown(viewMode: viewMode, onChanged: onViewModeChanged),
        ],
      ),
    );
  }
}

// ─── 상태 필터 드롭다운 ──────────────────────────────────────────────────
class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown(
      {required this.filterStatus, required this.onChanged});
  final String? filterStatus;
  final ValueChanged<String?> onChanged;

  String get _label {
    for (final (status, label) in _statusFilters) {
      if (status == filterStatus) return label;
    }
    return '全て';
  }

  @override
  Widget build(BuildContext context) {
    final color =
        filterStatus == null ? AppColors.primary : _statusColor(filterStatus!);
    return PopupMenuButton<String?>(
      tooltip: '',
      // onSelected은 null 값에서 미작동 케이스 있음 → itemBuilder.onTap 사용
      offset: const Offset(0, 38),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
      itemBuilder: (_) => _statusFilters.map((f) {
        final (status, label) = f;
        final c = status == null ? AppColors.primary : _statusColor(status);
        return PopupMenuItem<String?>(
          value: status,
          onTap: () {
            // 메뉴 닫힌 후 콜백 (microtask로 안전하게)
            Future.microtask(() => onChanged(status));
          },
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontWeight: status == filterStatus
                          ? FontWeight.w700
                          : FontWeight.w400)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── 담당자 필터 드롭다운 ─────────────────────────────────────────────────
class _StaffDropdown extends ConsumerWidget {
  const _StaffDropdown(
      {required this.filterStaffId, required this.onChanged});
  final String? filterStaffId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(activeStaffProvider).valueOrNull ?? [];

    String label = '全スタッフ';
    Color color = AppColors.textSecondary;
    if (filterStaffId != null) {
      for (final s in staff) {
        if (s.id == filterStaffId) {
          label = s.name;
          color = _parseColor(s.color);
          break;
        }
      }
    }

    return PopupMenuButton<String?>(
      tooltip: '',
      offset: const Offset(0, 38),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (filterStaffId != null)
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color)),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: color),
          ],
        ),
      ),
      itemBuilder: (_) => [
        PopupMenuItem<String?>(
          value: null,
          onTap: () => Future.microtask(() => onChanged(null)),
          child: Text('全スタッフ',
              style: TextStyle(
                  fontWeight: filterStaffId == null
                      ? FontWeight.w700
                      : FontWeight.w400)),
        ),
        ...staff.map((s) {
          final c = _parseColor(s.color);
          return PopupMenuItem<String?>(
            value: s.id,
            onTap: () => Future.microtask(() => onChanged(s.id)),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(s.name,
                    style: TextStyle(
                        fontWeight: s.id == filterStaffId
                            ? FontWeight.w700
                            : FontWeight.w400)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── 뷰 모드 드롭다운 ─────────────────────────────────────────────────────
class _ViewModeDropdown extends StatelessWidget {
  const _ViewModeDropdown(
      {required this.viewMode, required this.onChanged});
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onChanged;

  String get _label {
    switch (viewMode) {
      case _ViewMode.day:
        return '日';
      case _ViewMode.week:
        return '週';
      case _ViewMode.month:
        return '月';
      case _ViewMode.list:
        return '一覧';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ViewMode>(
      tooltip: '',
      onSelected: onChanged,
      offset: const Offset(0, 38),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
          ],
        ),
      ),
      itemBuilder: (_) => [
        _vmItem(_ViewMode.day, '日'),
        _vmItem(_ViewMode.week, '週'),
        _vmItem(_ViewMode.month, '月'),
        _vmItem(_ViewMode.list, '一覧'),
      ],
    );
  }

  PopupMenuItem<_ViewMode> _vmItem(_ViewMode m, String label) =>
      PopupMenuItem<_ViewMode>(
        value: m,
        child: Text(label,
            style: TextStyle(
                fontWeight:
                    viewMode == m ? FontWeight.w700 : FontWeight.w400)),
      );
}

// ─── 날짜 네비게이션 ──────────────────────────────────────────────────────
class _DateNav extends StatelessWidget {
  const _DateNav({
    required this.selectedDate,
    required this.viewMode,
    required this.onChanged,
  });

  final DateTime selectedDate;
  final _ViewMode viewMode;
  final ValueChanged<DateTime> onChanged;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: () => onChanged(_prevDate()),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        GestureDetector(
          onTap: () => _pickDate(context),
          child: Container(
            width: 140,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _label(),
              textAlign: TextAlign.center,
              style: AppTextStyles.body2.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: () => onChanged(_nextDate()),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  String _label() {
    switch (viewMode) {
      case _ViewMode.day:
        return '${selectedDate.month}月${selectedDate.day}日 (${_weekdays[selectedDate.weekday - 1]})';
      case _ViewMode.week:
        final end = selectedDate.add(const Duration(days: 6));
        return '${selectedDate.month}/${selectedDate.day}〜${end.month}/${end.day}';
      case _ViewMode.month:
      case _ViewMode.list:
        return '${selectedDate.year}年${selectedDate.month}月';
    }
  }

  DateTime _prevDate() {
    switch (viewMode) {
      case _ViewMode.day:
        return selectedDate.subtract(const Duration(days: 1));
      case _ViewMode.week:
        return selectedDate.subtract(const Duration(days: 7));
      case _ViewMode.month:
      case _ViewMode.list:
        return DateTime(selectedDate.year, selectedDate.month - 1, 1);
    }
  }

  DateTime _nextDate() {
    switch (viewMode) {
      case _ViewMode.day:
        return selectedDate.add(const Duration(days: 1));
      case _ViewMode.week:
        return selectedDate.add(const Duration(days: 7));
      case _ViewMode.month:
      case _ViewMode.list:
        return DateTime(selectedDate.year, selectedDate.month + 1, 1);
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) onChanged(picked);
  }
}

// ─── 하루 캘린더 (드래그 지원) ────────────────────────────────────────────
class _DayCalendar extends ConsumerStatefulWidget {
  const _DayCalendar({
    required this.date,
    required this.filterStatus,
    required this.onEmptySlotTap,
    this.filterStaffId,
  });

  final DateTime date;
  final String? filterStatus;
  final String? filterStaffId;
  final void Function(DateTime startAt, String staffId) onEmptySlotTap;

  @override
  ConsumerState<_DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends ConsumerState<_DayCalendar> {
  final _vertCtrl = ScrollController();   // 그리드 수직 스크롤
  final _timeCtrl = ScrollController();   // 시간 컬럼 동기화 전용
  final _horizCtrl = ScrollController();
  final _gridKey = GlobalKey();

  // 스태프 컬럼 폭 (LayoutBuilder에서 5명이 뷰포트를 꽉 채우도록 계산)
  double _staffColWidth = _staffColWidthFallback;

  // 드래그 상태
  AppointmentDetail? _dragApt;
  Offset _dragPos = Offset.zero;
  DateTime? _dropTime;
  String? _dropStaffId;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    // 오늘 날짜일 때만 현재 시각으로 자동 스크롤
    if (_isToday(widget.date)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = DateTime.now();
        final offset = ((now.hour - _startHour) * _slotHeight - 80)
            .clamp(0.0, _totalHeight - 200);
        if (_vertCtrl.hasClients) {
          _vertCtrl.animateTo(offset,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
        if (_timeCtrl.hasClients) {
          _timeCtrl.jumpTo(offset.clamp(0.0, _timeCtrl.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    _vertCtrl.dispose();
    _timeCtrl.dispose();
    _horizCtrl.dispose();
    super.dispose();
  }

  // ─── 드래그 시작 ────────────────────────────────────────────────────
  void _startDrag(AppointmentDetail apt, Offset globalPos) {
    setState(() {
      _dragApt = apt;
      _dragPos = globalPos;
      // 드롭 기준선을 예약 시작 시간에 고정
      _dropTime = apt.startDt;
    });
    _overlayEntry = OverlayEntry(
      builder: (_) => _DragOverlay(
        apt: apt,
        position: _dragPos,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateDrag(Offset globalPos) {
    _dragPos = globalPos;
    _overlayEntry?.markNeedsBuild();
    // rebuild overlay with new position
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (_) => _DragOverlay(apt: _dragApt!, position: _dragPos),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _calculateDrop(globalPos);
    setState(() {});
  }

  void _endDrag(Offset globalPos) async {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_dragApt != null && _dropTime != null && _dropStaffId != null) {
      await _applyReschedule(_dragApt!, _dropTime!, _dropStaffId!);
    }
    setState(() {
      _dragApt = null;
      _dropTime = null;
      _dropStaffId = null;
    });
  }

  void _calculateDrop(Offset globalPos) {
    final box =
        _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    // globalToLocal은 ScrollView 내부에서 스크롤 오프셋을 이미 포함하여 변환함
    // 별도로 vertOffset/horizOffset을 더하면 이중 계산이 되어 위치 오차 발생
    final local = box.globalToLocal(globalPos);

    // 수직: local.dy 는 이미 그리드 전체 좌표계 기준
    final minutesFromStart = _yToMin(local.dy.clamp(0, _totalHeight));
    // 15분 단위 스냅 후 -30분 오프셋 (기준선이 예약블록에 가리지 않도록)
    final snappedMin = (((minutesFromStart / 15).round() * 15) - 30)
        .clamp(0, (_endHour - _startHour) * 60);
    final targetDt = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      _startHour + snappedMin ~/ 60,
      snappedMin % 60,
    );

    // 수평: local.dx 는 이미 그리드 전체 좌표계 기준
    final staffAsync = ref.read(activeStaffProvider);
    final staff = staffAsync.valueOrNull ?? [];
    if (staff.isEmpty) return;
    final staffIdx = (local.dx / _staffColWidth)
        .floor()
        .clamp(0, staff.length - 1);

    setState(() {
      _dropTime = targetDt;
      _dropStaffId = staff[staffIdx].id;
    });
  }

  Future<void> _applyReschedule(
      AppointmentDetail det, DateTime newStart, String newStaffId) async {
    final duration = det.endDt.difference(det.startDt);
    final newEnd = newStart.add(duration);
    final db = ref.read(databaseProvider);
    await (db.update(db.appointments)
          ..where((t) => t.id.equals(det.apt.id)))
        .write(AppointmentsCompanion(
      startAt: Value(newStart.toIso8601String()),
      endAt: Value(newEnd.toIso8601String()),
      staffId: Value(newStaffId),
      updatedAt: Value(DateTime.now().toIso8601String()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final aptsAsync =
        ref.watch(appointmentDetailsForDateProvider(widget.date));
    final staffAsync = ref.watch(activeStaffProvider);

    return staffAsync.when(
      data: (staff) {
        if (staff.isEmpty) {
          return const Center(child: Text('スタッフを登録してください'));
        }
        return aptsAsync.when(
          data: (allApts) {
            var apts = widget.filterStatus == null
                ? allApts
                : allApts
                    .where((a) => a.apt.status == widget.filterStatus)
                    .toList();
            if (widget.filterStaffId != null) {
              apts = apts.where((a) => a.apt.staffId == widget.filterStaffId).toList();
            }
            return _buildGrid(context, staff, apts);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<StaffData> staff,
    List<AppointmentDetail> apts,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      // 실제 스태프 수 기준으로 뷰포트를 꽉 채우는 컬럼 폭 계산
      // 스태프가 없을 경우 fallback(100px) 유지, 최소 80px 보장
      final count = staff.isEmpty ? 1 : staff.length;
      _staffColWidth = ((constraints.maxWidth - _timeColWidth) / count)
          .clamp(80.0, double.infinity);
      return _buildGridInner(context, staff, apts);
    });
  }

  Widget _buildGridInner(
    BuildContext context,
    List<StaffData> staff,
    List<AppointmentDetail> apts,
  ) {
    final colWidth = _staffColWidth;
    return Row(
      children: [
        // ─ 시간 컬럼 (좌측 고정) ─────────────────────────────────────
        SizedBox(
          width: _timeColWidth,
          child: Column(
            children: [
              // 빈 헤더 (스태프 헤더와 높이 동일)
              Container(
                height: _dayStaffHeaderHeight,
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(
                    right: BorderSide(color: AppColors.border),
                    bottom: BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              // 시간 눈금 (스크롤바 없음 — _vertCtrl과 동기)
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    controller: _timeCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    child: _TimeColumn(showNowLabel: _isToday(widget.date)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ─ 스태프 컬럼 (가로 스크롤, 스크롤바 없음) ─────────────────
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(scrollbars: false),
            child: SingleChildScrollView(
              controller: _horizCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: staff.length * colWidth,
                child: Column(
                  children: [
                    // 스태프 헤더
                    _StaffHeader(staff: staff, staffColWidth: colWidth),
                    // 그리드 본체
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n is ScrollUpdateNotification &&
                              n.metrics.axis == Axis.vertical) {
                            if (_timeCtrl.hasClients) {
                              _timeCtrl.jumpTo(n.metrics.pixels);
                            }
                          }
                          return false;
                        },
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                            controller: _vertCtrl,
                            child: SizedBox(
                              key: _gridKey,
                              height: _totalHeight,
                              child: Stack(
                                children: [
                                  // 배경 그리드 라인
                                  Row(
                                    children: staff
                                        .map((_) => _GridLines(staffColWidth: colWidth))
                                        .toList(),
                                  ),
                                  // 예약 블록들
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: staff.map((s) {
                                      final staffApts = apts
                                          .where(
                                              (a) => a.apt.staffId == s.id)
                                          .toList();
                                      return _StaffColumnContent(
                                        staff: s,
                                        staffColWidth: colWidth,
                                        appointments: staffApts,
                                        date: widget.date,
                                        dropTime: _dropStaffId == s.id
                                            ? _dropTime
                                            : null,
                                        dragAptId: _dragApt?.apt.id,
                                        onEmptyTap: (dt) => widget
                                            .onEmptySlotTap(dt, s.id),
                                        onAptDragStart: _startDrag,
                                        onAptDragMove: _updateDrag,
                                        onAptDragEnd: _endDrag,
                                        onAptTap: (det) =>
                                            _showDetail(context, det),
                                      );
                                    }).toList(),
                                  ),
                                  // 현재 시각 선 (오늘만)
                                  if (_isToday(widget.date))
                                    _NowLine(date: widget.date),
                                ],
                              ),
                            ),
                          ),    // ScrollConfiguration (vertical)
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),    // ScrollConfiguration (horizontal)
          ),
        ),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  void _showDetail(BuildContext ctx, AppointmentDetail det) {
    Future.microtask(() {
      if (!ctx.mounted) return;
      showDialog(
        context: ctx,
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(80),
        useRootNavigator: true,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
              horizontal: 80, vertical: 40),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          child: SizedBox(
            width: 420,
            child: _AppointmentDetailSheet(detail: det),
          ),
        ),
      );
    });
  }
}

// ─── 드래그 오버레이 카드 ─────────────────────────────────────────────────
class _DragOverlay extends StatelessWidget {
  const _DragOverlay({required this.apt, required this.position});
  final AppointmentDetail apt;
  final Offset position;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 60,
      top: position.dy - 30,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 120,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _statusColor(apt.apt.status).withAlpha(230),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(apt.displayName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(apt.menuSummary,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 스태프 헤더 ──────────────────────────────────────────────────────────
class _StaffHeader extends StatelessWidget {
  const _StaffHeader({required this.staff, required this.staffColWidth});
  final List<StaffData> staff;
  final double staffColWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _dayStaffHeaderHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: staff.map((s) {
          final color = _parseColor(s.color);
          return Container(
            width: staffColWidth,
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: color,
                    child: Text(
                      s.name.isNotEmpty ? s.name[0] : '?',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(s.name,
                        style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── 시간 컬럼 ────────────────────────────────────────────────────────────
class _TimeColumn extends StatefulWidget {
  const _TimeColumn({this.showNowLabel = false});
  final bool showNowLabel;

  @override
  State<_TimeColumn> createState() => _TimeColumnState();
}

class _TimeColumnState extends State<_TimeColumn> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.showNowLabel) {
      // 매분 정각 + 1초에 업데이트 (초 단위 오차 최소화)
      _scheduleTimer();
    }
  }

  void _scheduleTimer() {
    _timer?.cancel();
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day,
        now.hour, now.minute + 1, 1);
    final delay = nextMinute.difference(now);
    _timer = Timer(delay, () {
      if (mounted) {
        setState(() => _now = DateTime.now());
        _scheduleTimer();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _endHour - _startHour;
    final items = <Widget>[];
    for (int i = 0; i < hours; i++) {
      final hour = _startHour + i;
      items.add(Positioned(
        top: i * _slotHeight,
        left: 0, right: 0,
        child: Container(
          height: _slotHeight / 2,
          color: AppColors.surface,
          padding: const EdgeInsets.only(right: 6, top: 3),
          child: Text(
            '$hour:00',
            textAlign: TextAlign.right,
            style: AppTextStyles.caption
                .copyWith(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ));
      items.add(Positioned(
        top: i * _slotHeight + _slotHeight / 2,
        left: 0, right: 0,
        child: Container(
          height: _slotHeight / 2,
          color: AppColors.surface,
          padding: const EdgeInsets.only(right: 6, top: 3),
          child: Text(
            '$hour:30',
            textAlign: TextAlign.right,
            style: AppTextStyles.caption.copyWith(
                fontSize: 10, color: AppColors.textSecondary.withAlpha(140)),
          ),
        ),
      ));
    }

    // 현재 시각 레이블 (오늘만, 영업시간 내)
    if (widget.showNowLabel &&
        _now.hour >= _startHour && _now.hour < _endHour) {
      final top = (_now.hour - _startHour + _now.minute / 60) * _slotHeight;
      items.add(Positioned(
        top: top - 9,
        left: 0, right: 0,
        child: Container(
          padding: const EdgeInsets.only(right: 4),
          color: AppColors.surface,
          child: Text(
            '${_now.hour}:${_now.minute.toString().padLeft(2, '0')}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.error,
            ),
          ),
        ),
      ));
    }

    return SizedBox(height: _totalHeight, child: Stack(children: items));
  }
}

// ─── 그리드 라인 배경 ─────────────────────────────────────────────────────
class _GridLines extends StatelessWidget {
  const _GridLines({required this.staffColWidth});
  final double staffColWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: staffColWidth,
      height: _totalHeight,
      child: Stack(
        children: [
          // 1시간 선 (더 진한 실선)
          ...List.generate(_endHour - _startHour, (i) => Positioned(
                top: i * _slotHeight,
                left: 0,
                right: 0,
                child: Container(
                    height: 1, color: const Color(0xFFCDD1D8)),
              )),
          // 30분 선 (연한 선)
          ...List.generate(_endHour - _startHour, (i) => Positioned(
                top: i * _slotHeight + _slotHeight / 2,
                left: 0,
                right: 0,
                child: Container(
                    height: 1,
                    color: const Color(0xFFE8EAED)),
              )),
          // 우측 구분선
          const Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: VerticalDivider(width: 1, color: AppColors.border),
          ),
        ],
      ),
    );
  }
}

// ─── 현재 시각 선 ─────────────────────────────────────────────────────────
class _NowLine extends StatelessWidget {
  const _NowLine({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    if (now.hour < _startHour || now.hour >= _endHour) {
      return const SizedBox.shrink();
    }
    final top =
        (now.hour - _startHour) * _slotHeight + now.minute * _slotHeight / 60;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.error, shape: BoxShape.circle)),
            Expanded(
                child: Container(height: 2, color: AppColors.error)),
          ],
        ),
      ),
    );
  }
}

// ─── 스태프 컬럼 콘텐츠 ──────────────────────────────────────────────────
class _StaffColumnContent extends StatelessWidget {
  const _StaffColumnContent({
    required this.staff,
    required this.staffColWidth,
    required this.appointments,
    required this.date,
    required this.dropTime,
    required this.dragAptId,
    required this.onEmptyTap,
    required this.onAptDragStart,
    required this.onAptDragMove,
    required this.onAptDragEnd,
    required this.onAptTap,
  });

  final StaffData staff;
  final double staffColWidth;
  final List<AppointmentDetail> appointments;
  final DateTime date;
  final DateTime? dropTime;
  final String? dragAptId;
  final ValueChanged<DateTime> onEmptyTap;
  final void Function(AppointmentDetail, Offset) onAptDragStart;
  final ValueChanged<Offset> onAptDragMove;
  final ValueChanged<Offset> onAptDragEnd;
  final ValueChanged<AppointmentDetail> onAptTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: staffColWidth,
      height: _totalHeight,
      child: Stack(
        children: [
          // 빈 슬롯 탭 영역 (15분 단위)
          ..._buildEmptySlots(),

          // 드롭 타겟 표시
          if (dropTime != null) _DropIndicator(time: dropTime!),

          // 예약 블록
          ...appointments.map((det) {
            final start = det.startDt;
            final end = det.endDt;
            final topPx =
                (start.hour - _startHour + start.minute / 60) * _slotHeight;
            final durationMin = end.difference(start).inMinutes;
            final heightPx = _minToY(durationMin);

            if (topPx < 0 || topPx >= _totalHeight) {
              return const SizedBox.shrink();
            }

            final isDragging = det.apt.id == dragAptId;

            return Positioned(
              top: topPx + 1,
              left: 2,
              right: 2,
              height: (heightPx - 2).clamp(20.0, _totalHeight),
              child: Opacity(
                opacity: isDragging ? 0.35 : 1.0,
                child: _AppointmentBlock(
                  detail: det,
                  onTap: () => onAptTap(det),
                  onLongPressStart: (pos) => onAptDragStart(det, pos),
                  onLongPressMoveUpdate: onAptDragMove,
                  onLongPressEnd: onAptDragEnd,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  List<Widget> _buildEmptySlots() {
    final totalMin = (_endHour - _startHour) * 60;
    const step = 15;
    return List.generate(totalMin ~/ step, (i) {
      final min = i * step;
      final topPx = _minToY(min);
      final dt = DateTime(date.year, date.month, date.day,
          _startHour + min ~/ 60, min % 60);
      return Positioned(
        top: topPx,
        left: 0,
        right: 0,
        height: _minToY(step),
        child: GestureDetector(
          onTap: () => onEmptyTap(dt),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

// ─── 드롭 인디케이터 ──────────────────────────────────────────────────────
class _DropIndicator extends StatelessWidget {
  const _DropIndicator({required this.time});
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final topPx =
        (time.hour - _startHour + time.minute / 60) * _slotHeight;
    return Positioned(
      top: topPx,
      left: 2,
      right: 2,
      height: 2,
      child: Container(color: AppColors.primary),
    );
  }
}

// ─── 예약 블록 (★ 핵심) ──────────────────────────────────────────────────
class _AppointmentBlock extends StatelessWidget {
  const _AppointmentBlock({
    required this.detail,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
  });

  final AppointmentDetail detail;
  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPressStart;
  final ValueChanged<Offset> onLongPressMoveUpdate;
  final ValueChanged<Offset> onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    final apt = detail.apt;
    final blockColor = apt.color != null
        ? _parseColor(apt.color!)
        : detail.staffColor != null
            ? _parseColor(detail.staffColor!)
            : _statusColor(apt.status);

    final durationMin = detail.durationMin;
    final processingMin = detail.processingMin;
    final isCompact = durationMin < 15;

    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (d) => onLongPressStart(d.globalPosition),
      onLongPressMoveUpdate: (d) => onLongPressMoveUpdate(d.globalPosition),
      onLongPressEnd: (d) => onLongPressEnd(d.globalPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: blockColor.withAlpha(38),
            border: Border.all(color: blockColor.withAlpha(80), width: 0.5),
          ),
          child: Stack(
            children: [
              // 좌측 색상 바 (상태 표시)
              Positioned(
                top: 0, bottom: 0, left: 0,
                width: 4,
                child: Container(color: blockColor),
              ),
              // Processing time 영역 (하단 스트라이프)
              if (detail.hasProcessing && !isCompact)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: (_minToY(processingMin) - 1)
                      .clamp(0, _minToY(durationMin)),
                  child: _ProcessingStripe(color: blockColor),
                ),

              // 메인 콘텐츠 — Positioned.fill + ClipRect + OverflowBox
              // ClipRect: 렌더링을 블록 경계로 자름
              // OverflowBox(maxHeight: ∞): tight constraints를 해제해
              //   Column이 필요한 만큼 렌더링 → 레이아웃 오버플로 경고 없음
              Positioned.fill(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          8, isCompact ? 2 : 4, 4, isCompact ? 2 : 4),
                      child: isCompact
                          ? _CompactContent(detail: detail, color: blockColor)
                          : _FullContent(detail: detail, color: blockColor),
                    ),
                  ),
                ),
              ),

              // 초회 배지
              if (apt.isFirstVisit)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withAlpha(220),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('初回',
                        style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),

              // 반복 예약 배지
              if (apt.repeatGroupId != null)
                Positioned(
                  top: apt.isFirstVisit ? 18 : 3,
                  right: 3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: blockColor.withAlpha(180),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.repeat,
                        size: 10, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 압축 콘텐츠 (30분 미만) ─────────────────────────────────────────────
class _CompactContent extends StatelessWidget {
  const _CompactContent({required this.detail, required this.color});
  final AppointmentDetail detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '${_hm(detail.startDt)} ${detail.displayName}',
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── 풀 콘텐츠 (30분 이상) ───────────────────────────────────────────────
class _FullContent extends StatelessWidget {
  const _FullContent({required this.detail, required this.color});
  final AppointmentDetail detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final showMenus = detail.durationMin >= 20;
    final showProcessingLabel =
        detail.hasProcessing && detail.durationMin >= 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 시간
        Text(
          '${_hm(detail.startDt)}〜${_hm(detail.endDt)}',
          style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        // 고객명 + 주의 아이콘
        Row(
          children: [
            Flexible(
              child: Text(
                detail.displayName,
                style: AppTextStyles.body2.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (detail.cautionFlag || detail.allergies != null) ...[
              const SizedBox(width: 3),
              const Icon(Icons.warning_amber_rounded,
                  size: 11, color: AppColors.error),
            ],
          ],
        ),
        // 메뉴명
        if (showMenus && detail.menuSummary.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            detail.menuSummary,
            style: AppTextStyles.caption
                .copyWith(fontSize: 10, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        // 담당자명 (40분 이상 블록)
        if (detail.durationMin >= 25 && detail.staffName != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.content_cut,
                  size: 9, color: color.withAlpha(160)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  detail.staffName!,
                  style: TextStyle(
                      fontSize: 9,
                      color: color.withAlpha(180),
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
        // Processing time 라벨
        if (showProcessingLabel) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 10, color: color.withAlpha(180)),
              const SizedBox(width: 2),
              Text(
                '発色${detail.processingMin}分',
                style: TextStyle(
                    fontSize: 9,
                    color: color.withAlpha(180),
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Processing Time 스트라이프 ──────────────────────────────────────────
class _ProcessingStripe extends StatelessWidget {
  const _ProcessingStripe({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StripePainter(color),
      child: const SizedBox.expand(),
    );
  }
}

class _StripePainter extends CustomPainter {
  const _StripePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withAlpha(35)
      ..style = PaintingStyle.fill;

    const pitch = 14.0;
    const stripeW = 7.0;

    for (double x = -size.height; x < size.width + size.height; x += pitch) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + size.height, size.height)
        ..lineTo(x + size.height + stripeW, size.height)
        ..lineTo(x + stripeW, 0)
        ..close();
      canvas.drawPath(path, paint);
    }

    // 상단 구분선
    canvas.drawLine(
      Offset(0, 0),
      Offset(size.width, 0),
      Paint()
        ..color = color.withAlpha(80)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.color != color;
}

// ─── 예약 상세 시트 ───────────────────────────────────────────────────────
class _AppointmentDetailSheet extends ConsumerWidget {
  const _AppointmentDetailSheet({required this.detail});
  final AppointmentDetail detail;

  static const _statusLabels = <String, (String, Color, Color)>{
    'pending': ('確認待ち', Color(0xFFFFB300), Color(0xFFFFF8ED)),
    'confirmed': ('確認済み', Color(0xFF0064FF), Color(0xFFE8F1FF)),
    'in_progress': ('施術中', Color(0xFF00B746), Color(0xFFE6F9EE)),
    'completed': ('完了', Color(0xFF8B95A1), Color(0xFFF5F6F8)),
    'cancelled': ('キャンセル', Color(0xFFF04452), Color(0xFFFFECEE)),
    'no_show': ('無断欠席', Color(0xFFF04452), Color(0xFFFFECEE)),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apt = detail.apt;
    final statusColor = _statusColor(apt.status);

    // ConstrainedBox로 최대 높이 제한, mainAxisSize.min + Flexible로
    // bounded constraint 없이도 올바르게 레이아웃
    return Column(
      mainAxisSize: MainAxisSize.min,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                _StatusBadge(status: apt.status, labels: _statusLabels),
                const SizedBox(width: 8),
                Text(
                  '${_hm(detail.startDt)}〜${_hm(detail.endDt)}',
                  style: AppTextStyles.h4,
                ),
                if (apt.isFirstVisit) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('初回',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AppointmentFormScreen(
                                appointmentId: apt.id)));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 본문
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 고객 정보
                  if (detail.customerName != null) ...[
                    InkWell(
                      onTap: detail.apt.customerId != null
                          ? () {
                              Navigator.pop(context);
                              context.push(
                                  '${AppRoutes.customers}/${detail.apt.customerId}');
                            }
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: _DetailRow(
                          icon: Icons.person_outline,
                          label: '顧客',
                          value: detail.customerName!,
                          isLink: detail.apt.customerId != null),
                    ),
                    if (detail.customerPhone != null)
                      _DetailRow(
                          icon: Icons.phone_outlined,
                          label: '電話',
                          value: detail.customerPhone!),
                    // 방문 횟수 + 최근 방문일
                    if (detail.customerTotalVisits > 0 || detail.customerLastVisit != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 4, top: 4, bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.history, size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              '来店 ${detail.customerTotalVisits}回',
                              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                            ),
                            if (detail.customerLastVisit != null) ...[
                              Text(' · ', style: AppTextStyles.caption.copyWith(color: AppColors.textDisabled)),
                              Text(
                                '前回 ${detail.customerLastVisit}',
                                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // 메뉴
                  if (detail.menuNames.isNotEmpty) ...[
                    Text('メニュー',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    ...detail.menuNames.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.only(
                                      right: 8, top: 2),
                                  decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle)),
                              Text(m, style: AppTextStyles.body2),
                            ],
                          ),
                        )),
                    if (detail.hasProcessing) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined,
                              size: 14,
                              color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '発色時間 ${detail.processingMin}分（スタッフ離席可）',
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // 金額
                  if (detail.totalPrice > 0)
                    _DetailRow(
                        icon: Icons.payments_outlined,
                        label: '金額',
                        value: '¥${_fmt(detail.totalPrice)}'),

                  // 고객 주의사항
                  if (detail.cautionFlag || detail.allergies != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 14, color: AppColors.error),
                              const SizedBox(width: 4),
                              Text('注意事項',
                                  style: AppTextStyles.label.copyWith(
                                      color: AppColors.error,
                                      fontSize: 11)),
                            ],
                          ),
                          if (detail.cautionNote != null) ...[
                            const SizedBox(height: 4),
                            Text(detail.cautionNote!,
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.error.withOpacity(0.8))),
                          ],
                          if (detail.allergies != null) ...[
                            const SizedBox(height: 4),
                            Text('アレルギー: ${detail.allergies}',
                                style: AppTextStyles.caption.copyWith(
                                    color: AppColors.error.withOpacity(0.8))),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // メモ
                  if (apt.notes != null && apt.notes!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('メモ',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(apt.notes!, style: AppTextStyles.body2),
                  ],
                ],
              ),  // Column
            ),    // SingleChildScrollView
          ),      // ConstrainedBox
        ),        // Flexible

          // 액션 버튼
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _ActionButtons(detail: detail),
          ),
        ],
      );  // Column
  }
}

// ─── 상세 행 ──────────────────────────────────────────────────────────────
class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.icon, required this.label, required this.value,
      this.isLink = false});
  final IconData icon;
  final String label;
  final String value;
  final bool isLink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text('$label ',
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.textSecondary)),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(value,
                      style: AppTextStyles.body2.copyWith(
                          color: isLink ? AppColors.primary : null,
                          decoration: isLink
                              ? TextDecoration.underline
                              : TextDecoration.none,
                          decorationColor: AppColors.primary)),
                ),
                if (isLink) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.open_in_new,
                      size: 12, color: AppColors.primary),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 액션 버튼 ────────────────────────────────────────────────────────────
class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.detail});
  final AppointmentDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = detail.apt.status;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 来店確認
        if (status == 'pending' || status == 'confirmed')
          _ActionBtn(
            label: '来店確認',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
            onTap: () => _updateStatus(context, ref, 'in_progress'),
          ),

        // 会計へ
        if (status == 'in_progress')
          _ActionBtn(
            label: '会計へ',
            icon: Icons.point_of_sale_outlined,
            color: AppColors.primary,
            filled: true,
            onTap: () => _goToCheckout(context, ref),
          ),

        // 確認済みに
        if (status == 'pending')
          _ActionBtn(
            label: '確認済みに',
            icon: Icons.thumb_up_outlined,
            color: AppColors.primary,
            onTap: () => _updateStatus(context, ref, 'confirmed'),
          ),

        // ノーショー (당일 예약에만)
        if (status == 'pending' || status == 'confirmed')
          _ActionBtn(
            label: 'ノーショー',
            icon: Icons.person_off_outlined,
            color: AppColors.error,
            onTap: () => _showNoShowConfirm(context, ref),
          ),

        // キャンセル
        if (status != 'cancelled' && status != 'completed')
          _ActionBtn(
            label: 'キャンセル',
            icon: Icons.cancel_outlined,
            color: AppColors.error,
            onTap: () => _showCancelConfirm(context, ref),
          ),

        // カルテを見る (고객 있을 때)
        if (detail.apt.customerId != null)
          _ActionBtn(
            label: 'カルテ',
            icon: Icons.assignment_outlined,
            color: const Color(0xFF6366F1),
            onTap: () {
              Navigator.pop(context);
              context.push(
                  '${AppRoutes.customers}/${detail.apt.customerId}?tab=1');
            },
          ),

        // リマインダーコピー (확정/미확정 예약에만)
        if (detail.customerName != null &&
            (status == 'pending' || status == 'confirmed'))
          _ActionBtn(
            label: 'リマインダー',
            icon: Icons.notification_add_outlined,
            color: const Color(0xFF10B981),
            onTap: () => _copyReminder(context),
          ),
      ],
    );
  }

  void _copyReminder(BuildContext context) {
    final apt = detail.apt;
    final dt = DateTime.tryParse(apt.startAt);
    final dateStr = dt != null
        ? '${dt.month}月${dt.day}日（${_weekday(dt.weekday)}）${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : apt.startAt;
    final menus = detail.menuNames.isNotEmpty
        ? detail.menuNames.join('・')
        : 'ご予約';
    final staff = detail.staffName != null ? '担当: ${detail.staffName}' : '';

    final msg = '【ご予約リマインダー】\n'
        '${detail.customerName}様\n\n'
        '明日のご予約をお知らせいたします。\n\n'
        '📅 $dateStr\n'
        '💇 $menus\n'
        '${staff.isNotEmpty ? '👤 $staff\n' : ''}'
        '\nご不明な点はお気軽にお問い合わせください。\nお待ちしております！';

    Clipboard.setData(ClipboardData(text: msg));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('リマインダーメッセージをコピーしました'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _weekday(int w) {
    const days = ['月', '火', '水', '木', '金', '土', '日'];
    return days[(w - 1) % 7];
  }

  // 会計へ: POS에 예약 정보 연동 후 이동
  Future<void> _goToCheckout(BuildContext ctx, WidgetRef ref) async {
    final apt = detail.apt;
    final db = ref.read(databaseProvider);
    final pos = ref.read(posProvider.notifier);

    // 1. 기존 장바구니가 있으면 확인
    final currentItems = ref.read(posProvider).items;
    if (currentItems.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (d) => AlertDialog(
          title: const Text('会計を切り替えますか？'),
          content: const Text('現在の会計内容がクリアされます。予約の内容で上書きしてよろしいですか？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('キャンセル')),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              child: const Text('切り替える'),
            ),
          ],
        ),
      );
      if (ok != true || !ctx.mounted) return;
      pos.clear();
    }

    // 2. 고객 연결
    if (apt.customerId != null) {
      final customer = await (db.select(db.customers)
            ..where((t) => t.id.equals(apt.customerId!)))
          .getSingleOrNull();
      if (customer != null) {
        pos.setCustomer(customer.id, customer.name);
      }
    }

    // 3. 예약 연결
    pos.linkAppointment(apt.id);

    // 4. 담당 스태프 설정
    pos.setStaff(apt.staffId);

    // 5. 예약 메뉴 → POS 카트에 추가
    final menuLinks = await (db.select(db.appointmentMenus)
          ..where((t) => t.appointmentId.equals(apt.id))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    for (final link in menuLinks) {
      final menu = await (db.select(db.menus)
            ..where((t) => t.id.equals(link.menuId)))
          .getSingleOrNull();
      if (menu != null) {
        final staff = await (db.select(db.staff)
              ..where((t) => t.id.equals(apt.staffId)))
            .getSingleOrNull();
        pos.addMenu(menu, staffId: apt.staffId, staffName: staff?.name);
      }
    }

    if (!ctx.mounted) return;
    Navigator.pop(ctx); // 상세 다이얼로그 닫기
    ctx.go(AppRoutes.pos); // POS 탭으로 이동
  }

  Future<void> _updateStatus(
      BuildContext ctx, WidgetRef ref, String newStatus) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.appointments)
          ..where((t) => t.id.equals(detail.apt.id)))
        .write(AppointmentsCompanion(
      status: Value(newStatus),
      updatedAt: Value(DateTime.now().toIso8601String()),
    ));
    if (ctx.mounted) Navigator.pop(ctx);
  }

  Future<void> _showNoShowConfirm(BuildContext ctx, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('ノーショー処理'),
        content: Text(
            '「${detail.displayName}」をノーショーとして記録します。この操作は取り消せません。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('ノーショーにする'),
          ),
        ],
      ),
    );
    if (ok == true && ctx.mounted) {
      await _updateStatus(ctx, ref, 'no_show');
    }
  }

  Future<void> _showCancelConfirm(BuildContext ctx, WidgetRef ref) async {
    String? selectedReason;
    const reasons = [
      '顧客都合',
      'スタッフ都合',
      '体調不良',
      '忘れた',
      '日程変更',
      'その他',
    ];
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setLocal) => AlertDialog(
          title: const Text('予約キャンセル'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('「${detail.displayName}」の予約をキャンセルしますか？'),
              const SizedBox(height: 16),
              const Text('キャンセル理由（任意）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: reasons.map((r) => ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 12)),
                      selected: selectedReason == r,
                      onSelected: (_) =>
                          setLocal(() => selectedReason = selectedReason == r ? null : r),
                    )).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dlgCtx, false),
                child: const Text('戻る')),
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('キャンセルする'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && ctx.mounted) {
      // 취소 이유를 notes에 저장
      if (selectedReason != null) {
        final db = ref.read(databaseProvider);
        final existing = detail.apt.notes;
        final newNotes = existing != null && existing.isNotEmpty
            ? '$existing\n[キャンセル理由: $selectedReason]'
            : '[キャンセル理由: $selectedReason]';
        await (db.update(db.appointments)
              ..where((t) => t.id.equals(detail.apt.id)))
            .write(AppointmentsCompanion(notes: Value(newNotes)));
      }
      await _updateStatus(ctx, ref, 'cancelled');
    }
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 40),
            backgroundColor: color,
            foregroundColor: Colors.white),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          foregroundColor: color,
          side: BorderSide(color: color)),
    );
  }
}

// ─── 빠른 예약 생성 시트 ──────────────────────────────────────────────────
class _QuickCreateSheet extends ConsumerStatefulWidget {
  const _QuickCreateSheet(
      {required this.startAt, required this.staffId});

  final DateTime startAt;
  final String staffId;

  @override
  ConsumerState<_QuickCreateSheet> createState() =>
      _QuickCreateSheetState();
}

class _QuickCreateSheetState extends ConsumerState<_QuickCreateSheet> {
  int _durationMin = 60;
  bool _saving = false;

  static const _durations = [30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final endAt = widget.startAt.add(Duration(minutes: _durationMin));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('クイック予約', style: AppTextStyles.h4),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 4),
          // 시간 표시
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  '${_hm(widget.startAt)}〜${_hm(endAt)}',
                  style: AppTextStyles.body1.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 시간 선택
          Text('所要時間',
              style: AppTextStyles.label
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _durations.map((min) {
              final selected = min == _durationMin;
              return ChoiceChip(
                label: Text('$min分'),
                selected: selected,
                onSelected: (_) => setState(() => _durationMin = min),
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                    color: selected
                        ? Colors.white
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // 詳細フォームへ
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => AppointmentFormScreen(
                                  initialStartAt: widget.startAt,
                                  initialStaffId: widget.staffId,
                                )));
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('詳細設定'),
                ),
              ),
              const SizedBox(width: 12),
              // 即時予約
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _quickSave,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.add, size: 16),
                  label: const Text('予約する'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _quickSave() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final endAt =
          widget.startAt.add(Duration(minutes: _durationMin));
      await db.into(db.appointments).insert(AppointmentsCompanion.insert(
        id: _uuid.v4(),
        staffId: widget.staffId,
        startAt: widget.startAt.toIso8601String(),
        endAt: endAt.toIso8601String(),
        status: const Value('confirmed'),
        source: const Value('pos'),
        isFirstVisit: const Value(false),
        isRepeatParent: const Value(false),
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
}

// ─── 상태 배지 ────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge(
      {required this.status, required this.labels});

  final String status;
  final Map<String, (String, Color, Color)> labels;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = labels[status] ??
        ('不明', AppColors.textSecondary, AppColors.background);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: fg, fontWeight: FontWeight.w700)),
    );
  }
}

// ─── 유틸 함수 ────────────────────────────────────────────────────────────
String _hm(DateTime dt) =>
    '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

String _fmt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

Color _parseColor(String? hex) {
  if (hex == null || hex.isEmpty || hex == 'null') {
    return AppColors.primary;
  }
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return AppColors.primary;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ─── 1일 단위 스냅 ScrollPhysics ──────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
class _DaySnapPhysics extends ScrollPhysics {
  const _DaySnapPhysics({required this.dayWidth, super.parent});
  final double dayWidth;

  @override
  _DaySnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _DaySnapPhysics(dayWidth: dayWidth, parent: buildParent(ancestor));

  double _snapTarget(ScrollMetrics pos, double velocity) {
    double page = pos.pixels / dayWidth;
    if (velocity < -200) {
      page = page.ceilToDouble();
    } else if (velocity > 200) {
      page = page.floorToDouble();
    } else {
      page = page.roundToDouble();
    }
    return (page * dayWidth).clamp(pos.minScrollExtent, pos.maxScrollExtent);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics pos, double velocity) {
    final target = _snapTarget(pos, velocity);
    if ((target - pos.pixels).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring, pos.pixels, target, velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// ─── 주 단위 스크롤 뷰 (시간축 고정 + 1일 스냅) ──────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
class _WeekScrollView extends ConsumerStatefulWidget {
  const _WeekScrollView({
    required this.selectedDate,
    required this.filterStatus,
    required this.onDateChanged,
    required this.onSwitchToDay,
    this.onFocusedDateChanged,
    this.focusedDate,
    this.filterStaffId,
  });

  final DateTime selectedDate;
  final String? filterStatus;
  final String? filterStaffId;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<DateTime> onSwitchToDay;
  final ValueChanged<DateTime?>? onFocusedDateChanged;
  final DateTime? focusedDate; // 외부에서 설정하는 포커스 날짜 (미니달력 탭)

  @override
  ConsumerState<_WeekScrollView> createState() => _WeekScrollViewState();
}

class _WeekScrollViewState extends ConsumerState<_WeekScrollView> {
  // 전체 날짜 범위: 기준일 ±500일
  static const _totalDays = 1001;
  static const _baseIdx = 500;

  late final DateTime _baseDate; // 초기 selectedDate = 수평 스크롤 기준점

  final _vertCtrl = ScrollController();     // 그리드 세로 스크롤
  final _timeCtrl = ScrollController();     // 시간축 미러 (NeverScrollable)
  final _horizCtrl = ScrollController();    // 그리드 가로 스크롤 (스냅 physics)
  final _horizHdrCtrl = ScrollController(); // 헤더 미러 (NeverScrollable)
  final _gridKey = GlobalKey();

  double _dayWidth = 0;
  bool _initialized = false;

  DateTime? _focusedDate;

  // 드래그 상태
  AppointmentDetail? _dragApt;
  Offset _dragPos = Offset.zero;
  DateTime? _dropTime;
  DateTime? _dropDate;
  OverlayEntry? _overlayEntry;

  // 엣지 스크롤 (드래그 중 끝 열에서 자동 이동)
  Timer? _edgeScrollTimer;
  int _edgeScrollDir = 0; // -1 왼쪽, +1 오른쪽, 0 없음
  static const _edgeZone = 40.0;       // 엣지 감지 영역 (px)
  static const _edgeInterval = Duration(milliseconds: 350);

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    _baseDate = widget.selectedDate;
    _horizCtrl.addListener(_syncHeader);
  }

  // 수평 그리드 스크롤 → 헤더 동기화 (드래그 중이면 drop 위치도 재계산)
  void _syncHeader() {
    if (_horizHdrCtrl.hasClients) {
      _horizHdrCtrl.jumpTo(_horizCtrl.offset);
    }
    // 엣지 스크롤로 뷰가 이동할 때 drop 타겟 갱신
    if (_dragApt != null) {
      _calculateDrop(_dragPos);
    }
  }

  // 날짜 → 수평 오프셋 (px)
  double _dateToOffset(DateTime date) {
    final diff = DateTime(date.year, date.month, date.day)
        .difference(DateTime(_baseDate.year, _baseDate.month, _baseDate.day))
        .inDays;
    return (_baseIdx + diff) * _dayWidth;
  }

  // 수평 오프셋 → 날짜
  DateTime _offsetToDate(double offset) {
    if (_dayWidth == 0) return widget.selectedDate;
    final idx = (offset / _dayWidth).round().clamp(0, _totalDays - 1);
    return _baseDate.add(Duration(days: idx - _baseIdx));
  }

  void _initScroll(double dayWidth) {
    _dayWidth = dayWidth;
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final offset = _dateToOffset(widget.selectedDate);
        if (_horizCtrl.hasClients) _horizCtrl.jumpTo(offset);
        if (_horizHdrCtrl.hasClients) _horizHdrCtrl.jumpTo(offset);
      });
    }
  }

  @override
  void didUpdateWidget(_WeekScrollView old) {
    super.didUpdateWidget(old);
    // 외부 날짜 변경 (헤더 네비, 미니달력) → 수평 스크롤 동기화
    if (widget.selectedDate != old.selectedDate && _initialized && _dayWidth > 0) {
      final target = _dateToOffset(widget.selectedDate);
      if (_horizCtrl.hasClients && (_horizCtrl.offset - target).abs() > 0.5) {
        _horizCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
    // 미니달력 등 외부에서 포커스 날짜 설정 시 동기화
    if (widget.focusedDate != old.focusedDate) {
      setState(() => _focusedDate = widget.focusedDate);
    }
  }

  @override
  void dispose() {
    _edgeScrollTimer?.cancel();
    _horizCtrl.removeListener(_syncHeader);
    _vertCtrl.dispose();
    _timeCtrl.dispose();
    _horizCtrl.dispose();
    _horizHdrCtrl.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  // ─── 엣지 스크롤 ──────────────────────────────────────────────────────
  void _checkEdgeScroll(Offset globalPos) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _dayWidth == 0) return;
    final local = box.globalToLocal(globalPos);
    final w = box.size.width;

    int dir = 0;
    if (local.dx >= w - _edgeZone) {
      dir = 1; // 오른쪽 끝 → 앞으로
    } else if (local.dx <= _edgeZone && local.dx >= 0) {
      dir = -1; // 왼쪽 끝 → 뒤로
    }

    if (dir == _edgeScrollDir) return; // 방향 변화 없으면 그대로
    _edgeScrollDir = dir;
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = null;

    if (dir != 0) {
      _edgeScrollTimer = Timer.periodic(_edgeInterval, (_) {
        if (!_horizCtrl.hasClients || _dayWidth == 0) return;
        final target = (_horizCtrl.offset + dir * _dayWidth)
            .clamp(0.0, _horizCtrl.position.maxScrollExtent);
        _horizCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _stopEdgeScroll() {
    _edgeScrollDir = 0;
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = null;
  }

  // ─── Drag & Drop ───────────────────────────────────────────────────────
  void _startDrag(AppointmentDetail apt, Offset globalPos) {
    setState(() {
      _dragApt = apt;
      _dragPos = globalPos;
      _dropTime = apt.startDt;
      _dropDate = apt.startDt;
    });
    _overlayEntry = OverlayEntry(
      builder: (_) => _DragOverlay(apt: apt, position: _dragPos),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _updateDrag(Offset globalPos) {
    _dragPos = globalPos;
    _overlayEntry?.remove();
    _overlayEntry = OverlayEntry(
      builder: (_) => _DragOverlay(apt: _dragApt!, position: _dragPos),
    );
    Overlay.of(context).insert(_overlayEntry!);
    _calculateDrop(globalPos);
    _checkEdgeScroll(globalPos);
  }

  void _endDrag(Offset globalPos) async {
    _stopEdgeScroll();
    _overlayEntry?.remove();
    _overlayEntry = null;
    final apt = _dragApt;
    final dropDt = _dropTime;
    if (apt != null && dropDt != null) {
      await _applyReschedule(apt, dropDt);
    }
    setState(() {
      _dragApt = null;
      _dropTime = null;
      _dropDate = null;
    });
  }

  void _calculateDrop(Offset globalPos) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _dayWidth == 0) return;
    final local = box.globalToLocal(globalPos);

    // Y → 시간 (15분 스냅, -30분 오프셋)
    final minutesFromStart = _yToMin(local.dy.clamp(0, _totalHeight));
    final snappedMin = (((minutesFromStart / 15).round() * 15) - 30)
        .clamp(0, (_endHour - _startHour) * 60);

    // X → 날짜 (수평 스크롤 오프셋 합산)
    final absX = local.dx + _horizCtrl.offset;
    final dayIdx = (absX / _dayWidth).floor().clamp(0, _totalDays - 1);
    final targetDate = _baseDate.add(Duration(days: dayIdx - _baseIdx));

    final targetDt = DateTime(
      targetDate.year, targetDate.month, targetDate.day,
      _startHour + snappedMin ~/ 60, snappedMin % 60,
    );
    setState(() {
      _dropDate = targetDate;
      _dropTime = targetDt;
    });
  }

  Future<void> _applyReschedule(AppointmentDetail det, DateTime newStart) async {
    final duration = det.endDt.difference(det.startDt);
    final newEnd = newStart.add(duration);
    final db = ref.read(databaseProvider);
    await (db.update(db.appointments)
          ..where((t) => t.id.equals(det.apt.id)))
        .write(AppointmentsCompanion(
      startAt: Value(newStart.toIso8601String()),
      endAt: Value(newEnd.toIso8601String()),
      updatedAt: Value(DateTime.now().toIso8601String()),
    ));
  }

  void _showDetail(BuildContext ctx, AppointmentDetail det) {
    Future.microtask(() {
      if (!ctx.mounted) return;
      showDialog(
        context: ctx,
        barrierDismissible: true,
        barrierColor: Colors.black.withAlpha(80),
        useRootNavigator: true,
        builder: (_) => UncontrolledProviderScope(
          container: ProviderScope.containerOf(ctx),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SizedBox(width: 420, child: _AppointmentDetailSheet(detail: det)),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return LayoutBuilder(builder: (context, constraints) {
      final dayWidth = (constraints.maxWidth - _timeColWidth) / 7;
      _initScroll(dayWidth);

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 고정 시간 컬럼 (왼쪽, 세로 스크롤 미러) ─────────────────
          SizedBox(
            width: _timeColWidth,
            child: Column(
              children: [
                // 헤더 높이 자리 맞춤
                Container(
                  height: _headerHeight,
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      right: BorderSide(color: AppColors.border),
                      bottom: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
                // 시간 라벨 (NeverScrollable, _timeCtrl로 동기화)
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      controller: _timeCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        height: _totalHeight,
                        child: Stack(
                          children: List.generate(_endHour - _startHour, (i) =>
                            Positioned(
                              top: i * _slotHeight,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: _slotHeight,
                                decoration: const BoxDecoration(
                                  color: AppColors.surface,
                                  border: Border(
                                    right: BorderSide(color: AppColors.border),
                                    bottom: BorderSide(color: AppColors.divider),
                                  ),
                                ),
                                padding: const EdgeInsets.only(right: 6, top: 4),
                                child: Text(
                                  '${_startHour + i}:00',
                                  textAlign: TextAlign.right,
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── 날짜 헤더 + 그리드 (오른쪽, 수평 스냅 스크롤) ───────────
          Expanded(
            child: Column(
              children: [
                // 날짜 헤더 (NeverScrollable, _horizHdrCtrl → _horizCtrl 미러)
                SizedBox(
                  height: _headerHeight,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: ListView.builder(
                      controller: _horizHdrCtrl,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      itemExtent: dayWidth,
                      itemCount: _totalDays,
                      itemBuilder: (ctx, idx) {
                        final d = _baseDate.add(Duration(days: idx - _baseIdx));
                        final isToday = d.year == today.year &&
                            d.month == today.month && d.day == today.day;
                        final isFocused = _focusedDate != null &&
                            d.year == _focusedDate!.year &&
                            d.month == _focusedDate!.month &&
                            d.day == _focusedDate!.day;
                        final isSat = d.weekday == 6;
                        final isSun = d.weekday == 7;
                        return GestureDetector(
                          onTap: () {
                            final newFocus = isFocused ? null : d;
                            setState(() => _focusedDate = newFocus);
                            widget.onFocusedDateChanged?.call(newFocus);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isFocused
                                  ? AppColors.primary.withAlpha(20)
                                  : AppColors.surface,
                              border: Border(
                                right: const BorderSide(
                                    color: AppColors.border, width: 0.5),
                                bottom: isFocused
                                    ? const BorderSide(
                                        color: AppColors.primary, width: 2)
                                    : const BorderSide(
                                        color: AppColors.border),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _weekdays[d.weekday - 1],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isFocused
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: isSun
                                        ? AppColors.error
                                        : isSat
                                            ? AppColors.primary
                                            : isFocused
                                                ? AppColors.primary
                                                : AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? AppColors.primary
                                        : isFocused
                                            ? AppColors.primaryLight
                                            : Colors.transparent,
                                    shape: BoxShape.circle,
                                    border: isFocused && !isToday
                                        ? Border.all(
                                            color: AppColors.primary,
                                            width: 1.5)
                                        : null,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${d.day}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isToday
                                            ? Colors.white
                                            : isSun
                                                ? AppColors.error
                                                : isSat
                                                    ? AppColors.primary
                                                    : isFocused
                                                        ? AppColors.primary
                                                        : AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // 그리드 (세로 스크롤 + 가로 1일 스냅 스크롤)
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // 세로 스크롤 → 시간축 동기화
                      if (n.metrics.axis == Axis.vertical &&
                          (n is ScrollUpdateNotification ||
                              n is ScrollEndNotification) &&
                          _timeCtrl.hasClients) {
                        _timeCtrl.jumpTo(_vertCtrl.offset);
                      }
                      // 가로 스크롤 완료 → 날짜 업데이트
                      if (n is ScrollEndNotification &&
                          n.metrics.axis == Axis.horizontal) {
                        final newDate = _offsetToDate(_horizCtrl.offset);
                        final d0 = DateTime(
                            newDate.year, newDate.month, newDate.day);
                        final d1 = DateTime(widget.selectedDate.year,
                            widget.selectedDate.month,
                            widget.selectedDate.day);
                        if (!d0.isAtSameMomentAs(d1)) {
                          widget.onDateChanged(newDate);
                          widget.onFocusedDateChanged?.call(null);
                        }
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: _vertCtrl,
                      child: SizedBox(
                        key: _gridKey,
                        height: _totalHeight,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ListView.builder(
                            controller: _horizCtrl,
                            scrollDirection: Axis.horizontal,
                            physics: _DaySnapPhysics(dayWidth: dayWidth),
                            itemExtent: dayWidth,
                            itemCount: _totalDays,
                            itemBuilder: (ctx, idx) {
                              final d = _baseDate
                                  .add(Duration(days: idx - _baseIdx));
                              final isFocused = _focusedDate != null &&
                                  d.year == _focusedDate!.year &&
                                  d.month == _focusedDate!.month &&
                                  d.day == _focusedDate!.day;
                              final isDropTarget = _dropDate != null &&
                                  d.year == _dropDate!.year &&
                                  d.month == _dropDate!.month &&
                                  d.day == _dropDate!.day;
                              return _WeekDayColumn(
                                date: d,
                                filterStatus: widget.filterStatus,
                                filterStaffId: widget.filterStaffId,
                                isFocused: isFocused,
                                dropTime: isDropTarget ? _dropTime : null,
                                dragAptId: _dragApt?.apt.id,
                                onAptTap: (det) => _showDetail(context, det),
                                onAptDragStart: _startDrag,
                                onAptDragMove: _updateDrag,
                                onAptDragEnd: _endDrag,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}

// ─── 주 뷰 하루 컬럼 ──────────────────────────────────────────────────────
class _WeekDayColumn extends ConsumerWidget {
  const _WeekDayColumn({
    required this.date,
    required this.filterStatus,
    required this.onAptTap,
    required this.onAptDragStart,
    required this.onAptDragMove,
    required this.onAptDragEnd,
    this.isFocused = false,
    this.dropTime,
    this.dragAptId,
    this.filterStaffId,
  });

  final DateTime date;
  final String? filterStatus;
  final String? filterStaffId;
  final ValueChanged<AppointmentDetail> onAptTap;
  final void Function(AppointmentDetail, Offset) onAptDragStart;
  final ValueChanged<Offset> onAptDragMove;
  final ValueChanged<Offset> onAptDragEnd;
  final bool isFocused;
  final DateTime? dropTime;
  final String? dragAptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aptsAsync = ref.watch(appointmentDetailsForDateProvider(date));
    final blockedAsync = ref.watch(blockedTimesForDateProvider(date));
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    final bgColor = isFocused
        ? AppColors.primary.withAlpha(18)
        : isToday
            ? AppColors.primaryLight.withAlpha(40)
            : AppColors.surface;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: const BorderSide(color: AppColors.border, width: 0.5),
          left: isFocused
              ? const BorderSide(color: AppColors.primary, width: 1.5)
              : BorderSide.none,
        ),
      ),
      child: Stack(
        children: [
          // 정시 그리드 라인 (진한)
          ...List.generate(_endHour - _startHour, (i) => Positioned(
            top: i * _slotHeight,
            left: 0, right: 0,
            child: Container(height: 1, color: const Color(0xFFCDD1D8)),
          )),
          // 30분 그리드 라인 (연한)
          ...List.generate(_endHour - _startHour, (i) => Positioned(
            top: i * _slotHeight + _slotHeight / 2,
            left: 0, right: 0,
            child: Container(height: 1, color: const Color(0xFFE8EAED)),
          )),
          // 블록 타임 (昼休み 등)
          ...blockedAsync.maybeWhen(
            data: (blocks) => blocks.where((b) {
              if (filterStaffId != null && b.staffId != filterStaffId) return false;
              return true;
            }).map((b) {
              final start = DateTime.tryParse(b.startAt);
              final end = DateTime.tryParse(b.endAt);
              if (start == null || end == null) return const SizedBox.shrink();
              final topPx = (start.hour - _startHour + start.minute / 60) * _slotHeight;
              final heightPx = _minToY(end.difference(start).inMinutes);
              if (topPx < 0 || topPx >= _totalHeight) return const SizedBox.shrink();
              return Positioned(
                top: topPx,
                left: 0, right: 0,
                height: heightPx.clamp(12.0, _totalHeight),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0x1A8B95A1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      b.description ?? '---',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF8B95A1),
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              );
            }).toList(),
            orElse: () => [],
          ),
          // 드롭 인디케이터
          if (dropTime != null) _DropIndicator(time: dropTime!),
          // 예약 블록
          ...aptsAsync.maybeWhen(
            data: (apts) {
              var filtered = filterStatus == null
                  ? apts
                  : apts.where((a) => a.apt.status == filterStatus).toList();
              if (filterStaffId != null) {
                filtered = filtered.where((a) => a.apt.staffId == filterStaffId).toList();
              }
              return filtered.map((det) {
                final start = det.startDt;
                final end = det.endDt;
                final topPx = (start.hour - _startHour + start.minute / 60) * _slotHeight;
                final heightPx = _minToY(end.difference(start).inMinutes);
                if (topPx < 0 || topPx >= _totalHeight) return const SizedBox.shrink();
                final blockColor = det.apt.color != null
                    ? _parseColor(det.apt.color!)
                    : _statusColor(det.apt.status);
                final isDragging = det.apt.id == dragAptId;
                return Positioned(
                  top: topPx + 1,
                  left: 2, right: 2,
                  height: (heightPx - 2).clamp(16.0, _totalHeight),
                  child: Opacity(
                    opacity: isDragging ? 0.35 : 1.0,
                    child: GestureDetector(
                      onTap: () => onAptTap(det),
                      onLongPressStart: (d) => onAptDragStart(det, d.globalPosition),
                      onLongPressMoveUpdate: (d) => onAptDragMove(d.globalPosition),
                      onLongPressEnd: (d) => onAptDragEnd(d.globalPosition),
                      child: Container(
                        decoration: BoxDecoration(
                          color: blockColor.withAlpha(38),
                          borderRadius: BorderRadius.circular(4),
                          border: Border(
                            left: BorderSide(color: blockColor, width: 3),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(4, 2, 2, 2),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 시간 + 상태 배지 (한 줄)
                            Row(
                              children: [
                                Text(
                                  _hm(start),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: blockColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (det.apt.status == 'confirmed') ...[
                                  const SizedBox(width: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                                    decoration: BoxDecoration(
                                      color: blockColor.withAlpha(40),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Text('確',
                                      style: TextStyle(fontSize: 7, color: blockColor, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ] else if (det.apt.status == 'checked_in') ...[
                                  const SizedBox(width: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withAlpha(40),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: const Text('在',
                                      style: TextStyle(fontSize: 7, color: AppColors.success, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            // 고객명
                            Text(
                              det.displayName,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // 시술명 (박스 높이 충분 시만)
                            if (heightPx >= 52 && det.menuSummary.isNotEmpty)
                              Text(
                                det.menuSummary,
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            // 담당자 (박스 높이 충분 시만)
                            if (heightPx >= 72 && det.staffName != null)
                              Text(
                                '担: ${det.staffName}',
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList();
            },
            orElse: () => [],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ─── 월 단위 캘린더 ────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
class _MonthCalendar extends ConsumerStatefulWidget {
  const _MonthCalendar({
    required this.selectedDate,
    required this.onDateFocused,
    this.filterStatus,
    this.filterStaffId,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateFocused;
  final String? filterStatus;
  final String? filterStaffId;

  @override
  ConsumerState<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends ConsumerState<_MonthCalendar> {
  DateTime? _focusedDate;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final year = widget.selectedDate.year;
    final month = widget.selectedDate.month;
    final firstDay = DateTime(year, month, 1);
    final offset = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final daysInPrevMonth = DateTime(year, month, 0).day;
    final rowCount = ((offset + daysInMonth) / 7).ceil();

    return Column(
      children: [
        // 요일 헤더
        Container(
          color: AppColors.surface,
          child: Row(
            children: List.generate(7, (i) {
              final isSat = i == 5;
              final isSun = i == 6;
              return Expanded(
                child: Container(
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom:
                          const BorderSide(color: AppColors.border, width: 0.5),
                      right: i < 6
                          ? const BorderSide(
                              color: AppColors.divider, width: 0.5)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    _weekdays[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSun
                          ? AppColors.error
                          : isSat
                              ? AppColors.primary
                              : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        // 날짜 그리드 (화면 높이에 맞게 동적 계산)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellHeight = constraints.maxHeight / rowCount;
              return Column(
                children: List.generate(rowCount, (row) {
                  return SizedBox(
                    height: cellHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(7, (col) {
                        final idx = row * 7 + col;
                        final dayNum = idx - offset + 1;

                        // 이전 달 날짜
                        if (dayNum < 1) {
                          final prevDay = daysInPrevMonth + dayNum;
                          final prevDate =
                              DateTime(year, month - 1, prevDay);
                          return _MonthCellOther(
                            date: prevDate,
                            col: col,
                            isLastRow: row == rowCount - 1,
                          );
                        }
                        // 다음 달 날짜
                        if (dayNum > daysInMonth) {
                          final nextDay = dayNum - daysInMonth;
                          final nextDate = DateTime(year, month + 1, nextDay);
                          return _MonthCellOther(
                            date: nextDate,
                            col: col,
                            isLastRow: row == rowCount - 1,
                          );
                        }

                        // 현재 달 날짜
                        final d = DateTime(year, month, dayNum);
                        final isToday = d.year == today.year &&
                            d.month == today.month &&
                            d.day == today.day;
                        final isFocused = _focusedDate != null &&
                            d.year == _focusedDate!.year &&
                            d.month == _focusedDate!.month &&
                            d.day == _focusedDate!.day;
                        final isSat = d.weekday == 6;
                        final isSun = d.weekday == 7;

                        return Expanded(
                          child: _MonthCell(
                            date: d,
                            isToday: isToday,
                            isFocused: isFocused,
                            isSat: isSat,
                            isSun: isSun,
                            col: col,
                            isLastRow: row == rowCount - 1,
                            filterStatus: widget.filterStatus,
                            filterStaffId: widget.filterStaffId,
                            onTap: () {
                              final newFocus = isFocused ? null : d;
                              setState(() => _focusedDate = newFocus);
                              if (newFocus != null)
                                widget.onDateFocused(newFocus);
                            },
                          ),
                        );
                      }),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── 월 뷰 셀 (현재 달) ───────────────────────────────────────────────────
class _MonthCell extends ConsumerWidget {
  const _MonthCell({
    required this.date,
    required this.isToday,
    required this.isFocused,
    required this.isSat,
    required this.isSun,
    required this.col,
    required this.isLastRow,
    required this.onTap,
    this.filterStatus,
    this.filterStaffId,
  });

  final DateTime date;
  final bool isToday;
  final bool isFocused;
  final bool isSat;
  final bool isSun;
  final int col;
  final bool isLastRow;
  final VoidCallback onTap;
  final String? filterStatus;
  final String? filterStaffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aptsAsync = ref.watch(appointmentDetailsForDateProvider(date)).whenData(
      (list) {
        var filtered = list;
        if (filterStatus != null) {
          filtered = filtered.where((d) => d.apt.status == filterStatus).toList();
        }
        if (filterStaffId != null) {
          filtered = filtered.where((d) => d.apt.staffId == filterStaffId).toList();
        }
        return filtered;
      },
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isFocused
              ? AppColors.primaryLight
              : isToday
                  ? AppColors.primaryLight.withAlpha(60)
                  : AppColors.surface,
          border: Border(
            right: col < 6
                ? const BorderSide(color: AppColors.divider, width: 0.5)
                : BorderSide.none,
            bottom: isLastRow
                ? BorderSide.none
                : const BorderSide(color: AppColors.divider, width: 0.5),
            top: isFocused
                ? const BorderSide(color: AppColors.primary, width: 2)
                : BorderSide.none,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(5, 4, 3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 날짜 숫자 + 건수
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColors.primary
                        : isFocused
                            ? AppColors.primary.withAlpha(30)
                            : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isToday || isFocused
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: isToday
                            ? Colors.white
                            : isFocused
                                ? AppColors.primary
                                : isSun
                                    ? AppColors.error
                                    : isSat
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                // 총 예약 건수 배지
                aptsAsync.maybeWhen(
                  data: (apts) => apts.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Text(
                            '${apts.length}件',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: isSun
                                  ? AppColors.error.withAlpha(160)
                                  : isSat
                                      ? AppColors.primary.withAlpha(160)
                                      : AppColors.textSecondary,
                            ),
                          ),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            // 예약 시간 범위 세로 나열
            Expanded(
              child: aptsAsync.maybeWhen(
                data: (apts) {
                  if (apts.isEmpty) return const SizedBox.shrink();
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      // 한 줄 높이 약 16px (fontSize 11 + padding)
                      const lineHeight = 16.0;
                      final maxLines =
                          (constraints.maxHeight / lineHeight).floor();
                      final canShow = maxLines.clamp(0, apts.length);
                      final overflow = apts.length - canShow;

                      if (canShow == 0) {
                        // 공간이 전혀 없으면 건수만
                        return Center(
                          child: Text(
                            '+${apts.length}件',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...apts.take(canShow).map((det) {
                            final c = _statusColor(det.apt.status);
                            return SizedBox(
                              height: lineHeight,
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 3,
                                    margin: const EdgeInsets.only(
                                        right: 3, top: 1),
                                    decoration: BoxDecoration(
                                        color: c, shape: BoxShape.circle),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${_hm(det.startDt)}-${_hm(det.endDt)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: c,
                                        fontWeight: FontWeight.w600,
                                        height: 1.1,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          if (overflow > 0)
                            Expanded(
                              child: Center(
                                child: Text(
                                  '+$overflow件',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 월 뷰 셀 (이전/다음 달) ─────────────────────────────────────────────
class _MonthCellOther extends ConsumerWidget {
  const _MonthCellOther({
    required this.date,
    required this.col,
    required this.isLastRow,
  });

  final DateTime date;
  final int col;
  final bool isLastRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aptsAsync = ref.watch(appointmentDetailsForDateProvider(date));
    final isSat = date.weekday == 6;
    final isSun = date.weekday == 7;

    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          // 약간 어둡게 — 현재 달과 구별
          color: const Color(0xFFF2F3F5),
          border: Border(
            right: col < 6
                ? const BorderSide(color: AppColors.divider, width: 0.5)
                : BorderSide.none,
            bottom: isLastRow
                ? BorderSide.none
                : const BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(5, 4, 3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: isSun
                    ? AppColors.error.withAlpha(120)
                    : isSat
                        ? AppColors.primary.withAlpha(120)
                        : AppColors.textDisabled,
              ),
            ),
            Expanded(
              child: aptsAsync.maybeWhen(
                data: (apts) {
                  if (apts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: apts.take(3).map((det) {
                      final c = _statusColor(det.apt.status).withAlpha(140);
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _hm(det.startDt),
                          style: TextStyle(
                            fontSize: 9,
                            color: c,
                            height: 1.2,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ─── 좌측 패널 (미니 달력 + 예약 리스트) ───────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
class _LeftPanel extends ConsumerStatefulWidget {
  const _LeftPanel({
    required this.selectedDate,
    required this.viewMode,
    required this.onDateChanged,
    required this.onAptTap,
    this.onFocusDateChanged,
  });

  final DateTime selectedDate;
  final _ViewMode viewMode;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<AppointmentDetail> onAptTap;
  final ValueChanged<DateTime?>? onFocusDateChanged;

  @override
  ConsumerState<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends ConsumerState<_LeftPanel> {
  late DateTime _calendarMonth;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    _calendarMonth = DateTime(
        widget.selectedDate.year, widget.selectedDate.month);
  }

  // 시간표 날짜가 바뀌면 미니 달력 월도 따라감
  @override
  void didUpdateWidget(_LeftPanel old) {
    super.didUpdateWidget(old);
    if (widget.selectedDate.year != old.selectedDate.year ||
        widget.selectedDate.month != old.selectedDate.month) {
      setState(() {
        _calendarMonth = DateTime(
            widget.selectedDate.year, widget.selectedDate.month);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final aptsAsync =
        ref.watch(appointmentDetailsForDateProvider(widget.selectedDate));
    final staffMap = ref.watch(staffMapProvider).valueOrNull ?? {};
    final now = DateTime.now();
    final isToday = widget.selectedDate.year == now.year &&
        widget.selectedDate.month == now.month &&
        widget.selectedDate.day == now.day;
    final isSat = widget.selectedDate.weekday == 6;
    final isSun = widget.selectedDate.weekday == 7;

    return SizedBox(
      width: 260,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─ 상단 날짜 + 건수 (BookingHeader 와 같은 높이) ──────────
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppColors.primary
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${widget.selectedDate.day}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isToday
                            ? Colors.white
                            : isSun
                                ? AppColors.error
                                : isSat
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.selectedDate.year}年'
                        '${widget.selectedDate.month}月',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        _weekdays[widget.selectedDate.weekday - 1],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSun
                              ? AppColors.error
                              : isSat
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  aptsAsync.maybeWhen(
                    data: (list) => list.isEmpty
                        ? const SizedBox.shrink()
                        : Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${list.length}件',
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // ─ 미니 달력 (8월 6주 최대 기준 2/5) ────────────────────
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // 월 네비게이션
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 18),
                          onPressed: () => setState(() {
                            _calendarMonth = DateTime(
                                _calendarMonth.year,
                                _calendarMonth.month - 1);
                          }),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        ),
                        Expanded(
                          child: Text(
                            '${_calendarMonth.year}年'
                            '${_calendarMonth.month}月',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body2.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 18),
                          onPressed: () => setState(() {
                            _calendarMonth = DateTime(
                                _calendarMonth.year,
                                _calendarMonth.month + 1);
                          }),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                  ),
                  // 달력 그리드
                  Expanded(
                    child: Builder(builder: (ctx) {
                      // 시간표의 실제 스크롤 위치 (첫 번째 열 날짜)
                      // _sidebarDate가 아닌 selectedDateProvider를 기준으로 범위 계산
                      final timetableStart = ref.watch(selectedDateProvider);
                      return _MiniCalendarGrid(
                        month: _calendarMonth,
                        selectedDate: widget.selectedDate,
                        viewMode: widget.viewMode,
                        // 주 단위: 실제 시간표 위치 기준 범위 하이라이트
                        weekRangeStart: widget.viewMode == _ViewMode.week
                            ? timetableStart
                            : null,
                        onDateTap: (d) {
                          if (widget.viewMode == _ViewMode.week) {
                            // 범위 체크: _sidebarDate가 아닌 timetableStart 사용
                            final s = DateTime(timetableStart.year,
                                timetableStart.month, timetableStart.day);
                            final e = s.add(const Duration(days: 6));
                            final day = DateTime(d.year, d.month, d.day);
                            final inRange = !day.isBefore(s) && !day.isAfter(e);
                            if (!inRange) widget.onDateChanged(d);
                            widget.onFocusDateChanged?.call(d);
                          } else {
                            widget.onDateChanged(d);
                          }
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ─ 예약 리스트 (나머지 3/5) ──────────────────────────────
            Expanded(
              flex: 3,
              child: aptsAsync.when(
                data: (list) => list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.event_available_outlined,
                                size: 36, color: AppColors.border),
                            const SizedBox(height: 6),
                            Text(
                              '予約なし',
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: list.length,
                        itemBuilder: (ctx, i) => _SidePanelAptCard(
                          detail: list[i],
                          staffMap: staffMap,
                          onTap: () => widget.onAptTap(list[i]),
                        ),
                      ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 미니 달력 그리드 ─────────────────────────────────────────────────────
class _MiniCalendarGrid extends ConsumerWidget {
  const _MiniCalendarGrid({
    required this.month,
    required this.selectedDate,
    required this.viewMode,
    required this.onDateTap,
    this.weekRangeStart,
  });

  final DateTime month;
  final DateTime selectedDate;
  final _ViewMode viewMode;
  final ValueChanged<DateTime> onDateTap;
  /// 주 단위에서 실제 시간표 스크롤 위치 (범위 하이라이트 기준).
  /// null이면 selectedDate를 사용.
  final DateTime? weekRangeStart;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  // 현재 뷰 모드에 따른 하이라이트 범위 계산
  (DateTime, DateTime) get _rangeForView {
    switch (viewMode) {
      case _ViewMode.day:
        return (selectedDate, selectedDate);
      case _ViewMode.week:
        // weekRangeStart가 있으면 실제 시간표 스크롤 위치 기준으로 계산
        final rangeStart = weekRangeStart ?? selectedDate;
        return (rangeStart, rangeStart.add(const Duration(days: 6)));
      case _ViewMode.month:
      case _ViewMode.list:
        final first = DateTime(selectedDate.year, selectedDate.month, 1);
        final last =
            DateTime(selectedDate.year, selectedDate.month + 1, 0);
        return (first, last);
    }
  }

  bool _inRange(DateTime d) {
    final (start, end) = _rangeForView;
    final date = DateTime(d.year, d.month, d.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !date.isBefore(s) && !date.isAfter(e);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final firstDay = DateTime(month.year, month.month, 1);
    final offset = (firstDay.weekday - 1) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = ((offset + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: [
        // 요일 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: List.generate(7, (i) {
              final isSat = i == 5;
              final isSun = i == 6;
              return Expanded(
                child: Center(
                  child: Text(
                    _weekdays[i],
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: isSun
                          ? AppColors.error
                          : isSat
                              ? AppColors.primary
                              : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 2),
        // 날짜 그리드
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
            ),
            itemCount: totalCells,
            itemBuilder: (context, idx) {
              final dayNum = idx - offset + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox();
              }
              final d = DateTime(month.year, month.month, dayNum);
              final isToday = d.year == today.year &&
                  d.month == today.month &&
                  d.day == today.day;
              final isSelected = d.year == selectedDate.year &&
                  d.month == selectedDate.month &&
                  d.day == selectedDate.day;
              final inRange = _inRange(d);
              final isSat = d.weekday == 6;
              final isSun = d.weekday == 7;
              final aptsAsync =
                  ref.watch(appointmentDetailsForDateProvider(d));
              final hasApts =
                  aptsAsync.valueOrNull?.isNotEmpty ?? false;

              return GestureDetector(
                onTap: () => onDateTap(d),
                child: Container(
                  margin: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : isToday
                            ? AppColors.primaryLight
                            : inRange
                                ? AppColors.primary.withAlpha(18)
                                : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: inRange && !isSelected && !isToday
                        ? Border.all(
                            color: AppColors.primary.withAlpha(40),
                            width: 0.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected || isToday || inRange
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? Colors.white
                              : isToday
                                  ? AppColors.primary
                                  : isSun
                                      ? AppColors.error
                                      : isSat
                                          ? AppColors.primary
                                          : inRange
                                              ? AppColors.primary
                                              : AppColors.textPrimary,
                        ),
                      ),
                      if (hasApts && !isSelected)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary
                                : AppColors.primary.withAlpha(180),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── 사이드패널 예약 카드 ─────────────────────────────────────────────────
class _SidePanelAptCard extends StatelessWidget {
  const _SidePanelAptCard({
    required this.detail,
    required this.staffMap,
    required this.onTap,
  });

  final AppointmentDetail detail;
  final Map<String, dynamic> staffMap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final apt = detail.apt;
    final status = apt.status;
    final color = _statusColor(status);

    final start = DateTime.parse(apt.startAt);
    final end = DateTime.parse(apt.endAt);
    final timeStr =
        '${_t(start.hour)}:${_t(start.minute)} − ${_t(end.hour)}:${_t(end.minute)}';

    final staff = staffMap[apt.staffId];
    final staffName = (staff?.name ?? '') as String;
    final staffColor = staff != null
        ? _parseHexColor(staff.color as String)
        : AppColors.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상태 컬러 바 (좌측)
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10)),
                ),
              ),
              // 카드 내용
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 시간
                      Text(
                        timeStr,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      // 고객명
                      Text(
                        detail.displayName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 메뉴 요약
                      if (detail.menuSummary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          detail.menuSummary,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 5),
                      // 스태프 + 상태 배지
                      Row(
                        children: [
                          if (staffName.isNotEmpty) ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: staffColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                staffName,
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withAlpha(20),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: TextStyle(
                                fontSize: 9,
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 화살표
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _t(int v) => v.toString().padLeft(2, '0');

  Color _parseHexColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return AppColors.primary;
    }
  }

  String _statusLabel(String status) {
    const labels = {
      'pending': '確認待',
      'confirmed': '確認済',
      'in_progress': '施術中',
      'completed': '完了',
      'no_show': 'ノーショー',
    };
    return labels[status] ?? status;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ─── 목록 뷰 (一覧) ────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════
class _ListCalendar extends ConsumerWidget {
  const _ListCalendar({
    required this.selectedDate,
    required this.filterStatus,
    required this.filterStaffId,
    required this.onAptTap,
  });

  final DateTime selectedDate;
  final String? filterStatus;
  final String? filterStaffId;
  final ValueChanged<AppointmentDetail> onAptTap;

  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  static const _statusLabels = <String, String>{
    'pending': '確認待ち',
    'confirmed': '確認済み',
    'in_progress': '施術中',
    'completed': '完了',
    'no_show': 'ノーショー',
    'cancelled': 'キャンセル',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = DateTime(selectedDate.year, selectedDate.month);
    final aptsAsync = ref.watch(appointmentDetailsForMonthProvider(month));
    final staffMap = ref.watch(staffMapProvider).valueOrNull ?? {};

    return aptsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (allApts) {
        // 필터 적용
        var apts = allApts;
        if (filterStatus != null) {
          apts = apts.where((a) => a.apt.status == filterStatus).toList();
        }
        if (filterStaffId != null) {
          apts = apts.where((a) => a.apt.staffId == filterStaffId).toList();
        }

        if (apts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy_outlined,
                    size: 48, color: AppColors.border),
                const SizedBox(height: 12),
                Text(
                  '${selectedDate.year}年${selectedDate.month}月の予約はありません',
                  style: AppTextStyles.body1
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // ─ 테이블 헤더 ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 1)),
              ),
              child: Row(
                children: [
                  // 건수 배지
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '全${apts.length}件',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  // 컬럼 헤더
                  const SizedBox(width: _listColDate),
                  _ListHeader('顧客名', flex: _listFlexCustomer),
                  _ListHeader('メニュー', flex: _listFlexMenu),
                  _ListHeader('担当', flex: _listFlexStaff),
                  SizedBox(
                    width: 72,
                    child: Text('状態',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        )),
                  ),
                  const SizedBox(width: 20), // chevron 공간
                ],
              ),
            ),

            // ─ 테이블 바디 ──────────────────────────────────────────
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: apts.length,
                itemBuilder: (ctx, i) {
                  final det = apts[i];
                  final apt = det.apt;
                  final staffData = staffMap[apt.staffId];
                  final staffName = staffData?.name ?? '';
                  final staffColor = _parseColor(staffData?.color);
                  final statusColor = _statusColor(apt.status);
                  final statusLabel =
                      _statusLabels[apt.status] ?? apt.status;

                  final d = det.startDt;
                  final dayLabel =
                      '${d.month}/${d.day}(${_weekdays[d.weekday - 1]})';
                  final timeLabel =
                      '${_hm(det.startDt)}〜${_hm(det.endDt)}';

                  final isSun = d.weekday == 7;
                  final isSat = d.weekday == 6;
                  final dateColor = isSun
                      ? AppColors.error
                      : isSat
                          ? AppColors.primary
                          : AppColors.textPrimary;

                  return InkWell(
                    onTap: () => onAptTap(det),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 0),
                      decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: AppColors.divider, width: 0.5)),
                      ),
                      height: 52,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 날짜 + 시간
                          SizedBox(
                            width: _listColDate,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dayLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: dateColor,
                                  ),
                                ),
                                Text(
                                  timeLabel,
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 고객명
                          Expanded(
                            flex: _listFlexCustomer,
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    det.displayName,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (det.cautionFlag || det.allergies != null) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.warning_amber_rounded,
                                      size: 12, color: AppColors.error),
                                ],
                              ],
                            ),
                          ),
                          // 메뉴
                          Expanded(
                            flex: _listFlexMenu,
                            child: Text(
                              det.menuSummary.isEmpty ? '−' : det.menuSummary,
                              style: AppTextStyles.caption.copyWith(
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 담당자
                          Expanded(
                            flex: _listFlexStaff,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (staffName.isNotEmpty) ...[
                                  Container(
                                    width: 7, height: 7,
                                    decoration: BoxDecoration(
                                        color: staffColor,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    staffName.isEmpty ? '−' : staffName,
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 상태
                          SizedBox(
                            width: 72,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: statusColor.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                statusLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              size: 16, color: AppColors.textDisabled),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// 목록 뷰 컬럼 폭 상수
const double _listColDate = 88.0;
const int _listFlexCustomer = 3;
const int _listFlexMenu = 4;
const int _listFlexStaff = 2;

class _ListHeader extends StatelessWidget {
  const _ListHeader(this.label, {this.flex = 1});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

// ─── ブロックタイム追加ダイアログ ─────────────────────────────────────────
class _AddBlockDialog extends ConsumerStatefulWidget {
  const _AddBlockDialog({required this.initialDate});
  final DateTime initialDate;

  @override
  ConsumerState<_AddBlockDialog> createState() => _AddBlockDialogState();
}

class _AddBlockDialogState extends ConsumerState<_AddBlockDialog> {
  late DateTime _startAt;
  late DateTime _endAt;
  String? _staffId;
  String _desc = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate;
    _startAt = DateTime(d.year, d.month, d.day, 12, 0);
    _endAt = DateTime(d.year, d.month, d.day, 13, 0);
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startAt : _endAt;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startAt = DateTime(
            _startAt.year, _startAt.month, _startAt.day,
            picked.hour, picked.minute);
      } else {
        _endAt = DateTime(
            _endAt.year, _endAt.month, _endAt.day,
            picked.hour, picked.minute);
      }
    });
  }

  Future<void> _save() async {
    if (_staffId == null) return;
    if (!_endAt.isAfter(_startAt)) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      await db.into(db.blockedTimes).insert(BlockedTimesCompanion.insert(
        id: const Uuid().v4(),
        staffId: _staffId!,
        startAt: _startAt.toIso8601String(),
        endAt: _endAt.toIso8601String(),
        description: Value(_desc.isEmpty ? null : _desc),
      ));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffMapProvider);
    final staffList = staffAsync.valueOrNull?.values.toList() ?? [];

    final startHm = '${_startAt.hour.toString().padLeft(2,'0')}:${_startAt.minute.toString().padLeft(2,'0')}';
    final endHm = '${_endAt.hour.toString().padLeft(2,'0')}:${_endAt.minute.toString().padLeft(2,'0')}';

    return AlertDialog(
      title: const Text('ブロック時間を追加'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 스태프 선택
            DropdownButtonFormField<String>(
              value: _staffId,
              decoration: const InputDecoration(labelText: 'スタッフ *'),
              items: staffList.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name),
                  )).toList(),
              onChanged: (v) => setState(() => _staffId = v),
            ),
            const SizedBox(height: 12),
            // 시간 선택
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text('開始: $startHm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(false),
                    child: Text('終了: $endHm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 설명
            TextField(
              decoration: const InputDecoration(
                labelText: '内容 (例: 昼休み)',
                hintText: '昼休み、清掃、ミーティング…',
              ),
              onChanged: (v) => _desc = v,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル')),
        FilledButton(
          onPressed: (_staffId == null || _saving) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}

