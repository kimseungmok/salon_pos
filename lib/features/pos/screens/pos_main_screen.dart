import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../../customer/screens/customer_search_sheet.dart';
import '../../reports/providers/reports_provider.dart';
import '../providers/pos_provider.dart';
import 'open_register_screen.dart';
import 'payment_screen.dart';

// ─── POS 메인 화면 ────────────────────────────────────────────────────────
class PosMainScreen extends ConsumerStatefulWidget {
  const PosMainScreen({super.key});

  @override
  ConsumerState<PosMainScreen> createState() => _PosMainScreenState();
}

class _PosMainScreenState extends ConsumerState<PosMainScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(posProvider.notifier).loadDraft();
      _restoreLastStaff();
    });
  }

  Future<void> _restoreLastStaff() async {
    // 마지막 담당자를 불러와서 현재 선택이 없으면 자동 적용
    final lastStaffId = await ref.read(lastStaffProvider.future);
    if (!mounted || lastStaffId == null) return;
    final currentStaffId = ref.read(posProvider).selectedStaffId;
    if (currentStaffId == null) {
      ref.read(posProvider.notifier).setStaff(lastStaffId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(activeSessionProvider);
    return sessionAsync.when(
      data: (session) => session == null
          ? const _NoSessionView()
          : _PosBody(session: session),
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('エラー: $e'))),
    );
  }
}

// ─── 개점 전 화면 ─────────────────────────────────────────────────────────
class _NoSessionView extends StatelessWidget {
  const _NoSessionView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.store_outlined,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text('レジを開いてください', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            Text('営業を開始するには開店処理が必要です',
                style: AppTextStyles.body2
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 32),
            SizedBox(
              width: 220,
              child: ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.openRegister),
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('開店する'),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(220, 52)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── POS 바디 ────────────────────────────────────────────────────────────
class _PosBody extends ConsumerWidget {
  const _PosBody({required this.session});
  final RegisterSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CallbackShortcuts(
        bindings: {
          // F1: カートリセット
          const SingleActivator(LogicalKeyboardKey.f1): () {
            ref.read(posProvider.notifier).clear();
          },
          // F9: お会計（カートに商品があれば）
          const SingleActivator(LogicalKeyboardKey.f9): () {
            final state = ref.read(posProvider);
            if (state.items.isNotEmpty) {
              _goCheckout(context, session);
            }
          },
          // Escape: カート内容リセット確認
          const SingleActivator(LogicalKeyboardKey.escape): () {
            final state = ref.read(posProvider);
            if (state.items.isNotEmpty) {
              ref.read(posProvider.notifier).clear();
            }
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 메뉴 패널 (좌측)
                    Expanded(flex: 3, child: _MenuPanel()),
                    // 구분선
                    const VerticalDivider(width: 1, color: AppColors.border),
                    // 주문 패널 (우측 고정 340px)
                    SizedBox(width: 340, child: _OrderPanel(session: session)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _goCheckout(BuildContext context, RegisterSession session) {
    // checkout 버튼과 동일한 동작 — 화면 이동은 OrderPanel에서 처리하므로 스낵바만 표시
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('F9: お会計はカートのお会計ボタンをタップしてください'),
          duration: Duration(seconds: 2)),
    );
  }
}

// ─── AppBar ───────────────────────────────────────────────────────────────
class _PosAppBar extends ConsumerWidget {
  const _PosAppBar({required this.session});
  final RegisterSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final weekDays = ['月', '火', '水', '木', '金', '土', '日'];
    final dayStr =
        '${now.month}月${now.day}日(${weekDays[now.weekday - 1]})';

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.store_outlined, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(dayStr,
              style: AppTextStyles.body2
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          // 영업중 뱃지
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('営業中',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  void _showCashManagement(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(width: 460, height: 520, child: _CashManagementSheet(sessionId: session.id)),
      ),
    );
  }

  void _showCloseRegister(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(width: 460, height: 520, child: CloseRegisterSheet(session: session)),
      ),
    );
  }
}

class _AppBarBtn extends StatelessWidget {
  const _AppBarBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.label.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

// ─── 메뉴 패널 ────────────────────────────────────────────────────────────
class _MenuPanel extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends ConsumerState<_MenuPanel>
    with TickerProviderStateMixin {
  late TabController _tabCtrl;
  int _tabLen = 1;
  bool _editMode = false;
  GlobalKey<_EditModeGridState> _editGridKey = GlobalKey<_EditModeGridState>();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 1, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_editMode && !_tabCtrl.indexIsChanging) {
      setState(() => _editMode = false);
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _rebuildTabs(int catCount) {
    final newLen = 2 + catCount + 2; // よく使う + 売上ランキング + カテゴリ + セット + 物販
    if (newLen == _tabLen) return;
    _tabLen = newLen;
    final old = _tabCtrl;
    old.removeListener(_onTabChanged);
    _tabCtrl = TabController(length: newLen, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    old.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final catsAsync = ref.watch(menuCategoriesProvider);

    return catsAsync.when(
      data: (cats) {
        final newLen = 2 + cats.length + 2; // よく使う + 売上ランキング + カテゴリ + セット + 物販

        // TabController 길이 불일치 시 즉시 재생성 스케줄
        if (_tabCtrl.length != newLen) {
          Future.microtask(() => _rebuildTabs(cats.length));
          return const Center(child: CircularProgressIndicator());
        }

        final tabs = <Widget>[
          const Tab(
            height: 52,
            child: Icon(Icons.star_rounded, size: 22, color: AppColors.warning),
          ),
          const Tab(
            height: 52,
            child: Icon(Icons.bar_chart_rounded, size: 22, color: Color(0xFF6366F1)),
          ),
          ...cats.map((c) => Tab(height: 52, text: c.name)),
          const Tab(
            height: 52,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.view_module_outlined, size: 17, color: Color(0xFF10B981)),
                SizedBox(width: 5),
                Text('セット'),
              ],
            ),
          ),
          const Tab(
            height: 52,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shopping_bag_outlined, size: 17, color: AppColors.textSecondary),
                SizedBox(width: 5),
                Text('物販'),
              ],
            ),
          ),
        ];

        return Column(
          children: [
            // 탭바 + 검색
            Container(
              color: AppColors.surface,
              child: Row(
                children: [
                  Expanded(
                    child: TabBar(
                      controller: _tabCtrl,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: tabs,
                      labelStyle: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 14),
                      unselectedLabelStyle: AppTextStyles.label.copyWith(
                          fontSize: 14, fontWeight: FontWeight.w500),
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorWeight: 3,
                      indicatorColor: AppColors.primary,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 22),
                      splashBorderRadius: BorderRadius.circular(10),
                      overlayColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.pressed)) {
                          return AppColors.primary.withAlpha(30);
                        }
                        return AppColors.primary.withAlpha(12);
                      }),
                    ),
                  ),
                  // < > 화살표 탭 이동
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22,
                        color: AppColors.textSecondary),
                    tooltip: '前のタブ',
                    onPressed: () {
                      final idx = _tabCtrl.index;
                      if (idx > 0) _tabCtrl.animateTo(idx - 1);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22,
                        color: AppColors.textSecondary),
                    tooltip: '次のタブ',
                    onPressed: () {
                      final idx = _tabCtrl.index;
                      if (idx < _tabCtrl.length - 1) _tabCtrl.animateTo(idx + 1);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, size: 22,
                        color: AppColors.textSecondary),
                    tooltip: 'メニュー検索',
                    onPressed: () => _showMenuSearch(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 탭 콘텐츠
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _FavoritesGrid(editMode: _editMode),
                  _RankingGrid(),
                  ...cats.map((c) => _MenuGrid(categoryId: c.id, editMode: _editMode, editGridKey: _editGridKey)),
                  _BundleGrid(),
                  _ProductGrid(),
                ],
              ),
            ),
            // 하단 바: 편집모드 + 상품추가
            _MenuPanelBottomBar(
              editMode: _editMode,
              onToggleEdit: () => setState(() => _editMode = !_editMode),
              onAddMenu: () => context.push(AppRoutes.settingsMenus),
              onCancelEdit: () async {
                await _editGridKey.currentState?.revertAll();
                if (mounted) setState(() => _editMode = false);
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('$e', style: AppTextStyles.caption)),
    );
  }

  void _showMenuSearch(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _MenuSearchDialog(),
    );
  }
}

