import 'package:go_router/go_router.dart';
import '../../../../core/router/app_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── Providers ───────────────────────────────────────────────────────────────
final _bundlesProvider = StreamProvider<List<MenuBundle>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menuBundles)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

final _bundleItemsProvider =
    FutureProvider.family<List<MenusData>, String>((ref, bundleId) async {
  final db = ref.watch(databaseProvider);
  final items = await (db.select(db.menuBundleItems)
        ..where((t) => t.bundleId.equals(bundleId))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .get();
  if (items.isEmpty) return [];
  final menuIds = items.map((i) => i.menuId).toList();
  final menus = await (db.select(db.menus)
        ..where((t) => t.id.isIn(menuIds)))
      .get();
  // sortOrder 순서대로 정렬
  final menuMap = {for (final m in menus) m.id: m};
  return items
      .map((i) => menuMap[i.menuId])
      .whereType<MenusData>()
      .toList();
});

final _allMenusForBundleProvider = FutureProvider<List<MenusData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menus)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
});

// ─── セットメニュー管理画面 ──────────────────────────────────────────────────
class MenuBundleScreen extends ConsumerWidget {
  const MenuBundleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundlesAsync = ref.watch(_bundlesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('セットメニュー管理'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _showForm(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新規作成'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
      body: bundlesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (bundles) => bundles.isEmpty
            ? _EmptyState(onTap: () => _showForm(context, ref, null))
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: bundles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => _BundleCard(
                  bundle: bundles[i],
                  onEdit: () => _showForm(context, ref, bundles[i]),
                  onDelete: () => _delete(context, ref, bundles[i]),
                ),
              ),
      ),
    );
  }

  void _showForm(BuildContext context, WidgetRef ref, MenuBundle? bundle) {
    showDialog(
      context: context,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: SizedBox(
            width: 580,
            child: _BundleFormSheet(bundle: bundle),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, MenuBundle bundle) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('削除確認'),
        content: Text('「${bundle.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok == true) {
      final db = ref.read(databaseProvider);
      await (db.update(db.menuBundles)
            ..where((t) => t.id.equals(bundle.id)))
          .write(const MenuBundlesCompanion(isActive: Value(false)));
    }
  }
}

// ─── セットメニューカード (トスプレイス風) ─────────────────────────────────────
class _BundleCard extends ConsumerWidget {
  const _BundleCard({
    required this.bundle,
    required this.onEdit,
    required this.onDelete,
  });
  final MenuBundle bundle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(_bundleItemsProvider(bundle.id));
    final hasDiscount = bundle.discountRate > 0;
    final hasFixedPrice = bundle.bundlePrice != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 이름 + 가격/할인 배지 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // セットバッジ
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('セット',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.3)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(bundle.name,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                // 가격 / 할인 배지
                if (hasFixedPrice)
                  _PriceBadge(
                    label: '¥${_fmt(bundle.bundlePrice!)}',
                    color: AppColors.primary,
                    bg: AppColors.primary.withValues(alpha: 0.08),
                  )
                else if (hasDiscount)
                  _PriceBadge(
                    label: '${bundle.discountRate}% OFF',
                    color: const Color(0xFFE04444),
                    bg: const Color(0xFFFFF0F0),
                  ),
              ],
            ),
          ),

          // ── 구분선 ──
          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── 포함 메뉴 칩 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: itemsAsync.when(
              loading: () => const SizedBox(
                height: 20,
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (menus) => menus.isEmpty
                  ? Text('メニュー未設定',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textDisabled))
                  : _MenuChips(menus: menus),
            ),
          ),

          // ── 하단: 설명 + 액션 버튼 ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Row(
              children: [
                if (bundle.description != null &&
                    bundle.description!.isNotEmpty) ...[
                  Expanded(
                    child: Text(bundle.description!,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ] else
                  const Spacer(),
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: '編集',
                  color: AppColors.primary,
                  onTap: onEdit,
                ),
                const SizedBox(width: 4),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: '削除',
                  color: AppColors.error,
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge(
      {required this.label, required this.color, required this.bg});
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color)),
      );
}

class _MenuChips extends StatelessWidget {
  const _MenuChips({required this.menus});
  final List<MenusData> menus;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: menus.map((m) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6FA),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.name,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
              const SizedBox(width: 4),
              Text('¥${_fmt(m.price)}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
}

// ─── セットメニューフォーム ───────────────────────────────────────────────────
class _BundleFormSheet extends ConsumerStatefulWidget {
  const _BundleFormSheet({this.bundle});
  final MenuBundle? bundle;

