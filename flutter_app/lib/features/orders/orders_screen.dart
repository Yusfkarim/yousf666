import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/marketplace_repository.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';
import '../../core/models/marketplace_models.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;
  String _role = 'buyer';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _role = ref.read(profileProvider).valueOrNull?['role'] as String? ?? 'buyer';
    _ordersFuture = ref.read(marketplaceRepositoryProvider).getMyOrders(role: _role);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _ordersFuture;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final profileRole = ref.watch(profileProvider).valueOrNull?['role'] as String? ?? _role;
    if (_role != profileRole) {
      _role = profileRole;
      _ordersFuture = ref.read(marketplaceRepositoryProvider).getMyOrders(role: _role);
    }
    if (user == null) {
      return MarketplaceScaffold(body: clayEmpty('چوونەژوورەوە پێویستە', subtitle: 'بۆ بینینی داواکارییەکان بچۆ ژوورەوە.', icon: Icons.receipt_long_rounded));
    }
    return MarketplaceScaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return clayLoading(label: 'داواکارییەکان دەهێنرێن...');
          if (snapshot.hasError) return clayEmpty('نەتوانرا داواکارییەکان بهێنرێن', subtitle: '${snapshot.error}');
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return RefreshIndicator(onRefresh: _refresh, color: ClayColors.orange, child: ListView(children: [const SizedBox(height: 80), clayEmpty('هێشتا داواکارییەک نییە', subtitle: 'کاتێک داواکاری بکەیت، لێرە دەردەکەوێت.') ]));
          return RefreshIndicator(
            onRefresh: _refresh,
            color: ClayColors.orange,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 9, 16, 22),
              children: [
                sectionTitle('داواکارییەکان'),
                for (final row in rows)
                  _OrderCard(
                    row: row,
                    role: _role,
                    onTap: () => context.push('/order/${row['id']}'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.row, required this.role, required this.onTap});
  final Map<String, dynamic> row;
  final String role;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = row['stores'];
    final storeName = store is Map<String, dynamic> ? store['name'] as String? ?? 'دوکان' : 'دوکان';
    final status = row['status'] as String? ?? 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClayCard(
        onTap: onTap,
        padding: const EdgeInsets.all(13),
        child: Row(children: [
          ClayIconBadge(icon: role == 'driver' ? Icons.delivery_dining_rounded : Icons.receipt_long_rounded, size: 46, tone: status == 'delivered' ? ClayTone.green : ClayTone.orange),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('#${row['order_number']} · $storeName', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(orderStatusLabel(status), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(context, status))),
            Text(formatIqd((row['total_iqd'] as num?)?.toInt() ?? 0), style: TextStyle(color: context.clayMuted, fontSize: 12)),
          ])),
          Icon(Icons.chevron_left_rounded, color: context.clayMuted),
        ]),
      ),
    );
  }

  Color _statusColor(BuildContext context, String status) => switch (status) {
        'delivered' => context.clayPositive,
        'rejected' || 'cancelled' => context.clayNegative,
        'pending' => context.clayAccent,
        _ => context.clayMuted,
      };
}
