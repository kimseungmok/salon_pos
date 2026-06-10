import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

// ─── 현재 선택된 날짜 ─────────────────────────────────────────────────────
final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

// ─── 예약 상세 데이터 클래스 ────────────────────────────────────────────────
class AppointmentDetail {
  final Appointment apt;
  final String? customerName;
  final String? customerPhone;
  final String? staffName;  // 담당자명
  final List<String> menuNames;
  final int totalPrice;
  final int processingMin; // 발색 등 스태프 이석 가능 시간
  final int bufferMin;     // 정리 시간 (스태프 사용 불가)
  final bool cautionFlag;
  final String? cautionNote;
  final String? allergies;
  final int customerTotalVisits;   // 고객 총 방문 횟수
  final String? customerLastVisit; // 고객 최근 방문일
  final String? staffColor;        // 스태프 지정 색상 (hex)

  const AppointmentDetail({
    required this.apt,
    this.customerName,
    this.customerPhone,
    this.staffName,
    required this.menuNames,
    this.totalPrice = 0,
    this.processingMin = 0,
    this.bufferMin = 0,
    this.cautionFlag = false,
    this.cautionNote,
    this.allergies,
    this.customerTotalVisits = 0,
    this.customerLastVisit,
    this.staffColor,
  });

  bool get hasProcessing => processingMin > 0;

  DateTime get startDt => DateTime.parse(apt.startAt);
  DateTime get endDt => DateTime.parse(apt.endAt);
  int get durationMin => endDt.difference(startDt).inMinutes;
  int get serviceDurationMin =>
      (durationMin - processingMin).clamp(15, durationMin);

  String get displayName =>
      customerName ?? (menuNames.isNotEmpty ? menuNames.first : '予約');
  String get menuSummary => menuNames.isEmpty
      ? ''
      : menuNames.length == 1
          ? menuNames.first
          : '${menuNames.first} 他${menuNames.length - 1}件';
}

