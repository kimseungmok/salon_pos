import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

const _uuid = Uuid();

// ─── Providers ────────────────────────────────────────────────────────────
final _categoriesProvider = StreamProvider<List<MenuCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.menuCategories)
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder),
                   (t) => OrderingTerm.asc(t.name)]))
      .watch();
});

final _selectedCategoryIdProvider = StateProvider<String?>((ref) => null);

// 이달 인기 메뉴 ID TOP5
final _topMenuIdsProvider = FutureProvider<Set<String>>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  final prefix = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-';
  // 이달 매출 ID 조회
  final sales = await (db.select(db.sales)
        ..where((t) => t.saleDate.like('$prefix%')))
      .get();
  if (sales.isEmpty) return {};
  final saleIds = sales.map((s) => s.id).toList();
  // 해당 매출의 아이템 조회
  final items = await (db.select(db.saleItems)
        ..where((t) => t.saleId.isIn(saleIds)))
      .get();
  final counts = <String, int>{};
  for (final i in items) {
    if (i.refId != null && i.itemType == 'menu') {
      counts[i.refId!] = (counts[i.refId!] ?? 0) + i.quantity;
    }
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).map((e) => e.key).toSet();
});

final _menusForCategoryProvider =
    StreamProvider.family<List<MenusData>, String?>((ref, catId) {
  final db = ref.watch(databaseProvider);
  final q = db.select(db.menus);
  if (catId != null) {
    q.where((t) => t.categoryId.equals(catId));
  } else {
    q.where((t) => t.categoryId.isNull());
  }
  q.orderBy([
    (t) => OrderingTerm.asc(t.sortOrder),
    (t) => OrderingTerm.asc(t.name),
  ]);
  return q.watch();
});

