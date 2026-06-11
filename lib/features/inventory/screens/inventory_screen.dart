import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/widgets/top_banner.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/inventory_provider.dart';

const _uuid = Uuid();

// ─── 재고관리 메인 화면 ───────────────────────────────────────────────────
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String? _selectedCategoryId; // null = 全て
  bool _showLowStockOnly = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final productsAsync = _showLowStockOnly
        ? ref.watch(lowStockProductsProvider)
        : ref.watch(productsProvider(_selectedCategoryId));
    final lowStockAsync = ref.watch(lowStockProductsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.settings),
        ),
        title: const Text('在庫管理'),
        actions: [
          // 부족재고 알림 아이콘
          lowStockAsync.when(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: Badge(
                      label: Text('${items.length}'),
                      child: const Icon(Icons.warning_amber_outlined),
                    ),
                    onPressed: () =>
                        setState(() => _showLowStockOnly = !_showLowStockOnly),
                    tooltip: '在庫不足',
                    color: _showLowStockOnly ? AppColors.warning : null,
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          // 발주 리스트 클립보드 복사
          lowStockAsync.when(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.assignment_outlined),
                    tooltip: '発注リストをコピー',
                    onPressed: () => _copyOrderList(context, items),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showProductForm(context, null),
            tooltip: '商品追加',
          ),
        ],
      ),
      body: Column(
        children: [
          // 검색바
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: '商品名で検索',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),

          // 카테고리 탭
          if (!_showLowStockOnly)
            categoriesAsync.when(
              data: (cats) => _CategoryTabs(
                categories: cats,
                selected: _selectedCategoryId,
                onSelected: (id) =>
                    setState(() => _selectedCategoryId = id),
              ),
              loading: () => const SizedBox(height: 52),
              error: (_, __) => const SizedBox(height: 52),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              color: AppColors.warning.withAlpha(20),
              child: Row(
                children: [
                  Icon(Icons.warning_amber,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text('在庫不足の商品のみ表示中',
                      style: AppTextStyles.body2
                          .copyWith(color: AppColors.warning)),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        setState(() => _showLowStockOnly = false),
                    child: const Text('解除'),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // 상품 목록
          Expanded(
            child: productsAsync.when(
              data: (products) {
                // 검색 필터
                final filtered = _searchQuery.isEmpty
                    ? products
                    : products
                        .where((p) => p.name
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()))
                        .toList();

                if (filtered.isEmpty) {
                  return _EmptyState(showLowStock: _showLowStockOnly);
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _ProductCard(
                    product: filtered[i],
                    onAdjust: () => _showAdjustDialog(ctx, filtered[i]),
                    onEdit: () => _showProductForm(ctx, filtered[i]),
                  ),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showAdjustDialog(BuildContext ctx, Product product) {
    showDialog(
      context: ctx,
      builder: (_) => _AdjustDialog(product: product),
    );
  }

  void _copyOrderList(BuildContext ctx, List<Product> items) {
    final now = DateTime.now();
    final header =
        '発注リスト  ${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    final lines = items.map((p) {
      final stock = p.stockQuantity;
      final reorder = p.reorderPoint > 0 ? '発注点${p.reorderPoint}' : '';
      return '・${p.name}  現在庫:${stock}${p.unit}  $reorder';
    }).join('\n');
    Clipboard.setData(ClipboardData(text: '$header\n$lines'));
    showTopBanner(ctx, '発注リストをクリップボードにコピーしました (${items.length}件)',
        icon: Icons.assignment_outlined, color: AppColors.primary);
  }

  void _showProductForm(BuildContext ctx, Product? existing) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(ctx),
        child: _ProductFormSheet(existing: existing),
      ),
    );
  }
}

// ─── 카테고리 탭 ──────────────────────────────────────────────────────────
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });
  final List<ProductCategory> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _Tab(
            label: '全て',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          ...categories.map((c) => _Tab(
                label: c.name,
                selected: selected == c.id,
                onTap: () => onSelected(c.id),
              )),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.label.copyWith(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 상품 카드 ────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onAdjust,
    required this.onEdit,
  });
  final Product product;
  final VoidCallback onAdjust;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isLow = product.reorderPoint > 0 &&
        product.stockQuantity <= product.reorderPoint;
    final isCritical = product.minStock > 0 &&
        product.stockQuantity <= product.minStock;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCritical
              ? AppColors.error.withAlpha(180)
              : isLow
                  ? AppColors.warning.withAlpha(180)
                  : AppColors.border,
          width: isCritical || isLow ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // 재고 상태 인디케이터
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: isCritical
                    ? AppColors.error
                    : isLow
                        ? AppColors.warning
                        : AppColors.success,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),

            // 상품 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: AppTextStyles.body1
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (product.sku != null)
                        Text(
                          product.sku!,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _StockBadge(
                        qty: product.stockQuantity,
                        unit: product.unit,
                        isCritical: isCritical,
                        isLow: isLow,
                      ),
                      if (product.reorderPoint > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '発注点 ${product.reorderPoint}${product.unit}',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary),
                        ),
                      ],
                      const Spacer(),
                      if (product.retailPrice > 0)
                        Text(
                          '¥${_fmt(product.retailPrice)}',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 액션 버튼
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: onAdjust,
                  tooltip: '在庫調整',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    backgroundColor: AppColors.primary.withAlpha(15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  tooltip: '編集',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
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

class _StockBadge extends StatelessWidget {
  const _StockBadge({
    required this.qty,
    required this.unit,
    required this.isCritical,
    required this.isLow,
  });
  final int qty;
  final String unit;
  final bool isCritical;
  final bool isLow;

  @override
  Widget build(BuildContext context) {
    final color = isCritical
        ? AppColors.error
        : isLow
            ? AppColors.warning
            : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCritical
                ? Icons.error_outline
                : isLow
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            '$qty $unit',
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 재고 조정 다이얼로그 (調整 + 履歴 탭) ───────────────────────────────
class _AdjustDialog extends ConsumerStatefulWidget {
  const _AdjustDialog({required this.product});
  final Product product;

  @override
  ConsumerState<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends ConsumerState<_AdjustDialog>
    with SingleTickerProviderStateMixin {
  final _qtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _type = 'purchase'; // purchase | adjustment | loss | return
  bool _isLoading = false;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _notesCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.product.name,
                        style: AppTextStyles.h4
                            .copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 현재 재고 표시
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('現在庫', style: AppTextStyles.body2),
                    Text(
                      '${widget.product.stockQuantity} ${widget.product.unit}',
                      style: AppTextStyles.h4
                          .copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            // 탭
            TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: '在庫調整'),
                Tab(text: '調整履歴'),
              ],
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
            ),
            const Divider(height: 1),
            // 탭 콘텐츠
            SizedBox(
              height: 280,
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── 調整 탭 ──
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('調整タイプ',
                            style: AppTextStyles.label
                                .copyWith(color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _TypeChip(
                                label: '入庫',
                                value: 'purchase',
                                selected: _type == 'purchase',
                                onTap: () =>
                                    setState(() => _type = 'purchase')),
                            _TypeChip(
                                label: '調整',
                                value: 'adjustment',
                                selected: _type == 'adjustment',
                                onTap: () =>
                                    setState(() => _type = 'adjustment')),
                            _TypeChip(
                                label: '廃棄',
                                value: 'loss',
                                selected: _type == 'loss',
                                onTap: () =>
                                    setState(() => _type = 'loss')),
                            _TypeChip(
                                label: '返品',
                                value: 'return',
                                selected: _type == 'return',
                                onTap: () =>
                                    setState(() => _type = 'return')),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _type == 'loss' || _type == 'return'
                              ? '減少数量'
                              : '増加数量',
                          style: AppTextStyles.label
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _qtyCtrl,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '数量を入力',
                            suffixText: widget.product.unit,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _notesCtrl,
                          decoration: InputDecoration(
                            hintText: 'メモ（任意）',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── 履歴 탭 ──
                  _MovementHistoryTab(
                      productId: widget.product.id,
                      unit: widget.product.unit),
                ],
              ),
            ),
            // 조정 탭일 때만 저장 버튼 표시
            ListenableBuilder(
              listenable: _tabCtrl,
              builder: (_, __) => _tabCtrl.index == 0
                  ? Padding(
                      padding:
                          const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('保存'),
                        ),
                      ),
                    )
                  : const SizedBox(height: 16),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final qty = int.tryParse(_qtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      showTopBanner(context, '数量を正しく入力してください',
          icon: Icons.warning_rounded);
      return;
    }
    setState(() => _isLoading = true);
    final isNegative = _type == 'loss' || _type == 'return';
    try {
      await ref.read(inventoryNotifierProvider.notifier).adjustStock(
            productId: widget.product.id,
            delta: isNegative ? -qty : qty,
            type: _type,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    }
  }
}

// ─── 조정 이력 탭 ─────────────────────────────────────────────────────────
class _MovementHistoryTab extends ConsumerWidget {
  const _MovementHistoryTab(
      {required this.productId, required this.unit});
  final String productId;
  final String unit;

  static const _typeLabels = {
    'purchase': ('入庫', Color(0xFF00B746)),
    'adjustment': ('調整', Color(0xFF0064FF)),
    'loss': ('廃棄', Color(0xFFF04452)),
    'return': ('返品', Color(0xFFF5A623)),
    'initial': ('初期', Color(0xFF64748B)),
    'sale': ('販売', Color(0xFFF04452)),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movementsAsync =
        ref.watch(recentMovementsProvider(productId));

    return movementsAsync.when(
      data: (movements) {
        if (movements.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 36, color: AppColors.border),
                const SizedBox(height: 8),
                Text('調整履歴がありません',
                    style: AppTextStyles.body2
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: movements.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 46),
          itemBuilder: (_, i) {
            final m = movements[i];
            final info = _typeLabels[m.movementType] ??
                (m.movementType, AppColors.textSecondary);
            final isPlus = m.quantity > 0;
            final dateStr = m.createdAt.length >= 10
                ? m.createdAt.substring(0, 10)
                : m.createdAt;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: info.$2.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(info.$1,
                          style: TextStyle(
                              fontSize: 9,
                              color: info.$2,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.notes != null && m.notes!.isNotEmpty)
                          Text(m.notes!,
                              style: AppTextStyles.body2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)
                        else
                          Text(info.$1,
                              style: AppTextStyles.body2),
                        Text(dateStr,
                            style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isPlus ? '+' : ''}${m.quantity} $unit',
                        style: AppTextStyles.body2.copyWith(
                          color: isPlus
                              ? AppColors.success
                              : AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text('→ ${m.stockAfter} $unit',
                          style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10)),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withAlpha(30),
      checkmarkColor: AppColors.primary,
      labelStyle: AppTextStyles.label.copyWith(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }
}

// ─── 상품 등록/수정 폼 ────────────────────────────────────────────────────
class _ProductFormSheet extends ConsumerStatefulWidget {
  const _ProductFormSheet({this.existing});
  final Product? existing;

  @override
  ConsumerState<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends ConsumerState<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _retailPriceCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _reorderCtrl = TextEditingController();
  final _minStockCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  String? _categoryId;
  String _productType = 'retail';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _nameCtrl.text = p.name;
      _skuCtrl.text = p.sku ?? '';
      _retailPriceCtrl.text = p.retailPrice > 0 ? '${p.retailPrice}' : '';
      _costPriceCtrl.text = p.costPrice > 0 ? '${p.costPrice}' : '';
      _stockCtrl.text = '${p.stockQuantity}';
      _reorderCtrl.text = p.reorderPoint > 0 ? '${p.reorderPoint}' : '';
      _minStockCtrl.text = p.minStock > 0 ? '${p.minStock}' : '';
      _unitCtrl.text = p.unit;
      _categoryId = p.categoryId;
      _productType = p.productType;
    } else {
      _unitCtrl.text = '個';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _skuCtrl.dispose();
    _retailPriceCtrl.dispose();
    _costPriceCtrl.dispose();
    _stockCtrl.dispose();
    _reorderCtrl.dispose();
    _minStockCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(productCategoriesProvider);
    final isEdit = widget.existing != null;

    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 60),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
            child: Row(
              children: [
                Text(isEdit ? '商品編集' : '商品追加',
                    style: AppTextStyles.h3),
                const Spacer(),
                if (isEdit)
                  TextButton(
                    onPressed: _deactivate,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.error),
                    child: const Text('削除'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 폼
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // 상품명
                  _Field(label: '商品名 *', child: TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(hintText: 'トリートメント A など'),
                    validator: (v) => (v?.trim().isEmpty ?? true) ? '入力必須' : null,
                  )),

                  // 카테고리
                  _Field(
                    label: 'カテゴリ',
                    child: categoriesAsync.when(
                      data: (cats) => DropdownButtonFormField<String?>(
                        value: _categoryId,
                        decoration: const InputDecoration(hintText: 'カテゴリを選択'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('なし')),
                          ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),

                  // SKU / 단위
                  Row(children: [
                    Expanded(child: _Field(label: 'SKU', child: TextFormField(
                      controller: _skuCtrl,
                      decoration: const InputDecoration(hintText: 'SKU-001'),
                    ))),
                    const SizedBox(width: 12),
                    SizedBox(width: 100, child: _Field(label: '単位', child: TextFormField(
                      controller: _unitCtrl,
                      decoration: const InputDecoration(hintText: '個'),
                    ))),
                  ]),

                  // 가격
                  Row(children: [
                    Expanded(child: _Field(label: '販売価格', child: TextFormField(
                      controller: _retailPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(prefixText: '¥', hintText: '0'),
                    ))),
                    const SizedBox(width: 12),
                    Expanded(child: _Field(label: '仕入原価', child: TextFormField(
                      controller: _costPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(prefixText: '¥', hintText: '0'),
                    ))),
                  ]),

                  // 재고
                  Row(children: [
                    Expanded(child: _Field(label: '現在庫数', child: TextFormField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '0'),
                    ))),
                    const SizedBox(width: 12),
                    Expanded(child: _Field(label: '発注点', child: TextFormField(
                      controller: _reorderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '5'),
                    ))),
                    const SizedBox(width: 12),
                    Expanded(child: _Field(label: '最低在庫', child: TextFormField(
                      controller: _minStockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '2'),
                    ))),
                  ]),

                  const SizedBox(height: 8),

                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? '更新する' : '登録する'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final now = DateTime.now().toIso8601String();
    final companion = ProductsCompanion(
      id: widget.existing != null
          ? Value(widget.existing!.id)
          : Value(_uuid.v4()),
      categoryId: Value(_categoryId),
      name: Value(_nameCtrl.text.trim()),
      sku: Value(_skuCtrl.text.trim().isEmpty ? null : _skuCtrl.text.trim()),
      unit: Value(_unitCtrl.text.trim().isEmpty ? '個' : _unitCtrl.text.trim()),
      retailPrice: Value(int.tryParse(_retailPriceCtrl.text.trim()) ?? 0),
      costPrice: Value(int.tryParse(_costPriceCtrl.text.trim()) ?? 0),
      stockQuantity: Value(int.tryParse(_stockCtrl.text.trim()) ?? 0),
      reorderPoint: Value(int.tryParse(_reorderCtrl.text.trim()) ?? 0),
      minStock: Value(int.tryParse(_minStockCtrl.text.trim()) ?? 0),
      productType: Value(_productType),
      updatedAt: Value(now),
    );

    try {
      final notifier = ref.read(inventoryNotifierProvider.notifier);
      if (widget.existing != null) {
        await notifier.updateProduct(widget.existing!.id, companion);
      } else {
        await notifier.addProduct(companion);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    }
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('商品を削除'),
        content: Text('「${widget.existing!.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref
          .read(inventoryNotifierProvider.notifier)
          .deactivateProduct(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.label
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.showLowStock});
  final bool showLowStock;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            showLowStock
                ? Icons.check_circle_outline
                : Icons.inventory_2_outlined,
            size: 64,
            color: AppColors.border,
          ),
          const SizedBox(height: 12),
          Text(
            showLowStock ? '在庫不足の商品はありません' : '商品がありません',
            style: AppTextStyles.body1
                .copyWith(color: AppColors.textSecondary),
          ),
          if (!showLowStock) ...[
            const SizedBox(height: 8),
            Text('右上の＋から商品を追加してください',
                style: AppTextStyles.body2
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

// ─── 유틸 ─────────────────────────────────────────────────────────────────
String _fmt(int n) {
  if (n >= 1000) {
    return n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }
  return n.toString();
}
