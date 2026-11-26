import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class SellerProductsTab extends ConsumerStatefulWidget {
  const SellerProductsTab({required this.store, super.key});
  final StoreModel store;

  @override
  ConsumerState<SellerProductsTab> createState() => _SellerProductsTabState();
}

class _SellerProductsTabState extends ConsumerState<SellerProductsTab> {
  List<ProductModel> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ref.read(apiProvider).from('products').select().eq('store_id', widget.store.id).order('created_at', ascending: false);
      if (mounted) setState(() => _products = List<Map<String, dynamic>>.from(rows).map(ProductModel.fromMap).toList());
    } catch (error) {
      if (mounted) _message('کاڵاکان نەهێنران: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([ProductModel? product]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ProductEditorSheet(storeId: widget.store.id, product: product),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _toggle(ProductModel product, bool value) async {
    try {
      await ref.read(apiProvider).from('products').update({'is_available': value}).eq('id', product.id);
      await _load();
    } catch (error) {
      _message('دۆخی کاڵا نەگۆڕا: $error');
    }
  }

  Future<void> _delete(ProductModel product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('سڕینەوەی کاڵا'),
        content: Text('دڵنیایت لە سڕینەوەی «${product.name}»؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('پاشگەزبوونەوە')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('بسڕەوە', style: TextStyle(color: context.clayNegative))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(apiProvider).from('products').delete().eq('id', product.id);
      await _load();
    } catch (error) {
      _message('کاڵا نەسڕایەوە: $error');
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (_loading && _products.isEmpty) return clayLoading(label: 'کاڵاکان دەهێنرێن...');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
        child: Row(children: [
          Expanded(child: sectionTitle('کاڵاکان')),
          ClayPillButton(label: 'زیادکردن', icon: Icons.add_rounded, compact: true, onPressed: () => _openEditor()),
        ]),
      ),
      Expanded(
        child: _products.isEmpty
            ? clayEmpty('کاڵایەک زیاد بکە', subtitle: 'ناو، نرخ و وێنەی کاڵاکەت دابنێ.')
            : RefreshIndicator(
                onRefresh: _load,
                color: ClayColors.orange,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(15, 2, 15, 16),
                  itemCount: _products.length,
                  itemBuilder: (context, index) {
                    final product = _products[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: ClayCard(padding: const EdgeInsets.all(11), child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: product.imageUrl == null || product.imageUrl!.isEmpty
                                ? Container(color: context.claySoftSurface, child: Icon(Icons.inventory_2_rounded, color: context.clayAccent))
                                : CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: context.claySoftSurface, child: const Icon(Icons.image_not_supported_rounded))),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(formatIqd(product.priceIqd), style: TextStyle(color: context.clayAccent, fontWeight: FontWeight.w700, fontSize: 12)),
                          Text(product.isAvailable ? 'بەردەستە' : 'نەماوە', style: TextStyle(color: product.isAvailable ? context.clayPositive : context.clayNegative, fontSize: 10)),
                        ])),
                        Switch.adaptive(value: product.isAvailable, activeColor: context.clayPositive, onChanged: (value) => _toggle(product, value)),
                        PopupMenuButton<String>(
                          onSelected: (value) => value == 'edit' ? _openEditor(product) : _delete(product),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('دەستکاری')),
                            PopupMenuItem(value: 'delete', child: Text('سڕینەوە')),
                          ],
                        ),
                      ])),
                    );
                  },
                ),
              ),
      ),
    ]);
  }
}

class ProductEditorSheet extends ConsumerStatefulWidget {
  const ProductEditorSheet({required this.storeId, super.key, this.product});
  final String storeId;
  final ProductModel? product;

  @override
  ConsumerState<ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends ConsumerState<ProductEditorSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  XFile? _image;
  bool _available = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    if (product != null) {
      _name.text = product.name;
      _description.text = product.description;
      _price.text = product.priceIqd.toString();
      _available = product.isAvailable;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (image != null && mounted) setState(() => _image = image);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim());
    if (name.isEmpty || price == null || price < 0) {
      _message('ناوی کاڵا و نرخی دروست بنووسە.');
      return;
    }
    setState(() => _busy = true);
    try {
      String? imageUrl = widget.product?.imageUrl;
      if (_image != null) {
        imageUrl = await ref.read(imageUploadServiceProvider).upload(File(_image!.path), folder: 'products');
      }
      final body = {
        'name': name,
        'description': _description.text.trim(),
        'price_iqd': price,
        'image_url': imageUrl,
        'is_available': _available,
      };
      final client = ref.read(apiProvider);
      if (widget.product == null) {
        await client.from('products').insert({...body, 'store_id': widget.storeId});
      } else {
        await client.from('products').update(body).eq('id', widget.product!.id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) _message('کاڵا پاشەکەوت نەکرا: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: context.clayPageSurface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: ClayColors.line, borderRadius: BorderRadius.circular(5)))),
            const SizedBox(height: 15),
            Text(widget.product == null ? 'زیادکردنی کاڵای نوێ' : 'دەستکاریی کاڵا', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 13),
            _EditorField(controller: _name, hint: 'ناوی کاڵا'),
            const SizedBox(height: 9),
            _EditorField(controller: _description, hint: 'وەسف (ئارەزوومەندانە)', maxLines: 2),
            const SizedBox(height: 9),
            _EditorField(controller: _price, hint: 'نرخ بە دینار', keyboard: TextInputType.number),
            const SizedBox(height: 9),
            ClayInsetContainer(
              child: Row(children: [
                Icon(Icons.image_rounded, color: context.clayAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(_image?.name ?? (widget.product?.imageUrl == null ? 'وێنەی کاڵا' : 'وێنەی پێشوو بەردەستە'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                TextButton(onPressed: _busy ? null : _pickImage, child: const Text('هەڵبژێرە')),
              ]),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('بەردەستە'),
              value: _available,
              activeColor: context.clayPositive,
              onChanged: (value) => setState(() => _available = value),
            ),
            const SizedBox(height: 7),
            ClayPillButton(label: _busy ? 'پاشەکەوت دەکرێت...' : 'پاشەکەوتکردن', icon: Icons.save_rounded, expand: true, onPressed: _busy ? null : _save),
          ]),
        ),
      );
}

class _EditorField extends StatelessWidget {
  const _EditorField({required this.controller, required this.hint, this.maxLines = 1, this.keyboard});
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext context) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        child: TextField(controller: controller, keyboardType: keyboard, maxLines: maxLines, decoration: InputDecoration(border: InputBorder.none, hintText: hint)),
      );
}
