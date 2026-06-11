import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../../features/notifications/providers/notification_provider.dart';
import '../../features/reports/providers/reports_provider.dart';

// ─── 탭 정의 ────────────────────────────────────────────────────────────────
class _TabItem {
  const _TabItem({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final String path;
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

const _tabs = [
  _TabItem(path: '/',          icon: Icons.point_of_sale_outlined,  activeIcon: Icons.point_of_sale,   label: '会計'),
  _TabItem(path: '/booking',   icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month,  label: '予約'),
  _TabItem(path: '/customers', icon: Icons.people_outline,           activeIcon: Icons.people,          label: '顧客'),
  _TabItem(path: '/reports',   icon: Icons.bar_chart_outlined,       activeIcon: Icons.bar_chart,       label: 'レポート'),
  _TabItem(path: '/settings',  icon: Icons.settings_outlined,        activeIcon: Icons.settings,        label: '設定'),
];

// ─── MainShell ────────────────────────────────────────────────────────────
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late Timer _clockTimer;
  DateTime _now = DateTime.now();

  // 가상 온라인/오프라인 상태 (추후 connectivity_plus 연동)
  final bool _isOnline = true;
  // 지점명 (추후 설정에서 편집 가능하게)
  static const _branchName = '渋谷店';

  static const _sidebarWidth = 230.0;
  static const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  int _currentIndex(String location) {
    for (int i = 0; i < _tabs.length; i++) {
      if (_tabs[i].path == location) return i;
    }
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (_tabs[i].path != '/' && location.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  String _timeStr() {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _dateStr() {
    return '${_now.month}/${_now.day}(${_weekdays[_now.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _currentIndex(location);
    final notifCount = ref.watch(notifCountProvider);
    final tab = _tabs[idx];
    final topPad = MediaQuery.of(context).padding.top;

    final canPop = context.canPop();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawerScrimColor: Colors.black.withAlpha(100),
      enableOpenDragGesture: false,
      drawer: Drawer(
        width: _sidebarWidth,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: _SidebarPanel(
          currentIndex: idx,
          notifCount: notifCount,
          topPad: topPad,
          onNavigate: (path) {
            Navigator.of(context).pop();
            context.go(path);
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Safe area
          SizedBox(height: topPad),
          // 글로벌 상단 바
          _GlobalTopBar(
            tab: tab,
            canPop: canPop,
            isOnline: _isOnline,
            branchName: _branchName,
            dateStr: _dateStr(),
            timeStr: _timeStr(),
            notifCount: notifCount,
            onHamburger: () => _scaffoldKey.currentState?.openDrawer(),
            onBack: canPop ? () => context.pop() : null,
          ),
          // 화면 본체
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

// ─── 글로벌 상단 바 ──────────────────────────────────────────────────────
class _GlobalTopBar extends ConsumerWidget {
  const _GlobalTopBar({
    required this.tab,
    required this.canPop,
    required this.isOnline,
    required this.branchName,
    required this.dateStr,
    required this.timeStr,
    required this.notifCount,
    required this.onHamburger,
    this.onBack,
  });

  final _TabItem tab;
  final bool canPop;
  final bool isOnline;
  final String branchName;
  final String dateStr;
  final String timeStr;
  final int notifCount;
  final VoidCallback onHamburger;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayRevenueProvider);

    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 뒤로가기 or 햄버거
          if (canPop)
            _IconBtn(
              icon: Icons.arrow_back,
              onTap: onBack!,
              size: 22,
            )
          else
            _IconBtn(
              icon: Icons.menu_rounded,
              onTap: onHamburger,
              size: 22,
            ),
          const SizedBox(width: 6),
          // 화면 아이콘 + 이름
          Icon(tab.activeIcon, size: 18, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            tab.label,
            style: AppTextStyles.h4.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),

          const Spacer(),

          // 온라인/오프라인 상태
          _OnlineStatusBadge(isOnline: isOnline),
          const SizedBox(width: 10),

          // 지점명
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.store_outlined, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  branchName,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // 날짜 + 시간
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: AppTextStyles.body2.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontSize: 15,
                ),
              ),
              Text(
                dateStr,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),

          // 오늘 매출 실시간 표시 (날짜 오른쪽 최우선)
          _TodayRevenueBadge(asyncValue: todayAsync),
          const SizedBox(width: 4),

          // 알림 벨
          _NotificationBtn(count: notifCount),

          // ⋮ 메뉴 버튼 (추후 기능 연결)
          _IconBtn(
            icon: Icons.more_vert_rounded,
            onTap: () {},
            size: 22,
          ),
        ],
      ),
    );
  }
}

// ─── 오늘 매출 배지 ──────────────────────────────────────────────────────
class _TodayRevenueBadge extends StatelessWidget {
  const _TodayRevenueBadge({required this.asyncValue});
  final AsyncValue<TodayRevenueSummary> asyncValue;

  String _fmt(int v) {
    // 천 단위 콤마
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '¥${buf.toString()}';
  }

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 6),
            Text(
              '読み込み中...',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (summary) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withAlpha(10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.today_outlined, size: 12, color: AppColors.primary),
            const SizedBox(width: 5),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmt(summary.revenue),
                  style: TextStyle(
                    fontFamily: 'NotoSansJP',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  '${summary.count}件',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 온라인/오프라인 배지 ─────────────────────────────────────────────────
class _OnlineStatusBadge extends StatelessWidget {
  const _OnlineStatusBadge({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppColors.success : AppColors.error;
    final bgColor = isOnline ? AppColors.successLight : AppColors.errorLight;
    final label = isOnline ? 'オンライン' : 'オフライン';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              fontFamily: 'NotoSansJP',
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 알림 버튼 ─────────────────────────────────────────────────────────────
class _NotificationBtn extends StatelessWidget {
  const _NotificationBtn({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const Icon(Icons.notifications_outlined, size: 22, color: AppColors.textSecondary),
          if (count > 0)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Color(0xFFF04452),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
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
}

// ─── 아이콘 버튼 ────────────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.size = 22});
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Icon(icon, size: size, color: AppColors.textSecondary),
      ),
    );
  }
}

// ─── 사이드바 패널 ────────────────────────────────────────────────────────
class _SidebarPanel extends StatelessWidget {
  const _SidebarPanel({
    required this.currentIndex,
    required this.notifCount,
    required this.topPad,
    required this.onNavigate,
    required this.onClose,
  });

  final int currentIndex;
  final int notifCount;
  final double topPad;
  final ValueChanged<String> onNavigate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 16,
            offset: Offset(4, 0),
          ),
        ],
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.content_cut, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Salon POS', style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w700)),
                      Text('v1.0.0', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontSize: 10)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            // 내비게이션 아이템
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: List.generate(_tabs.length, (i) {
                  final tab = _tabs[i];
                  final isActive = i == currentIndex;
                  final showBadge = i == 1 && notifCount > 0;

                  return _SidebarItem(
                    tab: tab,
                    isActive: isActive,
                    badge: showBadge ? notifCount : 0,
                    onTap: () => onNavigate(tab.path),
                  );
                }),
              ),
            ),

            // 하단 버전/정보
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
              ),
              child: Text(
                'Salon POS © 2026',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textDisabled,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 사이드바 아이템 ──────────────────────────────────────────────────────
class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.tab,
    required this.isActive,
    required this.badge,
    required this.onTap,
  });

  final _TabItem tab;
  final bool isActive;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withAlpha(15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // 액티브 인디케이터 바
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 3,
              height: isActive ? 24 : 0,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isActive ? tab.activeIcon : tab.icon,
              size: 20,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontFamily: 'NotoSansJP',
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  color: isActive ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF04452),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge > 9 ? '9+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