// ─── 메뉴 패널 하단 바 ────────────────────────────────────────────────────
class _MenuPanelBottomBar extends StatelessWidget {
  const _MenuPanelBottomBar({
    required this.editMode,
    required this.onToggleEdit,
    required this.onAddMenu,
    required this.onCancelEdit,
  });
  final bool editMode;
  final VoidCallback onToggleEdit;
  final VoidCallback onAddMenu;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (editMode) ...[
            InkWell(
              onTap: onCancelEdit,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('キャンセル',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 20, color: AppColors.border),
          ],
          // 編集モード / 完了
          InkWell(
            onTap: onToggleEdit,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    editMode ? Icons.check_circle_outline : Icons.edit_outlined,
                    size: 16,
                    color: editMode ? AppColors.primary : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    editMode ? '完了' : '編集モード',
                    style: AppTextStyles.caption.copyWith(
                      color: editMode ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: editMode ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!editMode) ...[
            Container(width: 1, height: 20, color: AppColors.border),
            // 商品追加
            InkWell(
              onTap: onAddMenu,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_circle_outline,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text('商品追加',
                        style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 메뉴 패널 하단 바 ────────────────────────────────────────────────────

// ─── セットメニューグリッド ────────────────────────────────────────────────
class _BundleGrid extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BundleGrid> createState() => _BundleGridState();
}

class _BundleGridState extends ConsumerState<_BundleGrid> {
  late Future<List<MenuBundle>> _bundlesFuture;

  @override
  void initState() {
    super.initState();
    final db = ref.read(databaseProvider);
    _bundlesFuture = (db.select(db.menuBundles)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MenuBundle>>(
      future: _bundlesFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final bundles = snap.data ?? [];
        if (bundles.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.view_module_outlined,
                    size: 48, color: AppColors.textDisabled),
                const SizedBox(height: 12),
                Text('登録済みセットメニューがありません',
                    style: AppTextStyles.body2
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 110,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: bundles.length,
            itemBuilder: (_, i) => _BundleCard(bundle: bundles[i]),
          ),
        );
      },
    );
  }
}

class _BundleCard extends ConsumerStatefulWidget {
  const _BundleCard({required this.bundle});
  final MenuBundle bundle;

  @override
  ConsumerState<_BundleCard> createState() => _BundleCardState();
}

class _BundleCardState extends ConsumerState<_BundleCard> {
  late Future<List<MenusData>> _menusFuture;

  @override
  void initState() {
    super.initState();
    _menusFuture = _loadMenus();
  }

  Future<List<MenusData>> _loadMenus() async {
    final db = ref.read(databaseProvider);
    final items = await (db.select(db.menuBundleItems)
          ..where((t) => t.bundleId.equals(widget.bundle.id)))
        .get();
    if (items.isEmpty) return [];
    return (db.select(db.menus)
          ..where((t) => t.id.isIn(items.map((b) => b.menuId).toList())))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    final qty = ref.watch(posProvider.select((s) => s.items
        .where((i) => i.refId == widget.bundle.id && i.itemType == 'bundle')
        .fold(0, (sum, i) => sum + i.qty)));

    return FutureBuilder<List<MenusData>>(
      future: _menusFuture,
      builder: (context, menuSnap) {
        final menus = menuSnap.data ?? [];
        final price = (widget.bundle.bundlePrice ?? 0) > 0
            ? widget.bundle.bundlePrice!
            : menus.fold<int>(0, (sum, m) => sum + m.price);
        final finalPrice = widget.bundle.discountRate > 0
            ? (price * (1 - widget.bundle.discountRate / 100)).round()
            : price;

        return GestureDetector(
              onTap: () {
                ref.read(posProvider.notifier).addBundle(widget.bundle, menus);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${widget.bundle.name} をカートに追加'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: qty > 0
                          ? const Color(0xFF10B981).withAlpha(20)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: qty > 0
                            ? const Color(0xFF10B981)
                            : AppColors.border,
                        width: qty > 0 ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.view_module_outlined,
                                size: 14, color: Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            if (widget.bundle.discountRate > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${widget.bundle.discountRate.toStringAsFixed(0)}%OFF',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.bundle.name,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          '¥${_fmtPrice(finalPrice)}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981)),
                        ),
                      ],
                    ),
                  ),
                  if (qty > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text('$qty',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                ],
              ),
            );
      },
    );
  }

  String _fmtPrice(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─── 즐겨찾기 그리드 ──────────────────────────────────────────────────────
// ─── 物販グリッド ─────────────────────────────────────────────────────────
class _ProductGrid extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProductGrid> createState() => _ProductGridState();
}

class _ProductGridState extends ConsumerState<_ProductGrid> {
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    final db = ref.read(databaseProvider);
    _productsFuture = (db.select(db.products)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _productsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snap.data ?? [];
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 48, color: AppColors.textDisabled),
                const SizedBox(height: 12),
                Text('登録済み商品がありません',
                    style: AppTextStyles.body2
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return Scrollbar(
          thumbVisibility: true,
          trackVisibility: true,
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisExtent: 90,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: products.length,
            itemBuilder: (_, i) => _ProductCard(product: products[i]),
          ),
        );
      },
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = product.retailPrice > 0
        ? product.retailPrice
        : product.costPrice;
    final cartQty = ref.watch(posProvider.select((s) => s.items
        .where((i) => i.refId == product.id && i.itemType == 'product')
        .fold(0, (sum, i) => sum + i.qty)));
    final isOutOfStock = product.stockQuantity <= 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: isOutOfStock
              ? AppColors.background
              : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: isOutOfStock
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    ref.read(posProvider.notifier).addProduct(product);
                  },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isOutOfStock
                      ? AppColors.border
                      : const Color(0xFF8B5CF6).withOpacity(0.35),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md - 1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                        width: 4,
                        color: isOutOfStock
                            ? AppColors.border
                            : const Color(0xFF8B5CF6)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                style: TextStyle(
                                  fontFamily: 'NotoSansJP',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isOutOfStock
                                      ? AppColors.textDisabled
                                      : const Color(0xFF8B5CF6)
                                          .withOpacity(0.85),
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '¥${_fmt(price)}',
                                  style: TextStyle(
                                    fontFamily: 'NotoSansJP',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isOutOfStock
                                        ? AppColors.textDisabled
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  isOutOfStock
                                      ? '在庫切れ'
                                      : '残${product.stockQuantity}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isOutOfStock
                                        ? AppColors.error
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // 카트 뱃지
        if (cartQty > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFF8B5CF6),
                shape: BoxShape.circle,
              ),
              constraints:
                  const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                '$cartQty',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── 즐겨찾기 그리드 ──────────────────────────────────────────────────────
class _FavoritesGrid extends ConsumerWidget {
  const _FavoritesGrid({required this.editMode});
  final bool editMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(favoritesMenusProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('エラー: $e')),
      data: (menus) {
        if (menus.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star_border,
                    size: 48, color: AppColors.textDisabled),
                const SizedBox(height: 12),
                Text('お気に入りがありません',
                    style: AppTextStyles.body2
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('編集モードで★をタップするとここに表示されます',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textDisabled)),
              ],
            ),
          );
        }
        return _MenuGridView(menus: menus, editMode: editMode);
      },
    );
  }
}

// ─── 売上ランキング ────────────────────────────────────────────────────────
class _RankingGrid extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RankingGrid> createState() => _RankingGridState();
}

class _RankingGridState extends ConsumerState<_RankingGrid> {
  late Future<List<MenusData>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(databaseProvider).getFrequentMenus();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MenusData>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final menus = snap.data ?? [];
        if (menus.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bar_chart_rounded,
                    size: 48, color: AppColors.textDisabled),
                const SizedBox(height: 12),
                Text('まだ売上データがありません',
                    style: AppTextStyles.body2
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text('会計を重ねると、よく使うメニューが\nここに表示されます',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textDisabled)),
              ],
            ),
          );
        }
        return _MenuGridView(menus: menus, editMode: false);
      },
    );
  }
}

// ─── 카테고리별 메뉴 그리드 ───────────────────────────────────────────────
class _MenuGrid extends ConsumerWidget {
  const _MenuGrid({required this.categoryId, required this.editMode, this.editGridKey});
  final String categoryId;
  final bool editMode;
  final GlobalKey<_EditModeGridState>? editGridKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menusAsync = editMode
        ? ref.watch(menusByCategoryAllProvider(categoryId))
        : ref.watch(menusByCategoryProvider(categoryId));
    return menusAsync.when(
      data: (menus) => _MenuGridView(menus: menus, editMode: editMode, editGridKey: editGridKey),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          Center(child: Text('$e', style: AppTextStyles.caption)),
    );
  }
}

// ─── 페이지네이션 그리드 뷰 ──────────────────────────────────────────────
const int _kCols = 5;
const int _kRows = 2;
const int _kPerPage = _kCols * _kRows;
const double _kCardW = 152.0;
const double _kCardH = 90.0;
const double _kSpacing = 8.0;

