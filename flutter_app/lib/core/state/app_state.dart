import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/marketplace_models.dart';
import '../data/marketplace_repository.dart';
import '../services/image_upload_service.dart';
import '../services/push_token_service.dart';

final marketplaceRepositoryProvider = Provider<MarketplaceRepository>(
  (ref) => MarketplaceRepository(ref.watch(supabaseProvider)),
);

final imageUploadServiceProvider = Provider<ImageUploadService>(
  (ref) => createImageUploadService(ref.watch(supabaseProvider)),
);

final pushTokenServiceProvider = Provider<PushTokenService>((ref) {
  final service = PushTokenService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final client = ref.watch(supabaseProvider);
  final user = client.auth.currentUser;
  if (user == null) return null;
  return client.from('profiles').select().eq('id', user.id).maybeSingle();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

class CartState {
  const CartState({this.store, this.lines = const []});

  final StoreModel? store;
  final List<CartLine> lines;

  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);
  bool get isEmpty => lines.isEmpty;

  CartState copyWith({StoreModel? store, List<CartLine>? lines, bool clearStore = false}) => CartState(
        store: clearStore ? null : (store ?? this.store),
        lines: lines ?? this.lines,
      );
}

class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState());

  bool add(ProductModel product, StoreModel store) {
    final replacedStore = state.store != null && state.store!.id != store.id;
    final currentLines = replacedStore ? <CartLine>[] : [...state.lines];
    final index = currentLines.indexWhere((line) => line.product.id == product.id);
    if (index < 0) {
      currentLines.add(CartLine(product: product, quantity: 1));
    } else {
      currentLines[index] = currentLines[index].copyWith(quantity: currentLines[index].quantity + 1);
    }
    state = CartState(store: store, lines: currentLines);
    return replacedStore;
  }

  void decrement(String productId) {
    final currentLines = [...state.lines];
    final index = currentLines.indexWhere((line) => line.product.id == productId);
    if (index < 0) return;
    if (currentLines[index].quantity <= 1) {
      currentLines.removeAt(index);
    } else {
      currentLines[index] = currentLines[index].copyWith(quantity: currentLines[index].quantity - 1);
    }
    state = CartState(store: currentLines.isEmpty ? null : state.store, lines: currentLines);
  }

  void increment(String productId) {
    final currentLines = [...state.lines];
    final index = currentLines.indexWhere((line) => line.product.id == productId);
    if (index < 0) return;
    currentLines[index] = currentLines[index].copyWith(quantity: currentLines[index].quantity + 1);
    state = state.copyWith(lines: currentLines);
  }

  void clear() => state = const CartState();
}

final cartProvider = StateNotifierProvider<CartController, CartState>((ref) => CartController());

final cartQuoteProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(authStateProvider);
  final cart = ref.watch(cartProvider);
  final client = ref.watch(supabaseProvider);
  if (cart.isEmpty || cart.store == null || client.auth.currentUser == null) return null;
  final response = await client.rpc('quote_order', params: {
    'p_store_id': cart.store!.id,
    'p_items_json': cart.lines.map((line) => {
          'product_id': line.product.id,
          'quantity': line.quantity,
        }).toList(),
  });
  return Map<String, dynamic>.from(response as Map);
});
