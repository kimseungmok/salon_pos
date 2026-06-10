import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/theme/app_theme.dart';

// ─── キャッシュドロア設定 画面 ──────────────────────────────────────────────
// レジの開設金額と締め方法を設定します
class CashSettingsScreen extends ConsumerWidget {
  const CashSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('キャッシュドロア'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─ 開設金額 ─────────────────────────────────────────────────
          _InfoCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'レジ開設・締め',
            subtitle: 'POS画面からレジを開設・締め操作ができます',
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.touch_app_outlined,
                    text: 'POS画面 右上のレジアイコンから開設金額・中間締め・閉店締めができます',
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    icon: Icons.history,
                    text: 'レジ開設・締め履歴は取引一覧から確認できます',
                  ),
                  const SizedBox(height: 16),
                  // POS 화면으로 바로 이동하는 버튼
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                    label: const Text('POS画面へ'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ─ 현금 관련 설명 ────────────────────────────────────────────
          _InfoCard(
            icon: Icons.info_outline,
            title: '現金管理について',
            subtitle: '現金の入出金・残高管理の説明',
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.add_circle_outline,
                    text: '入金: レジへの現金補充（両替など）',
                  ),
                  const SizedBox(height: 6),
                  _InfoRow(
                    icon: Icons.remove_circle_outline,
                    text: '出金: レジからの現金引き出し（経費払いなど）',
                  ),
                  const SizedBox(height: 6),
                  _InfoRow(
                    icon: Icons.lock_outline,
                    text: '締め: 日次の現金照合・売上確定',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.h4),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: AppTextStyles.body2.copyWith(
                  color: AppColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }
}
