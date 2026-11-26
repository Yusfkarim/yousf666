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

class DriverViewScreen extends ConsumerStatefulWidget {
  const DriverViewScreen({super.key});

  @override
  ConsumerState<DriverViewScreen> createState() => _DriverViewScreenState();
}

class _DriverViewScreenState extends ConsumerState<DriverViewScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  LocalChannel? _channel;
  MarketplaceClient get _client => ref.read(apiProvider);

  @override
  void initState() {
    super.initState();
    _load();
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      _channel = _client
          .channel('driver-orders-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'driver_id', value: userId),
            callback: (_) => _load(silent: true),
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    if (_channel != null) unawaited(_client.removeChannel(_channel!).then((_) {}));
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final rows = await _client.from('orders').select('id, order_number, store_id, driver_id, status, total_iqd, delivery_lat, delivery_lng, delivery_address, stores(name)').eq('driver_id', userId).order('created_at', ascending: false).limit(100);
      if (mounted) setState(() { _orders = List<Map<String, dynamic>>.from(rows); _loading = false; });
    } catch (error) {
      if (mounted) { setState(() => _loading = false); _message('$error'); }
    }
  }

  Future<void> _deliver(String id) async {
    try {
      await _client.rpc('update_order_status', params: {'p_order_id': id, 'p_new_status': 'delivered'});
      await _load(silent: true);
    } catch (error) { if (mounted) _message('گەیاندن تۆمار نەکرا: $error'); }
  }

  Future<void> _map(Map<String, dynamic> order) async {
    final lat = (order['delivery_lat'] as num?)?.toDouble();
    final lng = (order['delivery_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) { _message('شوێنی GPS دیاری نییە.'); return; }
    await launchUrl(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '$lat,$lng'}), mode: LaunchMode.externalApplication);
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (_client.auth.currentUser == null) return MarketplaceScaffold(body: clayEmpty('چوونەژوورەوە پێویستە'));
    if (_loading && _orders.isEmpty) return MarketplaceScaffold(body: clayLoading(label: 'داواکارییەکان دەهێنرێن...'));
    return MarketplaceScaffold(body: RefreshIndicator(
      onRefresh: _load,
      color: ClayColors.orange,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 9, 16, 20), children: [
        sectionTitle('داواکارییەکانی گەیاندن'),
        if (_orders.isEmpty) clayEmpty('هیچ داواکارییەکی پێسپێردراو نییە', subtitle: 'داواکارییە نوێیەکان کاتێک شۆفێرێک دیاری کرێت دەردەکەون.', icon: Icons.delivery_dining_rounded),
        for (final order in _orders)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: ClayCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const ClayIconBadge(icon: Icons.delivery_dining_rounded, size: 44, tone: ClayTone.green),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('داواکاری #${order['order_number']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(orderStatusLabel(order['status'] as String? ?? ''), style: TextStyle(color: context.clayMuted, fontSize: 12)),
              ])),
              Text(formatIqd((order['total_iqd'] as num?)?.toInt() ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: context.clayAccent)),
            ]),
            const SizedBox(height: 8),
            Text(order['delivery_address'] as String? ?? '', style: TextStyle(color: context.clayMuted)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ClayPillButton(label: 'نەخشە', icon: Icons.map_rounded, compact: true, tone: ClayTone.lavender, onPressed: () => _map(order))),
              if (order['status'] == 'on_the_way') ...[
                const SizedBox(width: 8),
                Expanded(child: ClayPillButton(label: 'گەیەندرا', icon: Icons.task_alt_rounded, compact: true, tone: ClayTone.green, onPressed: () => _deliver(order['id'] as String))),
              ],
              const SizedBox(width: 8),
              IconButton(onPressed: () => context.push('/order/${order['id']}'), icon: Icon(Icons.chat_rounded, color: context.clayAccent)),
            ]),
          ]))),
      ]),
    ));
  }
}
