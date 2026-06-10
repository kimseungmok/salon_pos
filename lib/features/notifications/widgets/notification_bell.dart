import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/notification_provider.dart';

// ─── 알림 벨 (배지 포함) ─────────────────────────────────────────────────
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(notifCountProvider);

    return GestureDetector(
      onTap: () => _showPanel(context),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined, size: 24),
          if (count > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Color(0xFFF04452),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (_) => const _NotificationPanel(),
    );
  }
}

// ─── 알림 패널 ────────────────────────────────────────────────────────────
class _NotificationPanel extends ConsumerStatefulWidget {
  const _NotificationPanel();

  @override
  ConsumerState<_NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends ConsumerState<_NotificationPanel> {
  @override
  void initState() {
    super.initState();
    // 패널을 열면 즉시 배지 카운트 클리어
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notifDismissedAtProvider.notifier).state = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifsAsync = ref.watch(notificationsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.notifications, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('通知', style: AppTextStyles.h3),
                  const Spacer(),
                  notifsAsync.maybeWhen(
                    data: (list) => list.isNotEmpty
                        ? Text(
                            '${list.length}件',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          )
                        : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  // すべてクリア ボタン
                  notifsAsync.maybeWhen(
                    data: (list) => list.isNotEmpty
                        ? TextButton(
                            onPressed: () {
                              ref.read(notifDismissedAtProvider.notifier).state =
                                  DateTime.now();
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'すべてクリア',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 알림 리스트
            Expanded(
              child: notifsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('エラー: $e')),
                data: (list) => list.isEmpty
                    ? const _EmptyNotif()
                    : ListView.separated(
                        controller: scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 56),
                        itemBuilder: (_, i) => _NotifTile(notif: list[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 알림 타일 ────────────────────────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.notif});
  final SalonNotif notif;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (notif.type) {
      NotifType.pendingConfirm => (const Color(0xFFFFB300), Icons.hourglass_empty),
      NotifType.startingSoon   => (const Color(0xFF0064FF), Icons.schedule),
      NotifType.possibleNoShow => (const Color(0xFFF04452), Icons.person_off_outlined),
      NotifType.birthday       => (const Color(0xFFFF4E8C), Icons.cake_outlined),
      NotifType.lowStock       => (const Color(0xFFFF6B00), Icons.inventory_2_outlined),
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        notif.title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      subtitle: Text(
        notif.body,
        style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
      onTap: () {
        Navigator.of(context).pop();
        if (notif.type == NotifType.birthday && notif.customerId != null) {
          context.push('${AppRoutes.customers}/${notif.customerId}');
        } else if (notif.type == NotifType.lowStock) {
          context.go(AppRoutes.settingsInventory);
        } else {
          context.go(AppRoutes.booking);
        }
      },
    );
  }
}

// ─── 빈 상태 ──────────────────────────────────────────────────────────────
class _EmptyNotif extends StatelessWidget {
  const _EmptyNotif();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_off_outlined, size: 48, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Text(
            '通知はありません',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
