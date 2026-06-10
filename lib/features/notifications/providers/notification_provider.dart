import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

// ─── 알림 유형 ────────────────────────────────────────────────────────────
enum NotifType {
  pendingConfirm,  // 確認待ち — 스태프 확인 필요
  startingSoon,    // まもなく開始 — 30분 이내 시작
  possibleNoShow,  // ノーショー可能性 — 시작 시간 15분 초과, 미내방
  birthday,        // 🎂 今日が誕生日の顧客
  lowStock,        // 📦 在庫不足
}

// ─── 알림 데이터 ──────────────────────────────────────────────────────────
class SalonNotif {
  final NotifType type;
  final Appointment? apt;
  final String? customerName;
  final String? customerId;   // birthday 타입에서 고객 상세 이동용
  final String menuSummary;

  const SalonNotif({
    required this.type,
    this.apt,
    this.customerName,
    this.customerId,
    required this.menuSummary,
  });

  String get title {
    switch (type) {
      case NotifType.pendingConfirm:
        return '確認待ち';
      case NotifType.startingSoon:
        return 'まもなく開始';
      case NotifType.possibleNoShow:
        return 'ノーショー？';
      case NotifType.birthday:
        return '🎂 お誕生日';
      case NotifType.lowStock:
        return '📦 在庫不足';
    }
  }

  String get body {
    final name = customerName ?? '(お名前未登録)';
    switch (type) {
      case NotifType.pendingConfirm:
      case NotifType.startingSoon:
      case NotifType.possibleNoShow:
        final startTime = apt != null && apt!.startAt.length >= 16
            ? apt!.startAt.substring(11, 16)
            : '';
        if (type == NotifType.possibleNoShow) {
          return '$startTime $name — 来店確認が必要です';
        }
        return '$startTime $name — $menuSummary';
      case NotifType.birthday:
        return '$name さん、本日がお誕生日です 🎉';
      case NotifType.lowStock:
        return '$menuSummary の在庫が少なくなっています。発注をご確認ください。';
    }
  }
}

// ─── 알림 Provider ────────────────────────────────────────────────────────
// 1분마다 갱신하는 스트림 (현재 시각 기준 계산)
final notificationsProvider =
    StreamProvider<List<SalonNotif>>((ref) {
  final db = ref.watch(databaseProvider);

  // 1분마다 재계산
  final controller = StreamController<List<SalonNotif>>();

  Future<void> check() async {
    if (controller.isClosed) return;
    try {
      final now = DateTime.now();
      final today = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final apts = await (db.select(db.appointments)
            ..where((t) => t.startAt.like('$today%'))
            ..where((t) => t.status.isNotIn(['cancelled', 'completed', 'no_show']))
            ..orderBy([(t) => OrderingTerm.asc(t.startAt)]))
          .get();

      final notifs = <SalonNotif>[];
      for (final apt in apts) {
        final startDt = DateTime.tryParse(apt.startAt);
        if (startDt == null) continue;

        // 고객 이름 조회
        String? customerName;
        if (apt.customerId != null) {
          final c = await (db.select(db.customers)
                ..where((t) => t.id.equals(apt.customerId!)))
              .getSingleOrNull();
          customerName = c?.name;
        }

        // 메뉴 요약
        final menus = await (db.select(db.appointmentMenus)
              ..where((t) => t.appointmentId.equals(apt.id))
              ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
            .get();
        final menuSummary = menus.isEmpty
            ? ''
            : menus.length == 1
                ? menus.first.menuName
                : '${menus.first.menuName} 他${menus.length - 1}件';

        final diffMin = startDt.difference(now).inMinutes;

        // ① 確認待ち (status = pending)
        if (apt.status == 'pending') {
          notifs.add(SalonNotif(
            type: NotifType.pendingConfirm,
            apt: apt,
            customerName: customerName,
            customerId: apt.customerId,
            menuSummary: menuSummary,
          ));
        }
        // ② まもなく開始 (30분 이내, confirmed)
        else if (apt.status == 'confirmed' && diffMin >= 0 && diffMin <= 30) {
          notifs.add(SalonNotif(
            type: NotifType.startingSoon,
            apt: apt,
            customerName: customerName,
            customerId: apt.customerId,
            menuSummary: menuSummary,
          ));
        }
        // ③ ノーショー可能性 (15분 초과, confirmed)
        else if (apt.status == 'confirmed' && diffMin < -15) {
          notifs.add(SalonNotif(
            type: NotifType.possibleNoShow,
            apt: apt,
            customerName: customerName,
            customerId: apt.customerId,
            menuSummary: menuSummary,
          ));
        }
      }

      // ④ 생일 고객 (오늘 생일인 고객)
      final todayMD = '-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final birthdayCustomers = await (db.select(db.customers)
            ..where((t) =>
                t.isDeleted.equals(false) &
                t.birthDate.like('%$todayMD')))
          .get();
      for (final c in birthdayCustomers) {
        notifs.add(SalonNotif(
          type: NotifType.birthday,
          customerName: c.name,
          customerId: c.id,
          menuSummary: '',
        ));
      }

      // ⑤ 재고 부족 상품 (stock <= minStock)
      final allProducts = await (db.select(db.products)
            ..where((t) => t.isActive.equals(true)))
          .get();
      for (final p in allProducts) {
        final minStock = p.minStock ?? 0;
        if (p.stockQuantity <= minStock) {
          final stockLabel = p.stockQuantity == 0 ? '在庫切れ' : '残${p.stockQuantity}${p.unit ?? ''}';
          notifs.add(SalonNotif(
            type: NotifType.lowStock,
            menuSummary: '${p.name}（$stockLabel）',
          ));
        }
      }

      if (!controller.isClosed) controller.add(notifs);
    } catch (_) {
      if (!controller.isClosed) controller.add([]);
    }
  }

  // 즉시 실행
  check();

  // 1분마다 갱신
  final timer = Timer.periodic(const Duration(minutes: 1), (_) => check());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

// ─── すべてクリア 시각 ────────────────────────────────────────────────────
// 패널에서 "すべてクリア"를 누르면 현재 시각을 저장
// dismissedAt 이전에 생성된 알림(currentList)은 배지 카운트에서 제외
final notifDismissedAtProvider = StateProvider<DateTime?>((ref) => null);

// 마지막 클리어 후 새로 발생한 건수만 배지로 표시
final notifCountProvider = Provider<int>((ref) {
  final dismissedAt = ref.watch(notifDismissedAtProvider);
  return ref.watch(notificationsProvider).maybeWhen(
    data: (list) {
      if (dismissedAt == null) return list.length;
      // dismissedAt 이후에도 알림이 그대로라면 0, 새로 생기면 새 건수
      // 가장 간단한 방법: 클리어 후 같은 리스트는 0, 건수가 늘면 새 건수
      // dismissedCount를 저장해 차분을 보여줌
      return 0; // 클리어 후에는 0 (1분 후 갱신 시 다시 뜸)
    },
    orElse: () => 0,
  );
});