// ─── 날짜별 예약 목록 (상세 포함) ─────────────────────────────────────────
final appointmentDetailsForDateProvider =
    StreamProvider.family<List<AppointmentDetail>, DateTime>((ref, date) {
  final db = ref.watch(databaseProvider);
  final dateStr = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  return (db.select(db.appointments)
        ..where((t) => t.startAt.like('$dateStr%'))
        ..where((t) => t.status.isNotIn(['cancelled']))
        ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
      .watch()
      .asyncMap((apts) async {
    return Future.wait(apts.map((apt) async {
      // 고객 이름
      String? customerName;
      String? customerPhone;
      bool cautionFlag = false;
      String? cautionNote;
      String? allergies;
      int customerTotalVisits = 0;
      String? customerLastVisit;
      if (apt.customerId != null) {
        final c = await (db.select(db.customers)
              ..where((t) => t.id.equals(apt.customerId!)))
            .getSingleOrNull();
        customerName = c?.name;
        customerPhone = c?.phone;
        cautionFlag = c?.cautionFlag ?? false;
        cautionNote = c?.cautionNote;
        allergies = c?.allergies;
        customerTotalVisits = c?.totalVisits ?? 0;
        customerLastVisit = c?.lastVisitDate;
      }

      // 담당자 이름 + 색상
      String? staffName;
      String? staffColor;
      final s = await (db.select(db.staff)
            ..where((t) => t.id.equals(apt.staffId)))
          .getSingleOrNull();
      staffName = s?.name;
      staffColor = s?.color;

      // 예약 메뉴 목록
      final aptMenus = await (db.select(db.appointmentMenus)
            ..where((t) => t.appointmentId.equals(apt.id))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

      final menuNames = aptMenus.map((m) => m.menuName).toList();
      final totalPrice = aptMenus.fold(0, (s, m) => s + m.price);

      // menus 테이블에서 processing/buffer 시간 조회
      int processingMin = 0;
      int bufferMin = 0;
      for (final am in aptMenus) {
        final menu = await (db.select(db.menus)
              ..where((t) => t.id.equals(am.menuId)))
            .getSingleOrNull();
        if (menu != null) {
          if (menu.processingMin > processingMin) {
            processingMin = menu.processingMin;
          }
          if (menu.bufferMin > bufferMin) {
            bufferMin = menu.bufferMin;
          }
        }
      }

      return AppointmentDetail(
        apt: apt,
        customerName: customerName,
        customerPhone: customerPhone,
        staffName: staffName,
        menuNames: menuNames,
        totalPrice: totalPrice,
        processingMin: processingMin,
        bufferMin: bufferMin,
        cautionFlag: cautionFlag,
        cautionNote: cautionNote,
        allergies: allergies,
        customerTotalVisits: customerTotalVisits,
        customerLastVisit: customerLastVisit,
        staffColor: staffColor,
      );
    }));
  });
});

// ─── 월별 예약 목록 (목록 뷰용) ──────────────────────────────────────────
final appointmentDetailsForMonthProvider =
    StreamProvider.family<List<AppointmentDetail>, DateTime>((ref, month) {
  final db = ref.watch(databaseProvider);
  final prefix = '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}-';

  return (db.select(db.appointments)
        ..where((t) => t.startAt.like('$prefix%'))
        ..where((t) => t.status.isNotIn(['cancelled']))
        ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
      .watch()
      .asyncMap((apts) async {
    return Future.wait(apts.map((apt) async {
      String? customerName;
      String? customerPhone;
      bool cautionFlag2 = false;
      String? cautionNote2;
      String? allergies2;
      int totalVisits2 = 0;
      String? lastVisit2;
      if (apt.customerId != null) {
        final c = await (db.select(db.customers)
              ..where((t) => t.id.equals(apt.customerId!)))
            .getSingleOrNull();
        customerName = c?.name;
        customerPhone = c?.phone;
        cautionFlag2 = c?.cautionFlag ?? false;
        cautionNote2 = c?.cautionNote;
        allergies2 = c?.allergies;
        totalVisits2 = c?.totalVisits ?? 0;
        lastVisit2 = c?.lastVisitDate;
      }
      final sRow = await (db.select(db.staff)
            ..where((t) => t.id.equals(apt.staffId)))
          .getSingleOrNull();
      final staffName = sRow?.name;
      final staffColor2 = sRow?.color;
      final aptMenus = await (db.select(db.appointmentMenus)
            ..where((t) => t.appointmentId.equals(apt.id))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();
      final menuNames = aptMenus.map((m) => m.menuName).toList();
      final totalPrice = aptMenus.fold(0, (s, m) => s + m.price);
      int processingMin = 0;
      int bufferMin = 0;
      for (final am in aptMenus) {
        final menu = await (db.select(db.menus)
              ..where((t) => t.id.equals(am.menuId)))
            .getSingleOrNull();
        if (menu != null) {
          if (menu.processingMin > processingMin) processingMin = menu.processingMin;
          if (menu.bufferMin > bufferMin) bufferMin = menu.bufferMin;
        }
      }
      return AppointmentDetail(
        apt: apt,
        customerName: customerName,
        customerPhone: customerPhone,
        staffName: staffName,
        menuNames: menuNames,
        totalPrice: totalPrice,
        processingMin: processingMin,
        bufferMin: bufferMin,
        cautionFlag: cautionFlag2,
        cautionNote: cautionNote2,
        allergies: allergies2,
        customerTotalVisits: totalVisits2,
        customerLastVisit: lastVisit2,
        staffColor: staffColor2,
      );
    }));
  });
});

// ─── 단일 예약 메뉴 목록 ─────────────────────────────────────────────────
final appointmentMenusProvider =
    StreamProvider.family<List<AppointmentMenusData>, String>(
        (ref, appointmentId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.appointmentMenus)
        ..where((t) => t.appointmentId.equals(appointmentId))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── 스태프 맵 (id → StaffData) ──────────────────────────────────────────
final staffMapProvider = StreamProvider<Map<String, StaffData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.staff)..where((t) => t.isActive.equals(true)))
      .watch()
      .map((list) => {for (final s in list) s.id: s});
});

// ─── 대기자 목록 ─────────────────────────────────────────────────────────
final waitlistForDateProvider =
    StreamProvider.family<List<WaitlistData>, DateTime>((ref, date) {
  final db = ref.watch(databaseProvider);
  final dateStr = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return (db.select(db.waitlist)
        ..where((t) => t.preferredDate.equals(dateStr))
        ..where((t) => t.status.equals('waiting'))
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
      .watch();
});

// ─── 날짜 기준 블록 타임 ─────────────────────────────────────────────────
final blockedTimesForDateProvider =
    StreamProvider.family<List<BlockedTime>, DateTime>((ref, date) {
  final db = ref.watch(databaseProvider);
  final dateStr = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return (db.select(db.blockedTimes)
        ..where((t) => t.startAt.like('$dateStr%'))
        ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
      .watch();
});
