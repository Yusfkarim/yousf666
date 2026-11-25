import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state.dart';
import 'clay_widgets.dart';

class MarketplaceScaffold extends ConsumerWidget {
  const MarketplaceScaffold({
    required this.body,
    super.key,
    this.secondary,
    this.showNavigation = true,
  });

  final Widget body;
  final Widget? secondary;
  final bool showNavigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(profileProvider).valueOrNull?['role'] as String? ?? 'buyer';
    final currentPath = GoRouterState.of(context).uri.path;
    final items = <ClayNavItem>[
      const ClayNavItem(label: 'بازاڕ', icon: Icons.storefront_rounded, path: '/home'),
      if (role == 'seller') const ClayNavItem(label: 'دوکان', icon: Icons.dashboard_rounded, path: '/seller'),
      if (role == 'driver') const ClayNavItem(label: 'شۆفێر', icon: Icons.delivery_dining_rounded, path: '/driver'),
      const ClayNavItem(label: 'داواکاری', icon: Icons.receipt_long_rounded, path: '/orders'),
      const ClayNavItem(label: 'هەژمار', icon: Icons.person_rounded, path: '/profile'),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _ClayAppHeader(),
            if (secondary != null) Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 4), child: secondary!),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: showNavigation
          ? FloatingClayNavBar(
              items: items,
              currentPath: currentPath,
              onSelect: (path) => context.go(path),
              actionLabel: role == 'seller' ? 'کاڵای نوێ' : role == 'driver' ? 'شوێن' : 'سەبەتە',
              actionIcon: role == 'seller' ? Icons.add_rounded : role == 'driver' ? Icons.map_rounded : Icons.shopping_bag_rounded,
              onAction: () {
                if (role == 'seller') {
                  context.go('/seller?new=1');
                } else if (role == 'driver') {
                  context.go('/driver');
                } else {
                  context.push('/cart');
                }
              },
            )
          : null,
    );
  }
}

class _ClayAppHeader extends ConsumerWidget {
  const _ClayAppHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: ClayCard(
          radius: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'نوێکردنەوە',
                style: IconButton.styleFrom(
                  backgroundColor: context.claySoftSurface,
                  foregroundColor: context.clayAccent,
                  fixedSize: const Size(44, 44),
                ),
                onPressed: () {
                  ref.invalidate(profileProvider);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('زانیارییەکان نوێ کرانەوە')));
                },
                icon: const Icon(Icons.sync_rounded),
              ),
              const Spacer(),
              Text(
                'بازاڕی یۆسف',
                style: TextStyle(color: context.clayAccent, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 9),
              const ClayIconBadge(icon: Icons.widgets_rounded, size: 42, radius: 15, tone: ClayTone.orange),
              const Spacer(),
              IconButton.filledTonal(
                tooltip: 'هەژمار و ڕێکخستن',
                style: IconButton.styleFrom(
                  backgroundColor: context.claySoftSurface,
                  foregroundColor: context.clayAccent,
                  fixedSize: const Size(44, 44),
                ),
                onPressed: () => context.push('/profile'),
                icon: const Icon(Icons.settings_rounded),
              ),
            ],
          ),
        ),
      );
}

Widget sectionTitle(String title, {String? action, VoidCallback? onAction}) => Builder(
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 7, 4, 10),
        child: Row(
          children: [
            Container(width: 5, height: 25, decoration: BoxDecoration(color: context.clayAccent, borderRadius: BorderRadius.circular(8))),
            const SizedBox(width: 9),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action, style: TextStyle(color: context.clayAccent))),
          ],
        ),
      ),
    );

Widget clayLoading({String label = 'تکایە چاوەڕێ بکە...'}) => Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: ClayColors.orange),
        const SizedBox(height: 10),
        Text(label),
      ]),
    );

Widget clayEmpty(String title, {String? subtitle, IconData icon = Icons.inbox_rounded}) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClayIconBadge(icon: icon, size: 62, tone: ClayTone.lavender),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
