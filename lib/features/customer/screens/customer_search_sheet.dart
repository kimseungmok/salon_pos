import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

class CustomerSearchSheet extends ConsumerStatefulWidget {
  const CustomerSearchSheet({super.key, required this.onSelected});
  final void Function(String id, String name) onSelected;

  @override
  ConsumerState<CustomerSearchSheet> createState() => _CustomerSearchSheetState();
}

class _CustomerSearchSheetState extends ConsumerState<CustomerSearchSheet> {
  final _ctrl = TextEditingController();
  List<Customer> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final db = ref.read(databaseProvider);
    final res = await db.searchCustomers(q);
    if (mounted) setState(() { _results = res; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('顧客検索', style: AppTextStyles.h4),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '名前・カナ・電話番号で検索',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _search,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        if (_searching)
          const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())
        else
          Expanded(
            child: _results.isEmpty && _ctrl.text.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_search_outlined, size: 48, color: AppColors.textDisabled),
                        const SizedBox(height: 8),
                        Text('「${_ctrl.text}」で顧客が見つかりません', style: AppTextStyles.caption),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (ctx, idx) => const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final c = _results[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: c.isVip ? AppColors.warningLight : AppColors.primaryLight,
                          child: Text(
                            c.name.isNotEmpty ? c.name.substring(0, 1) : '?',
                            style: TextStyle(
                              color: c.isVip ? AppColors.warning : AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(c.name, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
                            if (c.isVip) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('VIP', style: AppTextStyles.caption.copyWith(color: AppColors.warning, fontSize: 10)),
                              ),
                            ],
                            if (c.cautionFlag) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.error),
                            ],
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            if (c.nameKana != null) Text(c.nameKana!, style: AppTextStyles.caption),
                            if (c.phone != null) ...[
                              const SizedBox(width: 8),
                              Text(c.phone!, style: AppTextStyles.caption),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${c.totalVisits}回来店', style: AppTextStyles.caption),
                            Text('¥${_fmt(c.totalSpent)}', style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                          ],
                        ),
                        onTap: () => widget.onSelected(c.id, c.name),
                      );
                    },
                  ),
          ),
      ],
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
