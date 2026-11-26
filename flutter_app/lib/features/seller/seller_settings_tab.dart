import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class SellerSettingsTab extends ConsumerStatefulWidget {
  const SellerSettingsTab({required this.store, required this.onChanged, super.key});
  final StoreModel store;
  final ValueChanged<StoreModel> onChanged;

  @override
  ConsumerState<SellerSettingsTab> createState() => _SellerSettingsTabState();
}

class _SellerSettingsTabState extends ConsumerState<SellerSettingsTab> {
  late bool _isOpen;
  late String _deliveryMode;
  late int _deliveryFee;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _isOpen = widget.store.isOpen;
    _deliveryMode = widget.store.deliveryMode;
    _deliveryFee = widget.store.deliveryFeeIqd;
  }

  @override
  void didUpdateWidget(covariant SellerSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store.id != widget.store.id || oldWidget.store.isOpen != widget.store.isOpen || oldWidget.store.deliveryMode != widget.store.deliveryMode || oldWidget.store.deliveryFeeIqd != widget.store.deliveryFeeIqd) {
      _isOpen = widget.store.isOpen;
      _deliveryMode = widget.store.deliveryMode;
      _deliveryFee = widget.store.deliveryFeeIqd;
    }
  }

  Future<void> _save({bool? isOpen, String? mode, int? fee, double? latitude, double? longitude}) async {
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{};
      if (isOpen != null) body['is_open'] = isOpen;
      if (mode != null) body['delivery_mode'] = mode;
      if (fee != null) body['delivery_fee_iqd'] = fee;
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }
      await ref.read(apiProvider).from('stores').update(body).eq('id', widget.store.id);
      final next = StoreModel(
        id: widget.store.id,
        ownerId: widget.store.ownerId,
        name: widget.store.name,
        description: widget.store.description,
        city: widget.store.city,
        address: widget.store.address,
        phone: widget.store.phone,
        logoUrl: widget.store.logoUrl,
        coverUrl: widget.store.coverUrl,
        isOpen: isOpen ?? _isOpen,
        isApproved: widget.store.isApproved,
        deliveryFeeIqd: fee ?? _deliveryFee,
        deliveryMode: mode ?? _deliveryMode,
        commissionType: widget.store.commissionType,
        commissionValue: widget.store.commissionValue,
        categoryId: widget.store.categoryId,
        latitude: latitude ?? widget.store.latitude,
        longitude: longitude ?? widget.store.longitude,
      );
      widget.onChanged(next);
      if (mounted) _message('ڕێکخستنەکان پاشەکەوت کران.');
    } catch (error) {
      if (mounted) _message('ڕێکخستنەکان نەگۆڕان: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editFee() async {
    final controller = TextEditingController(text: _deliveryFee.toString());
    final value = await showDialog<int>(context: context, builder: (context) => AlertDialog(
          title: const Text('کرێی گەیاندن'),
          content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'بە دینار')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('پاشگەزبوونەوە')),
            TextButton(onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())), child: const Text('پاشەکەوت')),
          ],
        ));
    controller.dispose();
    if (value == null || value < 0) return;
    setState(() => _deliveryFee = value);
    await _save(fee: value);
  }

  Future<void> _captureLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('مۆڵەتی شوێن پێویستە.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await _save(latitude: position.latitude, longitude: position.longitude);
    } catch (error) {
      _message('شوێن وەرنەگیرا: $error');
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(15, 8, 15, 20), children: [
        sectionTitle('ڕێکخستنی دوکان'),
        ClayCard(child: Column(children: [
          Row(children: [
            const ClayIconBadge(icon: Icons.storefront_rounded, size: 48, tone: ClayTone.orange),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.store.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(widget.store.city, style: TextStyle(color: context.clayMuted, fontSize: 12)),
            ])),
            _ApprovalPill(approved: widget.store.isApproved),
          ]),
          const Divider(height: 24),
          Row(children: [
            const Expanded(child: Text('دۆخی دوکان', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(_isOpen ? 'کراوە' : 'داخراو', style: TextStyle(color: _isOpen ? context.clayPositive : context.clayNegative, fontWeight: FontWeight.w700)),
            Switch.adaptive(value: _isOpen, activeColor: context.clayPositive, onChanged: _busy ? null : (value) {
              setState(() => _isOpen = value);
              _save(isOpen: value);
            }),
          ]),
          const Divider(height: 15),
          Row(children: [
            const Expanded(child: Text('شێوازی گەیاندن', style: TextStyle(fontWeight: FontWeight.w700))),
            DropdownButton<String>(
              value: _deliveryMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'platform_driver', child: Text('شۆفێری ئەپ')),
                DropdownMenuItem(value: 'store_self', child: Text('گەیاندنی دوکان')),
              ],
              onChanged: _busy ? null : (value) {
                if (value == null) return;
                setState(() => _deliveryMode = value);
                _save(mode: value);
              },
            ),
          ]),
          const Divider(height: 15),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('کرێی گەیاندن', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('بە دیناری عێراقی', style: TextStyle(color: context.clayMuted, fontSize: 11)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(formatIqd(_deliveryFee), style: TextStyle(fontWeight: FontWeight.w800, color: context.clayAccent)), const SizedBox(width: 7), const Icon(Icons.edit_rounded, size: 17)]),
            onTap: _busy ? null : _editFee,
          ),
          const Divider(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.my_location_rounded, color: context.clayAccent),
            title: const Text('شوێنی دوکان', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(widget.store.latitude == null || widget.store.longitude == null ? 'GPS دیاری نەکراوە' : '${widget.store.latitude!.toStringAsFixed(4)}, ${widget.store.longitude!.toStringAsFixed(4)}', style: TextStyle(color: context.clayMuted, fontSize: 11)),
            trailing: TextButton(onPressed: _busy ? null : _captureLocation, child: const Text('نوێکردنەوە')),
          ),
        ])),
        sectionTitle('ڕێژەی کۆمسیۆن'),
        ClayCard(child: Row(children: [
          const ClayIconBadge(icon: Icons.percent_rounded, size: 43, tone: ClayTone.lavender),
          const SizedBox(width: 10),
          Expanded(child: Text('تەنها بەڕێوەبەر دەتوانێت ئەم ڕێژەیە بگۆڕێت.', style: TextStyle(color: context.clayMuted, fontSize: 12))),
          Text(widget.store.commissionType == 'percentage' ? '${widget.store.commissionValue}%' : formatIqd(widget.store.commissionValue), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: context.clayAccent)),
        ])),
        if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: ClayColors.orange))),
      ]);
}

class _ApprovalPill extends StatelessWidget {
  const _ApprovalPill({required this.approved});
  final bool approved;
  @override
  Widget build(BuildContext context) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        radius: 99,
        child: Text(approved ? 'پەسەندکراوە' : 'چاوەڕوانی پەسەندکردن', style: TextStyle(fontSize: 10, color: approved ? context.clayPositive : context.clayAccent, fontWeight: FontWeight.w700)),
      );
}