class _MenuGridView extends ConsumerStatefulWidget {
  const _MenuGridView({required this.menus, required this.editMode, this.editGridKey});
  final List<MenusData> menus;
  final bool editMode;
  final GlobalKey<_EditModeGridState>? editGridKey;

  @override
  ConsumerState<_MenuGridView> createState() => _MenuGridViewState();
}

class _MenuGridViewState extends ConsumerState<_MenuGridView> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_MenuGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editMode && !widget.editMode && _pageCtrl.hasClients) {
      _pageCtrl.jumpToPage(0);
      setState(() => _currentPage = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menus = widget.menus;
    if (menus.isEmpty) {
      return Center(child: Text('メニューがありません', style: AppTextStyles.caption));
    }

    if (widget.editMode) {
      return _EditModeGrid(key: widget.editGridKey, menus: menus, readOnly: false);
    }

    // 일반 모드: 슬롯 기반 페이지네이션
    return _EditModeGrid(menus: menus, readOnly: true);
  }
}

class _PageNav extends StatelessWidget {
  const _PageNav({
    required this.current,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });
  final int current;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            color: onPrev != null ? AppColors.textPrimary : AppColors.textDisabled,
            onPressed: onPrev,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          Text(
            '${current + 1} / $total',
            style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            color: onNext != null ? AppColors.textPrimary : AppColors.textDisabled,
            onPressed: onNext,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ─── 편집모드: 자유 배치 그리드 (빈 셀 허용) ────────────────────────────────
class _EditModeGrid extends ConsumerStatefulWidget {
  const _EditModeGrid({super.key, required this.menus, this.readOnly = false});
  final List<MenusData> menus;
  final bool readOnly;

  @override
  ConsumerState<_EditModeGrid> createState() => _EditModeGridState();
}

class _EditModeGridState extends ConsumerState<_EditModeGrid> {
  late Map<String, int> _slotMap;
  late Map<String, int> _originalSlotMap;
  int? _draggingMenuSlot;
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _slotMap = _buildSlotMap(widget.menus);
    _originalSlotMap = Map.from(_slotMap);
  }

  Future<void> revertAll() async {
    final db = ref.read(databaseProvider);
    for (final entry in _originalSlotMap.entries) {
      await (db.update(db.menus)..where((t) => t.id.equals(entry.key)))
          .write(MenusCompanion(posSlot: Value(entry.value)));
    }
    if (mounted) setState(() => _slotMap = Map.from(_originalSlotMap));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_EditModeGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.menus != widget.menus) {
      // 새 메뉴는 posSlot 반영, 기존 슬롯 맵 유지
      final newMap = _buildSlotMap(widget.menus);
      _slotMap = newMap;
    }
  }

  Map<String, int> _buildSlotMap(List<MenusData> menus) {
    final map = <String, int>{};
    final occupied = <int>{};

    // posSlot 이 있는 항목 먼저 배치
    for (final m in menus) {
      if (m.posSlot != null) {
        map[m.id] = m.posSlot!;
        occupied.add(m.posSlot!);
      }
    }
    // posSlot 없는 항목 자동 배치 (빈 슬롯 순서대로)
    int auto = 0;
    for (final m in menus) {
      if (m.posSlot == null) {
        while (occupied.contains(auto)) auto++;
        map[m.id] = auto;
        occupied.add(auto);
        auto++;
      }
    }
    return map;
  }

  int get _totalSlots {
    if (_slotMap.isEmpty) return _kCols;
    final maxSlot = _slotMap.values.reduce((a, b) => a > b ? a : b);
    // 최소 2행, 마지막 행 다음 빈 행 1개 추가
    final rows = (maxSlot / _kCols).floor() + 2;
    return rows * _kCols;
  }

  MenusData? _menuAtSlot(int slot) {
    final id = _slotMap.entries
        .where((e) => e.value == slot)
        .map((e) => e.key)
        .firstOrNull;
    if (id == null) return null;
    return widget.menus.firstWhere((m) => m.id == id);
  }

  Future<void> _moveToSlot(String menuId, int newSlot) async {
    // 목적지에 다른 아이템이 있으면 swap
    final existingId = _slotMap.entries
        .where((e) => e.value == newSlot)
        .map((e) => e.key)
        .firstOrNull;

    setState(() {
      if (existingId != null) {
        _slotMap[existingId] = _slotMap[menuId]!;
      }
      _slotMap[menuId] = newSlot;
      _draggingMenuSlot = null;
    });

    // DB 저장
    final db = ref.read(databaseProvider);
    await (db.update(db.menus)..where((t) => t.id.equals(menuId)))
        .write(MenusCompanion(posSlot: Value(newSlot)));
    if (existingId != null) {
      final swapSlot = _slotMap[menuId]!;
      // swap 후엔 이미 setState로 변경됐으므로 현재 _slotMap[existingId] 사용
      // (위 setState 에서 existingId → oldSlot 으로 이미 변경됨)
      final oldSlot = _slotMap[existingId]!;
      await (db.update(db.menus)..where((t) => t.id.equals(existingId)))
          .write(MenusCompanion(posSlot: Value(oldSlot)));
    }
  }

