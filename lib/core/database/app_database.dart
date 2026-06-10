import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/master_tables.dart';
import 'tables/staff_tables.dart';
import 'tables/customer_tables.dart';
import 'tables/menu_booking_tables.dart';
import 'tables/pos_sales_tables.dart';
import 'tables/inventory_tables.dart';
import 'tables/finance_tables.dart';
import 'tables/marketing_sync_tables.dart';
import 'tables/extension_tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  // Master
  SalonSettings,
  AppVersions,
  PrinterSettings,
  AuditLogs,
  // Staff
  Staff,
  StaffMenuCommissions,
  StaffCommissionTiers,
  ShiftPatterns,
  Shifts,
  Attendance,
  PayrollPeriods,
  Payroll,
  // Customer
  Customers,
  CustomerTags,
  CustomerTagLinks,
  TreatmentRecords,
  MembershipPlans,
  CustomerMemberships,
  MembershipUsage,
  PointHistory,
  GiftCards,
  GiftCardTransactions,
  // Menu & Booking
  MenuCategories,
  Menus,
  MenuStaffPrices,
  MenuOptionGroups,
  MenuOptions,
  Resources,
  ResourceMenuLinks,
  Appointments,
  AppointmentMenus,
  Waitlist,
  DraftAppointments,
  // POS & Sales
  RegisterSessions,
  CashMovements,
  Discounts,
  Coupons,
  CouponUsage,
  Sales,
  SaleItems,
  SaleDiscounts,
  SalePayments,
  Refunds,
  RefundItems,
  RefundPayments,
  DraftSales,
  // Inventory
  ProductCategories,
  Suppliers,
  Products,
  InventoryMovements,
  PurchaseOrders,
  PurchaseOrderItems,
  StockCounts,
  StockCountItems,
  // Finance
  ExpenseCategories,
  Expenses,
  DailySummaries,
  MonthlySummaries,
  YearlySummaries,
  TaxPeriods,
  KpiTargets,
  // Marketing & Sync
  MessageTemplates,
  Campaigns,
  MessageLogs,
  AutomationRules,
  SyncQueue,
  Devices,
  // Extensions
  FavoriteMenus,
  MenuBundles,
  MenuBundleItems,
  LoyaltyTiers,
  StaffAlerts,
  ConsentFormTemplates,
  CustomerConsentForms,
  BlockedTimeTypes,
  BlockedTimes,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _initDefaults();
          await _seedTestData();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 → v2: 새 테이블 추가 + 컬럼 추가
            await m.createTable(favoriteMenus);
            await m.createTable(menuBundles);
            await m.createTable(menuBundleItems);
            await m.createTable(loyaltyTiers);
            await m.createTable(staffAlerts);
            await m.createTable(consentFormTemplates);
            await m.createTable(customerConsentForms);
            await m.createTable(blockedTimeTypes);
            await m.createTable(blockedTimes);
            // 기존 테이블 컬럼 추가
            await m.addColumn(menus, menus.processingMin);
            await m.addColumn(appointments, appointments.repeatGroupId);
            await m.addColumn(appointments, appointments.repeatRule);
            await m.addColumn(appointments, appointments.isRepeatParent);
            await m.addColumn(customers, customers.noShowCount);
            await m.addColumn(customers, customers.cancelCount);
            await m.addColumn(customers, customers.loyaltyTierId);
            await m.addColumn(customers, customers.loyaltyPointsTotal);
            await m.addColumn(sales, sales.tipAmount);
            await m.addColumn(saleItems, saleItems.discountType);
            await m.addColumn(saleItems, saleItems.discountValue);
            // 초기 데이터
            await _initBlockedTimeTypes();
            await _initLoyaltyTiers();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode=WAL');
          await customStatement('PRAGMA foreign_keys=ON');
          await customStatement('PRAGMA cache_size=-65536');
          await customStatement('PRAGMA synchronous=NORMAL');
          await customStatement('PRAGMA temp_store=MEMORY');
          await customStatement('PRAGMA mmap_size=268435456');
          if (details.wasCreated) {
            await _createIndexes();
          }
        },
      );

  // ─── 초기 데이터 ──────────────────────────────────────────────────────
  Future<void> _initDefaults() async {
    await into(salonSettings).insert(
      SalonSettingsCompanion.insert(salonName: 'サロン'),
    );
    await into(appVersions).insert(
      AppVersionsCompanion.insert(
        id: 'v0.2.0',
        version: '0.2.0',
        buildNumber: 2,
        releaseDate: DateTime.now().toIso8601String().substring(0, 10),
        isCurrent: const Value(true),
      ),
    );
    await into(devices).insert(
      DevicesCompanion.insert(id: 'device-A', deviceName: 'A', deviceType: 'ipad'),
    );

    // 기본 메뉴 카테고리
    final cats = [
      ('cat-1', 'カット', 1),
      ('cat-2', 'カラー', 2),
      ('cat-3', 'パーマ', 3),
      ('cat-4', 'トリートメント', 4),
      ('cat-5', 'スパ・ヘッドスパ', 5),
      ('cat-6', 'その他', 6),
    ];
    for (final (id, name, order) in cats) {
      await into(menuCategories).insert(MenuCategoriesCompanion.insert(
        id: id, name: name, sortOrder: Value(order),
      ));
    }

    // 기본 경비 카테고리
    final expCats = [
      ('exp-1', '消耗品費', '消耗品費', 1),
      ('exp-2', '水道光熱費', '水道光熱費', 2),
      ('exp-3', '家賃・地代', '地代家賃', 3),
      ('exp-4', '通信費', '通信費', 4),
      ('exp-5', '広告宣伝費', '広告宣伝費', 5),
      ('exp-6', '外注費', '外注費', 6),
      ('exp-7', '旅費交通費', '旅費交通費', 7),
      ('exp-8', 'その他', '雑費', 8),
    ];
    for (final (id, name, code, order) in expCats) {
      await into(expenseCategories).insert(ExpenseCategoriesCompanion.insert(
        id: id, name: name,
        nameJp: Value(name), accountCode: Value(code), sortOrder: Value(order),
      ));
    }

    await _initBlockedTimeTypes();
    await _initLoyaltyTiers();
    await _initMessageTemplates();
  }

  Future<void> _initBlockedTimeTypes() async {
    final types = [
      ('bt-1', '昼休み', 'lunch_dining', 60, true, '#F59E0B', 1),
      ('bt-2', '清掃・片付け', 'cleaning_services', 15, true, '#8B95A1', 2),
      ('bt-3', 'ミーティング', 'groups', 30, true, '#0064FF', 3),
      ('bt-4', '研修・勉強', 'school', 60, true, '#9B5CDB', 4),
      ('bt-5', '休憩', 'coffee', 15, false, '#00BFAE', 5),
    ];
    for (final (id, name, icon, mins, paid, color, order) in types) {
      await into(blockedTimeTypes).insert(BlockedTimeTypesCompanion.insert(
        id: id, name: name, nameJp: Value(name),
        iconName: Value(icon),
        defaultMinutes: Value(mins),
        isPaid: Value(paid),
        color: Value(color),
        sortOrder: Value(order),
      ));
    }
  }

  Future<void> _initMessageTemplates() async {
    final templates = [
      ('tmpl-1', 'ご予約リマインダー', 'reminder',
          '{{customer_name}} 様\n\n明日のご予約のご確認です。\n日時：{{date}} {{time}}\nスタッフ：{{staff_name}}\n\nご不明点はお気軽にご連絡ください。\nよろしくお願いいたします。'),
      ('tmpl-2', '来店後フォローアップ', 'followup',
          '{{customer_name}} 様\n\n先日はご来店いただきありがとうございました。\nいかがでしょうか？\n\nまたのご来店をお待ちしております。'),
      ('tmpl-3', 'お誕生日メッセージ', 'birthday',
          '{{customer_name}} 様\n\nお誕生日おめでとうございます🎂\n\n本日ご来店のお客様に特別割引をご用意しております。\nぜひこの機会にご来店ください。'),
      ('tmpl-4', '長期未来店 再来店促進', 'reactivation',
          '{{customer_name}} 様\n\nお久しぶりです。最後のご来店から{{days_since}}日が経ちました。\n\nいつもご利用ありがとうございます。またのご来店をお待ちしております。'),
      ('tmpl-5', 'キャンセルお礼', 'followup',
          '{{customer_name}} 様\n\nキャンセルのご連絡ありがとうございました。\n\n次回のご予約はいつでもお待ちしております。'),
    ];
    for (final (id, name, type, body) in templates) {
      await into(messageTemplates).insert(MessageTemplatesCompanion.insert(
        id: id, name: name,
        templateType: type,
        channel: 'line',
        body: body,
      ));
    }
  }

  Future<void> _initLoyaltyTiers() async {
    final tiers = [
      ('tier-1', 'ブロンズ', 0, 1, 0, '#CD7F32', 1),
      ('tier-2', 'シルバー', 50000, 2, 3, '#9EA5AD', 2),
      ('tier-3', 'ゴールド', 150000, 3, 5, '#F59E0B', 3),
      ('tier-4', 'プラチナ', 300000, 5, 10, '#6366F1', 4),
    ];
    for (final (id, name, minAmt, mult, disc, color, order) in tiers) {
      await into(loyaltyTiers).insert(LoyaltyTiersCompanion.insert(
        id: id, name: name, nameJp: Value(name),
        minAmount: Value(minAmt),
        pointRateMultiplier: Value(mult),
        discountRate: Value(disc),
        color: Value(color),
        sortOrder: Value(order),
      ));
    }
  }

  // ─── 성능 인덱스 ──────────────────────────────────────────────────────
  Future<void> _createIndexes() async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_sales_date_staff ON sales(sale_date, staff_id)',
      'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_sales_session ON sales(session_id)',
      'CREATE INDEX IF NOT EXISTS idx_apt_date_staff ON appointments(date(start_at), staff_id)',
      'CREATE INDEX IF NOT EXISTS idx_apt_date_status ON appointments(date(start_at), status)',
      'CREATE INDEX IF NOT EXISTS idx_apt_customer ON appointments(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_apt_repeat_group ON appointments(repeat_group_id)',
      'CREATE INDEX IF NOT EXISTS idx_treatment_customer ON treatment_records(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_treatment_staff ON treatment_records(staff_id)',
      'CREATE INDEX IF NOT EXISTS idx_inv_mov_product ON inventory_movements(product_id)',
      'CREATE INDEX IF NOT EXISTS idx_inv_mov_date ON inventory_movements(date(created_at))',
      'CREATE INDEX IF NOT EXISTS idx_expense_cat_date ON expenses(category_id, expense_date)',
      'CREATE INDEX IF NOT EXISTS idx_point_customer ON point_history(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_point_created ON point_history(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_msg_customer ON message_logs(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_msg_sent_at ON message_logs(sent_at)',
      'CREATE INDEX IF NOT EXISTS idx_membership_expiry ON customer_memberships(end_date, status)',
      'CREATE INDEX IF NOT EXISTS idx_po_date ON purchase_orders(order_date)',
      'CREATE INDEX IF NOT EXISTS idx_cash_mov_session ON cash_movements(session_id)',
      'CREATE INDEX IF NOT EXISTS idx_sync_status ON sync_queue(status, priority)',
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments(sale_id)',
      'CREATE INDEX IF NOT EXISTS idx_coupon_usage_customer ON coupon_usage(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_shifts_staff_date ON shifts(staff_id, shift_date)',
      'CREATE INDEX IF NOT EXISTS idx_attendance_staff_date ON attendance(staff_id, work_date)',
      'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone)',
      'CREATE INDEX IF NOT EXISTS idx_customers_name_kana ON customers(name_kana)',
      'CREATE INDEX IF NOT EXISTS idx_staff_alerts_customer ON staff_alerts(customer_id)',
      'CREATE INDEX IF NOT EXISTS idx_blocked_times_staff ON blocked_times(staff_id, start_at)',
      'CREATE INDEX IF NOT EXISTS idx_fav_menus_order ON favorite_menus(sort_order)',
    ];
    for (final sql in indexes) {
      await customStatement(sql);
    }
  }

  // ─── 테스트 데이터 시드 (5~8월) ──────────────────────────────────────
  Future<void> _seedTestData() async {
    // ── 스태프 5명 ──
    const staffList = [
      ('staff-1', '青木 隆志', 'アオキ タカシ', '#0064FF', 'owner'),
      ('staff-2', '佐藤 雪', 'サトウ ユキ', '#00BFAE', 'stylist'),
      ('staff-3', '田中 明子', 'タナカ アキコ', '#9B5CDB', 'stylist'),
      ('staff-4', '山田 健二', 'ヤマダ ケンジ', '#F59E0B', 'stylist'),
      ('staff-5', '伊藤 美穂', 'イトウ ミホ', '#E74C3C', 'stylist'),
    ];
    for (final (id, name, kana, color, role) in staffList) {
      await into(staff).insertOnConflictUpdate(StaffCompanion.insert(
        id: id, name: name, nameKana: Value(kana),
        color: Value(color), role: Value(role),
        isActive: const Value(true),
      ));
    }

    // ── 고객 10명 ──
    const custList = [
      ('cust-01', '山本 花子', 'ヤマモト ハナコ', 'female'),
      ('cust-02', '中村 太郎', 'ナカムラ タロウ', 'male'),
      ('cust-03', '小林 美咲', 'コバヤシ ミサキ', 'female'),
      ('cust-04', '加藤 悠斗', 'カトウ ユウト', 'male'),
      ('cust-05', '松本 さくら', 'マツモト サクラ', 'female'),
      ('cust-06', '井上 翔太', 'イノウエ ショウタ', 'male'),
      ('cust-07', '木村 あおい', 'キムラ アオイ', 'female'),
      ('cust-08', '橋本 大輝', 'ハシモト ダイキ', 'male'),
      ('cust-09', '清水 彩', 'シミズ アヤ', 'female'),
      ('cust-10', '斎藤 拓也', 'サイトウ タクヤ', 'male'),
    ];
    for (final (id, name, kana, gender) in custList) {
      await into(customers).insertOnConflictUpdate(CustomersCompanion.insert(
        id: id, name: name, nameKana: Value(kana), gender: Value(gender),
      ));
    }

    // ── 메뉴 5개 ──
    const menuList = [
      ('menu-1', 'cat-1', 'カット', 4500, 60, '#4CAF50'),
      ('menu-2', 'cat-2', 'カラー', 8500, 90, '#FF9800'),
      ('menu-3', 'cat-3', 'パーマ', 12000, 120, '#9C27B0'),
      ('menu-4', 'cat-4', 'トリートメント', 6000, 60, '#2196F3'),
      ('menu-5', 'cat-5', 'ヘッドスパ', 4000, 45, '#00BCD4'),
    ];
    for (final (id, catId, name, price, dur, color) in menuList) {
      await into(menus).insertOnConflictUpdate(MenusCompanion.insert(
        id: id, name: name, categoryId: Value(catId),
        price: price, durationMin: Value(dur), color: Value(color),
        isActive: const Value(true),
      ));
    }

    // ── 예약 데이터 (5~8월, 주 5~6일 × 다양한 시간) ──
    final aptsRaw = <(String, String, String, String, String, int, int, String)>[
      // (id, staffId, custId, menuId, dateStr, startHour, startMin, status)
      // ─ 5월 ─
      ('apt-001','staff-1','cust-01','menu-1','2026-05-07',10,0,'confirmed'),
      ('apt-002','staff-2','cust-02','menu-2','2026-05-07',11,0,'confirmed'),
      ('apt-003','staff-3','cust-03','menu-3','2026-05-07',14,0,'confirmed'),
      ('apt-004','staff-4','cust-04','menu-4','2026-05-08',10,30,'confirmed'),
      ('apt-005','staff-5','cust-05','menu-5','2026-05-08',13,0,'completed'),
      ('apt-006','staff-1','cust-06','menu-2','2026-05-08',15,0,'completed'),
      ('apt-007','staff-2','cust-07','menu-1','2026-05-09',9,30,'completed'),
      ('apt-008','staff-3','cust-08','menu-5','2026-05-09',11,0,'completed'),
      ('apt-009','staff-4','cust-09','menu-3','2026-05-09',13,30,'no_show'),
      ('apt-010','staff-5','cust-10','menu-1','2026-05-12',10,0,'confirmed'),
      ('apt-011','staff-1','cust-01','menu-4','2026-05-12',11,30,'confirmed'),
      ('apt-012','staff-2','cust-03','menu-2','2026-05-13',10,0,'confirmed'),
      ('apt-013','staff-3','cust-05','menu-1','2026-05-13',14,30,'confirmed'),
      ('apt-014','staff-4','cust-07','menu-5','2026-05-14',9,0,'confirmed'),
      ('apt-015','staff-5','cust-02','menu-3','2026-05-14',13,0,'confirmed'),
      ('apt-016','staff-1','cust-04','menu-1','2026-05-19',10,30,'confirmed'),
      ('apt-017','staff-2','cust-06','menu-4','2026-05-19',13,0,'confirmed'),
      ('apt-018','staff-3','cust-08','menu-2','2026-05-20',11,0,'confirmed'),
      ('apt-019','staff-4','cust-10','menu-5','2026-05-20',15,30,'cancelled'),
      ('apt-020','staff-5','cust-09','menu-1','2026-05-21',9,30,'confirmed'),
      ('apt-021','staff-1','cust-01','menu-3','2026-05-22',14,0,'confirmed'),
      ('apt-022','staff-2','cust-03','menu-1','2026-05-22',10,0,'confirmed'),
      ('apt-023','staff-3','cust-05','menu-4','2026-05-26',13,30,'confirmed'),
      ('apt-024','staff-4','cust-07','menu-2','2026-05-26',11,0,'confirmed'),
      ('apt-025','staff-5','cust-09','menu-5','2026-05-27',10,0,'confirmed'),
      ('apt-026','staff-1','cust-02','menu-1','2026-05-28',9,0,'confirmed'),
      ('apt-027','staff-2','cust-04','menu-3','2026-05-28',13,0,'confirmed'),
      ('apt-028','staff-3','cust-06','menu-2','2026-05-29',11,30,'confirmed'),
      // ─ 6월 ─
      ('apt-029','staff-4','cust-08','menu-1','2026-06-02',10,0,'confirmed'),
      ('apt-030','staff-5','cust-10','menu-5','2026-06-02',13,30,'confirmed'),
      ('apt-031','staff-1','cust-01','menu-2','2026-06-03',11,0,'confirmed'),
      ('apt-032','staff-2','cust-03','menu-4','2026-06-03',14,0,'confirmed'),
      ('apt-033','staff-3','cust-05','menu-1','2026-06-04',9,30,'confirmed'),
      ('apt-034','staff-4','cust-07','menu-3','2026-06-04',13,0,'confirmed'),
      ('apt-035','staff-5','cust-09','menu-2','2026-06-05',10,30,'confirmed'),
      ('apt-036','staff-1','cust-02','menu-5','2026-06-05',15,0,'confirmed'),
      ('apt-037','staff-2','cust-04','menu-1','2026-06-09',9,0,'confirmed'),
      ('apt-038','staff-3','cust-06','menu-4','2026-06-09',11,30,'confirmed'),
      ('apt-039','staff-4','cust-08','menu-3','2026-06-10',13,0,'confirmed'),
      ('apt-040','staff-5','cust-10','menu-1','2026-06-10',10,0,'confirmed'),
      ('apt-041','staff-1','cust-01','menu-5','2026-06-11',14,30,'confirmed'),
      ('apt-042','staff-2','cust-03','menu-2','2026-06-11',9,30,'confirmed'),
      ('apt-043','staff-3','cust-05','menu-1','2026-06-12',11,0,'confirmed'),
      ('apt-044','staff-4','cust-07','menu-4','2026-06-12',13,30,'confirmed'),
      ('apt-045','staff-5','cust-09','menu-3','2026-06-16',10,0,'confirmed'),
      ('apt-046','staff-1','cust-02','menu-2','2026-06-16',14,0,'confirmed'),
      ('apt-047','staff-2','cust-04','menu-5','2026-06-17',9,0,'confirmed'),
      ('apt-048','staff-3','cust-06','menu-1','2026-06-17',11,30,'confirmed'),
      ('apt-049','staff-4','cust-08','menu-4','2026-06-18',13,0,'confirmed'),
      ('apt-050','staff-5','cust-10','menu-2','2026-06-18',10,30,'confirmed'),
      ('apt-051','staff-1','cust-01','menu-3','2026-06-23',9,30,'pending'),
      ('apt-052','staff-2','cust-03','menu-1','2026-06-23',11,0,'pending'),
      ('apt-053','staff-3','cust-05','menu-5','2026-06-24',14,0,'pending'),
      ('apt-054','staff-4','cust-07','menu-2','2026-06-24',10,0,'pending'),
      ('apt-055','staff-5','cust-09','menu-4','2026-06-25',13,30,'pending'),
      ('apt-056','staff-1','cust-02','menu-1','2026-06-25',9,0,'pending'),
      ('apt-057','staff-2','cust-04','menu-3','2026-06-26',11,30,'pending'),
      ('apt-058','staff-3','cust-06','menu-2','2026-06-26',14,30,'pending'),
      // ─ 7월 ─
      ('apt-059','staff-4','cust-08','menu-1','2026-07-01',10,0,'pending'),
      ('apt-060','staff-5','cust-10','menu-5','2026-07-01',13,0,'pending'),
      ('apt-061','staff-1','cust-01','menu-2','2026-07-02',9,30,'pending'),
      ('apt-062','staff-2','cust-03','menu-4','2026-07-02',11,30,'pending'),
      ('apt-063','staff-3','cust-05','menu-1','2026-07-03',14,0,'pending'),
      ('apt-064','staff-4','cust-07','menu-3','2026-07-03',10,30,'pending'),
      ('apt-065','staff-5','cust-09','menu-2','2026-07-07',9,0,'pending'),
      ('apt-066','staff-1','cust-02','menu-5','2026-07-07',13,30,'pending'),
      ('apt-067','staff-2','cust-04','menu-1','2026-07-08',11,0,'pending'),
      ('apt-068','staff-3','cust-06','menu-4','2026-07-08',14,30,'pending'),
      ('apt-069','staff-4','cust-08','menu-2','2026-07-09',10,0,'pending'),
      ('apt-070','staff-5','cust-10','menu-3','2026-07-09',13,0,'pending'),
      ('apt-071','staff-1','cust-01','menu-1','2026-07-10',9,30,'pending'),
      ('apt-072','staff-2','cust-03','menu-5','2026-07-10',11,30,'pending'),
      ('apt-073','staff-3','cust-05','menu-2','2026-07-14',14,0,'pending'),
      ('apt-074','staff-4','cust-07','menu-4','2026-07-14',10,0,'pending'),
      ('apt-075','staff-5','cust-09','menu-1','2026-07-15',13,30,'pending'),
      ('apt-076','staff-1','cust-02','menu-3','2026-07-15',9,0,'pending'),
      ('apt-077','staff-2','cust-04','menu-2','2026-07-16',11,0,'pending'),
      ('apt-078','staff-3','cust-06','menu-5','2026-07-16',14,30,'pending'),
      ('apt-079','staff-4','cust-08','menu-1','2026-07-17',10,30,'pending'),
      ('apt-080','staff-5','cust-10','menu-4','2026-07-17',13,0,'pending'),
      ('apt-081','staff-1','cust-01','menu-3','2026-07-22',9,30,'pending'),
      ('apt-082','staff-2','cust-03','menu-1','2026-07-22',11,0,'pending'),
      ('apt-083','staff-3','cust-05','menu-5','2026-07-23',14,0,'pending'),
      ('apt-084','staff-4','cust-07','menu-2','2026-07-23',10,0,'pending'),
      ('apt-085','staff-5','cust-09','menu-4','2026-07-24',13,30,'pending'),
      ('apt-086','staff-1','cust-02','menu-1','2026-07-24',9,0,'pending'),
      // ─ 8월 ─
      ('apt-087','staff-2','cust-04','menu-3','2026-08-04',11,0,'pending'),
      ('apt-088','staff-3','cust-06','menu-2','2026-08-04',14,0,'pending'),
      ('apt-089','staff-4','cust-08','menu-1','2026-08-05',10,0,'pending'),
      ('apt-090','staff-5','cust-10','menu-5','2026-08-05',13,30,'pending'),
      ('apt-091','staff-1','cust-01','menu-4','2026-08-06',9,30,'pending'),
      ('apt-092','staff-2','cust-03','menu-2','2026-08-06',11,30,'pending'),
      ('apt-093','staff-3','cust-05','menu-1','2026-08-07',14,0,'pending'),
      ('apt-094','staff-4','cust-07','menu-3','2026-08-07',10,30,'pending'),
      ('apt-095','staff-5','cust-09','menu-5','2026-08-11',9,0,'pending'),
      ('apt-096','staff-1','cust-02','menu-2','2026-08-11',13,0,'pending'),
      ('apt-097','staff-2','cust-04','menu-1','2026-08-12',11,0,'pending'),
      ('apt-098','staff-3','cust-06','menu-4','2026-08-12',14,30,'pending'),
      ('apt-099','staff-4','cust-08','menu-3','2026-08-13',10,0,'pending'),
      ('apt-100','staff-5','cust-10','menu-2','2026-08-13',13,30,'pending'),
      ('apt-101','staff-1','cust-01','menu-5','2026-08-18',9,30,'pending'),
      ('apt-102','staff-2','cust-03','menu-1','2026-08-18',11,0,'pending'),
      ('apt-103','staff-3','cust-05','menu-4','2026-08-19',14,0,'pending'),
      ('apt-104','staff-4','cust-07','menu-2','2026-08-19',10,0,'pending'),
      ('apt-105','staff-5','cust-09','menu-3','2026-08-20',13,30,'pending'),
      ('apt-106','staff-1','cust-02','menu-1','2026-08-20',9,0,'pending'),
      ('apt-107','staff-2','cust-04','menu-5','2026-08-25',11,30,'pending'),
      ('apt-108','staff-3','cust-06','menu-2','2026-08-25',14,30,'pending'),
      ('apt-109','staff-4','cust-08','menu-1','2026-08-26',10,0,'pending'),
      ('apt-110','staff-5','cust-10','menu-4','2026-08-26',13,0,'pending'),
      ('apt-111','staff-1','cust-01','menu-3','2026-08-27',9,30,'pending'),
      ('apt-112','staff-2','cust-03','menu-2','2026-08-27',11,0,'pending'),
    ];

    // 메뉴 길이 맵 (menuId → durationMin)
    final menuDurMap = <String, int>{
      'menu-1': 60, 'menu-2': 90, 'menu-3': 120, 'menu-4': 60, 'menu-5': 45,
    };
    // 메뉴 이름 맵
    final menuNameMap = <String, String>{
      'menu-1': 'カット', 'menu-2': 'カラー', 'menu-3': 'パーマ',
      'menu-4': 'トリートメント', 'menu-5': 'ヘッドスパ',
    };
    // 스태프별 색상
    const staffColorMap = {
      'staff-1': '#0064FF', 'staff-2': '#00BFAE', 'staff-3': '#9B5CDB',
      'staff-4': '#F59E0B', 'staff-5': '#E74C3C',
    };

    for (final (id, staffId, custId, menuId, dateStr, h, m, status) in aptsRaw) {
      final dur = menuDurMap[menuId]!;
      final start = DateTime(
        int.parse(dateStr.substring(0, 4)),
        int.parse(dateStr.substring(5, 7)),
        int.parse(dateStr.substring(8, 10)),
        h, m,
      );
      final end = start.add(Duration(minutes: dur));
      final aptId = id;
      await into(appointments).insertOnConflictUpdate(AppointmentsCompanion.insert(
        id: aptId,
        staffId: staffId,
        customerId: Value(custId),
        startAt: start.toIso8601String(),
        endAt: end.toIso8601String(),
        status: Value(status),
        color: Value(staffColorMap[staffId]),
        source: const Value('staff'),
      ));
      // 예약 메뉴 연결
      await into(appointmentMenus).insertOnConflictUpdate(
        AppointmentMenusCompanion.insert(
          id: '${aptId}_m',
          appointmentId: aptId,
          menuId: menuId,
          menuName: menuNameMap[menuId]!,
          price: 0,
          durationMin: dur,
        ),
      );
    }
  }

  // ─── 편의 메서드 ──────────────────────────────────────────────────────

  Future<RegisterSession?> get todayOpenSession async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return (select(registerSessions)
          ..where((t) => t.status.equals('open'))
          ..where((t) => t.openAt.like('$today%')))
        .getSingleOrNull();
  }

  Future<DraftSale?> get currentDraftSale =>
      (select(draftSales)..where((t) => t.id.equals('current'))).getSingleOrNull();

  Future<DraftAppointment?> get currentDraftAppointment =>
      (select(draftAppointments)..where((t) => t.id.equals('current'))).getSingleOrNull();

  Future<SalonSetting?> get settings =>
      (select(salonSettings)..where((t) => t.id.equals(1))).getSingleOrNull();

  Future<List<StaffData>> get activeStaff =>
      (select(staff)..where((t) => t.isActive.equals(true))).get();

  Future<List<Customer>> searchCustomers(String query) {
    final q = '%$query%';
    return (select(customers)
          ..where((t) => t.name.like(q) | t.nameKana.like(q) | t.phone.like(q))
          ..where((t) => t.isDeleted.equals(false))
          ..limit(50))
        .get();
  }

  Future<List<Appointment>> todayAppointments({String? staffId}) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final query = select(appointments)
      ..where((t) => t.startAt.like('$today%'));
    if (staffId != null) query.where((t) => t.staffId.equals(staffId));
    query.orderBy([(t) => OrderingTerm.asc(t.startAt)]);
    return query.get();
  }

  Future<List<Product>> get lowStockProducts => (select(products)
        ..where((t) => t.isActive.equals(true) &
            CustomExpression<bool>('stock_quantity <= reorder_point')))
      .get();

  /// 고객의 활성 스태프 알림 목록
  Future<List<StaffAlert>> getStaffAlerts(String customerId) =>
      (select(staffAlerts)
            ..where((t) => t.customerId.equals(customerId) & t.isActive.equals(true)))
          .get();

  /// 즐겨찾기 메뉴 (정렬순)
  Stream<List<FavoriteMenusData>> watchFavoriteMenus() =>
      (select(favoriteMenus)
            ..where((t) => t.isVisible.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  /// よく使うメニュー — 過去90日間の使用頻度上位8件
  Future<List<MenusData>> getFrequentMenus({int limit = 8}) async {
    final since = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .substring(0, 10);
    final rows = await customSelect(
      '''
      SELECT si.ref_id AS menu_id, COUNT(*) AS cnt
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE si.item_type = 'menu'
        AND si.ref_id IS NOT NULL
        AND s.sale_date >= ?
        AND s.status NOT IN ('voided')
      GROUP BY si.ref_id
      ORDER BY cnt DESC
      LIMIT ?
      ''',
      variables: [Variable.withString(since), Variable.withInt(limit)],
      readsFrom: {saleItems, sales},
    ).get();

    final ids = rows.map((r) => r.read<String>('menu_id')).toList();
    if (ids.isEmpty) return [];

    final menus = await (select(this.menus)
          ..where((t) => t.id.isIn(ids) & t.isActive.equals(true)))
        .get();

    // 使用頻度順に並び替え
    menus.sort((a, b) =>
        ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
    return menus;
  }

  /// 로열티 티어 전체
  Future<List<LoyaltyTier>> get allLoyaltyTiers =>
      (select(loyaltyTiers)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();

  /// 고객 누적 지출 기반 티어 계산
  Future<LoyaltyTier?> getTierForAmount(int totalAmount) async {
    final tiers = await allLoyaltyTiers;
    LoyaltyTier? result;
    for (final t in tiers) {
      if (totalAmount >= t.minAmount) result = t;
    }
    return result;
  }
}

// ─── DB 연결 ──────────────────────────────────────────────────────────────
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'salon_pos.db'));
    return NativeDatabase.createInBackground(file);
  });
}
