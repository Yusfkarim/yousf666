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

class SellerOrdersTab extends ConsumerStatefulWidget {
  const SellerOrdersTab({required this.store, super.key});
  final StoreModel store;

  @override
  ConsumerState<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends ConsumerState<SellerOrdersTab> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  final Set<String> _busyOrders = {};
  LocalChannel? _channel;

  MarketplaceClient get _client => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _client
        .channel('seller-orders-${widget.store.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'store_id', value: widget.store.id),
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
      final rows = await _client
          .from('orders')
          .select('id, order_number, buyer_id, store_id, driver_id, status, subtotal_iqd, delivery_fee_iqd, total_iqd, delivery_lat, delivery_lng, delivery_address, buyer_note, created_at, updated_at, delivered_at')
          .eq('store_id', widget.store.id)
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _orders = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (error) {
      if (mounted) setState(() => _loading = false);
      if (mounted) _message('نەتوانرا داواکارییەکان بهێنرێن: $error');
    }
  }

  Future<void> _changeStatus(String id, String status) async {
    setState(() => _busyOrders.add(id));
    try {
      await _client.rpc('update_order_status', params: {'p_order_id': id, 'p_new_status': status});
      await _load(silent: true);
    } catch (error) {
      if (mounted) _message('گۆڕینی دۆخ سەرکەوتوو نەبوو: $error');
    } finally {
      if (mounted) setState(() => _busyOrders.remove(id));
    }
  }

  Future<void> _assignDriver(String orderId) async {
    try {
      final result = await _client.rpc('list_active_drivers');
      final drivers = List<Map<String, dynamic>>.from(result as List);
      if (!mounted) return;
      if (drivers.isEmpty) {
        _message('هیچ شۆفێرێکی چالاک تۆمار نەکراوە.');
        return;
      }
      final driverId = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        builder: (context) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(14),
          children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('شۆفێر هەڵبژێرە', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            for (final driver in drivers)
              ListTile(
                leading: const ClayIconBadge(icon: Icons.delivery_dining_rounded, size: 40, tone: ClayTone.green),
                title: Text(driver['full_name'] as String? ?? 'شۆفێر'),
                subtitle: Text(driver['city'] as String? ?? '', style: TextStyle(color: context.clayMuted)),
                onTap: () => Navigator.pop(context, driver['driver_id'] as String),
              ),
          ],
        ),
      );
      if (driverId == null) return;
      await _client.rpc('assign_order_driver', params: {'p_order_id': orderId, 'p_driver_id': driverId});
      await _load(silent: true);
      if (mounted) _message('داواکارییەکە بۆ شۆفێر پێسپێردرا.');
    } catch (error) {
      if (mounted) _message('پێسپاردنی شۆفێر سەرکەوتوو نەبوو: $error');
    }
  }

  Future<void> _callBuyer(String id) async {
    try {
      final phone = await _client.rpc('get_order_buyer_phone', params: {'p_order_id': id});
      if (!await launchUrl(Uri(scheme: 'tel', path: phone.toString()))) throw StateError('Phone app unavailable');
    } catch (error) {
      if (mounted) _message('$error');
    }
  }

  Future<void> _openMap(Map<String, dynamic> order) async {
    final lat = (order['delivery_lat'] as num?)?.toDouble();
    final lng = (order['delivery_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      _message('GPS بۆ ئەم داواکارییە نییە.');
      return;
    }
    final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'});
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (_loading && _orders.isEmpty) return clayLoading(label: 'داواکارییە نوێیەکان دەهێنرێن...');
    if (_orders.isEmpty) return RefreshIndicator(onRefresh: _load, color: ClayColors.orange, child: ListView(children: [const SizedBox(height: 45), clayEmpty('داواکارییەک نییە', subtitle: 'داواکارییە نوێیەکان لێرە دەردەکەون.') ]));
    return RefreshIndicator(
      onRefresh: _load,
      color: ClayColors.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(15, 8, 15, 16), children: [
        sectionTitle('داواکارییە هاتووەکان'),
        for (final order in _orders) _orderCard(order),
      ]),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final id = order['id'] as String;
    final status = order['status'] as String? ?? 'pending';
    final busy = _busyOrders.contains(id);
    final action = switch (status) {
      'accepted' => ('preparing', 'ئامادەکردن', Icons.soup_kitchen_rounded),
      'preparing' => ('on_the_way', 'ناردن بۆ گەیاندن', Icons.delivery_dining_rounded),
      'on_the_way' => ('delivered', 'گەیەندرا', Icons.task_alt_rounded),
      _ => null,
    };
    final driverNeeded = status == 'preparing' && widget.store.deliveryMode == 'platform_driver' && order['driver_id'] == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClayCard(padding: const EdgeInsets.all(13), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const ClayIconBadge(icon: Icons.receipt_long_rounded, size: 43, tone: ClayTone.orange),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('داواکاری #${order['order_number']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(orderStatusLabel(status), style: TextStyle(fontSize: 12, color: context.clayMuted)),
          ])),
          Text(formatIqd((order['total_iqd'] as num?)?.toInt() ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: context.clayAccent)),
        ]),
        const SizedBox(height: 9),
        ClayInsetContainer(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            Icon(Icons.location_on_outlined, size: 17, color: context.clayAccent),
            const SizedBox(width: 5),
            Expanded(child: Text(order['delivery_address'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
            IconButton(onPressed: () => _openMap(order), tooltip: 'نەخشە', icon: Icon(Icons.map_outlined, color: context.clayAccent), visualDensity: VisualDensity.compact),
          ]),
        ),
        if (status == 'pending') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ClayPillButton(label: busy ? '...' : 'قبووڵکردن', icon: Icons.check_rounded, tone: ClayTone.green, compact: true, onPressed: busy ? null : () => _changeStatus(id, 'accepted'))),
            const SizedBox(width: 8),
            Expanded(child: ClayPillButton(label: 'ڕەتکردنەوە', icon: Icons.close_rounded, tone: ClayTone.coral, compact: true, onPressed: busy ? null : () => _changeStatus(id, 'rejected'))),
          ]),
        ] else if (action != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ClayPillButton(label: busy ? 'تکایە چاوەڕێ بکە...' : driverNeeded ? 'سەرەتا شۆفێر هەڵبژێرە' : action.$2, icon: action.$3, tone: ClayTone.green, compact: true, onPressed: busy || driverNeeded ? null : () => _changeStatus(id, action.$1))),
            const SizedBox(width: 8),
            ClayPillButton(label: 'پەیوەندی', icon: Icons.call_rounded, tone: ClayTone.mint, compact: true, onPressed: () => _callBuyer(id)),
          ]),
          if (widget.store.deliveryMode == 'platform_driver' && (status == 'accepted' || status == 'preparing')) ...[
            const SizedBox(height: 8),
            ClayPillButton(
              label: order['driver_id'] == null ? 'پێسپاردن بۆ شۆفێر' : 'گۆڕینی شۆفێر',
              icon: Icons.delivery_dining_rounded,
              tone: ClayTone.lavender,
              expand: true,
              onPressed: busy ? null : () => _assignDriver(id),
            ),
          ],
        ] else if (status == 'delivered') ...[
          const SizedBox(height: 7),
          Text('گەیاندن تەواو بوو', style: TextStyle(color: context.clayPositive, fontWeight: FontWeight.w700)),
        ],
        Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () => context.push('/order/$id'), child: const Text('وردەکاری و چات'))),
      ])),
    );
  }
}
