import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/marketplace_repository.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';
import 'seller_ledger_tab.dart';
import 'seller_orders_tab.dart';
import 'seller_products_tab.dart';
import 'seller_settings_tab.dart';
import 'store_application_form.dart';

class SellerDashboardScreen extends ConsumerStatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  ConsumerState<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends ConsumerState<SellerDashboardScreen> {
  late Future<StoreModel?> _storeFuture;
  StoreModel? _store;
  int _tabIndex = 0;
  bool _handledNewProduct = false;

  @override
  void initState() {
    super.initState();
    _storeFuture = ref.read(marketplaceRepositoryProvider).getMyStore();
  }

  void _reloadStore() {
    setState(() {
      _store = null;
      _storeFuture = ref.read(marketplaceRepositoryProvider).getMyStore();
    });
  }

  Future<void> _openProductEditor(StoreModel store) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ProductEditorSheet(storeId: store.id),
    );
    if (mounted) setState(() => _tabIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(apiProvider).auth.currentUser;
    if (user == null) {
      return MarketplaceScaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ClayCard(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ClayIconBadge(icon: Icons.storefront_rounded, size: 60, tone: ClayTone.orange),
                const SizedBox(height: 12),
                const Text('بۆ داشبۆرد بچۆ ژوورەوە', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 12),
                ClayPillButton(label: 'چوونەژوورەوە', icon: Icons.login_rounded, onPressed: () => context.push('/login')),
              ]),
            ),
          ),
        ),
      );
    }
    return MarketplaceScaffold(
      body: FutureBuilder<StoreModel?>(
        future: _storeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return clayLoading(label: 'داشبۆرد دەکرێتەوە...');
          if (snapshot.hasError) return clayEmpty('نەتوانرا زانیاریی دوکان بهێنرێت', subtitle: '${snapshot.error}');
          final store = _store ?? snapshot.data;
          if (store == null) return StoreApplicationForm(onCreated: _reloadStore);

          final query = GoRouterState.of(context).uri.queryParameters;
          if (query['new'] == '1' && !_handledNewProduct) {
            _handledNewProduct = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _tabIndex = 1);
              _openProductEditor(store);
            });
          } else if (query['new'] != '1') {
            _handledNewProduct = false;
          }

          return Column(children: [
            if (!store.isApproved)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 5, 15, 0),
                child: ClayInsetContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.hourglass_bottom_rounded, color: context.clayAccent, size: 18),
                    SizedBox(width: 7),
                    Expanded(child: Text('داواکاریی دوکانت لە چاوەڕوانی پەسەندکردندایە.', style: TextStyle(fontSize: 12, color: context.clayMuted))),
                  ]),
                ),
              ),
            _SellerTabBar(index: _tabIndex, onSelect: (index) => setState(() => _tabIndex = index)),
            Expanded(child: switch (_tabIndex) {
              0 => SellerOrdersTab(store: store),
              1 => SellerProductsTab(store: store),
              2 => SellerLedgerTab(store: store),
              _ => SellerSettingsTab(store: store, onChanged: (value) => setState(() => _store = value)),
            }),
          ]);
        },
      ),
    );
  }
}

class _SellerTabBar extends StatelessWidget {
  const _SellerTabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      ('داواکاری', Icons.receipt_long_rounded),
      ('کاڵاکان', Icons.inventory_2_rounded),
      ('حیسابات', Icons.account_balance_wallet_rounded),
      ('ڕێکخستن', Icons.settings_rounded),
    ];
    return SizedBox(
      height: 57,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 5),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, itemIndex) => ClayPillButton(
          label: tabs[itemIndex].$1,
          icon: tabs[itemIndex].$2,
          compact: true,
          tone: index == itemIndex ? ClayTone.orange : ClayTone.neutral,
          onPressed: () => onSelect(itemIndex),
        ),
      ),
    );
  }
}
