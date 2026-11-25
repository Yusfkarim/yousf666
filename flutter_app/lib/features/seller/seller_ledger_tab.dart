import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class SellerLedgerTab extends ConsumerStatefulWidget {
  const SellerLedgerTab({required this.store, super.key});
  final StoreModel store;

  @override
  ConsumerState<SellerLedgerTab> createState() => _SellerLedgerTabState();
}

class _SellerLedgerTabState extends ConsumerState<SellerLedgerTab> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _settlements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(supabaseProvider);
      final summary = await client.from('store_financial_summary').select().eq('store_id', widget.store.id).maybeSingle();
      final settlements = await client.from('settlements').select('id, amount_iqd, direction, note, created_at').eq('store_id', widget.store.id).order('created_at', ascending: false).limit(50);
      if (!mounted) return;
      setState(() {
        _summary = summary == null ? null : Map<String, dynamic>.from(summary);
        _settlements = List<Map<String, dynamic>>.from(settlements);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _message('حیسابات نەهێنرا: $error');
      }
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  int _number(String key) => (_summary?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) return clayLoading(label: 'حیسابات دەهێنرێت...');
    final commission = widget.store.commissionType == 'percentage'
        ? '${widget.store.commissionValue.toStringAsFixed(commissionDecimal(widget.store.commissionValue))}%'
        : formatIqd(widget.store.commissionValue);
    return RefreshIndicator(
      onRefresh: _load,
      color: ClayColors.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(15, 8, 15, 18), children: [
        sectionTitle('حیسابات و نسبە'),
        ClayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const ClayIconBadge(icon: Icons.account_balance_wallet_rounded, size: 46, tone: ClayTone.orange),
            const SizedBox(width: 10),
            const Expanded(child: Text('نسبەی ئێستای دوکان', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(commission, style: TextStyle(fontWeight: FontWeight.w900, color: context.clayAccent, fontSize: 17)),
          ]),
          const SizedBox(height: 13),
          Row(children: [
            Expanded(child: _FinancialMetric(label: 'فرۆشی گەیەندراو', value: formatIqd(_number('gross_sales_iqd')), icon: Icons.sell_rounded, tone: ClayTone.mint)),
            const SizedBox(width: 9),
            Expanded(child: _FinancialMetric(label: 'ژمارەی داواکاری', value: '${_number('total_delivered_orders')}', icon: Icons.receipt_rounded, tone: ClayTone.lavender)),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: _FinancialMetric(label: 'کۆی کۆمسیۆن', value: formatIqd(_number('total_commission_iqd')), icon: Icons.percent_rounded, tone: ClayTone.coral)),
            const SizedBox(width: 9),
            Expanded(child: _FinancialMetric(label: 'پاکتاوی کراو', value: formatIqd(_number('total_settled_iqd')), icon: Icons.payments_rounded, tone: ClayTone.green)),
          ]),
          const SizedBox(height: 10),
          ClayInsetContainer(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(children: [
              const Expanded(child: Text('باڵانسی ماوە', style: TextStyle(fontWeight: FontWeight.w800))),
              Text(formatIqd(_number('current_balance_due_iqd')), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: context.clayAccent)),
            ]),
          ),
          const SizedBox(height: 8),
          Text('کۆمسیۆن تەنها بۆ داواکارییە گەیەندراوەکان هەژمار دەکرێت.', style: TextStyle(color: context.clayMuted, fontSize: 11)),
        ])),
        sectionTitle('مێژووی پاکتاو'),
        if (_settlements.isEmpty)
          ClayCard(child: Text('هێشتا پاکتاوێک تۆمار نەکراوە.', style: TextStyle(color: context.clayMuted)))
        else
          for (final row in _settlements)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ClayCard(padding: const EdgeInsets.all(12), child: Row(children: [
                ClayIconBadge(
                  icon: row['direction'] == 'store_paid_platform' ? Icons.north_east_rounded : Icons.south_west_rounded,
                  size: 40,
                  tone: row['direction'] == 'store_paid_platform' ? ClayTone.green : ClayTone.lavender,
                ),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row['direction'] == 'store_paid_platform' ? 'دوکان بۆ پلاتفۆرمیدا' : 'پلاتفۆرم بۆ دوکانیدا', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  if ((row['note'] as String? ?? '').isNotEmpty) Text(row['note'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.clayMuted, fontSize: 11)),
                ])),
                Text(formatIqd((row['amount_iqd'] as num?)?.toInt() ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: context.clayAccent)),
              ])),
            ),
      ]),
    );
  }

  int commissionDecimal(num value) => value % 1 == 0 ? 0 : 2;
}

class _FinancialMetric extends StatelessWidget {
  const _FinancialMetric({required this.label, required this.value, required this.icon, required this.tone});
  final String label;
  final String value;
  final IconData icon;
  final ClayTone tone;

  @override
  Widget build(BuildContext context) => ClayInsetContainer(
        padding: const EdgeInsets.all(10),
        radius: 18,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClayIconBadge(icon: icon, size: 31, radius: 10, tone: tone, iconSize: 16),
          const SizedBox(height: 7),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: context.clayMuted)),
        ]),
      );
}
