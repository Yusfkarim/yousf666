import 'package:intl/intl.dart';

String formatIqd(num value) {
  final formatted = NumberFormat('#,##0', 'en').format(value);
  const latin = '0123456789';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final localized = formatted.split('').map((character) {
    final index = latin.indexOf(character);
    return index < 0 ? character : arabic[index];
  }).join();
  return '$localized د.ع';
}

String orderStatusLabel(String status) => switch (status) {
      'pending' => 'چاوەڕوانە',
      'accepted' => 'قبووڵکرا',
      'preparing' => 'لە ئامادەکردندایە',
      'on_the_way' => 'لە ڕێگادایە',
      'delivered' => 'گەیەندرا',
      'rejected' => 'ڕەتکرایەوە',
      'cancelled' => 'هەڵوەشایەوە',
      _ => status,
    };

class StoreModel {
  const StoreModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    required this.city,
    required this.address,
    required this.phone,
    required this.logoUrl,
    required this.coverUrl,
    required this.isOpen,
    required this.isApproved,
    required this.deliveryFeeIqd,
    required this.deliveryMode,
    required this.commissionType,
    required this.commissionValue,
    this.categoryId,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String ownerId;
  final String name;
  final String description;
  final String city;
  final String address;
  final String? phone;
  final String? logoUrl;
  final String? coverUrl;
  final bool isOpen;
  final bool isApproved;
  final int deliveryFeeIqd;
  final String deliveryMode;
  final String commissionType;
  final num commissionValue;
  final int? categoryId;
  final double? latitude;
  final double? longitude;

  factory StoreModel.fromMap(Map<String, dynamic> row) => StoreModel(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String? ?? '',
        name: row['name'] as String? ?? 'دوکان',
        description: row['description'] as String? ?? '',
        city: row['city'] as String? ?? '',
        address: row['address_text'] as String? ?? '',
        phone: row['phone'] as String?,
        logoUrl: row['logo_url'] as String?,
        coverUrl: row['cover_url'] as String?,
        isOpen: row['is_open'] as bool? ?? false,
        isApproved: row['is_approved'] as bool? ?? false,
        deliveryFeeIqd: (row['delivery_fee_iqd'] as num?)?.toInt() ?? 0,
        deliveryMode: row['delivery_mode'] as String? ?? 'store_self',
        commissionType: row['commission_type'] as String? ?? 'percentage',
        commissionValue: row['commission_value'] as num? ?? 0,
        categoryId: (row['category_id'] as num?)?.toInt(),
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
      );
}

class ProductModel {
  const ProductModel({
    required this.id,
    required this.storeId,
    required this.name,
    required this.description,
    required this.priceIqd,
    required this.isAvailable,
    this.imageUrl,
  });

  final String id;
  final String storeId;
  final String name;
  final String description;
  final int priceIqd;
  final bool isAvailable;
  final String? imageUrl;

  factory ProductModel.fromMap(Map<String, dynamic> row) => ProductModel(
        id: row['id'] as String,
        storeId: row['store_id'] as String,
        name: row['name'] as String? ?? '',
        description: row['description'] as String? ?? '',
        priceIqd: (row['price_iqd'] as num?)?.toInt() ?? 0,
        isAvailable: row['is_available'] as bool? ?? true,
        imageUrl: row['image_url'] as String?,
      );
}

class CartLine {
  const CartLine({required this.product, required this.quantity});

  final ProductModel product;
  final int quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        product: product,
        quantity: quantity ?? this.quantity,
      );
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.totalIqd,
    required this.subtotalIqd,
    required this.createdAt,
    required this.storeName,
  });

  final String id;
  final int orderNumber;
  final String status;
  final int totalIqd;
  final int subtotalIqd;
  final DateTime createdAt;
  final String storeName;

  factory OrderSummary.fromMap(Map<String, dynamic> row) {
    final store = row['stores'];
    return OrderSummary(
      id: row['id'] as String,
      orderNumber: (row['order_number'] as num?)?.toInt() ?? 0,
      status: row['status'] as String? ?? 'pending',
      totalIqd: (row['total_iqd'] as num?)?.toInt() ?? 0,
      subtotalIqd: (row['subtotal_iqd'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      storeName: store is Map<String, dynamic> ? (store['name'] as String? ?? 'دوکان') : 'دوکان',
    );
  }
}
