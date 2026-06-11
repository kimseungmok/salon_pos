import 'package:go_router/go_router.dart';

import '../../features/pos/screens/pos_main_screen.dart';
import '../../features/pos/screens/open_register_screen.dart';
import '../../features/booking/screens/booking_screen.dart';
import '../../features/customer/screens/customer_list_screen.dart';
import '../../features/customer/screens/customer_detail_screen.dart';
import '../../features/reports/screens/reports_screen.dart';
import '../../features/reports/screens/transactions_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/settings/screens/menu_management_screen.dart';
import '../../features/inventory/screens/inventory_screen.dart';
import '../../features/staff/screens/staff_screen.dart';
import '../../features/settings/screens/loyalty_settings_screen.dart';
import '../../features/settings/screens/receipt_settings_screen.dart';
import '../../features/settings/screens/cash_settings_screen.dart';
import '../../features/settings/screens/kpi_settings_screen.dart';
import '../../features/settings/screens/message_template_screen.dart';
import '../../features/settings/screens/salon_info_screen.dart';
import '../../features/settings/screens/campaign_screen.dart';
import '../../features/settings/screens/menu_bundle_screen.dart';
import '../../features/settings/screens/automation_rule_screen.dart';
import '../../features/settings/screens/loyalty_tiers_screen.dart';
import '../../features/settings/screens/consent_form_screen.dart';
import '../../features/settings/screens/prepaid_plan_screen.dart';
import '../../features/settings/screens/credit_management_screen.dart';
import '../../features/settings/screens/system_settings_screen.dart';
import '../../shared/widgets/main_shell.dart';

// ─── 라우트 경로 ──────────────────────────────────────────────────────────
class AppRoutes {
  AppRoutes._();

  static const pos       = '/';
  static const booking   = '/booking';
  static const customers = '/customers';
  static const reports   = '/reports';
  static const settings  = '/settings';
  static const settingsStaff     = '/settings/staff';
  static const settingsInventory = '/settings/inventory';
  static const settingsMenus     = '/settings/menus';
  static const settingsLoyalty   = '/settings/loyalty';
  static const settingsCash      = '/settings/cash';
  static const settingsReceipt   = '/settings/receipt';
  static const settingsKpi       = '/settings/kpi';
  static const settingsMessages  = '/settings/messages';
  static const settingsSalon     = '/settings/salon';
  static const settingsCampaign  = '/settings/campaign';
  static const settingsBundles    = '/settings/bundles';
  static const settingsAutomation  = '/settings/automation';
  static const settingsTiers        = '/settings/tiers';
  static const settingsConsent      = '/settings/consent';
  static const settingsPrepaid      = '/settings/prepaid';
  static const settingsCreditMgmt   = '/settings/credit';
  static const settingsSystem        = '/settings/system';
  static const openRegister      = '/open-register';
  static const transactions      = '/reports/transactions';
}

// ─── GoRouter ─────────────────────────────────────────────────────────────
final appRouter = GoRouter(
  initialLocation: AppRoutes.pos,
  debugLogDiagnostics: false,
  routes: [
    GoRoute(
      path: AppRoutes.openRegister,
      builder: (c, s) => const OpenRegisterPage(),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.pos,
          pageBuilder: (c, s) => const NoTransitionPage(child: PosMainScreen()),
        ),
        GoRoute(
          path: AppRoutes.booking,
          pageBuilder: (c, s) => const NoTransitionPage(child: BookingScreen()),
        ),
        GoRoute(
          path: AppRoutes.customers,
          pageBuilder: (c, s) => const NoTransitionPage(child: CustomerListScreen()),
          routes: [
            GoRoute(
              path: ':id',
              builder: (c, s) => CustomerDetailScreen(
                customerId: s.pathParameters['id']!,
                initialTab:
                    int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
              ),
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.reports,
          pageBuilder: (c, s) => const NoTransitionPage(child: ReportsScreen()),
          routes: [
            GoRoute(
              path: 'transactions',
              builder: (c, s) => const TransactionsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (c, s) => const NoTransitionPage(child: SettingsScreen()),
          routes: [
            GoRoute(
              path: 'menus',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: MenuManagementScreen()),
            ),
            GoRoute(
              path: 'inventory',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: InventoryScreen()),
            ),
            GoRoute(
              path: 'staff',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: StaffScreen()),
            ),
            GoRoute(
              path: 'loyalty',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: LoyaltySettingsScreen()),
            ),
            GoRoute(
              path: 'receipt',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: ReceiptSettingsScreen()),
            ),
            GoRoute(
              path: 'cash',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: CashSettingsScreen()),
            ),
            GoRoute(
              path: 'kpi',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: KpiSettingsScreen()),
            ),
            GoRoute(
              path: 'messages',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: MessageTemplateScreen()),
            ),
            GoRoute(
              path: 'salon',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: SalonInfoScreen()),
            ),
            GoRoute(
              path: 'campaign',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: CampaignScreen()),
            ),
            GoRoute(
              path: 'bundles',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: MenuBundleScreen()),
            ),
            GoRoute(
              path: 'automation',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: AutomationRuleScreen()),
            ),
            GoRoute(
              path: 'tiers',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: LoyaltyTiersScreen()),
            ),
            GoRoute(
              path: 'consent',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: ConsentFormScreen()),
            ),
            GoRoute(
              path: 'prepaid',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: PrepaidPlanScreen()),
            ),
            GoRoute(
              path: 'credit',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: CreditManagementScreen()),
            ),
            GoRoute(
              path: 'system',
              pageBuilder: (c, s) =>
                  const NoTransitionPage(child: SystemSettingsScreen()),
            ),
          ],
        ),
      ],
    ),
  ],
);
