import '../../core/services/marketplace_client.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

const _orderColumns = 'id, order_number, buyer_id, store_id, driver_id, status, payment_method, subtotal_iqd, delivery_fee_iqd, total_iqd, commission_type_snapshot, commission_value_snapshot, commission_amount_iqd, store_net_payout_iqd, delivery_lat, delivery_lng, delivery_address, buyer_note, created_at, updated_at, delivered_at, stores(name,owner_id)';

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({required this.orderId, super.key});
  final String orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _busy = false;
  LocalChannel? _channel;

  MarketplaceClient get _client => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _client
        .channel('order-detail-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.orderId),
          callback: (_) => _load(silent: true),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) unawaited(_client.removeChannel(_channel!).then((_) {}));
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final order = await _client.from('orders').select(_orderColumns).eq('id', widget.orderId).single();
      final items = await _client.from('order_items').select().eq('order_id', widget.orderId).order('id');
      if (!mounted) return;
      setState(() {
        _order = Map<String, dynamic>.from(order);
        _items = List<Map<String, dynamic>>.from(items);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (!silent) _message('داواکاری نەدۆزرایەوە: $error');
    }
  }

  Future<void> _changeStatus(String status) async {
    setState(() => _busy = true);
    try {
      await _client.rpc('update_order_status', params: {'p_order_id': widget.orderId, 'p_new_status': status});
      await _load(silent: true);
    } catch (error) {
      if (mounted) _message('گۆڕینی دۆخ سەرکەوتوو نەبوو: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callBuyer() async {
    try {
      final phone = await _client.rpc('get_order_buyer_phone', params: {'p_order_id': widget.orderId});
      final uri = Uri(scheme: 'tel', path: phone.toString());
      if (!await launchUrl(uri)) throw StateError('Phone app is unavailable');
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _openMap() async {
    final lat = (_order?['delivery_lat'] as num?)?.toDouble();
    final lng = (_order?['delivery_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      _message('شوێنی GPS بۆ ئەم داواکارییە دیاری نەکراوە.');
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) _message('نەخشەکە نەکرایەوە.');
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    final role = ref.watch(profileProvider).valueOrNull?['role'] as String? ?? 'buyer';
    if (_loading) return MarketplaceScaffold(body: clayLoading(label: 'داواکاری دەهێنرێت...'));
    if (_order == null) return MarketplaceScaffold(body: clayEmpty('داواکاری بەردەست نییە'));
    final status = _order!['status'] as String? ?? 'pending';
    final storeRow = _order!['stores'];
    final storeName = storeRow is Map<String, dynamic> ? storeRow['name'] as String? ?? 'دوکان' : 'دوکان';
    final isBuyer = _order!['buyer_id'] == user?.id;
    final isOwner = role == 'seller' && storeRow is Map<String, dynamic> && storeRow['owner_id'] == user?.id;
    final action = _nextAction(status, role, isBuyer, isOwner, _order!['driver_id'] == user?.id);
    return MarketplaceScaffold(
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
        ClayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const ClayIconBadge(icon: Icons.receipt_long_rounded, size: 50, tone: ClayTone.orange),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('داواکاری #${_order!['order_number']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(storeName, style: TextStyle(color: context.clayMuted)),
            ])),
            _StatusBadge(status: status),
          ]),
          const SizedBox(height: 15),
          _StatusTimeline(status: status),
          const SizedBox(height: 14),
          for (final item in _items) _OrderItemRow(item: item),
          const Divider(height: 22),
          _TotalRow(label: 'نرخی کاڵا', value: formatIqd((_order!['subtotal_iqd'] as num?)?.toInt() ?? 0)),
          const SizedBox(height: 6),
          _TotalRow(label: 'کرێی گەیاندن', value: formatIqd((_order!['delivery_fee_iqd'] as num?)?.toInt() ?? 0)),
          const SizedBox(height: 7),
          _TotalRow(label: 'کۆی گشتی · COD', value: formatIqd((_order!['total_iqd'] as num?)?.toInt() ?? 0), bold: true),
        ])),
        const SizedBox(height: 12),
        ClayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('شوێنی گەیاندن', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_order!['delivery_address'] as String? ?? '', style: TextStyle(color: context.clayMuted)),
          if ((_order!['buyer_note'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('تێبینی: ${_order!['buyer_note']}', style: TextStyle(color: context.clayMuted)),
          ],
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ClayPillButton(label: 'کردنەوەی نەخشە', icon: Icons.map_rounded, compact: true, tone: ClayTone.green, onPressed: _openMap),
            if (!isBuyer && status != 'pending' && !['rejected', 'cancelled'].contains(status))
              ClayPillButton(label: 'پەیوەندی بە کڕیار', icon: Icons.call_rounded, compact: true, tone: ClayTone.mint, onPressed: _callBuyer),
            if (!['rejected', 'cancelled', 'delivered'].contains(status))
              ClayPillButton(label: 'چات', icon: Icons.chat_bubble_outline_rounded, compact: true, tone: ClayTone.lavender, onPressed: () => context.push('/chat/${widget.orderId}')),
          ]),
        ])),
        if (action != null) ...[
          const SizedBox(height: 12),
          ClayPillButton(
            label: _busy ? 'تکایە چاوەڕێ بکە...' : action.label,
            icon: action.icon,
            tone: action.tone,
            expand: true,
            onPressed: _busy ? null : () => _changeStatus(action.status),
          ),
          if (status == 'pending' && (role == 'seller' || role == 'admin')) ...[
            const SizedBox(height: 8),
            ClayPillButton(
              label: 'ڕەتکردنەوە',
              icon: Icons.close_rounded,
              tone: ClayTone.coral,
              expand: true,
              onPressed: _busy ? null : () => _changeStatus('rejected'),
            ),
          ],
        ],
      ]),
    );
  }

  _StatusAction? _nextAction(String status, String role, bool isBuyer, bool isOwner, bool assignedDriver) {
    if (isBuyer && status == 'pending') return const _StatusAction('cancelled', 'هەڵوەشاندنەوەی داواکاری', Icons.close_rounded, ClayTone.coral);
    if ((role == 'seller' || role == 'admin') && status == 'pending') {
      return const _StatusAction('accepted', 'قبووڵکردنی داواکاری', Icons.check_rounded, ClayTone.green);
    }
    if ((role == 'seller' || role == 'admin') && status == 'accepted') {
      return const _StatusAction('preparing', 'دەستپێکردنی ئامادەکردن', Icons.soup_kitchen_rounded, ClayTone.green);
    }
    if ((role == 'seller' || role == 'admin') && status == 'preparing') {
      return const _StatusAction('on_the_way', 'ناردن بۆ گەیاندن', Icons.delivery_dining_rounded, ClayTone.green);
    }
    if (((role == 'seller' && isOwner) || role == 'admin' || (role == 'driver' && assignedDriver)) && status == 'on_the_way') {
      return const _StatusAction('delivered', 'تۆمارکردنی گەیاندن', Icons.task_alt_rounded, ClayTone.green);
    }
    return null;
  }
}

