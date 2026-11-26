import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/clay_widgets.dart';
import 'features/auth/auth_screen.dart';
import 'features/cart/cart_screen.dart';
import 'features/cart/checkout_screen.dart';
import 'features/home/home_screen.dart';
import 'features/orders/order_chat_screen.dart';
import 'features/orders/order_detail_screen.dart';
import 'features/orders/orders_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/seller/driver_view_screen.dart';
import 'features/seller/seller_dashboard_screen.dart';
import 'features/store/store_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const AuthScreen()),
        GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/store/:storeId', builder: (context, state) => StoreScreen(storeId: state.pathParameters['storeId']!)),
        GoRoute(path: '/cart', builder: (context, state) => const CartScreen()),
        GoRoute(path: '/checkout', builder: (context, state) => const CheckoutScreen()),
        GoRoute(path: '/orders', builder: (context, state) => const OrdersScreen()),
        GoRoute(path: '/order/:orderId', builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['orderId']!)),
        GoRoute(path: '/chat/:orderId', builder: (context, state) => OrderChatScreen(orderId: state.pathParameters['orderId']!)),
        GoRoute(path: '/seller', builder: (context, state) => const SellerDashboardScreen()),
        GoRoute(path: '/driver', builder: (context, state) => const DriverViewScreen()),
        GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded, size: 50, color: ClayColors.coral),
          const SizedBox(height: 8),
          Text('پەڕەکە نەدۆزرایەوە: ${state.error ?? ''}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => context.go('/home'), child: const Text('گەڕانەوە بۆ بازاڕ')),
        ]))),
      ),
    ));

class MarketplaceApp extends ConsumerWidget {
  const MarketplaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authStateProvider, (previous, next) {
      final previousUserId = previous?.valueOrNull?.session?.user.id;
      final currentUserId = next.valueOrNull?.session?.user.id;
      if (previousUserId != currentUserId) ref.invalidate(profileProvider);
      final pushService = ref.read(pushTokenServiceProvider);
      if (currentUserId == null) {
        unawaited(pushService.clearCurrentUser());
      } else {
        unawaited(pushService.syncCurrentUser(ref.read(apiProvider)));
      }
    });
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'بازاڕی یۆسف',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class ConfigurationRequiredApp extends StatelessWidget {
  const ConfigurationRequiredApp({super.key, this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ClayCard(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const ClayIconBadge(icon: Icons.settings_suggest_rounded, size: 60),
                      const SizedBox(height: 12),
                      const Text('پەیوەندی بە ڕاژەی ناوخۆییەوە نەکرا', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('دڵنیابە ڕاژەی API کارا دەکات و ئامێرەکەت هەمان تۆڕی تایلسکەیل بەکاردەهێنێت.', textAlign: TextAlign.center),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: ClayColors.coral, fontSize: 11)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
