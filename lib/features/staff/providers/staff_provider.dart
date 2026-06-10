import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

const _uuid = Uuid();

// ─── 스태프 목록 ──────────────────────────────────────────────────────────
final staffListProvider = StreamProvider<List<StaffData>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.staff)
        ..where((t) => t.isActive.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch();
});

// ─── 스태프 Notifier ──────────────────────────────────────────────────────
class StaffNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> addStaff(StaffCompanion companion) async {
    final db = ref.read(databaseProvider);
    await db.into(db.staff).insert(companion);
  }

  Future<void> updateStaff(String id, StaffCompanion companion) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.staff)..where((t) => t.id.equals(id))).write(companion);
  }

  Future<void> deactivateStaff(String id) async {
    final db = ref.read(databaseProvider);
    await (db.update(db.staff)..where((t) => t.id.equals(id))).write(
      StaffCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now().toIso8601String()),
      ),
    );
  }
}

final staffNotifierProvider =
    AsyncNotifierProvider<StaffNotifier, void>(StaffNotifier.new);

// ─── 역할 라벨 ─────────────────────────────────────────────────────────────
const staffRoles = [
  ('owner', 'オーナー'),
  ('manager', 'マネージャー'),
  ('stylist', 'スタイリスト'),
  ('assistant', 'アシスタント'),
  ('reception', 'レセプション'),
];

String roleLabel(String role) =>
    staffRoles.firstWhere((r) => r.$1 == role, orElse: () => (role, role)).$2;

// ─── 스태프 색상 팔레트 ────────────────────────────────────────────────────
const staffColorOptions = [
  '#0064FF', '#00B746', '#F5A623', '#F04452', '#6366F1',
  '#EC4899', '#14B8A6', '#F97316', '#8B5CF6', '#64748B',
];

// ─── UUID 생성 ─────────────────────────────────────────────────────────────
String newStaffId() => _uuid.v4();