  Future<void> _toggleVisibility(MenusData menu) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.menus)..where((t) => t.id.equals(menu.id)))
        .write(MenusCompanion(isActive: Value(!menu.isActive)));
  }

  Future<void> _toggleFavorite(MenusData menu) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.menus)..where((t) => t.id.equals(menu.id)))
        .write(MenusCompanion(isFavorite: Value(!menu.isFavorite)));
  }

  @override
  Widget build(BuildContext context) {
    final totalSlots = _totalSlots;
    final rows = (totalSlots / _kCols).ceil();
    final readOnly = widget.readOnly;

    // readOnly(일반 모드) 일 때는 페이지 단위로 보여줌 (< N/M > 네비게이터 포함)
    if (readOnly) {
      final pageCount = (rows / _kRows).ceil().clamp(1, 999);
      return Column(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (ctx, constraints) {
              final cardW = (constraints.maxWidth - 20 - (_kCols - 1) * _kSpacing) / _kCols;
              return PageView.builder(
                controller: _pageCtrl,
                onPageChanged: (p) => setState(() => _currentPage = p),
                itemCount: pageCount,
                itemBuilder: (_, page) {
                  final rowStart = page * _kRows;
                  final rowEnd = (rowStart + _kRows).clamp(0, rows);
                  return Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: List.generate(rowEnd - rowStart, (ri) {
                        final row = rowStart + ri;
                        return Padding(
                          padding: EdgeInsets.only(bottom: ri < rowEnd - rowStart - 1 ? _kSpacing : 0),
                          child: Row(
                            children: List.generate(_kCols, (col) {
                              final slot = row * _kCols + col;
                              final menu = _menuAtSlot(slot);
                              return Padding(
                                padding: EdgeInsets.only(right: col < _kCols - 1 ? _kSpacing : 0),
                                child: SizedBox(
                                  width: cardW,
                                  height: _kCardH,
                                  child: menu != null ? _MenuCard(menu: menu) : const SizedBox(),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ),
                  );
                },
              );
            }),
          ),
          _PageNav(
            current: _currentPage,
            total: pageCount,
            onPrev: _currentPage > 0
                ? () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeInOut)
                : null,
            onNext: _currentPage < pageCount - 1
                ? () => _pageCtrl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeInOut)
                : null,
          ),
        ],
      );
    }

    // 편집 모드
    return Container(
      color: AppColors.background,
      child: LayoutBuilder(builder: (context, constraints) {
        final cardW = (constraints.maxWidth - 20 - (_kCols - 1) * _kSpacing) / _kCols;
        return SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: List.generate(rows, (row) {
            return Padding(
              padding: const EdgeInsets.only(bottom: _kSpacing),
              child: Row(
                children: List.generate(_kCols, (col) {
                  final slot = row * _kCols + col;
                  final menu = _menuAtSlot(slot);
                  return Padding(
                    padding: EdgeInsets.only(right: col < _kCols - 1 ? _kSpacing : 0),
                    child: SizedBox(
                      width: cardW,
                      height: _kCardH,
                      child: menu != null
                          ? _EditCard(
                              key: ValueKey(menu.id),
                              menu: menu,
                              slot: slot,
                              onMoveToSlot: _moveToSlot,
                              onDragStart: () => setState(() => _draggingMenuSlot = slot),
                              onDragEnd: () => setState(() => _draggingMenuSlot = null),
                              onToggleVisibility: () => _toggleVisibility(menu),
                              onToggleFavorite: () => _toggleFavorite(menu),
                            )
                          : _EmptySlot(
                              slot: slot,
                              isDragOver: false,
                              onAccept: (menuId) => _moveToSlot(menuId, slot),
                            ),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
        );
      }),
    );
  }
}

// ─── 편집모드 카드 ─────────────────────────────────────────────────────────
class _EditCard extends StatelessWidget {
  const _EditCard({
    super.key,
    required this.menu,
    required this.slot,
    required this.onMoveToSlot,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onToggleVisibility,
    required this.onToggleFavorite,
  });
  final MenusData menu;
  final int slot;
  final Future<void> Function(String menuId, int slot) onMoveToSlot;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onToggleVisibility;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(menu.color) ?? AppColors.primary;
    final isHidden = !menu.isActive;
    final isFav = menu.isFavorite;

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != menu.id,
      onAcceptWithDetails: (d) => onMoveToSlot(d.data, slot),
      builder: (context, candidateData, _) {
        final isOver = candidateData.isNotEmpty;
        return LongPressDraggable<String>(
          data: menu.id,
          delay: const Duration(milliseconds: 180),
          onDragStarted: onDragStart,
          onDraggableCanceled: (_, __) => onDragEnd(),
          onDragCompleted: onDragEnd,
          feedback: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: _kCardW,
              height: _kCardH,
              child: _buildContent(color, isHidden, isFav, opacity: 0.95),
            ),
          ),
          childWhenDragging: Container(
            decoration: BoxDecoration(
              color: AppColors.border.withAlpha(80),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: AppColors.border, width: 1.5,
                  style: BorderStyle.solid),
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: isOver
                  ? Border.all(color: AppColors.primary, width: 2.5)
                  : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildContent(color, isHidden, isFav,
                    opacity: isHidden ? 0.45 : 1.0),
                // 비표시 토글 (우상단)
                Positioned(
                  top: 3,
                  right: 3,
                  child: _EditIconBtn(
                    icon: isHidden ? Icons.visibility_off : Icons.visibility,
                    color: isHidden ? AppColors.textDisabled : AppColors.primary,
                    onTap: onToggleVisibility,
                  ),
                ),
                // 즐겨찾기 토글 (우하단)
                Positioned(
                  bottom: 3,
                  right: 3,
                  child: _EditIconBtn(
                    icon: isFav ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isFav ? AppColors.warning : AppColors.textDisabled,
                    onTap: onToggleFavorite,
                  ),
                ),
                // 드래그 핸들 표시 (좌상단)
                Positioned(
                  top: 4,
                  left: 6,
                  child: Icon(Icons.drag_indicator,
                      size: 14, color: color.withAlpha(140)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(Color color, bool isHidden, bool isFav,
      {required double opacity}) {
    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: isHidden
                    ? AppColors.border
                    : color.withAlpha(80),
                width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md - 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    width: 4,
                    color: isHidden ? AppColors.border : color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 28, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            menu.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isHidden
                                  ? AppColors.textDisabled
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '¥${_fmt(menu.price)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isHidden ? AppColors.textDisabled : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditIconBtn extends StatelessWidget {
  const _EditIconBtn(
      {required this.icon, required this.color, required this.onTap});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(230),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(25), blurRadius: 4, offset: const Offset(0, 1))
          ],
        ),
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}

// ─── 빈 슬롯 (드롭 타겟) ────────────────────────────────────────────────────
class _EmptySlot extends StatelessWidget {
  const _EmptySlot(
      {required this.slot, required this.isDragOver, required this.onAccept});
  final int slot;
  final bool isDragOver;
  final void Function(String menuId) onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidateData, _) {
        final over = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: over
                ? AppColors.primary.withAlpha(18)
                : AppColors.border.withAlpha(40),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: over ? AppColors.primary : AppColors.border,
              width: over ? 2 : 1,
              style: BorderStyle.solid,
            ),
          ),
        );
      },
    );
  }
}

// ─── 메뉴 카드 (흰색 배경 + 카테고리 컬러 액센트) ──────────────────────────
class _MenuCard extends ConsumerWidget {
  const _MenuCard({required this.menu});
  final MenusData menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _parseColor(menu.color) ?? AppColors.primary;
    // 카트 내 이 메뉴의 수량
    final cartQty = ref.watch(posProvider.select((s) => s.items
        .where((i) => i.refId == menu.id && i.itemType == 'menu')
        .fold(0, (sum, i) => sum + i.qty)));

    return Stack(
      clipBehavior: Clip.none,
      children: [
    Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        splashColor: color.withOpacity(0.12),
        highlightColor: color.withOpacity(0.06),
        onTap: () {
          HapticFeedback.selectionClick();
          ref.read(posProvider.notifier).addMenu(menu);
        },
        onLongPress: () => _showMenuDetail(context, menu),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: color.withOpacity(0.35), width: 1.2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md - 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 컬러 바
                Container(width: 4, color: color),
                // 카드 콘텐츠
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            menu.name,
                            style: TextStyle(
                              fontFamily: 'NotoSansJP',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: color.withOpacity(0.85),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '¥${_fmt(menu.price)}',
                              style: const TextStyle(
                                fontFamily: 'NotoSansJP',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${menu.durationMin}分',
                              style: const TextStyle(
                                fontFamily: 'NotoSansJP',
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
        // 카트 수량 배지
        if (cartQty > 0)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$cartQty',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showMenuDetail(BuildContext context, MenusData menu) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(width: 400, child: _MenuDetailSheet(menu: menu)),
      ),
    );
  }
}

// ─── 메뉴 상세 시트 ───────────────────────────────────────────────────────
class _MenuDetailSheet extends ConsumerWidget {
  const _MenuDetailSheet({required this.menu});
  final MenusData menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(menu.name, style: AppTextStyles.h4),
          if (menu.description != null) ...[
            const SizedBox(height: 6),
            Text(menu.description!,
                style: AppTextStyles.body2
                    .copyWith(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: '料金', value: '¥${_fmt(menu.price)}'),
              _InfoChip(label: '施術', value: '${menu.durationMin}分'),
              _InfoChip(label: '消費税', value: '${menu.taxType}%'),
              if (menu.processingMin > 0)
                _InfoChip(
                  label: '発色待機',
                  value: '${menu.processingMin}分',
                  color: AppColors.statusProcessing,
                ),
              if (menu.bufferMin > 0)
                _InfoChip(
                    label: 'バッファ', value: '${menu.bufferMin}分'),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              ref.read(posProvider.notifier).addMenu(menu);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('会計に追加'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(
      {required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color?.withOpacity(0.12) ?? AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color ?? AppColors.border),
      ),
      child: Column(
        children: [
          Text(label,
              style: AppTextStyles.caption.copyWith(fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: AppTextStyles.label.copyWith(
                  color: color ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── 주문 패널 ────────────────────────────────────────────────────────────
class _OrderPanel extends ConsumerWidget {
  const _OrderPanel({required this.session});
  final RegisterSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(posProvider);
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // 주문 아이템
          Expanded(child: _OrderItemList(items: state.items)),
          const Divider(height: 1),
          // 금액 요약
          _AmountSummary(state: state),
          const Divider(height: 1),
          // 액션 + 결제 버튼
          _OrderActions(state: state, session: session),
        ],
      ),
    );
  }
}

// ─── 고객 선택 행 ──────────────────────────────────────────────────────────
class _CustomerRow extends ConsumerStatefulWidget {
  const _CustomerRow(
      {required this.customerId, required this.customerName});
  final String? customerId;
  final String? customerName;

  @override
  ConsumerState<_CustomerRow> createState() => _CustomerRowState();
}

class _CustomerRowState extends ConsumerState<_CustomerRow> {
  Future<Customer?>? _customerFuture;
  String? _loadedId;

  void _maybeReload() {
    if (widget.customerId != _loadedId) {
      _loadedId = widget.customerId;
      if (widget.customerId == null) {
        _customerFuture = null;
      } else {
        final db = ref.read(databaseProvider);
        _customerFuture = (db.select(db.customers)
              ..where((t) => t.id.equals(widget.customerId!)))
            .getSingleOrNull();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeReload();
  }

  @override
  void didUpdateWidget(_CustomerRow old) {
    super.didUpdateWidget(old);
    _maybeReload();
  }

  @override
  Widget build(BuildContext context) {
    final customerId = widget.customerId;
    final customerName = widget.customerName;

    return InkWell(
      onTap: () => _selectCustomer(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: customerId != null
                  ? AppColors.primaryLight
                  : AppColors.background,
              child: Icon(
                customerId != null
                    ? Icons.person
                    : Icons.person_add_outlined,
                size: 16,
                color: customerId != null
                    ? AppColors.primary
                    : AppColors.textDisabled,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: customerId != null
                  ? GestureDetector(
                      onLongPress: () =>
                          context.push('${AppRoutes.customers}/$customerId'),
                      child: FutureBuilder<Customer?>(
                      future: _customerFuture,
                      builder: (_, snap) {
                        final cust = snap.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  customerName ?? '',
                                  style: AppTextStyles.body2
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (cust?.cautionFlag == true || cust?.allergies != null) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.warning_amber_rounded,
                                      size: 13, color: AppColors.error),
                                ],
                                if (cust?.isVip == true) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningLight,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text('VIP',
                                        style: AppTextStyles.caption.copyWith(
                                            color: AppColors.warning,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ],
                            ),
                            if (cust != null)
                              Row(
                                children: [
                                  if (cust.pointBalance > 0) ...[
                                    const Icon(Icons.stars_rounded,
                                        size: 11, color: AppColors.warning),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${cust.pointBalance}pt',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.warning,
                                          fontSize: 10),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (cust.totalVisits > 0)
                                    Text(
                                      '来店${cust.totalVisits}回',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 10),
                                    ),
                                ],
                              ),
                            // 注意事項がある場合は赤バナー表示
                            if (cust?.cautionFlag == true && cust?.cautionNote != null) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.errorLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '⚠ ${cust!.cautionNote}',
                                  style: AppTextStyles.caption.copyWith(
                                      color: AppColors.error, fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    )
                  : Text(
                      'お客様を選択',
                      style: AppTextStyles.body2
                          .copyWith(color: AppColors.textDisabled),
                    ),
            ),
            if (customerId != null)
              GestureDetector(
                onTap: () => ref.read(posProvider.notifier).clearCustomer(),
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
        // 다음 예약 표시
        if (customerId != null)
          _NextAppointmentBanner(customerId: customerId!),
        ],
      ),
    );
  }

  void _selectCustomer(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 480, height: 520,
          child: CustomerSearchSheet(
            onSelected: (id, name) {
              ref.read(posProvider.notifier).setCustomer(id, name);
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }
}

// ─── 담당 스태프 선택 행 (드롭다운) ────────────────────────────────────────
class _StaffRow extends ConsumerWidget {
  const _StaffRow({required this.selectedStaffId});
  final String? selectedStaffId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(activeStaffProvider);
    return staffAsync.when(
      data: (staffList) {
        if (staffList.isEmpty) return const SizedBox(height: 36);
        final currentId = staffList.any((s) => s.id == selectedStaffId)
            ? selectedStaffId
            : null;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.cut_outlined, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('担当',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary)),
              const Spacer(),
              // ─── DropdownButton ───────────────────────────────────────
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: currentId,
                  isDense: true,
                  icon: const Icon(Icons.expand_more,
                      size: 16, color: AppColors.textSecondary),
                  style: AppTextStyles.body2.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                  hint: Text('未選択',
                      style: AppTextStyles.body2
                          .copyWith(color: AppColors.textDisabled)),
                  items: [
                    // 未選択オプション
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.textDisabled,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('未選択',
                              style: AppTextStyles.body2
                                  .copyWith(color: AppColors.textDisabled)),
                        ],
                      ),
                    ),
                    // スタッフ一覧
                    ...staffList.map((s) {
                      final color =
                          _parseColor(s.color) ?? AppColors.primary;
                      return DropdownMenuItem<String?>(
                        value: s.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(s.name),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (id) =>
                      ref.read(posProvider.notifier).setStaff(id),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox(height: 36),
      error: (_, __) => const SizedBox(height: 36),
    );
  }
}

// ─── 메모 행 ─────────────────────────────────────────────────────────────
class _NotesRow extends ConsumerWidget {
  const _NotesRow({required this.notes});
  final String? notes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _showNotesDialog(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.edit_note_outlined,
                size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: notes != null && notes!.isNotEmpty
                  ? Text(notes!,
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)
                  : Text('メモを追加',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textDisabled)),
            ),
            if (notes != null && notes!.isNotEmpty)
              GestureDetector(
                onTap: () =>
                    ref.read(posProvider.notifier).setNotes(null),
                child: const Icon(Icons.close,
                    size: 14, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  // 자주 쓰는 메모 프리셋
  static const _memoPresets = [
    'アレルギー確認済み',
    'パッチテスト実施',
    'カラー希望',
    'パーマ希望',
    'トリートメント追加',
    '次回クーポン適用',
  ];

  void _showNotesDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: notes ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('メモ'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 퀵 프리셋 칩
                Text('クイック追加', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _memoPresets.map((preset) => ActionChip(
                    label: Text(preset, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      final current = controller.text;
                      controller.text = current.isEmpty ? preset : '$current\n$preset';
                      controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: controller.text.length));
                    },
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    hintText: 'アレルギー情報・施術メモなど',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(posProvider.notifier).setNotes(controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 주문 아이템 리스트 ───────────────────────────────────────────────────
class _OrderItemList extends ConsumerWidget {
  const _OrderItemList({required this.items});
  final List<PosOrderItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_bag_outlined,
                size: 40, color: AppColors.textDisabled),
            const SizedBox(height: 8),
            Text('メニューを選択してください',
                style: AppTextStyles.caption),
          ],
        ),
      );
    }
    return Scrollbar(
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 14, endIndent: 14),
      itemBuilder: (_, i) {
        final item = items[i];
        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            color: AppColors.error.withOpacity(0.1),
            child: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
          onDismissed: (_) => ref.read(posProvider.notifier).removeItem(item.id),
          child: _OrderItemTile(item: item),
        );
      },
    ),
    );
  }
}

// ─── 주문 아이템 행 (탭하면 확장) ─────────────────────────────────────────
class _OrderItemTile extends ConsumerStatefulWidget {
  const _OrderItemTile({required this.item});
  final PosOrderItem item;

  @override
  ConsumerState<_OrderItemTile> createState() => _OrderItemTileState();
}

class _OrderItemTileState extends ConsumerState<_OrderItemTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final notifier = ref.read(posProvider.notifier);

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 항상 표시: 이름 ×갯수 + 금액
            Row(
              children: [
                // 스태프 도트
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 7, top: 1),
                  decoration: BoxDecoration(
                    color: item.staffId != null ? AppColors.primary : AppColors.border,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500),
                      children: [
                        TextSpan(text: item.name),
                        TextSpan(
                          text: ' ×${item.qty}',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('¥${_fmt(item.total)}',
                          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                      if (item.discountAmount > 0)
                        Text('¥${_fmt(item.unitPrice * item.qty)}',
                            style: AppTextStyles.caption.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.textDisabled,
                            )),
                    ],
                  ),
                  // 확장 화살표
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16, color: AppColors.textDisabled,
                    ),
                  ),
                ],
              ),
              // 확장 시: - qty + (좌측) | 스태프명/할인 | 삭제(우측)
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: ClipRect(
                  child: _expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // - qty + 좌측 정렬
                                _QtyBtn(
                                  icon: Icons.remove,
                                  onTap: () => notifier.updateQty(item.id, item.qty - 1),
                                ),
                                GestureDetector(
                                  onTap: () => _editQty(context),
                                  child: Container(
                                    constraints: const BoxConstraints(minWidth: 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text('${item.qty}',
                                        textAlign: TextAlign.center,
                                        style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w700)),
                                  ),
                                ),
                                _QtyBtn(
                                  icon: Icons.add,
                                  onTap: () => notifier.updateQty(item.id, item.qty + 1),
                                ),
                                const SizedBox(width: 8),
                                // 스태프명/할인 중앙
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (item.staffName != null)
                                        Text(item.staffName!,
                                            style: AppTextStyles.caption.copyWith(
                                                color: AppColors.textSecondary)),
                                      if (item.discountAmount > 0)
                                        Text('-¥${_fmt(item.discountAmount)} 割引',
                                            style: AppTextStyles.caption.copyWith(
                                                color: AppColors.error)),
                                    ],
                                  ),
                                ),
                                // 삭제 버튼 우측
                                GestureDetector(
                                  onTap: () {
                                    notifier.removeItem(item.id);
                                    showTopBanner(
                                      context,
                                      '「${item.name}」を削除しました',
                                      color: const Color(0xFF64748B),
                                      icon: Icons.delete_outline,
                                      duration: const Duration(seconds: 4),
                                      actionLabel: '元に戻す',
                                      onAction: () => notifier.restoreItem(item),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.delete_outline,
                                        size: 16, color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
    );
  }

  void _editQty(BuildContext context) {
    final item = widget.item;
    final ctrl = TextEditingController(text: '${item.qty}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name,
            style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          textAlign: TextAlign.center,
          style: AppTextStyles.h3,
          decoration: const InputDecoration(
            labelText: '数量',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () { ctrl.dispose(); Navigator.pop(ctx); },
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final newQty = int.tryParse(ctrl.text.trim());
              ctrl.dispose();
              Navigator.pop(ctx);
              if (newQty != null && newQty > 0) {
                ref.read(posProvider.notifier).updateQty(item.id, newQty);
              } else if (newQty == 0) {
                ref.read(posProvider.notifier).removeItem(item.id);
              }
            },
            child: const Text('変更'),
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: AppColors.textPrimary),
      ),
    );
  }
}

// ─── 아이템 액션 시트 (탭 → 슬라이드업) ─────────────────────────────────
class _ItemActionSheet extends ConsumerStatefulWidget {
  const _ItemActionSheet({required this.item});
  final PosOrderItem item;

  @override
  ConsumerState<_ItemActionSheet> createState() =>
      _ItemActionSheetState();
}

class _ItemActionSheetState extends ConsumerState<_ItemActionSheet> {
  String _mode = 'percent';
  final _ctrl = TextEditingController();
  int _inputVal = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = int.tryParse(_ctrl.text) ?? 0;
      if (v != _inputVal) setState(() => _inputVal = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.item.unitPrice * widget.item.qty;

    // Custom input preview
    int previewDisc = 0;
    if (_inputVal > 0) {
      previewDisc = _mode == 'amount'
          ? _inputVal.clamp(0, base)
          : (base * _inputVal / 100).round().clamp(0, base);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── ヘッダー ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.discount_outlined, color: AppColors.primary, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.item.name, style: AppTextStyles.h4,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    widget.item.qty > 1
                        ? '¥${_fmt(widget.item.unitPrice)} × ${widget.item.qty} = ¥${_fmt(base)}'
                        : '¥${_fmt(widget.item.unitPrice)}',
                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              )),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 割引率プリセット ─────────────────────────────────────────
              Text('割引率', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [10, 20, 30].map((p) {
                  final disc = (base * p / 100).round();
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: p < 30 ? 8.0 : 0),
                      child: _DiscountPresetBtn(
                        label: '$p%',
                        subLabel: '-¥${_fmt(disc)}',
                        isSelected: false,
                        onTap: () {
                          ref.read(posProvider.notifier).setItemDiscount(widget.item.id, disc);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // ── 定額割引プリセット ────────────────────────────────────────
              Text('定額割引', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [500, 1000, 3000].map((y) {
                  final disc = y.clamp(0, base);
                  final grayed = disc < y;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: y < 3000 ? 8.0 : 0),
                      child: _DiscountPresetBtn(
                        label: '¥${_fmt(y)}',
                        subLabel: grayed ? '上限' : '',
                        isSelected: false,
                        onTap: disc > 0 ? () {
                          ref.read(posProvider.notifier).setItemDiscount(widget.item.id, disc);
                          Navigator.pop(context);
                        } : () {},
                        color: grayed ? AppColors.textDisabled : AppColors.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              // ── カスタム入力 ─────────────────────────────────────────────
              Text('カスタム', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ToggleChip(
                    label: '割合(%)',
                    selected: _mode == 'percent',
                    onTap: () => setState(() { _mode = 'percent'; _ctrl.clear(); _inputVal = 0; }),
                  ),
                  const SizedBox(width: 8),
                  _ToggleChip(
                    label: '金額(¥)',
                    selected: _mode == 'amount',
                    onTap: () => setState(() { _mode = 'amount'; _ctrl.clear(); _inputVal = 0; }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: _mode == 'percent' ? '例: 15' : '例: 2000',
                        suffixText: _mode == 'percent' ? '%' : '円',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),

              // ── プレビュー ────────────────────────────────────────────────
              if (previewDisc > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text('¥${_fmt(base)}', style: AppTextStyles.caption.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.textSecondary)),
                      const Text(' → ', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      Text('¥${_fmt(base - previewDisc)}', style: AppTextStyles.body2.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('-¥${_fmt(previewDisc)}', style: AppTextStyles.label.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: previewDisc > 0 ? _apply : null,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(previewDisc > 0
                      ? '-¥${_fmt(previewDisc)} を適用'
                      : 'カスタム割引を入力'),
                ),
              ),

              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                  label: Text('このアイテムを削除',
                      style: AppTextStyles.body2.copyWith(color: AppColors.error)),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _apply() {
    final val = int.tryParse(_ctrl.text) ?? 0;
    if (val <= 0) return;
    final base = widget.item.unitPrice * widget.item.qty;
    final discAmt = _mode == 'amount'
        ? val.clamp(0, base)
        : (base * val / 100).round().clamp(0, base);
    ref.read(posProvider.notifier).setItemDiscount(widget.item.id, discAmt);
    Navigator.pop(context);
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip(
      {required this.label,
      required this.selected,
      required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryLight : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: AppTextStyles.label.copyWith(
              color: selected
                  ? AppColors.primary
                  : AppColors.textSecondary,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400,
            )),
      ),
    );
  }
}

// ─── 금액 요약 ────────────────────────────────────────────────────────────
class _AmountSummary extends StatelessWidget {
  const _AmountSummary({required this.state});
  final PosState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        children: [
          _SummaryRow('小計', '¥${_fmt(state.subtotal)}'),
          if (state.manualDiscountAmount > 0)
            _SummaryRow(
                '全体割引', '-¥${_fmt(state.manualDiscountAmount)}',
                color: AppColors.error),
          _SummaryRow(
              '消費税(10%)', '¥${_fmt(state.taxAmount10)}',
              small: true),
          if (state.taxAmount8 > 0)
            _SummaryRow(
                '消費税(8%)', '¥${_fmt(state.taxAmount8)}',
                small: true),
          if (state.pointUsed > 0)
            _SummaryRow(
                'ポイント使用', '-¥${_fmt(state.pointUsed)}',
                color: AppColors.success),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('合計',
                  style: AppTextStyles.body2
                      .copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('¥${_fmt(state.grandTotal)}',
                  style: AppTextStyles.priceMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value,
      {this.color, this.small = false});
  final String label;
  final String value;
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final ts = small
        ? AppTextStyles.caption
        : AppTextStyles.body2.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: ts),
          const Spacer(),
          Text(value, style: ts.copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── 주문 액션 + 결제 버튼 ────────────────────────────────────────────────
class _OrderActions extends ConsumerWidget {
  const _OrderActions({required this.state, required this.session});
  final PosState state;
  final RegisterSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItems = state.items.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // 보조 액션 3개
          Row(
            children: [
              _SmallBtn(
                icon: Icons.discount_outlined,
                label: '割引',
                onTap: hasItems
                    ? () => _showDiscountSheet(context, ref)
                    : null,
              ),
              const SizedBox(width: 6),
              _SmallBtn(
                icon: Icons.delete_outline,
                label: 'クリア',
                onTap: hasItems ? () => _confirmClear(context, ref) : null,
                color: AppColors.error,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 결제 버튼
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: hasItems
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PaymentScreen(session: session),
                          fullscreenDialog: true,
                        ),
                      )
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    hasItems ? AppColors.primary : AppColors.border,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('会計へ進む',
                      style: AppTextStyles.button
                          .copyWith(color: Colors.white)),
                  if (hasItems) ...[
                    const SizedBox(width: 8),
                    Text(
                      '¥${_fmt(state.grandTotal)}',
                      style: AppTextStyles.button.copyWith(
                          color: Colors.white.withOpacity(0.85),
                          fontWeight: FontWeight.w400),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward,
                      size: 18, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDiscountSheet(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(width: 460, child: _GlobalDiscountSheet()),
      ),
    );
  }

  void _showPointSheet(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: const SizedBox(width: 460, child: _PointSheet()),
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('会計をクリア'),
        content: const Text('現在の会計内容をすべて削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              final savedItems = [...ref.read(posProvider).items];
              final messenger = ScaffoldMessenger.of(context);
              final notifier = ref.read(posProvider.notifier);
              notifier.clear();
              Navigator.pop(ctx);
              messenger.hideCurrentSnackBar();
              showTopBanner(
                context,
                '会計をクリアしました (${savedItems.length}件)',
                color: const Color(0xFF64748B),
                icon: Icons.delete_sweep_outlined,
                duration: const Duration(seconds: 5),
                actionLabel: '元に戻す',
                onAction: () => notifier.restoreItems(savedItems),
              );
            },
            child: Text('クリア',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = onTap != null
        ? (color ?? AppColors.textPrimary)
        : AppColors.textDisabled;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(height: 2),
              Text(label,
                  style: AppTextStyles.caption
                      .copyWith(color: c, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 전체 할인 시트 ───────────────────────────────────────────────────────
class _GlobalDiscountSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_GlobalDiscountSheet> createState() =>
      _GlobalDiscountSheetState();
}

class _GlobalDiscountSheetState extends ConsumerState<_GlobalDiscountSheet> {
  String _mode = 'percent';
  final _ctrl = TextEditingController();
  int _inputVal = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final v = int.tryParse(_ctrl.text) ?? 0;
      if (v != _inputVal) setState(() => _inputVal = v);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = ref.watch(posProvider).subtotal;
    const presets = [5, 10, 15, 20, 30];

    int previewDisc = 0;
    if (_inputVal > 0) {
      previewDisc = _mode == 'percent'
          ? (subtotal * _inputVal / 100).round().clamp(0, subtotal)
          : _inputVal.clamp(0, subtotal);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── ヘッダー ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.discount_outlined, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('全体割引', style: AppTextStyles.h4),
                  Text('会計合計に割引を適用',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 対象合計
              Row(
                children: [
                  Text('対象合計', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  const Spacer(),
                  Text('¥${_fmt(subtotal)}',
                      style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 16),

              // ── クイック割引プリセット ───────────────────────────────────
              Text('クイック割引', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((p) {
                  final discAmt = (subtotal * p / 100).round();
                  final isSelected = _mode == 'percent' && _inputVal == p;
                  return _DiscountPresetBtn(
                    label: '$p%',
                    subLabel: '-¥${_fmt(discAmt)}',
                    isSelected: isSelected,
                    onTap: () => setState(() {
                      _mode = 'percent';
                      _ctrl.text = p.toString();
                      _inputVal = p;
                    }),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),
              // ── カスタム入力 ─────────────────────────────────────────────
              Text('カスタム', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ToggleChip(
                    label: '割合(%)',
                    selected: _mode == 'percent',
                    onTap: () => setState(() {
                      _mode = 'percent';
                      _ctrl.clear();
                      _inputVal = 0;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _ToggleChip(
                    label: '金額(¥)',
                    selected: _mode == 'amount',
                    onTap: () => setState(() {
                      _mode = 'amount';
                      _ctrl.clear();
                      _inputVal = 0;
                    }),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: _mode == 'percent' ? '例: 15' : '例: 2000',
                        suffixText: _mode == 'percent' ? '%' : '円',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),

              // ── プレビュー ────────────────────────────────────────────────
              if (previewDisc > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                      const SizedBox(width: 8),
                      Text('¥${_fmt(subtotal)}', style: AppTextStyles.body2.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.textSecondary)),
                      const Text('  →  ', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      Text('¥${_fmt(subtotal - previewDisc)}',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.success, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('-¥${_fmt(previewDisc)}',
                          style: AppTextStyles.label.copyWith(
                              color: AppColors.success, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: previewDisc > 0 ? _apply : null,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    previewDisc > 0
                        ? '¥${_fmt(previewDisc)} の割引を適用'
                        : '割引を設定してください',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _apply() {
    final val = int.tryParse(_ctrl.text) ?? 0;
    if (val <= 0) return;
    final subtotal = ref.read(posProvider).subtotal;
    final disc = _mode == 'percent'
        ? (subtotal * val / 100).round().clamp(0, subtotal)
        : val.clamp(0, subtotal);
    ref.read(posProvider.notifier).setDiscount(disc);
    Navigator.pop(context);
  }
}

// ─── 포인트 사용 시트 ─────────────────────────────────────────────────────
class _PointSheet extends ConsumerStatefulWidget {
  const _PointSheet();

  @override
  ConsumerState<_PointSheet> createState() => _PointSheetState();
}

class _PointSheetState extends ConsumerState<_PointSheet> {
  int _selectedPoint = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posProvider);
    final db = ref.watch(databaseProvider);
    final customerId = state.customerId;
    if (customerId == null) return const SizedBox.shrink();

    return FutureBuilder<Customer?>(
      future: (db.select(db.customers)
            ..where((t) => t.id.equals(customerId)))
          .getSingleOrNull(),
      builder: (context, snap) {
        final balance = snap.data?.pointBalance ?? 0;
        final maxUsable = balance.clamp(0, state.grandTotal);

        const accent = Color(0xFFF59E0B);
        const accentDark = Color(0xFFD97706);
        const accentBg = Color(0xFFFFFBEB);

        // Build preset list
        final presetValues = [100, 300, 500, 1000]
            .where((v) => v > 0 && v <= maxUsable)
            .toList();
        final hasAllBtn = maxUsable > 0 && !presetValues.contains(maxUsable);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── ヘッダー ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: accentBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.stars_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('ポイントを使用', style: AppTextStyles.h4),
                  const Spacer(),
                  // 残高バッジ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accentBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, color: accent, size: 13),
                        const SizedBox(width: 4),
                        Text('${_fmt(balance)} pt',
                            style: AppTextStyles.label.copyWith(
                                color: accentDark, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                    color: AppColors.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (maxUsable == 0) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              color: AppColors.textSecondary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            balance == 0
                                ? '利用可能なポイントがありません'
                                : '合計金額がポイント未満です',
                            style: AppTextStyles.body2
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Text('使用ポイントを選択',
                        style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    // ── プリセットカード ──────────────────────────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...presetValues.map((pt) => _PointPresetCard(
                          pt: pt,
                          isAll: false,
                          isSelected: _selectedPoint == pt,
                          onTap: () => setState(() => _selectedPoint = pt),
                        )),
                        if (hasAllBtn) _PointPresetCard(
                          pt: maxUsable,
                          isAll: true,
                          isSelected: _selectedPoint == maxUsable,
                          onTap: () => setState(() => _selectedPoint = maxUsable),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // ── スライダー ────────────────────────────────────────
                    Row(
                      children: [
                        const Icon(Icons.stars_rounded, size: 15, color: accent),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              activeTrackColor: accent,
                              inactiveTrackColor: accent.withOpacity(0.2),
                              thumbColor: accent,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayColor: accent.withOpacity(0.15),
                            ),
                            child: Slider(
                              value: _selectedPoint.toDouble(),
                              min: 0,
                              max: maxUsable.toDouble(),
                              divisions: (maxUsable ~/ 100).clamp(1, 100),
                              onChanged: (v) =>
                                  setState(() => _selectedPoint = v.round()),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accentBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${_fmt(_selectedPoint)} pt',
                              style: AppTextStyles.label.copyWith(
                                  color: accentDark, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    // ── プレビュー ────────────────────────────────────────
                    if (_selectedPoint > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: accentBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: accent.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stars_rounded, color: accent, size: 16),
                            const SizedBox(width: 6),
                            Text('${_fmt(_selectedPoint)}pt 使用',
                                style: AppTextStyles.body2
                                    .copyWith(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            Text('-¥${_fmt(_selectedPoint)} 割引',
                                style: AppTextStyles.body2.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _selectedPoint > 0
                          ? () {
                              ref
                                  .read(posProvider.notifier)
                                  .setPointUsed(_selectedPoint);
                              Navigator.pop(context);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        disabledBackgroundColor: AppColors.border,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        _selectedPoint > 0
                            ? '${_fmt(_selectedPoint)}pt を適用  (-¥${_fmt(_selectedPoint)})'
                            : 'ポイントを選択してください',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _selectedPoint > 0 ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}


// ─── 割引プリセットボタン ─────────────────────────────────────────────────
class _DiscountPresetBtn extends StatelessWidget {
  const _DiscountPresetBtn({
    required this.label,
    required this.subLabel,
    required this.isSelected,
    required this.onTap,
    this.color = AppColors.primary,
  });
  final String label;
  final String subLabel;
  final bool isSelected;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppTextStyles.label.copyWith(
              color: isSelected ? color : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            )),
            if (subLabel.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subLabel, style: AppTextStyles.caption.copyWith(
                color: isSelected ? color : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── ポイントプリセットカード ─────────────────────────────────────────────
class _PointPresetCard extends StatelessWidget {
  const _PointPresetCard({
    required this.pt,
    required this.isAll,
    required this.isSelected,
    required this.onTap,
  });
  final int pt;
  final bool isAll;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF59E0B);
    const accentDark = Color(0xFFD97706);
    const accentBg = Color(0xFFFFFBEB);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? accentBg : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accent : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAll) ...[
              const Icon(Icons.stars_rounded, color: accent, size: 13),
              const SizedBox(width: 4),
            ],
            Text(
              isAll ? '全て (${_fmt(pt)}pt)' : '${_fmt(pt)}pt',
              style: AppTextStyles.label.copyWith(
                color: isSelected ? accentDark : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 메뉴 검색 다이얼로그 ─────────────────────────────────────────────────
class _MenuSearchDialog extends ConsumerStatefulWidget {
  const _MenuSearchDialog();

  @override
  ConsumerState<_MenuSearchDialog> createState() =>
      _MenuSearchDialogState();
}

class _MenuSearchDialogState extends ConsumerState<_MenuSearchDialog> {
  final _ctrl = TextEditingController();
  List<MenusData> _results = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    final db = ref.read(databaseProvider);
    final res = await (db.select(db.menus)
          ..where((t) => t.name.like('%$q%') & t.isActive.equals(true))
          ..limit(20))
        .get();
    if (mounted) setState(() => _results = res);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        height: 480,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'メニューを検索',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _search,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _ctrl.text.isEmpty
                            ? 'メニュー名を入力してください'
                            : '該当するメニューがありません',
                        style: AppTextStyles.caption,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16),
                      itemBuilder: (_, i) {
                        final m = _results[i];
                        return ListTile(
                          title: Text(m.name,
                              style: AppTextStyles.body2),
                          subtitle: Text('${m.durationMin}分',
                              style: AppTextStyles.caption),
                          trailing: Text('¥${_fmt(m.price)}',
                              style: AppTextStyles.label.copyWith(
                                  fontWeight: FontWeight.w700)),
                          onTap: () {
                            ref
                                .read(posProvider.notifier)
                                .addMenu(m);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 시재관리 시트 ────────────────────────────────────────────────────────
class _CashManagementSheet extends ConsumerStatefulWidget {
  const _CashManagementSheet({required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<_CashManagementSheet> createState() =>
      _CashManagementSheetState();
}

class _CashManagementSheetState
    extends ConsumerState<_CashManagementSheet> {
  String _mode = 'in'; // in | out
  final _amtCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _amtCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('釣銭管理', style: AppTextStyles.h4),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 입금/출금 토글
          Row(
            children: [
              Expanded(
                child: _CashModeBtn(
                  label: 'お金を入れる',
                  icon: Icons.add_circle_outline,
                  selected: _mode == 'in',
                  color: AppColors.success,
                  onTap: () => setState(() => _mode = 'in'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CashModeBtn(
                  label: 'お金を出す',
                  icon: Icons.remove_circle_outline,
                  selected: _mode == 'out',
                  color: AppColors.error,
                  onTap: () => setState(() => _mode = 'out'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 빠른 금액
          Wrap(
            spacing: 8,
            children: [1000, 5000, 10000, 50000]
                .map((amt) => ActionChip(
                      label: Text('¥${_fmt(amt)}',
                          style: AppTextStyles.label),
                      onPressed: () =>
                          setState(() => _amtCtrl.text = amt.toString()),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _amtCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '金額', prefixText: '¥'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(
                labelText: '理由・メモ（任意）'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _mode == 'in' ? AppColors.success : AppColors.error,
            ),
            child: Text(_mode == 'in' ? '入金する' : '出金する'),
          ),
          const Divider(height: 20),
          Text('操作履歴',
              style: AppTextStyles.body2
                  .copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<CashMovement>>(
              stream: (db.select(db.cashMovements)
                    ..where(
                        (t) => t.sessionId.equals(widget.sessionId))
                    ..orderBy(
                        [(t) => OrderingTerm.desc(t.createdAt)]))
                  .watch(),
              builder: (context, snap) {
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return Text('操作履歴なし',
                      style: AppTextStyles.caption);
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final m = items[i];
                    final isIn = m.movementType == 'cash_in';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isIn
                            ? Icons.add_circle
                            : Icons.remove_circle,
                        color: isIn
                            ? AppColors.success
                            : AppColors.error,
                        size: 20,
                      ),
                      title: Text(
                          m.reason ?? (isIn ? '入金' : '出金'),
                          style: AppTextStyles.body2),
                      trailing: Text(
                        '${isIn ? '+' : '-'}¥${_fmt(m.amount)}',
                        style: AppTextStyles.label.copyWith(
                          color: isIn
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final amt = int.tryParse(_amtCtrl.text) ?? 0;
    if (amt <= 0) return;
    final db = ref.read(databaseProvider);
    final staffList = await db.activeStaff;
    final staffId =
        staffList.isNotEmpty ? staffList.first.id : 'staff-default';
    await db.into(db.cashMovements).insert(
          CashMovementsCompanion.insert(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            sessionId: widget.sessionId,
            staffId: staffId,
            movementType: _mode == 'in' ? 'cash_in' : 'cash_out',
            amount: amt,
            reason: Value(
                _reasonCtrl.text.isEmpty ? null : _reasonCtrl.text),
          ),
        );
    _amtCtrl.clear();
    _reasonCtrl.clear();
    if (mounted) {
      showTopBanner(
        context,
        _mode == 'in' ? '¥${_fmt(amt)} 入金しました' : '¥${_fmt(amt)} 出金しました',
        color: _mode == 'in' ? AppColors.success : AppColors.error,
        icon: _mode == 'in' ? Icons.add_circle_outline : Icons.remove_circle_outline,
      );
    }
  }
}

class _CashModeBtn extends StatelessWidget {
  const _CashModeBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color:
                    selected ? color : AppColors.textSecondary),
            const SizedBox(height: 4),
            Text(label,
                style: AppTextStyles.label.copyWith(
                    color: selected
                        ? color
                        : AppColors.textSecondary,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

// ─── 유틸 ─────────────────────────────────────────────────────────────────
Color? _parseColor(String? hex) {
  if (hex == null) return null;
  try {
    return Color(int.parse(hex.replaceAll('#', '0xFF')));
  } catch (_) {
    return null;
  }
}

// ─── POS 고객 다음 예약 배너 ─────────────────────────────────────────────
// ─── 今日の売上 KPI プログレス (AppBar用) ─────────────────────────────────
class _TodayKpiProgress extends ConsumerWidget {
  const _TodayKpiProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayRevenueProvider);
    final kpiAsync = ref.watch(kpiProgressProvider(ReportRange.forMonth()));

    return todayAsync.maybeWhen(
      data: (today) {
        // 일일 목표 = 월간 목표 / 영업일 수 (25일 기준)
        final monthlyTarget = kpiAsync.valueOrNull
            ?.where((k) => k.targetType == 'monthly_revenue')
            .firstOrNull
            ?.targetValue ?? 0;
        final dailyTarget = monthlyTarget == 0 ? 0 : (monthlyTarget / 25).round();
        final progress = dailyTarget == 0 ? 0.0 : (today.revenue / dailyTarget).clamp(0.0, 1.0);
        final isAchieved = dailyTarget > 0 && today.revenue >= dailyTarget;

        return SizedBox(
          width: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '¥${_fmtNum(today.revenue)}',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isAchieved ? AppColors.success : AppColors.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                  if (dailyTarget > 0) ...[
                    Text(
                      ' / ¥${_fmtNum(dailyTarget)}',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary, fontSize: 10),
                    ),
                    if (isAchieved)
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.check_circle,
                            size: 12, color: AppColors.success),
                      ),
                  ],
                ],
              ),
              if (dailyTarget > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isAchieved ? AppColors.success : AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _NextAppointmentBanner extends ConsumerWidget {
  const _NextAppointmentBanner({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final nextAptFuture = (db.select(db.appointments)
          ..where((t) =>
              t.customerId.equals(customerId) &
              t.startAt.isBiggerOrEqualValue(today) &
              t.status.isNotIn(['cancelled', 'no_show', 'completed']))
          ..orderBy([(t) => OrderingTerm.asc(t.startAt)])
          ..limit(1))
        .getSingleOrNull();

    return FutureBuilder<Appointment?>(
      future: nextAptFuture,
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data == null) return const SizedBox.shrink();
        final apt = snap.data!;
        final dt = DateTime.tryParse(apt.startAt);
        if (dt == null) return const SizedBox.shrink();
        final isToday = dt.toIso8601String().substring(0, 10) == today;
        final dateStr = isToday
            ? '本日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
            : '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          color: isToday
              ? AppColors.primary.withAlpha(12)
              : AppColors.background,
          child: Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 11,
                color: isToday ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '次回予約: $dateStr',
                style: AppTextStyles.caption.copyWith(
                  fontSize: 10,
                  color: isToday ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _fmt(int n) {
  if (n < 0) return '-${_fmt(-n)}';
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