// ─── 메뉴관리 화면 ────────────────────────────────────────────────────────
class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(_categoriesProvider);
    final selectedId = ref.watch(_selectedCategoryIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('メニュー管理'),
        actions: [
          TextButton.icon(
            onPressed: () => _showCategoryForm(context, ref, null),
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('カテゴリ追加'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // ─ 카테고리 패널 (좌측) ─────────────────────────────────────
          Container(
            width: 200,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: catsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (cats) {
                // 첫 번째 카테고리 자동 선택
                if (selectedId == null && cats.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(_selectedCategoryIdProvider.notifier).state =
                        cats.first.id;
                  });
                }
                return ListView(
                  children: [
                    ...cats.map((c) => _CategoryTile(
                          cat: c,
                          selected: c.id == selectedId,
                          onTap: () => ref
                              .read(_selectedCategoryIdProvider.notifier)
                              .state = c.id,
                          onEdit: () =>
                              _showCategoryForm(context, ref, c),
                          onDelete: () =>
                              _deleteCategory(context, ref, c),
                        )),
                  ],
                );
              },
            ),
          ),

          // ─ 메뉴 리스트 (우측) ────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // 메뉴 추가 버튼
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  color: AppColors.surface,
                  child: Row(
                    children: [
                      catsAsync.maybeWhen(
                        data: (cats) {
                          final cat = cats
                              .where((c) => c.id == selectedId)
                              .firstOrNull;
                          return Text(
                            cat?.name ?? 'カテゴリ未選択',
                            style: AppTextStyles.h3,
                          );
                        },
                        orElse: () => const SizedBox.shrink(),
                      ),
                      const Spacer(),
                      if (selectedId != null)
                        OutlinedButton.icon(
                          onPressed: () =>
                              _showBulkPriceDialog(context, ref, selectedId!),
                          icon: const Icon(Icons.percent_outlined, size: 16),
                          label: const Text('一括価格変更'),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: selectedId == null
                            ? null
                            : () => _showMenuForm(
                                context, ref, selectedId, null),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('メニュー追加'),
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 36)),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 메뉴 목록
                Expanded(
                  child: selectedId == null
                      ? const Center(
                          child: Text('カテゴリを選択してください',
                              style: TextStyle(
                                  color: AppColors.textSecondary)))
                      : _MenuList(categoryId: selectedId),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 카테고리 삭제 ─────────────────────────────────────────────────────
  Future<void> _deleteCategory(
      BuildContext context, WidgetRef ref, MenuCategory cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('カテゴリを削除'),
        content: Text('「${cat.name}」を削除しますか？\n配下のメニューも削除されます。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final db = ref.read(databaseProvider);
    // 배하 메뉴 먼저 삭제
    await (db.delete(db.menus)
          ..where((t) => t.categoryId.equals(cat.id)))
        .go();
    await (db.delete(db.menuCategories)
          ..where((t) => t.id.equals(cat.id)))
        .go();
    ref.read(_selectedCategoryIdProvider.notifier).state = null;
  }

  // ─── 카테고리 폼 ───────────────────────────────────────────────────────
  // ─── 일괄 가격 변경 다이얼로그 ────────────────────────────────────────────
  Future<void> _showBulkPriceDialog(
      BuildContext context, WidgetRef ref, String categoryId) async {
    final ctrl = TextEditingController();
    bool isPercent = true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('一括価格変更'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('このカテゴリのすべてのメニュー価格を変更します',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('%変更'),
                      selected: isPercent,
                      onSelected: (_) => setState(() => isPercent = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('円変更'),
                      selected: !isPercent,
                      onSelected: (_) => setState(() => isPercent = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  labelText: isPercent ? '変更率 (例: +10, -5)' : '変更額 (例: +500, -100)',
                  suffixText: isPercent ? '%' : '円',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル')),
            FilledButton(
              onPressed: () async {
                final val = double.tryParse(ctrl.text.trim());
                if (val == null) return;
                final db = ref.read(databaseProvider);
                final menus = await (db.select(db.menus)
                      ..where((t) => t.categoryId.equals(categoryId) & t.isActive.equals(true)))
                    .get();
                for (final m in menus) {
                  final newPrice = isPercent
                      ? (m.price * (1 + val / 100)).round()
                      : (m.price + val.round());
                  if (newPrice > 0) {
                    await (db.update(db.menus)..where((t) => t.id.equals(m.id)))
                        .write(MenusCompanion(price: Value(newPrice)));
                  }
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('適用'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
  }

  Future<void> _showCategoryForm(BuildContext context, WidgetRef ref,
      MenuCategory? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _CategoryFormSheet(existing: existing),
      ),
    );
  }

  // ─── 메뉴 폼 ──────────────────────────────────────────────────────────
  Future<void> _showMenuForm(BuildContext context, WidgetRef ref,
      String categoryId, MenusData? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _MenuFormSheet(categoryId: categoryId, existing: existing),
      ),
    );
  }
}

// ─── 카테고리 타일 ────────────────────────────────────────────────────────
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.cat,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });
  final MenuCategory cat;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(cat.color);
    return Container(
      color: selected ? AppColors.primary.withValues(alpha: 0.08) : null,
      child: ListTile(
        dense: true,
        leading: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        title: Text(
          cat.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
        selected: selected,
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          iconSize: 18,
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('編集')),
            const PopupMenuItem(
                value: 'delete',
                child: Text('削除', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }
}

// ─── 메뉴 리스트 ──────────────────────────────────────────────────────────
class _MenuList extends ConsumerWidget {
  const _MenuList({required this.categoryId});
  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menusAsync = ref.watch(_menusForCategoryProvider(categoryId));

    return menusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (menus) => menus.isEmpty
          ? const Center(
              child: Text('メニューがありません',
                  style: TextStyle(color: AppColors.textSecondary)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: menus.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final topIds = ref.watch(_topMenuIdsProvider).valueOrNull ?? {};
                return _MenuCard(
                  menu: menus[i],
                  isPopular: topIds.contains(menus[i].id),
                  onEdit: () => _showMenuForm(ctx, ref, categoryId, menus[i]),
                  onToggle: () => _toggleMenu(ref, menus[i]),
                  onDelete: () => _deleteMenu(ctx, ref, menus[i]),
                  onDuplicate: () => _duplicateMenu(ref, menus[i]),
                );
              },
            ),
    );
  }

  Future<void> _toggleMenu(WidgetRef ref, MenusData menu) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.menus)..where((t) => t.id.equals(menu.id)))
        .write(MenusCompanion(isActive: Value(!menu.isActive)));
  }

  Future<void> _deleteMenu(
      BuildContext context, WidgetRef ref, MenusData menu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('メニューを削除'),
        content: Text('「${menu.name}」を削除しますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await (db.delete(db.menus)..where((t) => t.id.equals(menu.id))).go();
  }

  Future<void> _duplicateMenu(WidgetRef ref, MenusData menu) async {
    final db = ref.read(databaseProvider);
    await db.into(db.menus).insert(MenusCompanion(
      id: Value(const Uuid().v4()),
      categoryId: Value(menu.categoryId),
      name: Value('${menu.name} (コピー)'),
      price: Value(menu.price),
      durationMin: Value(menu.durationMin),
      processingMin: Value(menu.processingMin),
      bufferMin: Value(menu.bufferMin),
      taxType: Value(menu.taxType),
      color: Value(menu.color),
      description: Value(menu.description),
      sortOrder: Value(menu.sortOrder),
      isActive: Value(menu.isActive),
    ));
  }

  Future<void> _showMenuForm(BuildContext context, WidgetRef ref,
      String catId, MenusData? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: _MenuFormSheet(categoryId: catId, existing: existing),
      ),
    );
  }
}

// ─── 메뉴 카드 ────────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.menu,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    this.onDuplicate,
    this.isPopular = false,
  });
  final MenusData menu;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback? onDuplicate;
  final bool isPopular;

  @override
  Widget build(BuildContext context) {
    final color = menu.color != null ? _parseColor(menu.color!) : AppColors.primary;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // 색상 바
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            // 메뉴 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        menu.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: menu.isActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (isPopular)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3CD),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFFFD700)),
                          ),
                          child: const Text('🔥人気',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8B6914))),
                        ),
                      if (!menu.isActive)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('非表示',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _InfoChip(
                          icon: Icons.payments_outlined,
                          label:
                              '¥${menu.price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}'),
                      const SizedBox(width: 8),
                      _InfoChip(
                          icon: Icons.schedule_outlined,
                          label: '${menu.durationMin}分'),
                      if (menu.processingMin > 0) ...[
                        const SizedBox(width: 8),
                        _InfoChip(
                            icon: Icons.hourglass_empty,
                            label: '発色${menu.processingMin}分',
                            color: const Color(0xFF8B5CF6)),
                      ],
                      const SizedBox(width: 8),
                      _InfoChip(
                          icon: Icons.percent,
                          label: menu.taxType == 'exempt'
                              ? '非課税'
                              : '${menu.taxType}%'),
                    ],
                  ),
                ],
              ),
            ),
            // 액션
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'toggle') onToggle();
                if (v == 'delete') onDelete();
                if (v == 'duplicate') onDuplicate?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('編集')),
                const PopupMenuItem(
                    value: 'duplicate',
                    child: Row(children: [
                      Icon(Icons.copy_outlined, size: 14),
                      SizedBox(width: 6),
                      Text('複製'),
                    ])),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(menu.isActive ? '非表示にする' : '表示する'),
                ),
                const PopupMenuItem(
                    value: 'delete',
                    child: Text('削除', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(
      {required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: c)),
      ],
    );
  }
}

