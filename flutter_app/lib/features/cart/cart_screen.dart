import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final quoteAsync = ref.watch(cartQuoteProvider);
    final quote = quoteAsync.valueOrNull;
    if (cart.isEmpty) {
      return MarketplaceScaffold(
        body: clayEmpty('سەبەتەکەت بەتاڵە', subtitle: 'لە دوکانێک کاڵا زیاد بکە و بگەڕێوە.', icon: Icons.shopping_bag_outlined),
      );
    }
    return MarketplaceScaffold(
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            children: [
              sectionTitle('سەبەتەی تۆ'),
              ClayInsetContainer(
                child: Row(children: [
                  Icon(Icons.storefront_rounded, color: context.clayAccent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(cart.store?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w800))),
                  Text('${cart.itemCount} دانە', style: TextStyle(color: context.clayMuted)),
                ]),
              ),
              const SizedBox(height: 10),
              for (final line in cart.lines) _CartLineCard(line: line),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: ClayCard(
            child: Column(children: [
              _PriceRow(label: 'نرخی کاڵا', value: quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['subtotal_iqd'] as num).toInt())),
              const SizedBox(height: 8),
              _PriceRow(label: 'کرێی گەیاندن', value: quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['delivery_fee_iqd'] as num).toInt())),
              const Divider(height: 18),
              _PriceRow(label: 'کۆی گشتی', value: quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['total_iqd'] as num).toInt()), bold: true),
              if (quoteAsync.hasError) ...[
                const SizedBox(height: 8),
                Text('${quoteAsync.error}', style: TextStyle(color: context.clayNegative, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              ClayPillButton(
                label: ref.read(apiProvider).auth.currentUser == null ? 'چوونەژوورەوە بۆ داواکردن' : quoteAsync.isLoading ? 'هەژمارکردنی نرخ...' : 'ناردنی داواکاری',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                onPressed: quoteAsync.isLoading || (ref.read(apiProvider).auth.currentUser != null && quote == null)
                    ? null
                    : () {
                        if (ref.read(apiProvider).auth.currentUser == null) {
                          context.push('/login');
                        } else {
                          context.push('/checkout');
                        }
                      },
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CartLineCard extends ConsumerWidget {
  const _CartLineCard({required this.line});
  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: ClayCard(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const ClayIconBadge(icon: Icons.inventory_2_rounded, size: 44, tone: ClayTone.mint),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('${formatIqd(line.product.priceIqd)} × ${line.quantity}', style: TextStyle(color: context.clayMuted, fontSize: 12)),
            ])),
            _CartStepper(
              quantity: line.quantity,
              onAdd: () => ref.read(cartProvider.notifier).increment(line.product.id),
              onRemove: () => ref.read(cartProvider.notifier).decrement(line.product.id),
            ),
          ]),
        ),
      );
}

class _CartStepper extends StatelessWidget {
  const _CartStepper({required this.quantity, required this.onAdd, required this.onRemove});
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        radius: 99,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: onRemove, icon: const Icon(Icons.remove_rounded), visualDensity: VisualDensity.compact, iconSize: 18),
          Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(onPressed: onAdd, icon: const Icon(Icons.add_rounded), visualDensity: VisualDensity.compact, iconSize: 18),
        ]),
      );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: bold ? context.clayText : context.clayMuted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
        Text(value, style: TextStyle(color: bold ? context.clayAccent : context.clayText, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]);
}
