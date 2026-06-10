import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/widgets/top_banner.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/theme/app_theme.dart';
import '../providers/pos_provider.dart';
import '../../reports/providers/reports_provider.dart';
import '../../customer/screens/customer_search_sheet.dart';
import 'refund_screen.dart';
import '../../booking/screens/appointment_form_screen.dart';

// ─── 결제 수단 정의 ───────────────────────────────────────────────────────
class _PayMethod {
  const _PayMethod(this.key, this.label, this.icon, this.color);
  final String key;
  final String label;
  final IconData icon;
  final Color color;
}

const _allMethods = [
  _PayMethod('cash', '現金', Icons.payments_outlined, AppColors.success),
  _PayMethod('credit_card', 'クレジット', Icons.credit_card, AppColors.primary),
  _PayMethod('ic_card', 'IC・電子マネー', Icons.contactless_outlined, Color(0xFF0EA5E9)),
  _PayMethod('qr', 'QRコード', Icons.qr_code_scanner, Color(0xFFFF6B35)),
  _PayMethod('gift_card', 'ギフトカード', Icons.card_giftcard_outlined, Color(0xFF9B5CDB)),
  _PayMethod('bank_transfer', '銀行振込', Icons.account_balance_outlined, Color(0xFF8D6E63)),
];

// ─── 결제 화면 ────────────────────────────────────────────────────────────
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.session});
  final RegisterSession session;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  // 選択中の支払い手段 (最大3件)
  final List<String> _selectedMethods = [];
  // 각 수단의 입력 금액 — ValueNotifier で局所 rebuild
  late final ValueNotifier<Map<String, int>> _amountsNotifier;
  // 現在編集中の支払い手段
  String? _editingMethod;
  bool _processing = false;
  // 10배 경고 중복 방지용 — 마지막으로 경고한 구간
  bool _warnedOverpay = false;

  // 편의 getter
  Map<String, int> get _amounts => _amountsNotifier.value;
  int get _grandTotal => ref.read(posProvider).grandTotal;
  int _calcTotalPaid(Map<String, int> amounts) =>
      amounts.values.fold(0, (s, v) => s + v);
  int _calcRemaining(Map<String, int> amounts) =>
      (_grandTotal - _calcTotalPaid(amounts)).clamp(0, 999999999);
  int _calcChange(Map<String, int> amounts) =>
      (_calcTotalPaid(amounts) - _grandTotal).clamp(0, 999999999);

  // 金額変更: ValueNotifier のみ更新 + 10배 경고 체크
  void _setAmount(String key, int value) {
    final next = Map<String, int>.from(_amounts);
    next[key] = value;
    _amountsNotifier.value = next;

    if (_grandTotal == 0) return; // 合計¥0 の場合はチェックしない

    final paid = _calcTotalPaid(next);
    final isOver = paid > _grandTotal * 10;
    if (isOver && !_warnedOverpay) {
      _warnedOverpay = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showTopBanner(
            context,
            '入力金額が合計の10倍を超えています。確認してください。',
            color: const Color(0xFFF59E0B),
            icon: Icons.warning_rounded,
            persistent: true, // 超過中はずっと表示
          );
        }
      });
    } else if (!isOver && _warnedOverpay) {
      _warnedOverpay = false;
      dismissTopBanner(); // 超過解消 → 即 dismiss
    }
  }

  @override
  void initState() {
    super.initState();
    _amountsNotifier = ValueNotifier({});
    // 결제수단은 빈 상태로 시작 — 직원이 직접 선택
  }

  @override
  void dispose() {
    _amountsNotifier.dispose();
    super.dispose();
  }

  void _addMethod(String key) {
    if (_selectedMethods.contains(key)) return;
    if (_selectedMethods.length >= _allMethods.length) return;
    final remaining = _calcRemaining(_amounts);
    setState(() {
      _selectedMethods.add(key);
      _editingMethod = key;
    });
    _setAmount(key, remaining);
  }

  void _removeMethod(String key) {
    setState(() {
      _selectedMethods.remove(key);
      if (_editingMethod == key) {
        _editingMethod =
            _selectedMethods.isNotEmpty ? _selectedMethods.last : null;
      }
    });
    final next = Map<String, int>.from(_amounts)..remove(key);
    _amountsNotifier.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(posProvider);
    final total = pos.grandTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: _PayAppBar(
          pos: pos,
          processing: _processing,
          onBack: () => _confirmBack(context),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左: 주문 요약 + 고객/담당/포인트
          SizedBox(
            width: 300,
            child: _OrderSummary(pos: pos),
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
          // 右: 支払い UI
          Expanded(
            child: ValueListenableBuilder<Map<String, int>>(
              valueListenable: _amountsNotifier,
              builder: (context, amounts, _) {
                final totalPaid = _calcTotalPaid(amounts);
                final remaining = _calcRemaining(amounts);
                final change = _calcChange(amounts);
                final editingKey = _editingMethod;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ① 支払い手段タブ — 수단이 없을 때는 숨김 (그리드가 전체 사용)
                    if (_selectedMethods.isNotEmpty) ...[
                      _MethodTabBar(
                        selectedMethods: _selectedMethods,
                        amounts: amounts,
                        editingKey: editingKey,
                        onSelect: (key) =>
                            setState(() => _editingMethod = key),
                        onAdd: _addMethod,
                        onRemove: _removeMethod,
                      ),
                      const Divider(height: 1, color: AppColors.border),
                    ],
                    // ② テンキー (Expanded) — ValueListenableBuilder 内なので局所 rebuild
                    Expanded(
                      child: editingKey == null
                          ? _MethodSelectGrid(
                              onSelect: _addMethod,
                            )
                          : editingKey == 'cash'
                              ? _CashNumpad(
                                  current: amounts['cash'] ?? 0,
                                  grandTotal: total,
                                  // 다른 수단이 있을 때 残 = 나머지 + 현금 현재값
                                  remaining: _selectedMethods.length > 1
                                      ? remaining + (amounts['cash'] ?? 0)
                                      : null,
                                  onPreset: (v) => _setAmount('cash', v),
                                  onInput: (v) => _setAmount('cash', v),
                                )
                              : _CardNumpad(
                                  current: amounts[editingKey] ?? 0,
                                  grandTotal: total,
                                  remaining: remaining +
                                      (amounts[editingKey] ?? 0),
                                  method: _allMethods.firstWhere(
                                      (m) => m.key == editingKey),
                                  onInput: (v) => _setAmount(editingKey, v),
                                ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    // ③ フッター (合計 + 決済ボタン)
                    _PaymentFooter(
                      total: total,
                      totalPaid: totalPaid,
                      remaining: remaining,
                      change: change,
                      processing: _processing,
                      onConfirm: remaining <= 0 ? _showConfirmDialog : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _confirmBack(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('会計をキャンセルしますか？'),
        content: const Text('入力した支払情報は失われます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('続ける'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('キャンセル',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true && mounted) Navigator.pop(context);
    });
  }

  Future<void> _showConfirmDialog() async {
    final snapshot = _amounts;
    if (_calcRemaining(snapshot) > 0 || _processing) return;
    final pos = ref.read(posProvider);
    final total = pos.grandTotal;
    final change = _calcChange(snapshot);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, minWidth: 340),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ヘッダー
                Row(
                  children: [
                    Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Text('決済を確定', style: AppTextStyles.h4),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: const Icon(Icons.close, size: 20,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // 합계 금액 (prominent)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text('お支払い合計',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Text('¥${_fmt(total)}',
                          style: AppTextStyles.price.copyWith(
                              fontSize: 34, color: AppColors.primary)),
                    ],
                  ),
                ),

                // 분할 결제 내역
                if (_selectedMethods.length > 1) ...[
                  const SizedBox(height: 12),
                  ..._selectedMethods
                      .where((k) => (snapshot[k] ?? 0) > 0)
                      .map((k) {
                    final m = _allMethods.firstWhere((m) => m.key == k);
                    final amt = snapshot[k] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: m.color.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(m.icon, size: 14, color: m.color),
                          ),
                          const SizedBox(width: 8),
                          Text(m.label, style: AppTextStyles.body2),
                          const Spacer(),
                          Text('¥${_fmt(amt)}',
                              style: AppTextStyles.body2.copyWith(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }),
                ],

                // おつり
                if (change > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_yen,
                            size: 16, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text('おつり',
                            style: AppTextStyles.body2
                                .copyWith(color: AppColors.success)),
                        const Spacer(),
                        Text('¥${_fmt(change)}',
                            style: AppTextStyles.h4
                                .copyWith(color: AppColors.success)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                Text('この操作は取り消せません。',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),

                // 버튼
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52)),
                        child: const Text('戻る'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text('決済する',
                                style: AppTextStyles.button.copyWith(
                                    color: Colors.white, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true) _confirmPayment();
  }

  Future<void> _confirmPayment() async {
    final snapshot = _amounts; // ValueNotifier のスナップショット
    if (_calcRemaining(snapshot) > 0 || _processing) return;
    setState(() => _processing = true);
    try {
      final pos = ref.read(posProvider);
      final total = pos.grandTotal;
      // completeSale() の後は posProvider がクリアされるため、await 前にキャプチャ
      final change = _calcChange(snapshot);
      final payments = <Map<String, dynamic>>[];
      var remaining = total;
      for (final key in _selectedMethods) {
        if (remaining <= 0) break;
        final rawAmt = snapshot[key] ?? 0;
        final actual = rawAmt.clamp(0, remaining);
        if (actual > 0) {
          payments.add({'method': key, 'amount': actual});
          remaining -= actual;
        }
      }
      final saleId = await ref
          .read(posProvider.notifier)
          .completeSale(sessionId: widget.session.id, payments: payments);

      // 앱바 매출 즉시 갱신
      ref.invalidate(todayRevenueProvider);

      if (mounted) {
        final earned = (total * 0.01).floor();
        // 완료 화면용 결제 내역 (수단 → 실제 지불 금액)
        final completedPayments = <String, int>{};
        for (final p in payments) {
          completedPayments[p['method'] as String] = p['amount'] as int;
        }
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => _CompletionScreen(
              saleId: saleId,
              total: total,
              change: change,
              pointEarned: earned,
              customerName: pos.customerName,
              customerId: pos.customerId,
              payments: completedPayments,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showTopBanner(context, '決済エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
        setState(() => _processing = false);
      }
    }
  }
}

// ─── 결제화면 왼쪽 패널 ────────────────────────────────────────────────────
class _OrderSummary extends ConsumerWidget {
  const _OrderSummary({required this.pos});
  final PosState pos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 주문 내용 리스트
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              children: [
                ...pos.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.qty > 1
                                      ? '${item.name} ×${item.qty}'
                                      : item.name,
                                  style: AppTextStyles.body2,
                                ),
                                if (item.discountAmount > 0)
                                  Text('-¥${_fmt(item.discountAmount)}',
                                      style: AppTextStyles.caption
                                          .copyWith(color: AppColors.error)),
                              ],
                            ),
                          ),
                          Text('¥${_fmt(item.total)}', style: AppTextStyles.label),
                        ],
                      ),
                    )),
                if (pos.manualDiscountAmount > 0) ...[
                  const Divider(height: 10),
                  _SummaryRow('全体割引', -pos.manualDiscountAmount, color: AppColors.error),
                ],
                if (pos.pointUsed > 0) ...[
                  const Divider(height: 10),
                  _SummaryRow('ポイント使用', -pos.pointUsed, color: AppColors.success),
                ],
                const Divider(height: 10),
                _SummaryRow('小計(税抜)', pos.subtotal - pos.totalTax),
                if (pos.taxAmount10 > 0)
                  _SummaryRow('消費税10%', pos.taxAmount10, isSmall: true),
                if (pos.taxAmount8 > 0)
                  _SummaryRow('消費税8%', pos.taxAmount8, isSmall: true),
              ],
            ),
          ),
          // ④ 포인트 사용 버튼 (고객 등록 시)
          if (pos.customerId != null)
            _PointUsageRow(pos: pos),
          const Divider(height: 1),
          // ⑤ 합계
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Text('合計', style: AppTextStyles.h4),
                const Spacer(),
                Text('¥${_fmt(pos.grandTotal)}',
                    style: AppTextStyles.priceMedium
                        .copyWith(color: AppColors.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 포인트 사용 행 (버튼 → 숫자패드 다이얼로그) ────────────────────────────
class _PointUsageRow extends ConsumerStatefulWidget {
  const _PointUsageRow({required this.pos});
  final PosState pos;

  @override
  ConsumerState<_PointUsageRow> createState() => _PointUsageRowState();
}

class _PointUsageRowState extends ConsumerState<_PointUsageRow> {
  int _balance = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void didUpdateWidget(_PointUsageRow old) {
    super.didUpdateWidget(old);
    if (widget.pos.customerId != old.pos.customerId) _loadBalance();
  }

  Future<void> _loadBalance() async {
    final cid = widget.pos.customerId;
    if (cid == null) return;
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.customers)..where((t) => t.id.equals(cid))).get();
    if (mounted && rows.isNotEmpty) {
      setState(() {
        _balance = rows.first.pointBalance;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _balance <= 0) return const SizedBox.shrink();

    final used = widget.pos.pointUsed;

    return InkWell(
      onTap: () => _showNumpad(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        color: AppColors.successLight.withOpacity(0.4),
        child: Row(
          children: [
            const Icon(Icons.loyalty_outlined, size: 16, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ポイント利用',
                      style: AppTextStyles.body2.copyWith(
                          color: AppColors.success, fontWeight: FontWeight.w600)),
                  Text('残 ${_balance}pt',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
            if (used > 0) ...[
              Text('-¥${_fmt(used)}',
                  style: AppTextStyles.body2.copyWith(
                      color: AppColors.success, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => ref.read(posProvider.notifier).setPointUsed(0),
                child: const Icon(Icons.close, size: 15, color: AppColors.textSecondary),
              ),
            ] else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text('入力',
                    style: AppTextStyles.caption.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  void _showNumpad(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PointNumpadDialog(
        balance: _balance,
        current: widget.pos.pointUsed,
        maxAmount: widget.pos.grandTotal + widget.pos.pointUsed,
      ),
    );
  }
}

// ─── 포인트 숫자패드 다이얼로그 ────────────────────────────────────────────
class _PointNumpadDialog extends ConsumerStatefulWidget {
  const _PointNumpadDialog({
    required this.balance,
    required this.current,
    required this.maxAmount,
  });
  final int balance;
  final int current;
  final int maxAmount;

  @override
  ConsumerState<_PointNumpadDialog> createState() => _PointNumpadDialogState();
}

class _PointNumpadDialogState extends ConsumerState<_PointNumpadDialog> {
  String _input = '';

  @override
  void initState() {
    super.initState();
    _input = widget.current > 0 ? '${widget.current}' : '';
  }

  int get _value => int.tryParse(_input) ?? 0;
  int get _max => widget.balance.clamp(0, widget.maxAmount);

  void _tap(String key) {
    setState(() {
      if (key == '⌫') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (key == '00') {
        if (_input.isNotEmpty) _input += '00';
      } else {
        if (_input == '0') {
          _input = key;
        } else {
          _input += key;
        }
        // 최대값 초과 방지
        if (_value > _max) _input = '$_max';
      }
    });
  }

  void _apply() {
    final v = _value.clamp(0, _max);
    ref.read(posProvider.notifier).setPointUsed(v);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final max = _max;
    final keys = ['1','2','3','4','5','6','7','8','9','00','0','⌫'];

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Row(
                children: [
                  const Icon(Icons.loyalty_outlined, size: 18, color: AppColors.success),
                  const SizedBox(width: 8),
                  Text('ポイント利用',
                      style: AppTextStyles.h4.copyWith(color: AppColors.success)),
                  const Spacer(),
                  Text('残 ${widget.balance}pt',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 12),
              // 입력 표시
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: v > 0 ? AppColors.success : AppColors.border,
                    width: v > 0 ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded, size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      _input.isEmpty ? '0' : _input,
                      style: AppTextStyles.h3.copyWith(
                          color: v > 0 ? AppColors.success : AppColors.textDisabled,
                          fontWeight: FontWeight.w700),
                    ),
                    Text(' pt', style: AppTextStyles.body2.copyWith(
                        color: AppColors.textSecondary)),
                    const Spacer(),
                    if (v > 0)
                      Text('-¥${_fmt(v)}',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.success, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 全額使用 버튼
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => setState(() => _input = '$max'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.success,
                    side: const BorderSide(color: AppColors.success),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  child: Text('全額使用 (${max}pt)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              // 숫자 패드
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                childAspectRatio: 1.8,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: keys.map((k) {
                  final isBack = k == '⌫';
                  return InkWell(
                    onTap: () => _tap(k),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isBack ? AppColors.errorLight : AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: isBack
                          ? const Icon(Icons.backspace_outlined, size: 18, color: AppColors.error)
                          : Text(k,
                              style: AppTextStyles.h4.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              // 버튼
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('キャンセル'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success),
                      child: const Text('適用'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 결제화면 AppBar ──────────────────────────────────────────────────────
class _PayAppBar extends ConsumerWidget {
  const _PayAppBar({
    required this.pos,
    required this.processing,
    required this.onBack,
  });
  final PosState pos;
  final bool processing;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ← 1/4: 뒤로 + 타이틀
          Expanded(
            flex: 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: processing ? null : onBack,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, size: 20,
                            color: processing
                                ? AppColors.textDisabled
                                : AppColors.textPrimary),
                        onPressed: processing ? null : onBack,
                      ),
                      Text('お会計', style: AppTextStyles.h4),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // 오른쪽 3/4: 고객 + 담당자 + 메모 균등 분할
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _AppBarCustomerChip(pos: pos)),
                const VerticalDivider(width: 1),
                Expanded(child: _AppBarStaffChip(pos: pos)),
                const VerticalDivider(width: 1),
                Expanded(child: _AppBarMemoChip(notes: pos.notes)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AppBar 고객 칩 ────────────────────────────────────────────────────────
class _AppBarCustomerChip extends ConsumerStatefulWidget {
  const _AppBarCustomerChip({required this.pos});
  final PosState pos;

  @override
  ConsumerState<_AppBarCustomerChip> createState() => _AppBarCustomerChipState();
}

class _AppBarCustomerChipState extends ConsumerState<_AppBarCustomerChip> {
  Customer? _customer;
  String? _loadedId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(_AppBarCustomerChip old) {
    super.didUpdateWidget(old);
    _maybeLoad();
  }

  void _maybeLoad() {
    if (widget.pos.customerId == _loadedId) return;
    _loadedId = widget.pos.customerId;
    _customer = null;
    if (_loadedId != null) _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final c = await (db.select(db.customers)
          ..where((t) => t.id.equals(_loadedId!)))
        .getSingleOrNull();
    if (mounted) setState(() => _customer = c);
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.pos.customerId;
    final name = widget.pos.customerName;
    final cust = _customer;
    final isEmpty = id == null;

    return SizedBox.expand(
      child: Material(
        color: isEmpty ? Colors.transparent : AppColors.primaryLight.withOpacity(0.4),
        child: InkWell(
          onTap: isEmpty
              ? () => _selectCustomer(context)
              : () => _showDetail(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  isEmpty ? Icons.person_add_outlined : Icons.person_rounded,
                  size: 18,
                  color: isEmpty ? AppColors.textDisabled : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: isEmpty
                      ? Text('お客様を追加',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.textDisabled,
                              fontStyle: FontStyle.italic))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name ?? '',
                                style: AppTextStyles.label.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                            if (cust != null)
                              Row(children: [
                                Text('${cust.totalVisits}回来店',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontSize: 11)),
                                if (cust.pointBalance > 0) ...[
                                  const SizedBox(width: 6),
                                  Text('${cust.pointBalance}pt',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.warning,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ]),
                          ],
                        ),
                ),
                // 선택된 상태: 변更 + × 버튼
                if (!isEmpty) ...[
                  GestureDetector(
                    onTap: () => _selectCustomer(context),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.swap_horiz, size: 16,
                          color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 2),
                  GestureDetector(
                    onTap: () => ref.read(posProvider.notifier).clearCustomer(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16,
                          color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectCustomer(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 480, height: 520,
          child: CustomerSearchSheet(
            onSelected: (id, name) {
              ref.read(posProvider.notifier).setCustomer(id, name);
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context) async {
    final id = widget.pos.customerId;
    if (id == null) return;
    final name = widget.pos.customerName ?? '';
    final db = ProviderScope.containerOf(context).read(databaseProvider);
    Customer? cust;
    List<Appointment> visits = [];
    List<Sale> sales = [];
    try {
      cust = await (db.select(db.customers)..where((t) => t.id.equals(id))).getSingleOrNull();
      visits = await (db.select(db.appointments)
            ..where((t) => t.customerId.equals(id) & t.status.equals('completed'))
            ..orderBy([(t) => OrderingTerm.desc(t.startAt)])
            ..limit(20))
          .get();
      sales = await (db.select(db.sales)
            ..where((t) => t.customerId.equals(id))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(20))
          .get();
    } catch (_) {}
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CustomerDetailDialog(
        customerId: id,
        customerName: name,
        customer: cust,
        visits: visits,
        purchases: sales,
      ),
    );
  }
}

// ─── 고객 상세 다이얼로그 (StatelessWidget — 데이터는 호출 측에서 사전 로드)
class _CustomerDetailDialog extends StatelessWidget {
  const _CustomerDetailDialog({
    required this.customerId,
    required this.customerName,
    required this.customer,
    required this.visits,
    required this.purchases,
  });
  final String customerId;
  final String customerName;
  final Customer? customer;
  final List<Appointment> visits;
  final List<Sale> purchases;

  @override
  Widget build(BuildContext context) {
    final cust = customer;
    return DefaultTabController(
      length: 3,
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 520,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.primaryLight,
                      child: Text(
                        customerName.isNotEmpty ? customerName[0] : '?',
                        style: AppTextStyles.h4.copyWith(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(customerName,
                                  style: AppTextStyles.h4,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (cust?.isVip == true) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('VIP',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.warning, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 4),
                          Row(children: [
                            _StatChip(
                                label: '来店',
                                value: '${cust?.totalVisits ?? 0}回',
                                color: AppColors.primary),
                            const SizedBox(width: 8),
                            _StatChip(
                                label: 'ポイント',
                                value: '${cust?.pointBalance ?? 0}pt',
                                color: AppColors.warning),
                            if (cust?.cautionFlag == true) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.warning_amber_rounded,
                                  size: 14, color: AppColors.error),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              if (cust?.cautionNote != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.errorLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('⚠ ${cust!.cautionNote}',
                        style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                  ),
                ),
              const SizedBox(height: 12),
              TabBar(
                tabs: const [
                  Tab(text: '基本情報'),
                  Tab(text: '来店履歴'),
                  Tab(text: '購買履歴'),
                ],
                labelStyle: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                unselectedLabelStyle: AppTextStyles.caption,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2,
              ),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildBasic(cust),
                    _buildVisits(),
                    _buildPurchases(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasic(Customer? cust) {
    if (cust == null) {
      return Center(
        child: Text('顧客情報なし',
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
      );
    }
    final rows = <_InfoRow>[
      if (cust.phone != null) _InfoRow('電話', cust.phone!),
      if (cust.email != null) _InfoRow('メール', cust.email!),
      if (cust.birthDate != null) _InfoRow('誕生日', cust.birthDate!),
      if (cust.allergies != null) _InfoRow('アレルギー', cust.allergies!, color: AppColors.error),
      if (cust.notes != null && cust.notes!.isNotEmpty) _InfoRow('メモ', cust.notes!),
    ];
    if (rows.isEmpty) {
      return Center(
        child: Text('追加情報なし',
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: rows.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(r.label,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(r.value,
                  style: AppTextStyles.body2.copyWith(
                      color: r.color ?? AppColors.textPrimary)),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildVisits() {
    if (visits.isEmpty) {
      return Center(
        child: Text('来店履歴なし',
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: visits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final apt = visits[i];
        final dt = apt.startAt.length >= 10 ? apt.startAt.substring(0, 10) : apt.startAt;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
              const SizedBox(width: 8),
              Text(dt, style: AppTextStyles.body2),
              const Spacer(),
              Text(apt.status,
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPurchases() {
    if (purchases.isEmpty) {
      return Center(
        child: Text('購買履歴なし',
            style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: purchases.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final sale = purchases[i];
        final dt = sale.createdAt.length >= 10 ? sale.createdAt.substring(0, 10) : sale.createdAt;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.receipt_outlined, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(dt, style: AppTextStyles.body2),
              const Spacer(),
              Text('¥${_fmt(sale.totalAmount)}',
                  style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: RichText(
        text: TextSpan(
          style: AppTextStyles.caption.copyWith(fontSize: 10),
          children: [
            TextSpan(text: '$label ', style: TextStyle(color: AppColors.textSecondary)),
            TextSpan(text: value,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ─── AppBar 담당자 칩 ─────────────────────────────────────────────────────
class _AppBarStaffChip extends ConsumerStatefulWidget {
  const _AppBarStaffChip({required this.pos});
  final PosState pos;

  @override
  ConsumerState<_AppBarStaffChip> createState() => _AppBarStaffChipState();
}

class _AppBarStaffChipState extends ConsumerState<_AppBarStaffChip> {
  String? _staffId;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _staffId = widget.pos.selectedStaffId;
  }

  Future<String?> _fetchLastUsedStaffId() async {
    final db = ref.read(databaseProvider);
    final result = await db.customSelect(
      'SELECT staff_id FROM sales WHERE staff_id IS NOT NULL ORDER BY created_at DESC LIMIT 1',
    ).getSingleOrNull();
    return result?.read<String?>('staff_id');
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(activeStaffProvider);
    return staffAsync.when(
      data: (staffList) {
        if (staffList.isEmpty) return const SizedBox.shrink();
        if (!_initialized) {
          _initialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            String? id = _staffId ?? await _fetchLastUsedStaffId();
            if (id == null || !staffList.any((s) => s.id == id)) {
              id = staffList.first.id;
            }
            if (mounted && id != _staffId) {
              setState(() => _staffId = id);
              ref.read(posProvider.notifier).setStaff(id);
            }
          });
        }
        final current = staffList.firstWhere(
          (s) => s.id == _staffId,
          orElse: () => staffList.first,
        );
        final isEmpty = _staffId == null;
        final selectedStaff = isEmpty
            ? null
            : staffList.firstWhere((s) => s.id == _staffId,
                orElse: () => staffList.first);
        return SizedBox.expand(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showPicker(context, staffList),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.content_cut_rounded,
                      size: 18,
                      color: isEmpty ? AppColors.textDisabled : AppColors.textPrimary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: isEmpty
                          ? Text('担当者を選択',
                              style: AppTextStyles.body2.copyWith(
                                  color: AppColors.textDisabled,
                                  fontStyle: FontStyle.italic))
                          : Row(children: [
                              if (selectedStaff?.color != null)
                                Container(
                                  width: 8, height: 8,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: _staffColor(selectedStaff!.color),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Expanded(
                                child: Text(selectedStaff?.name ?? '',
                                    style: AppTextStyles.label.copyWith(
                                        fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ]),
                    ),
                    const Icon(Icons.expand_more, size: 16,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _showPicker(BuildContext context, List<StaffData> staffList) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('担当者を選択'),
        children: [
          // 선택없음 옵션
          SimpleDialogOption(
            onPressed: () {
              setState(() => _staffId = null);
              ref.read(posProvider.notifier).setStaff(null);
              Navigator.pop(ctx);
            },
            child: Row(children: [
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: AppColors.textDisabled,
                  shape: BoxShape.circle,
                ),
              ),
              Text('選択なし',
                  style: AppTextStyles.body2.copyWith(
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary)),
              if (_staffId == null) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16, color: AppColors.primary),
              ],
            ]),
          ),
          const Divider(height: 1),
          ...staffList.map<Widget>((s) => SimpleDialogOption(
            onPressed: () {
              setState(() => _staffId = s.id);
              ref.read(posProvider.notifier).setStaff(s.id);
              Navigator.pop(ctx);
            },
            child: Row(children: [
              Container(
                width: 10, height: 10,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: _staffColor(s.color),
                  shape: BoxShape.circle,
                ),
              ),
              Text(s.name,
                  style: AppTextStyles.body2.copyWith(
                      fontWeight: s.id == _staffId ? FontWeight.w700 : FontWeight.normal,
                      color: s.id == _staffId ? AppColors.primary : AppColors.textPrimary)),
              if (s.id == _staffId) ...[
                const Spacer(),
                const Icon(Icons.check, size: 16, color: AppColors.primary),
              ],
            ]),
          )),
        ],
      ),
    );
  }

  Color _staffColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.textSecondary;
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return AppColors.textSecondary;
    }
  }
}

// ─── AppBar 메모 칩 ───────────────────────────────────────────────────────
class _AppBarMemoChip extends ConsumerWidget {
  const _AppBarMemoChip({required this.notes});
  final String? notes;

  static const _presets = [
    'アレルギー確認済み', 'パッチテスト実施', 'カラー希望',
    'パーマ希望', 'トリートメント追加', '次回クーポン適用',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmpty = notes == null || notes!.isEmpty;
    return SizedBox.expand(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDialog(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  isEmpty ? Icons.edit_note_outlined : Icons.sticky_note_2_outlined,
                  size: 18,
                  color: isEmpty ? AppColors.textDisabled : AppColors.textPrimary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: isEmpty
                      ? Text('メモを追加',
                          style: AppTextStyles.body2.copyWith(
                              color: AppColors.textDisabled,
                              fontStyle: FontStyle.italic))
                      : Text(notes!,
                          style: AppTextStyles.body2,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2),
                ),
                if (!isEmpty)
                  GestureDetector(
                    onTap: () => ref.read(posProvider.notifier).setNotes(null),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16,
                          color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: notes ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('メモ'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'メモを入力',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _presets.map((p) => ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 11)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: () { ctrl.text = p; setState(() {}); },
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { ctrl.dispose(); Navigator.pop(ctx); },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                final t = ctrl.text.trim();
                ctrl.dispose();
                Navigator.pop(ctx);
                ref.read(posProvider.notifier).setNotes(t.isEmpty ? null : t);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 결제화면 고객 선택 행 ─────────────────────────────────────────────────
class _PayCustomerRow extends ConsumerStatefulWidget {
  const _PayCustomerRow({required this.pos});
  final PosState pos;

  @override
  ConsumerState<_PayCustomerRow> createState() => _PayCustomerRowState();
}

class _PayCustomerRowState extends ConsumerState<_PayCustomerRow> {
  Future<Customer?>? _customerFuture;
  String? _loadedId;

  void _maybeReload() {
    if (widget.pos.customerId != _loadedId) {
      _loadedId = widget.pos.customerId;
      if (_loadedId == null) {
        _customerFuture = null;
      } else {
        final db = ref.read(databaseProvider);
        _customerFuture = (db.select(db.customers)
              ..where((t) => t.id.equals(_loadedId!)))
            .getSingleOrNull();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeReload();
  }

  @override
  void didUpdateWidget(_PayCustomerRow old) {
    super.didUpdateWidget(old);
    _maybeReload();
  }

  @override
  Widget build(BuildContext context) {
    final customerId = widget.pos.customerId;
    final customerName = widget.pos.customerName;

    return InkWell(
      onTap: () => _selectCustomer(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: customerId != null ? AppColors.primaryLight : AppColors.background,
              child: Icon(
                customerId != null ? Icons.person : Icons.person_add_outlined,
                size: 15,
                color: customerId != null ? AppColors.primary : AppColors.textDisabled,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: customerId != null
                  ? FutureBuilder<Customer?>(
                      future: _customerFuture,
                      builder: (_, snap) {
                        final cust = snap.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(customerName ?? '',
                                  style: AppTextStyles.body2
                                      .copyWith(fontWeight: FontWeight.w600)),
                              if (cust?.isVip == true) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.warningLight,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text('VIP',
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.warning,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ],
                              if (cust?.cautionFlag == true) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.warning_amber_rounded,
                                    size: 12, color: AppColors.error),
                              ],
                            ]),
                            if (cust != null && cust.pointBalance > 0)
                              Row(children: [
                                const Icon(Icons.stars_rounded,
                                    size: 11, color: AppColors.warning),
                                const SizedBox(width: 2),
                                Text('${cust.pointBalance}pt',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.warning, fontSize: 10)),
                              ]),
                          ],
                        );
                      },
                    )
                  : Text('お客様を選択',
                      style: AppTextStyles.body2
                          .copyWith(color: AppColors.textDisabled)),
            ),
            if (customerId != null)
              GestureDetector(
                onTap: () => ref.read(posProvider.notifier).clearCustomer(),
                child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  void _selectCustomer(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: SizedBox(
          width: 480, height: 520,
          child: CustomerSearchSheet(
            onSelected: (id, name) {
              ref.read(posProvider.notifier).setCustomer(id, name);
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }
}

// ─── 결제화면 메모 행 ──────────────────────────────────────────────────────
class _PayNotesRow extends ConsumerWidget {
  const _PayNotesRow({required this.notes});
  final String? notes;

  static const _memoPresets = [
    'アレルギー確認済み', 'パッチテスト実施', 'カラー希望', 'パーマ希望',
    'トリートメント追加', '次回クーポン適用',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _showDialog(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.edit_note_outlined, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: notes != null && notes!.isNotEmpty
                  ? Text(notes!, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text('メモを追加',
                      style: AppTextStyles.caption.copyWith(color: AppColors.textDisabled)),
            ),
            if (notes != null && notes!.isNotEmpty)
              GestureDetector(
                onTap: () => ref.read(posProvider.notifier).setNotes(null),
                child: const Icon(Icons.close, size: 14, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(text: notes ?? '');
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('メモ'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'メモを入力',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _memoPresets
                      .map((p) => ActionChip(
                            label: Text(p, style: const TextStyle(fontSize: 11)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onPressed: () {
                              ctrl.text = p;
                              setState(() {});
                            },
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { ctrl.dispose(); Navigator.pop(ctx); },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                final text = ctrl.text.trim();
                ctrl.dispose();
                Navigator.pop(ctx);
                ref.read(posProvider.notifier).setNotes(text.isEmpty ? null : text);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 담당者 선택 드롭다운 ─────────────────────────────────────────────────
class _StaffSelector extends ConsumerStatefulWidget {
  const _StaffSelector({required this.currentStaffId});
  final String? currentStaffId;

  @override
  ConsumerState<_StaffSelector> createState() => _StaffSelectorState();
}

class _StaffSelectorState extends ConsumerState<_StaffSelector> {
  String? _staffId;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _staffId = widget.currentStaffId;
  }

  /// 마지막으로 사용한 디자이너 ID를 DB에서 가져옴
  Future<String?> _fetchLastUsedStaffId() async {
    final db = ref.read(databaseProvider);
    final result = await db.customSelect(
      'SELECT staff_id FROM sales WHERE staff_id IS NOT NULL ORDER BY created_at DESC LIMIT 1',
    ).getSingleOrNull();
    return result?.read<String?>('staff_id');
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(activeStaffProvider);

    return staffAsync.when(
      data: (staffList) {
        if (staffList.isEmpty) return const SizedBox.shrink();

        // 스태프 목록이 로드됐을 때 한 번만 초기화
        if (!_initialized) {
          _initialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            String? id = _staffId ?? await _fetchLastUsedStaffId();
            // DB에 없거나 비활성화된 경우 첫 번째 스태프로 폴백
            if (id == null || !staffList.any((s) => s.id == id)) {
              id = staffList.first.id;
            }
            if (mounted && id != _staffId) {
              setState(() => _staffId = id);
              ref.read(posProvider.notifier).setStaff(id);
            }
          });
        }

        final current = staffList.firstWhere(
          (s) => s.id == _staffId,
          orElse: () => staffList.first,
        );

        return Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.person_outline,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('担当',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textSecondary)),
              const Spacer(),
              // 드롭다운
              DropdownButton<String>(
                value: current.id,
                underline: const SizedBox.shrink(),
                isDense: true,
                style: AppTextStyles.body2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600),
                icon: const Icon(Icons.expand_more, size: 16,
                    color: AppColors.textSecondary),
                items: staffList
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _staffColor(s.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(s.name),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() => _staffId = id);
                  ref.read(posProvider.notifier).setStaff(id);
                },
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Color _staffColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppColors.textSecondary;
    try {
      return Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      return AppColors.textSecondary;
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.amount,
      {this.color, this.isSmall = false});
  final String label;
  final int amount;
  final Color? color;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    final style =
        isSmall ? AppTextStyles.caption : AppTextStyles.body2;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(
            '${amount < 0 ? '-' : ''}¥${_fmt(amount.abs())}',
            style: style.copyWith(
                fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
// ─── 방안 C: 결제수단 가로 탭 바 (고정 높이 56px, 레이아웃 불변) ──────────
class _MethodTabBar extends StatelessWidget {
  const _MethodTabBar({
    required this.selectedMethods,
    required this.amounts,
    required this.editingKey,
    required this.onSelect,
    required this.onAdd,
    required this.onRemove,
  });
  final List<String> selectedMethods;
  final Map<String, int> amounts;
  final String? editingKey;
  final void Function(String) onSelect;
  final void Function(String) onAdd;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    final canAdd = selectedMethods.length < _allMethods.length;
    final available = _allMethods
        .where((m) => !selectedMethods.contains(m.key))
        .toList();

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // 선택된 수단 탭들
            ...selectedMethods.map((key) {
              final method = _allMethods.firstWhere((m) => m.key == key);
              final amount = amounts[key] ?? 0;
              final isActive = key == editingKey;
              return _MethodTab(
                method: method,
                amount: amount,
                isActive: isActive,
                canRemove: true,
                onTap: () => onSelect(key),
                onRemove: () => onRemove(key),
              );
            }),
            // 수단 추가 버튼 (전체 수단이 다 선택되기 전까지)
            if (canAdd) ...[
              const SizedBox(width: 4),
              _AddMethodPopupBtn(
                available: available,
                onAdd: onAdd,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── 탭 하나 ─────────────────────────────────────────────────────────────
class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.method,
    required this.amount,
    required this.isActive,
    required this.canRemove,
    required this.onTap,
    required this.onRemove,
  });
  final _PayMethod method;
  final int amount;
  final bool isActive;
  final bool canRemove;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 6, top: 9, bottom: 9),
        padding: const EdgeInsets.only(left: 8, right: 4),
        decoration: BoxDecoration(
          color: isActive ? method.color : AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? method.color : AppColors.border,
            width: isActive ? 0 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(method.icon,
                size: 13,
                color: isActive ? Colors.white : method.color),
            const SizedBox(width: 5),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method.label,
                  style: TextStyle(
                    fontFamily: 'NotoSansJP',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                if (amount > 0)
                  Text(
                    '¥${_fmt(amount)}',
                    style: TextStyle(
                      fontFamily: 'NotoSansJP',
                      fontSize: 10,
                      color: isActive
                          ? Colors.white.withAlpha(220)
                          : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            // 삭제 버튼 (2개 이상일 때)
            if (canRemove)
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withAlpha(60)
                        : AppColors.border,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 10,
                    color: isActive ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              )
            else
              const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ─── 결제수단 추가 팝업 버튼 ──────────────────────────────────────────────
class _AddMethodPopupBtn extends StatelessWidget {
  const _AddMethodPopupBtn({required this.available, required this.onAdd});
  final List<_PayMethod> available;
  final void Function(String) onAdd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 13, color: AppColors.primary),
            const SizedBox(width: 3),
            Text('追加',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.primary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('支払方法を追加', style: AppTextStyles.h4),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  color: AppColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),
              const SizedBox(height: 8),
              ...available.map((m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: m.color.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(m.icon, color: m.color, size: 18),
                    ),
                    title: Text(m.label, style: AppTextStyles.body2),
                    onTap: () {
                      Navigator.pop(ctx);
                      onAdd(m.key);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 결제수단 선택 그리드 (토스포스 스타일) ───────────────────────────────
class _MethodSelectGrid extends StatelessWidget {
  const _MethodSelectGrid({required this.onSelect});
  final void Function(String key) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '支払方法を選択',
            style: AppTextStyles.label.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              physics: const NeverScrollableScrollPhysics(),
              children: _allMethods.map((m) {
                return _MethodButton(method: m, onTap: () => onSelect(m.key));
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodButton extends StatelessWidget {
  const _MethodButton({required this.method, required this.onTap});
  final _PayMethod method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: method.color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: method.color.withOpacity(0.25), width: 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(method.icon, color: method.color, size: 24),
              const SizedBox(height: 6),
              Text(
                method.label,
                style: AppTextStyles.label.copyWith(
                  color: method.color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 현금 숫자 패드 ───────────────────────────────────────────────────────
class _CashNumpad extends StatelessWidget {
  const _CashNumpad({
    required this.current,
    required this.grandTotal,
    this.remaining,
    required this.onPreset,
    required this.onInput,
  });
  final int current;
  final int grandTotal;
  final int? remaining; // 분할 결제 시 현금에 할당 가능한 최대 금액 (null = 단독 결제)
  final void Function(int) onPreset;
  final void Function(int) onInput;

  @override
  Widget build(BuildContext context) {
    final isSplit = remaining != null;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 입력 금액 대형 표시 + C(클리어) 버튼
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '¥${_fmt(current)}',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.price,
                    ),
                  ),
                ),
                // C 버튼 - 전체 클리어
                if (current > 0)
                  GestureDetector(
                    onTap: () => onInput(0),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'C',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 분할 결제 시: +¥1000 / +¥5000 / +¥10000 누적 + 残額 버튼
          if (isSplit) ...[
            Row(
              children: [
                ...[1000, 5000, 10000].map((v) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ElevatedButton(
                      onPressed: () {
                        final next = current + v;
                        if (next <= 9999999) onInput(next);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 48),
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: AppColors.border),
                        elevation: 0,
                      ),
                      child: Text('+¥${_fmt(v)}', style: AppTextStyles.label),
                    ),
                  ),
                )),
                // 残額 버튼 — 맨 오른쪽
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ElevatedButton(
                      onPressed: () => onInput(remaining!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: current == remaining!
                            ? AppColors.success
                            : AppColors.surface,
                        foregroundColor: current == remaining!
                            ? Colors.white
                            : AppColors.success,
                        minimumSize: const Size(0, 48),
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: AppColors.success),
                        elevation: 0,
                      ),
                      child: Text('¥${_fmt(remaining!)}',
                          style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ] else ...[
          // 단독 현금 결제: ¥1000 / ¥5000 / ¥10000 누적 + 合計(오른쪽)
          Row(
            children: [
              // ¥1000 / ¥5000 / ¥10000 — 탭할 때마다 누적 추가
              ...[1000, 5000, 10000].map((v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ElevatedButton(
                    onPressed: () {
                      final next = current + v;
                      if (next <= 9999999) onInput(next);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppColors.border),
                      elevation: 0,
                    ),
                    child: Text('+¥${_fmt(v)}', style: AppTextStyles.label),
                  ),
                ),
              )),
              // 合計 버튼 — 맨 오른쪽, 실제 총금액 표시
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ElevatedButton(
                    onPressed: () => onPreset(grandTotal),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: current == grandTotal
                          ? AppColors.success
                          : AppColors.surface,
                      foregroundColor: current == grandTotal
                          ? Colors.white
                          : AppColors.success,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppColors.success),
                      elevation: 0,
                    ),
                    child: Text('¥${_fmt(grandTotal)}',
                        style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          ], // end else (단독 현금)
          const SizedBox(height: 6),
          // 숫자 패드 — Row+Expanded로 화면에 꽉 채움
          ...([
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['000', '0', '⌫'],
          ].map((row) => Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: row.map((k) {
                  final isDel = k == '⌫';
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Material(
                        color: isDel ? AppColors.errorLight : AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            if (isDel) {
                              final s = current.toString();
                              if (s.length <= 1) { onInput(0); return; }
                              onInput(int.parse(s.substring(0, s.length - 1)));
                            } else {
                              final next = int.tryParse('$current$k') ?? current;
                              if (next <= 9999999) onInput(next);
                            }
                          },
                          // ⌫ 길게 누르면 전체 클리어
                          onLongPress: isDel ? () => onInput(0) : null,
                          child: Center(
                            child: Text(
                              k,
                              style: isDel
                                  ? AppTextStyles.h4.copyWith(color: AppColors.error)
                                  : AppTextStyles.h4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ))),
        ],
      ),
    );
  }
}

// ─── 카드/QR/기타 숫자 패드 ─────────────────────────────────────────────────
class _CardNumpad extends StatelessWidget {
  const _CardNumpad({
    required this.current,
    required this.grandTotal,
    required this.remaining,
    required this.method,
    required this.onInput,
  });
  final int current;
  final int grandTotal;
  final int remaining; // 이 수단에 할당 가능한 최대 금액
  final _PayMethod method;
  final void Function(int) onInput;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 입력 금액 대형 표시 + C(클리어) 버튼
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: method.color.withAlpha(180), width: 1.5),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(method.icon, size: 18, color: method.color),
                        const SizedBox(width: 8),
                        Text(
                          '¥${_fmt(current)}',
                          style: AppTextStyles.price.copyWith(color: method.color),
                        ),
                      ],
                    ),
                  ),
                ),
                // C 버튼 - 전체 클리어
                if (current > 0)
                  GestureDetector(
                    onTap: () => onInput(0),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.errorLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'C',
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // +¥1000 / +¥5000 / +¥10000 누적 + 합계금액 버튼
          Row(
            children: [
              ...[1000, 5000, 10000].map((v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ElevatedButton(
                    onPressed: () {
                      final next = current + v;
                      if (next <= 9999999) onInput(next);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.textPrimary,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      side: const BorderSide(color: AppColors.border),
                      elevation: 0,
                    ),
                    child: Text('+¥${_fmt(v)}', style: AppTextStyles.label),
                  ),
                ),
              )),
              // 합계금액 버튼 — 맨 오른쪽
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ElevatedButton(
                    onPressed: () => onInput(remaining),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: current == remaining
                          ? method.color
                          : AppColors.surface,
                      foregroundColor: current == remaining
                          ? Colors.white
                          : method.color,
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: method.color),
                      elevation: 0,
                    ),
                    child: Text('¥${_fmt(remaining)}',
                        style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 숫자 패드
          ...([
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
            ['000', '0', '⌫'],
          ].map((row) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: row.map((k) {
                      final isDel = k == '⌫';
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Material(
                            color: isDel
                                ? AppColors.errorLight
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                if (isDel) {
                                  final s = current.toString();
                                  if (s.length <= 1) {
                                    onInput(0);
                                    return;
                                  }
                                  onInput(int.parse(
                                      s.substring(0, s.length - 1)));
                                } else {
                                  final next =
                                      int.tryParse('$current$k') ?? current;
                                  if (next <= 9999999) onInput(next);
                                }
                              },
                              // ⌫ 길게 누르면 전체 클리어
                              onLongPress: isDel ? () => onInput(0) : null,
                              child: Center(
                                child: Text(
                                  k,
                                  style: isDel
                                      ? AppTextStyles.h4
                                          .copyWith(color: AppColors.error)
                                      : AppTextStyles.h4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ))),
        ],
      ),
    );
  }
}

// ─── 결제 하단 푸터 ───────────────────────────────────────────────────────
class _PaymentFooter extends StatelessWidget {
  const _PaymentFooter({
    required this.total,
    required this.totalPaid,
    required this.remaining,
    required this.change,
    required this.processing,
    required this.onConfirm,
  });
  final int total;
  final int totalPaid;
  final int remaining;
  final int change;
  final bool processing;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          // 결제 합계
          Row(
            children: [
              Text('お支払い合計', style: AppTextStyles.body2),
              const Spacer(),
              Text('¥${_fmt(totalPaid)}',
                  style: AppTextStyles.priceSmall),
            ],
          ),
          // 거스름돈 / 잔액 — 항상 같은 高さ (레이아웃 변화 없음)
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: change > 0
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_yen,
                            size: 16, color: AppColors.success),
                        const SizedBox(width: 6),
                        Text('おつり',
                            style: AppTextStyles.body2
                                .copyWith(color: AppColors.success)),
                        const Spacer(),
                        Text('¥${_fmt(change)}',
                            style: AppTextStyles.h4
                                .copyWith(color: AppColors.success)),
                      ],
                    ),
                  )
                : remaining > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_outlined,
                                size: 16, color: AppColors.error),
                            const SizedBox(width: 6),
                            Text('残り',
                                style: AppTextStyles.body2
                                    .copyWith(color: AppColors.error)),
                            const Spacer(),
                            Text('¥${_fmt(remaining)}',
                                style: AppTextStyles.h4
                                    .copyWith(color: AppColors.error)),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: onConfirm != null
                    ? AppColors.primary
                    : AppColors.border,
              ),
              child: processing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.white),
                        const SizedBox(width: 8),
                        Text('¥${_fmt(total)} 決済する',
                            style: AppTextStyles.button
                                .copyWith(color: Colors.white)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 결제 완료 화면 ───────────────────────────────────────────────────────
class _CompletionScreen extends ConsumerStatefulWidget {
  const _CompletionScreen({
    required this.saleId,
    required this.total,
    required this.change,
    required this.pointEarned,
    this.customerName,
    this.customerId,
    this.payments,
  });
  final String saleId;
  final int total;
  final int change;
  final int pointEarned;
  final String? customerName;
  final String? customerId;
  final Map<String, int>? payments; // 결제 수단별 금액 내역

  @override
  ConsumerState<_CompletionScreen> createState() => _CompletionScreenState();
}

class _CompletionScreenState extends ConsumerState<_CompletionScreen> {
  bool _voided = false;
  List<String> _menuNames = [];
  String _staffName = '';

  @override
  void initState() {
    super.initState();
    _loadSaleDetail();
  }

  Future<void> _loadSaleDetail() async {
    final db = ref.read(databaseProvider);
    final items = await (db.select(db.saleItems)
          ..where((t) => t.saleId.equals(widget.saleId)))
        .get();
    final sale = await (db.select(db.sales)
          ..where((t) => t.id.equals(widget.saleId)))
        .getSingleOrNull();
    if (sale != null) {
      final staff = await (db.select(db.staff)
            ..where((t) => t.id.equals(sale.staffId)))
          .getSingleOrNull();
      if (mounted) {
        setState(() {
          _menuNames = items.map((i) => i.itemName).toList();
          _staffName = staff?.name ?? '';
        });
      }
    }
  }

  void _addNextBooking(BuildContext context) {
    // 内容から次回開始時刻をデフォルト翌週に設定
    final nextWeek = DateTime.now().add(const Duration(days: 7));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentFormScreen(
          initialStartAt: nextWeek.copyWith(
              hour: 10, minute: 0, second: 0, millisecond: 0),
          initialCustomerId: widget.customerId,
          initialCustomerName: widget.customerName,
        ),
      ),
    );
  }

  Future<void> _voidSale() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('この会計を無効にしますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('合計: ¥${_fmt(widget.total)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              '無効にすると売上から除外されます。\n払い戻し（現金返金）が必要な場合は「払い戻し」を使用してください。',
              style: AppTextStyles.body2
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('無効にする',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final db = ref.read(databaseProvider);
      await (db.update(db.sales)
            ..where((t) => t.id.equals(widget.saleId)))
          .write(const SalesCompanion(
        status: Value('voided'),
      ));
      if (mounted) setState(() => _voided = true);
    } catch (e) {
      if (mounted) {
        showTopBanner(context, 'エラー: $e',
            color: AppColors.error, icon: Icons.error_outline);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _voided
        ? const Color(0xFFFFF1F2)
        : const Color(0xFFF0FDF4);

    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 左: 完了情報 ─────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 아이콘
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: _voided ? AppColors.error : AppColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_voided ? AppColors.error : AppColors.success)
                              .withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      _voided ? Icons.block : Icons.check,
                      size: 44, color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_voided ? '会計無効' : 'お会計完了',
                      style: AppTextStyles.h2),
                  if (widget.customerName != null) ...[
                    const SizedBox(height: 6),
                    Text('${widget.customerName} 様',
                        style: AppTextStyles.body2
                            .copyWith(color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 32),

                  // 금액 카드
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _voided
                              ? AppColors.error.withOpacity(0.25)
                              : AppColors.border,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('お支払い合計',
                                  style: AppTextStyles.body2
                                      .copyWith(color: AppColors.textSecondary)),
                              Text('¥${_fmt(widget.total)}',
                                  style: AppTextStyles.price.copyWith(
                                    fontSize: 28,
                                    color: _voided
                                        ? AppColors.textDisabled
                                        : AppColors.textPrimary,
                                    decoration: _voided
                                        ? TextDecoration.lineThrough
                                        : null,
                                  )),
                            ],
                          ),

                          // おつり
                          if (widget.change > 0 && !_voided) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.successLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.currency_yen,
                                      size: 18, color: AppColors.success),
                                  const SizedBox(width: 6),
                                  Text('おつり',
                                      style: AppTextStyles.body2.copyWith(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w600)),
                                  const Spacer(),
                                  Text('¥${_fmt(widget.change)}',
                                      style: AppTextStyles.h3
                                          .copyWith(color: AppColors.success)),
                                ],
                              ),
                            ),
                          ],

                          // 분할 결제 내역
                          if (!_voided &&
                              widget.payments != null &&
                              widget.payments!.length > 1) ...[
                            const SizedBox(height: 14),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text('支払内訳',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...widget.payments!.entries.map((e) {
                              final m = _allMethods.firstWhere(
                                  (m) => m.key == e.key,
                                  orElse: () => _PayMethod(
                                      e.key, e.key, Icons.payment,
                                      AppColors.primary));
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 26, height: 26,
                                      decoration: BoxDecoration(
                                        color: m.color.withAlpha(25),
                                        borderRadius:
                                            BorderRadius.circular(7),
                                      ),
                                      child: Icon(m.icon,
                                          size: 14, color: m.color),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(m.label,
                                        style: AppTextStyles.body2),
                                    const Spacer(),
                                    Text('¥${_fmt(e.value)}',
                                        style: AppTextStyles.body2.copyWith(
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // 시술 메뉴 카드
                  if (_menuNames.isNotEmpty && !_voided) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.content_cut,
                                    size: 15, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text('施術メニュー',
                                    style: AppTextStyles.caption.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w600)),
                                if (_staffName.isNotEmpty) ...[
                                  const Spacer(),
                                  Text(_staffName,
                                      style: AppTextStyles.caption.copyWith(
                                          color: AppColors.textSecondary)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            ..._menuNames.map((name) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.5),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(name,
                                          style: AppTextStyles.body2.copyWith(
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 포인트 적립
                  if (widget.pointEarned > 0 && !_voided) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.warningLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.warning.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stars,
                                size: 20, color: AppColors.warning),
                            const SizedBox(width: 10),
                            Text('+${_fmt(widget.pointEarned)} ポイント獲得',
                                style: AppTextStyles.body2.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 무효 배너
                  if (_voided) ...[
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: AppColors.errorLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.error.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.block,
                                size: 18, color: AppColors.error),
                            const SizedBox(width: 10),
                            Text('この会計は無効になりました',
                                style: AppTextStyles.body2.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Divider
          const VerticalDivider(width: 1, color: AppColors.border),

          // ── 右: アクションボタン ───────────────────────────────────────
          Container(
            width: 272,
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 메인 액션: 次のお客様へ
                SizedBox(
                  height: 80,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).popUntil((r) => r.isFirst),
                    icon: const Icon(Icons.arrow_forward,
                        color: Colors.white, size: 26),
                    label: Text('次のお客様へ',
                        style: AppTextStyles.h3
                            .copyWith(color: Colors.white, fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                  ),
                ),

                if (!_voided) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('その他の操作',
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary)),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 次回予約
                  if (widget.customerId != null)
                    OutlinedButton.icon(
                      onPressed: () => _addNextBooking(context),
                      icon: const Icon(Icons.event_available_outlined,
                          color: AppColors.primary, size: 22),
                      label: const Text('次回予約を作成',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 64),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  if (widget.customerId != null) const SizedBox(height: 10),

                  // 領収書
                  OutlinedButton.icon(
                    onPressed: () => _showReceiptOptions(context),
                    icon: const Icon(Icons.receipt_long_outlined, size: 22),
                    label: const Text('領収書を発行',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 64),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 払い戻し
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              RefundScreen(saleId: widget.saleId)),
                    ),
                    icon: const Icon(Icons.keyboard_return,
                        color: AppColors.error, size: 22),
                    label: const Text('払い戻し',
                        style: TextStyle(
                            color: AppColors.error,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 64),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 会計無効
                  OutlinedButton.icon(
                    onPressed: _voidSale,
                    icon: const Icon(Icons.block,
                        color: AppColors.textSecondary, size: 20),
                    label: const Text('会計を無効にする',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 64),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showReceiptOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _ReceiptDialog(
        saleId: widget.saleId,
        customerName: widget.customerName,
      ),
    );
  }
}

// ─── 영수증 다이얼로그 ────────────────────────────────────────────────────
class _ReceiptDialog extends ConsumerWidget {
  const _ReceiptDialog({required this.saleId, this.customerName});
  final String saleId;
  final String? customerName;

  String _payMethodLabel(String key) {
    const m = {
      'cash': '現金',
      'credit_card': 'クレジット',
      'ic_card': 'IC・電子マネー',
      'qr': 'QR決済',
      'gift_card': 'ギフトカード',
      'point': 'ポイント',
    };
    return m[key] ?? key;
  }

  Future<Map<String, dynamic>> _load(AppDatabase db) async {
    final sale = await (db.select(db.sales)..where((t) => t.id.equals(saleId))).getSingleOrNull();
    final items = await (db.select(db.saleItems)..where((t) => t.saleId.equals(saleId))..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();
    final payments = await (db.select(db.salePayments)..where((t) => t.saleId.equals(saleId))).get();
    final settings = await db.settings;
    return {'sale': sale, 'items': items, 'payments': payments, 'settings': settings};
  }

  String _buildReceiptText(Map<String, dynamic> data) {
    final sale = data['sale'] as Sale?;
    final items = data['items'] as List<SaleItem>;
    final payments = data['payments'] as List<SalePayment>;
    final settings = data['settings'] as SalonSetting?;
    if (sale == null) return '';

    final buf = StringBuffer();
    buf.writeln('================================');
    buf.writeln('  ${settings?.salonName ?? 'サロン'}');
    buf.writeln('================================');
    buf.writeln('領収書 No. ${sale.saleNo}');
    buf.writeln('日付: ${sale.saleDate.substring(0, 10)}');
    if (customerName != null) buf.writeln('お客様: $customerName 様');
    buf.writeln('--------------------------------');
    for (final item in items) {
      final line = '${item.itemName}';
      final price = '¥${_fmt(item.totalPrice)}';
      buf.writeln('$line${price.padLeft(32 - line.length)}');
      if (item.quantity > 1) buf.writeln('  x${item.quantity} @ ¥${_fmt(item.unitPrice)}');
    }
    buf.writeln('--------------------------------');
    buf.writeln('小計${'¥${_fmt(sale.subtotal)}'.padLeft(28)}');
    if (sale.discountAmount > 0) buf.writeln('値引き${'-¥${_fmt(sale.discountAmount)}'.padLeft(25)}');
    if (sale.pointUsed > 0) buf.writeln('ポイント利用${'-¥${_fmt(sale.pointUsed)}'.padLeft(22)}');
    buf.writeln('================================');
    buf.writeln('合計${'¥${_fmt(sale.totalAmount)}'.padLeft(28)}');
    buf.writeln('================================');
    for (final p in payments) {
      buf.writeln('${_payMethodLabel(p.method)}${'¥${_fmt(p.amount)}'.padLeft(30 - _payMethodLabel(p.method).length)}');
    }
    if (sale.pointEarned > 0) buf.writeln('\nポイント積立: +${_fmt(sale.pointEarned)} pt');
    buf.writeln('\nありがとうございました');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _load(db),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError || !snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('エラーが発生しました: ${snap.error}'),
              );
            }

            final data = snap.data!;
            final sale = data['sale'] as Sale?;
            final items = data['items'] as List<SaleItem>;
            final payments = data['payments'] as List<SalePayment>;
            final settings = data['settings'] as SalonSetting?;
            final receiptText = _buildReceiptText(data);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ヘッダー
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text('領収書', style: AppTextStyles.h4),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // 本文
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 店名・日付
                        Center(
                          child: Column(
                            children: [
                              Text(settings?.salonName ?? 'サロン',
                                  style: AppTextStyles.h3),
                              const SizedBox(height: 4),
                              if (sale != null)
                                Text('${sale.saleDate.substring(0, 10)}  No. ${sale.saleNo}',
                                    style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                              if (customerName != null)
                                Text('$customerName 様',
                                    style: AppTextStyles.body2.copyWith(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),

                        // 明細
                        ...items.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(item.itemName, style: AppTextStyles.body2),
                              ),
                              if (item.quantity > 1)
                                Text('x${item.quantity}  ', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                              Text('¥${_fmt(item.totalPrice)}', style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )),
                        const Divider(),

                        // 小計・合計
                        if (sale != null) ...[
                          _SummaryRow('小計', sale.subtotal),
                          if (sale.discountAmount > 0) _SummaryRow('値引き', -sale.discountAmount, color: AppColors.error),
                          if (sale.pointUsed > 0) _SummaryRow('ポイント利用', -sale.pointUsed, color: AppColors.warning),
                          const Divider(thickness: 2),
                          _SummaryRow('合計', sale.totalAmount),
                          const SizedBox(height: 12),

                          // 決済内訳
                          ...payments.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(AppRadius.full),
                                  ),
                                  child: Text(_payMethodLabel(p.method), style: AppTextStyles.caption.copyWith(color: AppColors.primary)),
                                ),
                                const Spacer(),
                                Text('¥${_fmt(p.amount)}', style: AppTextStyles.body2),
                              ],
                            ),
                          )),

                          if (sale.pointEarned > 0) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.warningLight,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: AppColors.warning),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.stars, size: 16, color: AppColors.warning),
                                  const SizedBox(width: 6),
                                  Text('+${_fmt(sale.pointEarned)} ポイント積立',
                                      style: AppTextStyles.caption.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),

                // フッター ボタン
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      // クリップボードコピー
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: receiptText));
                            if (ctx.mounted) {
                              showTopBanner(ctx, 'クリップボードにコピーしました',
                                  color: AppColors.success,
                                  icon: Icons.check_circle_outline,
                                  duration: const Duration(seconds: 2));
                            }
                          },
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('コピー'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 印刷（近日公開）
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('印刷 (準備中)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── 유틸 ─────────────────────────────────────────────────────────────────
String _fmt(int n) {
  if (n < 0) return '-${_fmt(-n)}';
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
