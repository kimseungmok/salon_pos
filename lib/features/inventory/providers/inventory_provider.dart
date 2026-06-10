import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

const _uuid = Uuid();

// ─── 카테고리 목록 ────────────────────────────────────────────────────────
final productCategoriesProvider = StreamProvider<List<ProductCategory>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.productCategories)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();
});

// ─── 상품 목록 (카테고리 필터) ────────────────────────────────────────────
final productsProvider =
    StreamProvider.family<List<Product>, String?>((ref, categoryId) {
  final db = ref.watch(databaseProvider);
  final q = db.select(db.products)
    ..where((t) => t.isActive.equals(true));
  if (categoryId != null) {
    q.where((t) => t.categoryId.equals(categoryId));
  }
  q.orderBy([(t) => OrderingTerm.asc(t.name)]);
  return q.watch();
});

// ─── 부족재고 상품 목록 ───────────────────────────────────────────────────
final lowStockProductsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((t) =>
            t.isActive.equals(true) &
            CustomExpression<bool>('stock_quantity <= reorder_point AND reorder_point > 0'))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

// ─── 재고 이동 기록 (최근 30건) ───────────────────────────────────────────
final recentMovementsProvider =
    StreamProvider.family<List<InventoryMovement>, String>((ref, productId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.inventoryMovements)
        ..where((t) => t.productId.equals(productId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(30))
      .watch();
});

// ─── 재고 조정 Notifier ────────────────────────────────────────────────────
class InventoryNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// 재고 수량 직접 조정 (adjustment)
  Future<void> adjustStock({
    required String productId,
    required int delta,
    required String type, // purchase|adjustment|loss|return|initial
    String? notes,
    String? staffId,
  }) async {
    final db = ref.read(databaseProvider);
    // 현재 재고
    final product = await (db.select(db.products)
          ..where((t) => t.id.equals(productId)))
        .getSingleOrNull();
    if (product == null) return;

    final newStock = (product.stockQuantity + delta).clamp(0, 999999);
    final now = DateTime.now().toIso8601String();

    await db.batch((b) {
      // 재고 업데이트
      b.update(
        db.products,
        ProductsCompanion(
          stockQuantity: Value(newStock),
          updatedAt: Value(now),
        ),
        where: (t) => t.id.equals(productId),
      );
      // 이동 기록 추가
      b.insert(
        db.inventoryMovements,
        InventoryMovementsCompanion(
          id: Value(_uuid.v4()),
          productId: Value(productId),
          movementType: Value(type),
          quantity: Value(delta),
          stockAfter: Value(newStock),
          staffId: Value(staffId),
          notes: Value(notes),
          createdAt: Value(now),
        ),
      );
    });
  }

  /// 상품 추가
  Future<void> addProduct(ProductsCompanion companion) async {
    final db = ref.read(databaseProvider);
    await db.into(db.products).insert(companion);
  }

  /// 상품 수정
  Future<void> updateProduct(String id, ProductsCompanion companion) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.products)..where((t) => t.id.equals(id)))
        .write(companion);
  }

  /// 상품 비활성화 (삭제)
  Future<void> deactivateProduct(String id) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }

  /// 카테고리 추가
  Future<void> addCategory(String name) async {
    final db = ref.read(databaseProvider);
    final count = await db.select(db.productCategories).get();
    await db.into(db.productCategories).insert(ProductCategoriesCompanion(
          id: Value(_uuid.v4()),
          name: Value(name),
          sortOrder: Value(count.length),
        ));
  }
}

final inventoryNotifierProvider =
    AsyncNotifierProvider<InventoryNotifier, void>(InventoryNotifier.new);