class _StatusAction {
  const _StatusAction(this.status, this.label, this.icon, this.tone);
  final String status;
  final String label;
  final IconData icon;
  final ClayTone tone;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'delivered' => context.clayPositive,
      'rejected' || 'cancelled' => context.clayNegative,
      _ => context.clayAccent,
    };
    return ClayInsetContainer(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), radius: 99, child: Text(orderStatusLabel(status), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)));
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    const steps = ['pending', 'accepted', 'preparing', 'on_the_way', 'delivered'];
    final current = steps.indexOf(status);
    if (current < 0) return Text(orderStatusLabel(status), style: TextStyle(color: context.clayNegative, fontWeight: FontWeight.w700));
    return Row(children: [
      for (var index = 0; index < steps.length; index++)
        Expanded(child: Column(children: [
          ClayIconBadge(icon: index <= current ? Icons.check_rounded : Icons.circle_outlined, size: 28, radius: 10, tone: index <= current ? ClayTone.green : ClayTone.neutral, iconSize: 15),
          const SizedBox(height: 4),
          SizedBox(
            height: 24,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(orderStatusLabel(steps[index]).replaceAll('لە ', ''), style: TextStyle(fontSize: 9, color: index == current ? context.clayText : context.clayMuted)),
            ),
          ),
        ])),
    ]);
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
        Expanded(child: Text('${item['product_name_snapshot']} × ${item['quantity']}', style: const TextStyle(fontSize: 13))),
        Text(formatIqd((item['line_total_iqd'] as num?)?.toInt() ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]));
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? context.clayText : context.clayMuted))),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: bold ? context.clayAccent : context.clayText)),
      ]);
}
