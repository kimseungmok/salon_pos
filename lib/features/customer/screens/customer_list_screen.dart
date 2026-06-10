import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';

// ─── 고객 목록 Provider ───────────────────────────────────────────────────
final customerListProvider = StreamProvider.family<List<Customer>, String?>((ref, query) {
  final db = ref.watch(databaseProvider);
  final sel = db.select(db.customers)..where((t) => t.isDeleted.equals(false));

  if (query == 'vip') {
    sel.where((t) => t.isVip.equals(true));
  } else if (query == 'new') {
    // 初来店から30日以内
    final since = DateTime.now().subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
    sel.where((t) => t.firstVisitDate.isBiggerOrEqualValue(since));
  } else if (query == 'dormant') {
    // 90日以上未来店
    final before = DateTime.now().subtract(const Duration(days: 90)).toIso8601String().substring(0, 10);
    sel.where((t) => t.lastVisitDate.isSmallerOrEqualValue(before) | t.lastVisitDate.isNull());
  } else if (query == 'caution') {
    sel.where((t) => t.cautionFlag.equals(true));
  } else if (query == 'highspend') {
    // 累計売上 5万円以上
    sel.where((t) => t.totalSpent.isBiggerOrEqualValue(50000));
  } else if (query == 'birthday') {
    // 今月生まれ — birthDate は YYYY-MM-DD 形式
    final month = DateTime.now().month.toString().padLeft(2, '0');
    sel.where((t) => t.birthDate.like('%-$month-%'));
  } else if (query != null && query.isNotEmpty) {
    final q = '%$query%';
    sel.where((t) => t.name.like(q) | t.nameKana.like(q) | t.phone.like(q) | t.email.like(q));
  }

  sel.orderBy([(t) => OrderingTerm.desc(t.lastVisitDate)]);
  return sel.watch();
});

final customerSearchQueryProvider = StateProvider<String?>((ref) => null);

enum CustomerSortOrder { lastVisit, totalVisits, name, totalSpent, pointBalance }

final customerSortOrderProvider = StateProvider<CustomerSortOrder>((ref) => CustomerSortOrder.lastVisit);

