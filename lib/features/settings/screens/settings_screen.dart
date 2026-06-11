import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../shared/theme/app_theme.dart';
import 'system_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        children: [
          _SectionHeader(label: 'サロン設定'),
          _SettingsTile(
            icon: Icons.store_outlined,
            title: 'サロン基本情報',
            subtitle: 'サロン名・電話番号・住所・インボイス番号',
            onTap: () => context.go(AppRoutes.settingsSalon),
          ),
          const Divider(),
          _SectionHeader(label: 'サービス管理'),
          _SettingsTile(
            icon: Icons.spa_outlined,
            title: 'メニュー管理',
            subtitle: 'メニューとカテゴリの追加・編集',
            onTap: () => context.go(AppRoutes.settingsMenus),
          ),
          _SettingsTile(
            icon: Icons.inventory_2_outlined,
            title: '在庫管理',
            subtitle: '商品在庫の確認・入出庫',
            onTap: () => context.go(AppRoutes.settingsInventory),
          ),
          _SettingsTile(
            icon: Icons.chat_bubble_outline,
            title: 'メッセージテンプレート',
            subtitle: 'SMS・LINE用メッセージの作成・編集',
            onTap: () => context.go(AppRoutes.settingsMessages),
          ),
          _SettingsTile(
            icon: Icons.campaign_outlined,
            title: 'キャンペーン管理',
            subtitle: 'VIP・休眠・誕生日顧客向けキャンペーンの作成',
            onTap: () => context.go(AppRoutes.settingsCampaign),
          ),
          _SettingsTile(
            icon: Icons.view_module_outlined,
            title: 'セットメニュー管理',
            subtitle: '複数メニューをまとめてセット価格・割引を設定',
            onTap: () => context.go(AppRoutes.settingsBundles),
          ),
          _SettingsTile(
            icon: Icons.auto_awesome_outlined,
            title: '自動化ルール',
            subtitle: '来店後・誕生日・長期未来店など自動メッセージ設定',
            onTap: () => context.go(AppRoutes.settingsAutomation),
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: '施術同意書テンプレート',
            subtitle: 'パーマ・カラー等の施術同意書・カウンセリングシート管理',
            onTap: () => context.go(AppRoutes.settingsConsent),
          ),
          _SettingsTile(
            icon: Icons.card_membership_outlined,
            title: '回数券・プリペイドプラン',
            subtitle: '回数券・プリペイド券のプラン作成・管理',
            onTap: () => context.go(AppRoutes.settingsPrepaid),
          ),
          _SettingsTile(
            icon: Icons.receipt_long_outlined,
            title: '掛け売り管理',
            subtitle: '未収金の確認・収納管理',
            onTap: () => context.go(AppRoutes.settingsCreditMgmt),
          ),
          const Divider(),
          _SectionHeader(label: 'スタッフ管理'),
          _SettingsTile(
            icon: Icons.people_outline,
            title: 'スタッフ管理',
            subtitle: 'スタッフの登録・権限設定',
            onTap: () => context.go(AppRoutes.settingsStaff),
          ),
          const Divider(),
          _SectionHeader(label: 'システム'),
          _SettingsTile(
            icon: Icons.settings_outlined,
            title: 'システム設定',
            subtitle: '文字サイズ・表示設定',
            onTap: () => context.go(AppRoutes.settingsSystem),
          ),
          const Divider(),
          _SectionHeader(label: 'その他'),
          _SettingsTile(
            icon: Icons.flag_outlined,
            title: 'KPI目標設定',
            subtitle: '月間売上・来店客数などの目標管理',
            onTap: () => context.go(AppRoutes.settingsKpi),
          ),
          _SettingsTile(
            icon: Icons.loyalty_outlined,
            title: 'ポイント・会員設定',
            subtitle: '会員ランクとポイント倍率',
            onTap: () => context.go(AppRoutes.settingsLoyalty),
          ),
          _SettingsTile(
            icon: Icons.military_tech_outlined,
            title: '会員ランク管理',
            subtitle: 'ブロンズ・シルバー・ゴールド・プラチナのランク基準設定',
            onTap: () => context.go(AppRoutes.settingsTiers),
          ),
          _SettingsTile(
            icon: Icons.payments_outlined,
            title: 'キャッシュドロア',
            subtitle: 'レジ開設・締め設定',
            onTap: () => context.go(AppRoutes.settingsCash),
          ),
          _SettingsTile(
            icon: Icons.receipt_long_outlined,
            title: 'レシート設定',
            subtitle: '店名・ロゴ・フッター',
            onTap: () => context.go(AppRoutes.settingsReceipt),
          ),
          const Divider(),
          _SectionHeader(label: 'アプリ情報'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('SalonPOS',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    SizedBox(height: 2),
                    Text('v0.1.0 (build 1)  ·  Flutter 3.44.1',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