  @override
  ConsumerState<_BundleFormSheet> createState() => _BundleFormSheetState();
}

class _BundleFormSheetState extends ConsumerState<_BundleFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl =
      TextEditingController(text: widget.bundle?.name ?? '');
  late final _descCtrl =
      TextEditingController(text: widget.bundle?.description ?? '');
  late final _priceCtrl = TextEditingController(
      text: widget.bundle?.bundlePrice?.toString() ?? '');
  late int _discountRate = widget.bundle?.discountRate ?? 0;
  final Set<String> _selectedMenuIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.bundle != null) _loadExistingItems();
  }

  Future<void> _loadExistingItems() async {
    final db = ref.read(databaseProvider);
    final items = await (db.select(db.menuBundleItems)
          ..where((t) => t.bundleId.equals(widget.bundle!.id)))
        .get();
    setState(() {
      _selectedMenuIds.addAll(items.map((i) => i.menuId));
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  // 선택한 메뉴들의 합계 가격 계산
  int _calcTotal(List<MenusData> allMenus) {
    return allMenus
        .where((m) => _selectedMenuIds.contains(m.id))
        .fold(0, (sum, m) => sum + m.price);
  }

  @override
  Widget build(BuildContext context) {
    final allMenusAsync = ref.watch(_allMenusForBundleProvider);
    final isNew = widget.bundle == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 헤더 ──
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(isNew ? 'セットメニュー新規作成' : 'セットメニュー編集',
                  style: AppTextStyles.h3),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textSecondary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),

        // ── 폼 ──
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // セット名
                  _FormLabel('セット名', required: true),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      hintText: '例: カット＋カラーセット',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '名前を入力してください'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  // 설명 (옵션)
                  _FormLabel('説明（任意）'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _descCtrl,
                    decoration: InputDecoration(
                      hintText: '例: 人気No.1のお得なセット',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 14),

                  // 가격 설정
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FormLabel('セット価格（円）'),
                            const SizedBox(height: 2),
                            Text('未入力の場合は割引率を適用',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textDisabled)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _priceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '例: 9,800',
                                prefixText: '¥ ',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FormLabel('割引率'),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: _discountRate > 0
                                  ? _discountRate.toString()
                                  : '',
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: '0',
                                suffixText: '%',
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                isDense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                              ),
                              onChanged: (v) => setState(() {
                                _discountRate =
                                    int.tryParse(v.trim()) ?? 0;
                                if (_discountRate < 0) _discountRate = 0;
                                if (_discountRate > 100)
                                  _discountRate = 100;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 메뉴 선택
                  allMenusAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('$e',
                        style: const TextStyle(
                            color: AppColors.error)),
                    data: (menus) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _FormLabel('含まれるメニュー'),
                            const Spacer(),
                            if (_selectedMenuIds.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_selectedMenuIds.length}個選択中  合計 ¥${_fmt(_calcTotal(menus))}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints:
                              const BoxConstraints(maxHeight: 220),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: menus.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 52),
                            itemBuilder: (_, i) {
                              final m = menus[i];
                              final selected =
                                  _selectedMenuIds.contains(m.id);
                              return InkWell(
                                onTap: () => setState(() {
                                  if (selected) {
                                    _selectedMenuIds.remove(m.id);
                                  } else {
                                    _selectedMenuIds.add(m.id);
                                  }
                                }),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                            milliseconds: 150),
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.primary
                                              : Colors.transparent,
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.primary
                                                : AppColors.border,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: selected
                                            ? const Icon(Icons.check,
                                                size: 14,
                                                color: Colors.white)
                                            : null,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(m.name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: AppColors.textPrimary,
                                            )),
                                      ),
                                      Text('¥${_fmt(m.price)}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: selected
                                                  ? AppColors.primary
                                                  : AppColors
                                                      .textSecondary)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('保存する'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final name = _nameCtrl.text.trim();
      final desc = _descCtrl.text.trim();
      final price = int.tryParse(_priceCtrl.text.trim());
      String bundleId;

      if (widget.bundle == null) {
        bundleId = const Uuid().v4();
        await db.into(db.menuBundles).insert(MenuBundlesCompanion.insert(
          id: bundleId,
          name: name,
          description: Value(desc.isEmpty ? null : desc),
          bundlePrice: Value(price),
          discountRate: Value(_discountRate),
        ));
      } else {
        bundleId = widget.bundle!.id;
        await (db.update(db.menuBundles)
              ..where((t) => t.id.equals(bundleId)))
            .write(MenuBundlesCompanion(
          name: Value(name),
          description: Value(desc.isEmpty ? null : desc),
          bundlePrice: Value(price),
          discountRate: Value(_discountRate),
        ));
        await (db.delete(db.menuBundleItems)
              ..where((t) => t.bundleId.equals(bundleId)))
            .go();
      }

      int order = 0;
      for (final menuId in _selectedMenuIds) {
        await db
            .into(db.menuBundleItems)
            .insert(MenuBundleItemsCompanion.insert(
              id: const Uuid().v4(),
              bundleId: bundleId,
              menuId: menuId,
              sortOrder: Value(order++),
            ));
      }

      if (mounted) {
        ref.invalidate(_bundleItemsProvider(bundleId));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── フォームラベル ────────────────────────────────────────────────────────────
class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text, {this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          if (required) ...[
            const SizedBox(width: 4),
            const Text('*',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.error)),
          ],
        ],
      );
}

// ─── 空白ステート ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.layers_outlined,
                size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          Text('セットメニューはまだありません',
              style: AppTextStyles.h4
                  .copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(
            '複数のメニューをまとめて\n特別価格・割引で提供できます。',
            textAlign: TextAlign.center,
            style: AppTextStyles.body2
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('セットメニューを作成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
