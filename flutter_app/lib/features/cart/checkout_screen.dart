import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
  final _mapController = MapController();
  LatLng? _location;
  bool _busy = false;

  @override
  void dispose() {
    _addressController.dispose();
    _noteController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('مۆڵەتی شوێن پێویستە؛ دەتوانیت شوێن لەسەر نەخشەکە دیاری بکەیت.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final point = LatLng(position.latitude, position.longitude);
      setState(() => _location = point);
      _mapController.move(point, 15);
    } catch (error) {
      _message('شوێنەکەت وەرنەگیرا: $error');
    }
  }

  Future<void> _submit() async {
    final cart = ref.read(cartProvider);
    final user = ref.read(supabaseProvider).auth.currentUser;
    if (user == null) {
      context.push('/login');
      return;
    }
    if (cart.store == null || cart.lines.isEmpty) {
      _message('سەبەتەکەت بەتاڵە.');
      return;
    }
    if (_addressController.text.trim().isEmpty) {
      _message('ناونیشان یان نیشانەیەکی نزیک بنووسە.');
      return;
    }
    setState(() => _busy = true);
    try {
      final profile = ref.read(profileProvider).valueOrNull ?? await ref.read(profileProvider.future);
      final phone = profile?['phone'] as String?;
      if (phone == null || !RegExp(r'^07[0-9]{9}$').hasMatch(phone)) {
        if (mounted) {
          _message('سەرەتا ژمارەی مۆبایلی عێراقی لە هەژمارەکەت زیاد بکە.');
          context.push('/profile');
        }
        return;
      }
      final response = await ref.read(supabaseProvider).rpc('create_order', params: {
        'p_store_id': cart.store!.id,
        'p_items_json': cart.lines.map((line) => {
              'product_id': line.product.id,
              'quantity': line.quantity,
            }).toList(),
        'p_lat': _location?.latitude,
        'p_lng': _location?.longitude,
        'p_address': _addressController.text.trim(),
        'p_note': _noteController.text.trim(),
      });
      final order = Map<String, dynamic>.from(response as Map);
      ref.read(cartProvider.notifier).clear();
      ref.invalidate(profileProvider);
      if (mounted) context.go('/order/${order['id']}');
    } catch (error) {
      if (mounted) _message('داواکاری دروست نەبوو: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final quoteAsync = ref.watch(cartQuoteProvider);
    final quote = quoteAsync.valueOrNull;
    final profile = ref.watch(profileProvider).valueOrNull;
    if (cart.isEmpty || cart.store == null) {
      return MarketplaceScaffold(body: clayEmpty('سەبەتەکەت بەتاڵە', subtitle: 'بۆ داواکردن کاڵا زیاد بکە.'));
    }
    final phone = profile?['phone'] as String?;
    final center = _location ?? const LatLng(35.561, 45.4308);
    return MarketplaceScaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        children: [
          sectionTitle('شوێن و گەیاندن'),
          ClayCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const ClayIconBadge(icon: Icons.location_on_rounded, tone: ClayTone.orange, size: 42),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ناونیشانی گەیاندن', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text(phone ?? 'ژمارەی مۆبایل دابنێ', style: TextStyle(fontSize: 12, color: context.clayMuted)),
                ])),
                TextButton.icon(onPressed: _useGps, icon: const Icon(Icons.my_location_rounded), label: const Text('GPS')),
              ]),
              const SizedBox(height: 9),
              ClayInsetContainer(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                child: TextField(
                  controller: _addressController,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(border: InputBorder.none, hintText: 'گەڕەک، کۆڵان، یان نیشانەیەکی نزیک...', counterText: ''),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 235,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 12,
                      onTap: (_, point) => setState(() => _location = point),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.yousif.marketplace',
                      ),
                      if (_location != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: _location!,
                            width: 44,
                            height: 48,
                            child: Icon(Icons.location_pin, color: context.clayAccent, size: 44),
                          ),
                        ]),
                      const RichAttributionWidget(
                        attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text('بۆ دیاریکردنی خاڵێک لەسەر نەخشەکە دەست لێ بدە.', style: TextStyle(color: context.clayMuted, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 12),
          ClayInsetContainer(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            child: TextField(controller: _noteController, maxLength: 500, decoration: const InputDecoration(border: InputBorder.none, hintText: 'تێبینی بۆ دوکان (ئارەزوومەندانە)', counterText: '')),
          ),
          sectionTitle('پێداچوونەوەی پارە'),
          ClayCard(child: Column(children: [
            _CheckoutPriceRow(label: 'نرخی کاڵا', value: quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['subtotal_iqd'] as num).toInt())),
            const SizedBox(height: 8),
            _CheckoutPriceRow(label: 'کرێی گەیاندن', value: quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['delivery_fee_iqd'] as num).toInt())),
            const Divider(height: 19),
            _CheckoutPriceRow(label: 'کۆی گشتی (COD)', value: quote == null ? (quoteAsync.isLoading ? '...' : '—') : formatIqd((quote['total_iqd'] as num).toInt()), bold: true),
            if (quoteAsync.hasError) ...[
              const SizedBox(height: 8),
              Text('${quoteAsync.error}', style: TextStyle(color: context.clayNegative, fontSize: 11)),
            ],
            const SizedBox(height: 14),
            ClayPillButton(
              label: _busy ? 'داواکاری دەنێردرێت...' : quoteAsync.isLoading ? 'هەژمارکردنی نرخ...' : 'ناردنی داواکاری',
              icon: Icons.check_circle_outline_rounded,
              tone: ClayTone.orange,
              expand: true,
              onPressed: _busy || quoteAsync.isLoading || quote == null ? null : _submit,
            ),
          ])),
        ],
      ),
    );
  }
}

class _CheckoutPriceRow extends StatelessWidget {
  const _CheckoutPriceRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? context.clayText : context.clayMuted))),
        Text(value, style: TextStyle(fontWeight: FontWeight.w800, color: bold ? context.clayAccent : context.clayText)),
      ]);
}