// ─── 고객 목록 화면 ──────────────────────────────────────────────────────
class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(customerSearchQueryProvider);
    final sortOrder = ref.watch(customerSortOrderProvider);
    final customersAsync = ref.watch(customerListProvider(query));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          // ─── 사이드바 필터 ─────────────────────────────────────────────
          Container(
            width: 200,
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 52, 16, 16),
                  child: Text('顧客管理', style: AppTextStyles.h3),
                ),
                const Divider(height: 1),
                _FilterItem(label: 'すべて', icon: Icons.people_outline, isActive: query == null,
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = null;
                    }),
                _FilterItem(label: 'VIP顧客', icon: Icons.star_outline, isActive: query == 'vip',
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = 'vip';
                    }),
                _FilterItem(label: '新規顧客', icon: Icons.fiber_new_outlined, isActive: query == 'new',
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = 'new';
                    }),
                _FilterItem(label: '休眠顧客', icon: Icons.bedtime_outlined, isActive: query == 'dormant',
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = 'dormant';
                    }),
                _FilterItem(label: '今月誕生日', icon: Icons.cake_outlined, isActive: query == 'birthday',
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = 'birthday';
                    }),
                _FilterItem(label: '注意顧客', icon: Icons.warning_amber_outlined, isActive: query == 'caution',
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = 'caution';
                    }),
                _FilterItem(label: '高単価顧客', icon: Icons.monetization_on_outlined, isActive: query == 'highspend',
                    onTap: () {
                      _searchCtrl.clear();
                      ref.read(customerSearchQueryProvider.notifier).state = 'highspend';
                    }),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddCustomer(context),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('顧客追加'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                  ),
                ),
              ],
            ),
          ),

          // ─── 메인 컨텐츠 ──────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // 검색바
                Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.fromLTRB(16, 52, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            hintText: '名前・カナ・電話番号で検索',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => ref
                              .read(customerSearchQueryProvider.notifier)
                              .state = v.isEmpty ? null : v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 정렬 버튼
                      PopupMenuButton<CustomerSortOrder>(
                        tooltip: '並び順',
                        icon: const Icon(Icons.sort_outlined, color: AppColors.textSecondary),
                        initialValue: sortOrder,
                        onSelected: (v) => ref.read(customerSortOrderProvider.notifier).state = v,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: CustomerSortOrder.lastVisit, child: Text('前回来店順')),
                          PopupMenuItem(value: CustomerSortOrder.totalVisits, child: Text('来店回数順')),
                          PopupMenuItem(value: CustomerSortOrder.totalSpent, child: Text('累計売上順')),
                          PopupMenuItem(value: CustomerSortOrder.name, child: Text('名前順')),
                          PopupMenuItem(value: CustomerSortOrder.pointBalance, child: Text('ポイント残高順')),
                        ],
                      ),
                      // CSV コピーボタン
                      customersAsync.when(
                        data: (customers) => IconButton(
                          icon: const Icon(Icons.download_outlined,
                              color: AppColors.textSecondary),
                          tooltip: '顧客リストをCSVコピー',
                          onPressed: () =>
                              _copyAsCsv(context, customers),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 고객 목록
                Expanded(
                  child: customersAsync.when(
                    data: (rawCustomers) {
                      // 클라이언트 측 정렬 적용
                      final customers = [...rawCustomers];
                      switch (sortOrder) {
                        case CustomerSortOrder.lastVisit:
                          customers.sort((a, b) => (b.lastVisitDate ?? '').compareTo(a.lastVisitDate ?? ''));
                        case CustomerSortOrder.totalVisits:
                          customers.sort((a, b) => b.totalVisits.compareTo(a.totalVisits));
                        case CustomerSortOrder.totalSpent:
                          customers.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
                        case CustomerSortOrder.name:
                          customers.sort((a, b) => a.name.compareTo(b.name));
                        case CustomerSortOrder.pointBalance:
                          customers.sort((a, b) => b.pointBalance.compareTo(a.pointBalance));
                      }
                      return customers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_search_outlined, size: 56, color: AppColors.textDisabled),
                                const SizedBox(height: 12),
                                Text('顧客が見つかりません', style: AppTextStyles.caption),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: customers.length,
                            separatorBuilder: (ctx, idx) => const Divider(height: 1, indent: 72),
                            itemBuilder: (_, i) => _CustomerListTile(
                              customer: customers[i],
                              onTap: () => context.push('/customers/${customers[i].id}'),
                            ),
                          );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('$e')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copyAsCsv(BuildContext context, List<Customer> customers) {
    final buf = StringBuffer();
    // ヘッダー
    buf.writeln('名前,フリガナ,電話番号,メール,誕生日,初来店,前回来店,来店回数,累計売上,ポイント残高,VIP,注意フラグ');
    for (final c in customers) {
      String _esc(String? v) {
        if (v == null) return '';
        if (v.contains(',') || v.contains('"') || v.contains('\n')) {
          return '"${v.replaceAll('"', '""')}"';
        }
        return v;
      }
      buf.writeln([
        _esc(c.name),
        _esc(c.nameKana),
        _esc(c.phone),
        _esc(c.email),
        _esc(c.birthDate),
        _esc(c.firstVisitDate),
        _esc(c.lastVisitDate),
        c.totalVisits.toString(),
        c.totalSpent.toString(),
        c.pointBalance.toString(),
        c.isVip ? '○' : '',
        c.cautionFlag ? '○' : '',
      ].join(','));
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${customers.length}件の顧客データをCSV形式でコピーしました'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showAddCustomer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCustomerSheet(),
    );
  }
}

// ─── 고객 목록 타일 ───────────────────────────────────────────────────────
class _CustomerListTile extends StatelessWidget {
  const _CustomerListTile({required this.customer, required this.onTap});
  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasVisit = customer.lastVisitDate != null;
    final daysSince = hasVisit
        ? DateTime.now().difference(DateTime.parse(customer.lastVisitDate!)).inDays
        : null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: customer.isVip ? AppColors.warningLight : AppColors.primaryLight,
            child: Text(
              customer.name.isNotEmpty ? customer.name.substring(0, 1) : '?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: customer.isVip ? AppColors.warning : AppColors.primary,
              ),
            ),
          ),
          if (customer.cautionFlag)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 16, height: 16,
                decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                child: const Icon(Icons.warning_amber, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Text(customer.name, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
          if (customer.nameKana != null) ...[
            const SizedBox(width: 8),
            Text(customer.nameKana!, style: AppTextStyles.caption),
          ],
          if (customer.isVip) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(4)),
              child: Text('VIP', style: AppTextStyles.caption.copyWith(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
          // 휴면 뱃지
          if ((daysSince ?? 0) >= 180) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF64748B).withAlpha(20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF64748B).withAlpha(60)),
              ),
              child: Text('長期休眠', style: AppTextStyles.caption.copyWith(
                  color: const Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ] else if ((daysSince ?? 0) >= 90) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.warning.withAlpha(80)),
              ),
              child: Text('休眠', style: AppTextStyles.caption.copyWith(
                  color: AppColors.warning, fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          if (customer.phone != null) Text(customer.phone!, style: AppTextStyles.caption),
          if (customer.phone != null && hasVisit) Text(' · ', style: AppTextStyles.caption),
          if (hasVisit)
            Text(
              daysSince == 0 ? '本日来店' : '${daysSince}日前',
              style: AppTextStyles.caption.copyWith(
                color: (daysSince ?? 0) > 90 ? AppColors.warning : AppColors.textSecondary,
              ),
            )
          else if (!hasVisit)
            Text('来店記録なし',
                style: AppTextStyles.caption.copyWith(color: AppColors.textDisabled)),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${customer.totalVisits}回', style: AppTextStyles.label),
          Text('¥${_fmt(customer.totalSpent)}',
              style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
          if (customer.pointBalance > 0) ...[
            const SizedBox(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars_rounded, size: 10, color: AppColors.warning),
                const SizedBox(width: 2),
                Text('${customer.pointBalance}pt',
                    style: AppTextStyles.caption.copyWith(
                        color: AppColors.warning, fontSize: 10)),
              ],
            ),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

// ─── 필터 아이템 ──────────────────────────────────────────────────────────
class _FilterItem extends StatelessWidget {
  const _FilterItem({required this.label, required this.icon, required this.isActive, required this.onTap});
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryLight : Colors.transparent,
          border: isActive
              ? const Border(left: BorderSide(color: AppColors.primary, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(label, style: AppTextStyles.body2.copyWith(
                color: isActive ? AppColors.primary : AppColors.textPrimary,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

// ─── 고객 추가 시트 ───────────────────────────────────────────────────────
class _AddCustomerSheet extends ConsumerStatefulWidget {
  const _AddCustomerSheet();

  @override
  ConsumerState<_AddCustomerSheet> createState() => _AddCustomerSheetState();
}

class _AddCustomerSheetState extends ConsumerState<_AddCustomerSheet> {
  final _nameCtrl = TextEditingController();
  final _kanaCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  String? _gender;
  String? _referralSource;
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  static const _referralOptions = [
    'ホットペッパー', 'Instagram', 'Google', 'Twitter/X',
    '紹介', 'チラシ', '看板', '近隣', 'その他',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _kanaCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _birthCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(child: Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text('顧客追加', style: AppTextStyles.h4),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                children: [
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '名前 *')),
                  const SizedBox(height: 12),
                  TextField(controller: _kanaCtrl, decoration: const InputDecoration(labelText: 'フリガナ')),
                  const SizedBox(height: 12),
                  TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: '電話番号'), keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'メールアドレス'), keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 12),
                  // 생년월일 DatePicker
                  TextField(
                    controller: _birthCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '生年月日',
                      hintText: '選択してください',
                      suffixIcon: _birthCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () => setState(() => _birthCtrl.clear()),
                            )
                          : const Icon(Icons.cake_outlined, size: 18),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime(1990, 1, 1),
                        firstDate: DateTime(1920),
                        lastDate: DateTime.now(),
                        locale: const Locale('ja'),
                      );
                      if (picked != null) {
                        setState(() {
                          _birthCtrl.text =
                              '${picked.year.toString().padLeft(4, '0')}-'
                              '${picked.month.toString().padLeft(2, '0')}-'
                              '${picked.day.toString().padLeft(2, '0')}';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('性別', style: AppTextStyles.body2),
                      const SizedBox(width: 16),
                      ...['male', 'female', 'other'].map((g) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(g == 'male' ? '男性' : g == 'female' ? '女性' : 'その他'),
                          selected: _gender == g,
                          onSelected: (v) => setState(() => _gender = v ? g : null),
                        ),
                      )),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 来店経路 드롭다운
                  DropdownButtonFormField<String>(
                    value: _referralSource,
                    decoration: const InputDecoration(
                      labelText: '来店経路',
                      prefixIcon: Icon(Icons.campaign_outlined, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('選択しない')),
                      ..._referralOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (v) => setState(() => _referralSource = v),
                  ),
                  const SizedBox(height: 12),
                  // メモ
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'メモ',
                      hintText: '備考・要望など',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving || _nameCtrl.text.isEmpty ? null : _save,
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('顧客を追加'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final now = DateTime.now().toIso8601String();
      // 顧客番号 생성
      final count = await db.customSelect('SELECT COUNT(*) as cnt FROM customers').getSingle();
      final no = 'C${(count.read<int>('cnt') + 1).toString().padLeft(5, '0')}';
      await db.into(db.customers).insert(CustomersCompanion.insert(
        id: now.replaceAll(RegExp(r'[^0-9]'), ''),
        customerNo: Value(no),
        name: _nameCtrl.text.trim(),
        nameKana: Value(_kanaCtrl.text.trim().isEmpty ? null : _kanaCtrl.text.trim()),
        phone: Value(_phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim()),
        email: Value(_emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim()),
        gender: Value(_gender),
        birthDate: Value(_birthCtrl.text.trim().isEmpty ? null : _birthCtrl.text.trim()),
        referralSource: Value(_referralSource),
        notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        firstVisitDate: Value(DateTime.now().toIso8601String().substring(0, 10)),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
        setState(() => _saving = false);
      }
    }
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
