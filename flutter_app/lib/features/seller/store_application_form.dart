import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';

class StoreApplicationForm extends ConsumerStatefulWidget {
  const StoreApplicationForm({required this.onCreated, super.key});
  final VoidCallback onCreated;

  @override
  ConsumerState<StoreApplicationForm> createState() => _StoreApplicationFormState();
}

class _StoreApplicationFormState extends ConsumerState<StoreApplicationForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _city = TextEditingController(text: 'سلێمانی');
  final _address = TextEditingController();
  final _phone = TextEditingController();
  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  double? _latitude;
  double? _longitude;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final rows = await ref.read(apiProvider).from('categories').select().order('sort_order');
      if (mounted) setState(() => _categories = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  Future<void> _captureLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('مۆڵەتی شوێن پێویستە بۆ تۆمارکردنی شوێنی دوکان.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) setState(() { _latitude = position.latitude; _longitude = position.longitude; });
    } catch (error) {
      if (mounted) _message('شوێن وەرنەگیرا: $error');
    }
  }

  Future<void> _submit() async {
    final user = ref.read(apiProvider).auth.currentUser;
    if (user == null) {
      _message('بۆ دروستکردنی دوکان بچۆ ژوورەوە.');
      return;
    }
    if (_name.text.trim().length < 2 || _city.text.trim().isEmpty) {
      _message('ناوی دوکان و شار پێویستن.');
      return;
    }
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^07[0-9]{9}$').hasMatch(phone)) {
      _message('ژمارەی دوکان بە شێوەی 07xxxxxxxxx بنووسە.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).from('stores').insert({
        'owner_id': user.id,
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'category_id': _categoryId,
        'phone': phone.isEmpty ? null : phone,
        'city': _city.text.trim(),
        'address_text': _address.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'delivery_mode': 'store_self',
        'delivery_fee_iqd': 2000,
      });
      if (mounted) {
        _message('داواکاریی دوکان نێردرا؛ پاش پەسەندکردنی بەڕێوەبەر چالاک دەبێت.');
        widget.onCreated();
      }
    } catch (error) {
      if (mounted) _message('داواکاریی دوکان تۆمار نەکرا: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(18, 22, 18, 30), children: [
        const ClayIconBadge(icon: Icons.store_mall_directory_rounded, size: 62, tone: ClayTone.orange),
        const SizedBox(height: 12),
        const Text('دوکانەکەت تۆمار بکە', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('پاش پەسەندکردنی بەڕێوەبەر، مێنیو و داواکارییەکانت لێرە بەڕێوە دەبەیت.', textAlign: TextAlign.center, style: TextStyle(color: context.clayMuted)),
        const SizedBox(height: 18),
        ClayCard(child: Column(children: [
          _Input(controller: _name, hint: 'ناوی دوکان', icon: Icons.storefront_rounded),
          const SizedBox(height: 9),
          _Input(controller: _description, hint: 'وەسف', icon: Icons.notes_rounded, maxLines: 2),
          const SizedBox(height: 9),
          if (_categories.isNotEmpty)
            ClayInsetContainer(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: DropdownButtonFormField<int?>(
                value: _categoryId,
                decoration: const InputDecoration(border: InputBorder.none, hintText: 'جۆری دوکان'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('جۆری دوکان')),
                  for (final category in _categories)
                    DropdownMenuItem<int?>(value: (category['id'] as num).toInt(), child: Text(category['name_ku'] as String? ?? '')),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
            ),
          const SizedBox(height: 9),
          _Input(controller: _city, hint: 'شار', icon: Icons.location_city_rounded),
          const SizedBox(height: 9),
          _Input(controller: _address, hint: 'ناونیشانی دوکان', icon: Icons.location_on_outlined),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(child: Text('شوێنی GPS بۆ دووریی کڕیاران', style: TextStyle(fontSize: 11, color: context.clayMuted))),
            TextButton.icon(onPressed: _busy ? null : _captureLocation, icon: const Icon(Icons.my_location_rounded), label: Text(_latitude == null ? 'دیاریکردن' : 'دیاریکرا')),
          ]),
          _Input(controller: _phone, hint: 'ژمارەی دوکان 07xxxxxxxxx', icon: Icons.phone_rounded, keyboard: TextInputType.phone),
          const SizedBox(height: 15),
          ClayPillButton(label: _busy ? 'دەنێردرێت...' : 'ناردنی داواکاری', icon: Icons.send_rounded, expand: true, onPressed: _busy ? null : _submit),
        ])),
      ]);
}

class _Input extends StatelessWidget {
  const _Input({required this.controller, required this.hint, required this.icon, this.maxLines = 1, this.keyboard});
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final int maxLines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: TextField(controller: controller, maxLines: maxLines, keyboardType: keyboard, decoration: InputDecoration(border: InputBorder.none, hintText: hint, prefixIcon: Icon(icon))),
      );
}
