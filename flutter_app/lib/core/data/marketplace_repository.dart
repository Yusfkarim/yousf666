import '../services/marketplace_client.dart';

import '../models/marketplace_models.dart';

const _storeColumns = 'id, owner_id, name, description, category_id, logo_url, cover_url, phone, city, address_text, latitude, longitude, is_open, is_approved, delivery_mode, delivery_fee_iqd, created_at';

class MarketplaceRepository {
  MarketplaceRepository(this.client);

  final MarketplaceClient client;

  Future<List<Map<String, dynamic>>> getCategories() async {
    final rows = await client.from('categories').select().order('sort_order');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<StoreModel>> getStores({
    int offset = 0,
    int? categoryId,
    String query = '',
    int pageSize = 15,
  }) async {
    final search = query.trim();
    if (search.isEmpty) {
      dynamic builder = client.from('stores').select(_storeColumns).eq('is_approved', true);
      if (categoryId != null) builder = builder.eq('category_id', categoryId);
      final rows = await builder
          .order('is_open', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      return List<Map<String, dynamic>>.from(rows).map(StoreModel.fromMap).toList();
    }

    final pattern = '%$search%';
    dynamic storeQuery = client.from('stores').select(_storeColumns).eq('is_approved', true).ilike('name', pattern);
    if (categoryId != null) storeQuery = storeQuery.eq('category_id', categoryId);
    final storeRows = await storeQuery.range(offset, offset + pageSize - 1);

    dynamic productQuery = client.from('products').select('store_id').eq('is_available', true).ilike('name', pattern);
    final productRows = await productQuery.limit(100);
    final productStoreIds = List<Map<String, dynamic>>.from(productRows)
        .map((row) => row['store_id'] as String)
        .toSet()
        .toList();

    List<Map<String, dynamic>> productMatchedRows = [];
    if (productStoreIds.isNotEmpty) {
      dynamic matchedQuery = client.from('stores').select(_storeColumns).eq('is_approved', true).inFilter('id', productStoreIds);
      if (categoryId != null) matchedQuery = matchedQuery.eq('category_id', categoryId);
      productMatchedRows = List<Map<String, dynamic>>.from(await matchedQuery.limit(pageSize));
    }

    final merged = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(storeRows)) {
      merged[row['id'] as String] = row;
    }
    for (final row in productMatchedRows) {
      merged[row['id'] as String] = row;
    }
    final results = merged.values.toList()
      ..sort((a, b) {
        final openOrder = (b['is_open'] == true ? 1 : 0).compareTo(a['is_open'] == true ? 1 : 0);
        if (openOrder != 0) return openOrder;
        return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
      });
    return results.take(pageSize).map(StoreModel.fromMap).toList();
  }

  Future<StoreModel> getStore(String storeId) async {
    final row = await client.from('stores').select(_storeColumns).eq('id', storeId).single();
    return StoreModel.fromMap(row);
  }

  Future<List<ProductModel>> getProducts(String storeId, {bool onlyAvailable = true}) async {
    dynamic builder = client.from('products').select().eq('store_id', storeId);
    if (onlyAvailable) builder = builder.eq('is_available', true);
    final rows = await builder.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows).map(ProductModel.fromMap).toList();
  }

  Future<StoreModel?> getMyStore() async {
    final user = client.auth.currentUser;
    if (user == null) return null;
    final rows = await client.from('stores').select(_storeColumns).eq('owner_id', user.id).order('created_at').limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;
    final row = list.first;
    final commission = Map<String, dynamic>.from(
      await client.rpc('get_store_commission_settings', params: {'p_store_id': row['id']}) as Map,
    );
    return StoreModel.fromMap({...row, ...commission});
  }

  Future<List<Map<String, dynamic>>> getMyOrders({required String role}) async {
    final user = client.auth.currentUser;
    if (user == null) return [];
    dynamic builder = client
        .from('orders')
        .select('id, order_number, buyer_id, store_id, driver_id, status, subtotal_iqd, delivery_fee_iqd, total_iqd, delivery_address, created_at, updated_at, delivered_at, stores(name)');
    if (role == 'seller') {
      final store = await getMyStore();
      if (store == null) return [];
      builder = builder.eq('store_id', store.id);
    } else if (role == 'driver') {
      builder = builder.eq('driver_id', user.id);
    } else {
      builder = builder.eq('buyer_id', user.id);
    }
    final rows = await builder.order('created_at', ascending: false).limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }
}
