import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/marketplace_repository.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({required this.storeId, super.key});
  final String storeId;

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  late Future<StoreModel> _storeFuture;
  late Future<List<ProductModel>> _productsFuture;

  MarketplaceRepository get _repository => ref.read(marketplaceRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _storeFuture = _repository.getStore(widget.storeId);
    _productsFuture = _repository.getProducts(widget.storeId);
  }

  @override
  Widget build(BuildContext context) => MarketplaceScaffold(
        secondary: ClayInsetContainer(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          radius: 18,
          child: Row(children: [
            Icon(Icons.delivery_dining_rounded, color: context.clayAccent, size: 18),
            const SizedBox(width: 7),
            Text('COD', style: TextStyle(fontWeight: FontWeight.w700, color: context.clayText)),
            const Spacer(),
            Icon(Icons.map_outlined, color: context.clayMuted, size: 17),
            const SizedBox(width: 5),
            Text('گەیاندن لە شاری خۆت', style: TextStyle(color: context.clayMuted, fontSize: 12)),
          ]),
        ),
        body: FutureBuilder<StoreModel>(
          future: _storeFuture,
          builder: (context, storeSnapshot) {
            if (storeSnapshot.connectionState != ConnectionState.done) return clayLoading(label: 'زانیاریی دوکان دەهێنرێت...');
            if (storeSnapshot.hasError || !storeSnapshot.hasData) return clayEmpty('دوکانەکە بەردەست نییە', subtitle: '${storeSnapshot.error ?? ''}');
            final store = storeSnapshot.data!;
            return FutureBuilder<List<ProductModel>>(
              future: _productsFuture,
              builder: (context, productSnapshot) {
                if (productSnapshot.connectionState != ConnectionState.done) return clayLoading(label: 'کاڵاکان دەهێنرێن...');
                if (productSnapshot.hasError) return clayEmpty('نەتوانرا کاڵاکان بهێنرێن', subtitle: '${productSnapshot.error}');
                final products = productSnapshot.data ?? [];
                return Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        children: [
                          _StoreHero(store: store),
                          sectionTitle('مێنیو و کاڵاکان'),
                          if (products.isEmpty)
                            ClayCard(child: const Text('ئەم دوکانە هێشتا کاڵای بەردەستی نییە.', textAlign: TextAlign.center))
                          else
                            for (final product in products) _ProductCard(product: product, store: store),
                        ],
                      ),
                    ),
                    _StoreCartBar(store: store),
                  ],
                );
              },
            );
          },
        ),
      );
}

class _StoreHero extends StatelessWidget {
  const _StoreHero({required this.store});
  final StoreModel store;

  @override
  Widget build(BuildContext context) => ClayCard(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
            child: SizedBox(
              height: 126,
              child: store.coverUrl == null || store.coverUrl!.isEmpty
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: context.isClayDark
                              ? const [Color(0xFF3A2B22), Color(0xFF2B211B)]
                              : const [Color(0xFFFFC89F), Color(0xFFFFE7D2)],
                        ),
                      ),
                      child: Center(child: Icon(Icons.storefront_rounded, size: 60, color: context.clayAccent)),
                    )
                  : CachedNetworkImage(
                      imageUrl: store.coverUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: context.claySoftSurface),
                      errorWidget: (_, __, ___) => Container(color: context.claySoftSurface, child: Icon(Icons.storefront_rounded, size: 48, color: context.clayAccent)),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              ClayIconBadge(icon: Icons.storefront_rounded, tone: ClayTone.orange, size: 46),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(store.address.isEmpty ? store.city : store.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.clayMuted, fontSize: 12)),
              ])),
              const SizedBox(width: 6),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _StoreStatus(isOpen: store.isOpen),
                const SizedBox(height: 5),
                Text(formatIqd(store.deliveryFeeIqd), style: TextStyle(color: context.clayAccent, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ]),
          ),
          if (store.description.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 13), child: Text(store.description, style: TextStyle(color: context.clayMuted, fontSize: 12))),
        ]),
      );
}

class _StoreStatus extends StatelessWidget {
  const _StoreStatus({required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) => Text(
        isOpen ? 'کراوە' : 'داخراو',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isOpen ? context.clayPositive : context.clayNegative),
      );
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.store});
  final ProductModel product;
  final StoreModel store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    CartLine? line;
    if (cart.store?.id == store.id) {
      for (final item in cart.lines) {
        if (item.product.id == product.id) line = item;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: ClayCard(
        padding: const EdgeInsets.all(11),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 66,
              height: 66,
              child: product.imageUrl == null || product.imageUrl!.isEmpty
                  ? Container(color: context.claySoftSurface, child: Icon(Icons.fastfood_rounded, color: context.clayAccent, size: 28))
                  : CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: context.claySoftSurface),
                      errorWidget: (_, __, ___) => Container(color: context.claySoftSurface, child: Icon(Icons.inventory_2_rounded, color: context.clayAccent)),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (product.description.isNotEmpty) Text(product.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: context.clayMuted)),
            const SizedBox(height: 4),
            Text(formatIqd(product.priceIqd), style: TextStyle(color: context.clayAccent, fontWeight: FontWeight.w800)),
          ])),
          const SizedBox(width: 6),
          if (line == null)
            IconButton.filledTonal(
              onPressed: store.isOpen ? () {
                final replaced = ref.read(cartProvider.notifier).add(product, store);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(replaced ? 'سەبەتەکەت بۆ ئەم دوکانە نوێ کرایەوە' : 'کاڵا زیاد کرا')));
              } : null,
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(backgroundColor: context.claySoftSurface, foregroundColor: context.clayAccent),
            )
          else
            _QuantityStepper(
              quantity: line.quantity,
              onAdd: () => ref.read(cartProvider.notifier).increment(product.id),
              onRemove: () => ref.read(cartProvider.notifier).decrement(product.id),
            ),
        ]),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onAdd, required this.onRemove});
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        radius: 99,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _StepIcon(icon: Icons.remove_rounded, onTap: onRemove),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 7), child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w800))),
          _StepIcon(icon: Icons.add_rounded, onTap: onAdd),
        ]),
      );
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 17, color: context.clayAccent)),
      );
}

class _StoreCartBar extends ConsumerWidget {
  const _StoreCartBar({required this.store});
  final StoreModel store;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final quoteAsync = ref.watch(cartQuoteProvider);
    final quote = quoteAsync.valueOrNull;
    if (cart.isEmpty || cart.store?.id != store.id) return const SizedBox(height: 3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 9),
      child: ClayCard(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        radius: 25,
        child: Row(children: [
          ClayIconBadge(icon: Icons.shopping_bag_rounded, size: 42, tone: ClayTone.orange),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${cart.itemCount} دانە', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['total_iqd'] as num).toInt()), style: TextStyle(color: context.clayMuted, fontSize: 12)),
          ])),
          ClayPillButton(label: 'بینینی سەبەتە', icon: Icons.arrow_forward_rounded, compact: true, onPressed: () => context.push('/cart')),
        ]),
      ),
    );
  }
}
