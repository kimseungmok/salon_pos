import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── セットメニュー一覧 Provider ──────────────────────────────────────────────
final _bundlesProvider = StreamProvider<List<MenuBundle>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menuBundles)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── セットメニューのアイテム一覧 ──────────────────────────────────────────────
final _bundleItemsProvider =
    FutureProvider.family<List<MenusData>, String>((ref, bundleId) async {
  final db = ref.watch(databaseProvider);
  final items = await (db.select(db.menuBundleItems)
        ..where((t) => t.bundleId.equals(bundleId))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .get();
  final menus = <MenusData>[];
  for (final item in items) {
    final m = await (db.select(db.menus)
          ..where((t) => t.id.equals(item.menuId)))
        .getSingleOrNull();
    if (m != null) menus.add(m);
  }
  return menus;
});

// ─── 全メニュー一覧 (セット編集時の選択肢) ────────────────────────────────────
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
                padding: const EdgeInsets.all(16),
                itemCount: bundles.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
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
      builder: (_) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 560,
          child: _BundleFormSheet(bundle: bundle),
        ),
      ),
    );
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, MenuBundle bundle) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
          .write(const MenuBundlesCompanion(
              isActive: Value(false)));
    }
  }
}

// ─── セットメニューカード ────────────────────────────────────────────────────
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('セット',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(bundle.name,
                      style: AppTextStyles.h4,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (bundle.bundlePrice != null)
                  Text('¥${_fmt(bundle.bundlePrice!)}',
                      style: AppTextStyles.h4
                          .copyWith(color: AppColors.primary))
                else if (bundle.discountRate > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${bundle.discountRate}%OFF',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.error)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            itemsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (menus) => menus.isEmpty
                  ? Text('メニュー未設定',
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textDisabled))
                  : Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: menus
                          .map((m) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Text(m.name,
                                    style: AppTextStyles.caption),
                              ))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('編集'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(fontSize: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('削除'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    textStyle: const TextStyle(fontSize: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  late final _priceCtrl = TextEditingController(
      text: widget.bundle?.bundlePrice?.toString() ?? '');
  late int _discountRate = widget.bundle?.discountRate ?? 0;
  final Set<String> _selectedMenuIds = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.bundle != null) {
      _loadExistingItems();
    }
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
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allMenusAsync = ref.watch(_allMenusForBundleProvider);
    final isNew = widget.bundle == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ヘッダー
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
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
        // フォーム
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // セット名
                  _Label('セット名'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      hintText: '例: カット+カラーセット',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '名前を入力してください'
                        : null,
                  ),
                  const SizedBox(height: 16),

                  // セット価格
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('セット価格（円）'),
                            const SizedBox(height: 4),
                            Text('※空白の場合は合計金額から割引率を適用',
                                style: AppTextStyles.caption
                                    .copyWith(color: AppColors.textDisabled)),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _priceCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                hintText: '例: 8000',
                                prefixText: '¥',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
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
                            _Label('割引率 ($_discountRate%)'),
                            Slider(
                              value: _discountRate.toDouble(),
                              min: 0,
                              max: 50,
                              divisions: 50,
                              label: '$_discountRate%',
                              onChanged: (v) =>
                                  setState(() => _discountRate = v.round()),
                              activeColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // メニュー選択
                  _Label('含まれるメニュー'),
                  const SizedBox(height: 8),
                  allMenusAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) =>
                        Text('$e', style: const TextStyle(color: AppColors.error)),
                    data: (menus) => Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: menus.length,
                        itemBuilder: (_, i) {
                          final m = menus[i];
                          return CheckboxListTile(
                            value: _selectedMenuIds.contains(m.id),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedMenuIds.add(m.id);
                                } else {
                                  _selectedMenuIds.remove(m.id);
                                }
                              });
                            },
                            title: Text(m.name, style: AppTextStyles.body2),
                            subtitle: Text('¥${_fmt(m.price)}',
                                style: AppTextStyles.caption),
                            dense: true,
                            activeColor: AppColors.primary,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 保存ボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        textStyle: AppTextStyles.label.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('保存'),
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
      final price = int.tryParse(_priceCtrl.text.trim());
      String bundleId;

      if (widget.bundle == null) {
        bundleId = const Uuid().v4();
        await db.into(db.menuBundles).insert(MenuBundlesCompanion.insert(
          id: bundleId,
          name: name,
          bundlePrice: Value(price),
          discountRate: Value(_discountRate),
        ));
      } else {
        bundleId = widget.bundle!.id;
        await (db.update(db.menuBundles)
              ..where((t) => t.id.equals(bundleId)))
            .write(MenuBundlesCompanion(
          name: Value(name),
          bundlePrice: Value(price),
          discountRate: Value(_discountRate),
        ));
        // 기존 아이템 삭제
        await (db.delete(db.menuBundleItems)
              ..where((t) => t.bundleId.equals(bundleId)))
            .go();
      }

      // 새 아이템 저장
      int order = 0;
      for (final menuId in _selectedMenuIds) {
        await db.into(db.menuBundleItems).insert(MenuBundleItemsCompanion.insert(
          id: const Uuid().v4(),
          bundleId: bundleId,
          menuId: menuId,
          sortOrder: Value(order++),
        ));
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppTextStyles.label
          .copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.view_module_outlined,
              size: 64, color: AppColors.border),
          const SizedBox(height: 16),
          Text('セットメニューはまだありません',
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text(
            '複数のメニューをセットにして\n特別価格や割引を設定できます。',
            textAlign: TextAlign.center,
            style:
                AppTextStyles.body2.copyWith(color: AppColors.textDisabled),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add),
            label: const Text('セットメニューを作成'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
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
