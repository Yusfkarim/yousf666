import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/marketplace_repository.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _pageSize = 15;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  List<StoreModel> _stores = [];
  List<Map<String, dynamic>> _categories = [];
  int? _categoryId;
  Position? _position;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _query = '';

  MarketplaceRepository get _repository => ref.read(marketplaceRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
      _load(reset: true);
      _locate();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _repository.getCategories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      // Catalog remains usable if category seed data has not been imported yet.
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loadingMore || (!reset && !_hasMore)) return;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
          _error = null;
        } else {
          _loadingMore = true;
        }
      });
    }
    final offset = reset ? 0 : _stores.length;
    try {
      final result = await _repository.getStores(
        offset: offset,
        categoryId: _categoryId,
        query: _query,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _stores = reset ? result : [..._stores, ...result];
        _sortByDistance();
        _hasMore = result.length == _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = value.trim();
      _load(reset: true);
    });
  }

  Future<void> _locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      if (mounted) {
        setState(() {
          _position = position;
          _sortByDistance();
        });
      }
    } catch (_) {
      // Location is optional; store browsing works without GPS permission.
    }
  }

  double? _distanceFrom(StoreModel store) {
    if (_position == null || store.latitude == null || store.longitude == null) return null;
    const earthRadius = 6371.0;
    final dLat = _toRadians(store.latitude! - _position!.latitude);
    final dLon = _toRadians(store.longitude! - _position!.longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(_position!.latitude)) * math.cos(_toRadians(store.latitude!)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _toRadians(double degree) => degree * math.pi / 180;

  void _sortByDistance() {
    if (_position == null) return;
    _stores.sort((first, second) {
      final firstDistance = _distanceFrom(first) ?? double.infinity;
      final secondDistance = _distanceFrom(second) ?? double.infinity;
      return firstDistance.compareTo(secondDistance);
    });
  }

  @override
  Widget build(BuildContext context) => MarketplaceScaffold(
        secondary: Column(
          children: [
            Row(
              children: [
                ClayPillButton(label: '${_stores.length} دوکان', icon: Icons.people_alt_rounded, compact: true, tone: ClayTone.orange, onPressed: () {}),
                const Spacer(),
                ClayInsetContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  radius: 99,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.location_on_rounded, size: 17, color: _position == null ? context.clayMuted : context.clayPositive),
                    const SizedBox(width: 5),
                    Text(_position == null ? 'GPS ناچالاکە' : 'GPS چالاکە', style: TextStyle(color: context.clayMuted, fontSize: 12)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClayInsetContainer(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'گەڕان: ناوی دوکان یان کاڵا...',
                  prefixIcon: Icon(Icons.search_rounded, color: context.clayMuted),
                  suffixIcon: Icon(Icons.tune_rounded, color: context.clayAccent),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _CategoryChip(label: 'هەموو', selected: _categoryId == null, onTap: () => _selectCategory(null)),
                  for (final category in _categories)
                    _CategoryChip(
                      label: category['name_ku'] as String? ?? '',
                      selected: _categoryId == (category['id'] as num?)?.toInt(),
                      onTap: () => _selectCategory((category['id'] as num?)?.toInt()),
                    ),
                ],
              ),
            ),
          ],
        ),
        body: _buildStoreList(),
      );

  void _selectCategory(int? id) {
    setState(() => _categoryId = id);
    _load(reset: true);
  }

  Widget _buildStoreList() {
    if (_loading && _stores.isEmpty) return clayLoading(label: 'دوکانەکان دەهێنرێن...');
    if (_error != null && _stores.isEmpty) {
      return clayEmpty('نەتوانرا دوکانەکان بهێنرێن', subtitle: _error, icon: Icons.cloud_off_rounded);
    }
    if (_stores.isEmpty) return clayEmpty('هیچ دوکانێک نەدۆزرایەوە', subtitle: 'گەڕانەکەت بگۆڕە یان دواتر هەوڵ بدە.');
    return RefreshIndicator(
      color: ClayColors.orange,
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 22),
        itemCount: _stores.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) return sectionTitle(_query.isEmpty ? 'دوکانە نزیکەکان' : 'ئەنجامی گەڕان');
          if (index == _stores.length + 1) {
            if (_loadingMore) return const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator(color: ClayColors.orange)));
            return const SizedBox(height: 8);
          }
          final store = _stores[index - 1];
          return StoreCard(
            store: store,
            distanceKm: _distanceFrom(store),
            onTap: () => context.push('/store/${store.id}'),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 7),
        child: ClayPillButton(
          label: label,
          compact: true,
          tone: selected ? ClayTone.orange : ClayTone.neutral,
          onPressed: onTap,
        ),
      );
}

class StoreCard extends StatelessWidget {
  const StoreCard({required this.store, required this.onTap, super.key, this.distanceKm});
  final StoreModel store;
  final VoidCallback onTap;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ClayCard(
          padding: const EdgeInsets.all(12),
          onTap: onTap,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: store.logoUrl == null || store.logoUrl!.isEmpty
                      ? Container(color: context.claySoftSurface, child: Icon(Icons.storefront_rounded, color: context.clayAccent, size: 34))
                      : CachedNetworkImage(
                          imageUrl: store.logoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: context.claySoftSurface),
                          errorWidget: (_, __, ___) => Container(color: context.claySoftSurface, child: Icon(Icons.storefront_rounded, color: context.clayAccent)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 5),
                      _OpenBadge(isOpen: store.isOpen),
                    ]),
                    const SizedBox(height: 5),
                    Text(store.description.isEmpty ? store.city : store.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.clayMuted, fontSize: 12)),
                    const SizedBox(height: 7),
                    Wrap(spacing: 10, runSpacing: 4, children: [
                      _Meta(icon: Icons.delivery_dining_rounded, label: formatIqd(store.deliveryFeeIqd)),
                      if (distanceKm != null) _Meta(icon: Icons.near_me_rounded, label: '${distanceKm!.toStringAsFixed(1)} km'),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_left_rounded, color: context.clayMuted),
            ],
          ),
        ),
      );
}

class _OpenBadge extends StatelessWidget {
  const _OpenBadge({required this.isOpen});
  final bool isOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isOpen ? context.clayPositiveSurface : context.clayNegativeSurface,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(isOpen ? 'کراوە' : 'داخراو', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isOpen ? context.clayPositive : context.clayNegative)),
      );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: context.clayAccent),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: context.clayMuted)),
      ]);
}