// ─── 카테고리 폼 시트 ─────────────────────────────────────────────────────
class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({this.existing});
  final MenuCategory? existing;

  @override
  ConsumerState<_CategoryFormSheet> createState() =>
      _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  late TextEditingController _nameCtrl;
  String _color = '#0064FF';
  bool _saving = false;

  static const _presetColors = [
    '#0064FF', '#00B746', '#FFB300', '#F04452',
    '#8B5CF6', '#EC4899', '#06B6D4', '#F97316',
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.existing?.name ?? '');
    _color = widget.existing?.color ?? '#0064FF';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'カテゴリを編集' : 'カテゴリを追加',
                style: AppTextStyles.h3),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'カテゴリ名'),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Text('カラー', style: AppTextStyles.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _presetColors.map((c) {
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _parseColor(c),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: AppColors.textPrimary, width: 3)
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check,
                            size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中...' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    if (widget.existing != null) {
      await (db.update(db.menuCategories)
            ..where((t) => t.id.equals(widget.existing!.id)))
          .write(MenuCategoriesCompanion(
        name: Value(name),
        color: Value(_color),
      ));
    } else {
      await db.into(db.menuCategories).insert(MenuCategoriesCompanion.insert(
        id: _uuid.v4(),
        name: name,
        color: Value(_color),
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}

// ─── 메뉴 폼 시트 ─────────────────────────────────────────────────────────
class _MenuFormSheet extends ConsumerStatefulWidget {
  const _MenuFormSheet(
      {required this.categoryId, this.existing});
  final String categoryId;
  final MenusData? existing;

  @override
  ConsumerState<_MenuFormSheet> createState() => _MenuFormSheetState();
}

class _MenuFormSheetState extends ConsumerState<_MenuFormSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _durationCtrl;
  late TextEditingController _processingCtrl;
  late TextEditingController _bufferCtrl;
  String _taxType = '10';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl =
        TextEditingController(text: e != null ? '${e.price}' : '');
    _durationCtrl =
        TextEditingController(text: e != null ? '${e.durationMin}' : '60');
    _processingCtrl = TextEditingController(
        text: e != null ? '${e.processingMin}' : '0');
    _bufferCtrl =
        TextEditingController(text: e != null ? '${e.bufferMin}' : '0');
    _taxType = e?.taxType ?? '10';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    _processingCtrl.dispose();
    _bufferCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isEdit ? 'メニューを編集' : 'メニューを追加',
                  style: AppTextStyles.h3),
              const SizedBox(height: 16),
              // 메뉴명
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'メニュー名 *'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              // 가격 + 시술 시간
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      decoration:
                          const InputDecoration(labelText: '価格 (¥) *'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _durationCtrl,
                      decoration:
                          const InputDecoration(labelText: '施術時間 (分)'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 발색 시간 + 버퍼 시간
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _processingCtrl,
                      decoration: const InputDecoration(
                        labelText: '発色待ち (分)',
                        helperText: 'スタッフ離席可能な待ち時間',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _bufferCtrl,
                      decoration: const InputDecoration(
                        labelText: 'バッファ (分)',
                        helperText: '片付け・準備時間',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 세금
              Text('税率', style: AppTextStyles.label),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '10', label: Text('10%')),
                  ButtonSegment(value: '8', label: Text('8% (軽減)')),
                  ButtonSegment(value: 'exempt', label: Text('非課税')),
                ],
                selected: {_taxType},
                onSelectionChanged: (s) =>
                    setState(() => _taxType = s.first),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中...' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text) ?? 0;
    final duration = int.tryParse(_durationCtrl.text) ?? 60;
    final processing = int.tryParse(_processingCtrl.text) ?? 0;
    final buffer = int.tryParse(_bufferCtrl.text) ?? 0;
    if (name.isEmpty) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);

    if (widget.existing != null) {
      await (db.update(db.menus)
            ..where((t) => t.id.equals(widget.existing!.id)))
          .write(MenusCompanion(
        name: Value(name),
        price: Value(price),
        durationMin: Value(duration),
        processingMin: Value(processing),
        bufferMin: Value(buffer),
        taxType: Value(_taxType),
      ));
    } else {
      await db.into(db.menus).insert(MenusCompanion.insert(
        id: _uuid.v4(),
        name: name,
        price: price,
        durationMin: Value(duration),
        processingMin: Value(processing),
        bufferMin: Value(buffer),
        taxType: Value(_taxType),
        categoryId: Value(widget.categoryId),
      ));
    }
    if (mounted) Navigator.pop(context);
  }
}

// ─── 색상 파싱 ────────────────────────────────────────────────────────────
Color _parseColor(String hex) {
  try {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}
