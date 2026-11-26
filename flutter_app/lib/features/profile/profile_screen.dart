import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';
import '../../core/theme/marketplace_scaffold.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cityController = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(apiProvider).auth.currentUser;
    if (user == null) return;
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^07[0-9]{9}$').hasMatch(phone)) {
      _message('ژمارەی مۆبایل بە شێوەی 07xxxxxxxxx بنووسە.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).from('profiles').update({
        'full_name': _nameController.text.trim(),
        'phone': phone.isEmpty ? null : phone,
        'city': _cityController.text.trim(),
      }).eq('id', user.id);
      ref.invalidate(profileProvider);
      if (mounted) _message('زانیارییەکان پاشەکەوت کران.');
    } catch (error) {
      if (mounted) _message('پاشەکەوت نەکرا: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(apiProvider).auth.currentUser;
    if (user == null) {
      return MarketplaceScaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(22),
          child: ClayCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ClayIconBadge(icon: Icons.person_outline_rounded, size: 64, tone: ClayTone.lavender),
            const SizedBox(height: 12),
            const Text('بچۆ ژوورەوە', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            Text('بۆ داواکاری و بەڕێوەبردنی هەژمارەکەت.', textAlign: TextAlign.center, style: TextStyle(color: context.clayMuted)),
            const SizedBox(height: 15),
            ClayPillButton(label: 'چوونەژوورەوە', icon: Icons.login_rounded, onPressed: () => context.push('/login')),
          ])),
        )),
      );
    }

    final profileAsync = ref.watch(profileProvider);
    final profile = profileAsync.valueOrNull;
    if (profile != null && !_loaded) {
      _nameController.text = profile['full_name'] as String? ?? '';
      _phoneController.text = profile['phone'] as String? ?? '';
      _cityController.text = profile['city'] as String? ?? '';
      _loaded = true;
    }
    final role = profile?['role'] as String? ?? 'buyer';
    final themeMode = ref.watch(themeModeProvider);
    return MarketplaceScaffold(
      body: profileAsync.isLoading && profile == null
          ? const Center(child: CircularProgressIndicator(color: ClayColors.orange))
          : ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 20), children: [
              sectionTitle('هەژمار و ڕێکخستن'),
              ClayCard(child: Column(children: [
                Row(children: [
                  const ClayIconBadge(icon: Icons.person_rounded, size: 54, tone: ClayTone.orange),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile?['full_name'] as String? ?? 'بەکارهێنەر', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(user.email ?? '', style: TextStyle(color: context.clayMuted, fontSize: 12)),
                  ])),
                  _RoleBadge(role: role),
                ]),
                const SizedBox(height: 16),
                _profileInput(_nameController, 'ناوی تەواو', Icons.person_outline_rounded),
                const SizedBox(height: 10),
                _profileInput(_phoneController, 'ژمارەی مۆبایل 07xxxxxxxxx', Icons.phone_outlined, keyboard: TextInputType.phone),
                const SizedBox(height: 10),
                _profileInput(_cityController, 'شار (بۆ نموونە سلێمانی)', Icons.location_city_rounded),
                const SizedBox(height: 14),
                ClayPillButton(label: _saving ? 'پاشەکەوت دەکرێت...' : 'پاشەکەوتکردن', icon: Icons.save_rounded, expand: true, onPressed: _saving ? null : _save),
              ])),
              const SizedBox(height: 12),
              ClayCard(child: Column(children: [
                Row(children: [
                  const ClayIconBadge(icon: Icons.dark_mode_rounded, size: 42, tone: ClayTone.lavender),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('دۆخی تاریک', style: TextStyle(fontWeight: FontWeight.w700))),
                  Switch.adaptive(
                    value: themeMode == ThemeMode.dark,
                    activeColor: ClayColors.orange,
                    onChanged: (value) => ref.read(themeModeProvider.notifier).state = value ? ThemeMode.dark : ThemeMode.light,
                  ),
                ]),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const ClayIconBadge(icon: Icons.store_mall_directory_rounded, size: 42, tone: ClayTone.mint),
                  title: const Text('داشبۆردی دوکان', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('داواکاری دوکان یان بەڕێوەبردنی دوکان', style: TextStyle(fontSize: 11, color: context.clayMuted)),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => context.push('/seller'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const ClayIconBadge(icon: Icons.receipt_long_rounded, size: 42, tone: ClayTone.orange),
                  title: const Text('داواکارییەکان', style: TextStyle(fontWeight: FontWeight.w700)),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => context.push('/orders'),
                ),
              ])),
              const SizedBox(height: 12),
              ClayPillButton(label: 'چوونەدەرەوە', icon: Icons.logout_rounded, tone: ClayTone.coral, expand: true, onPressed: () async {
                await ref.read(apiProvider).auth.signOut();
                ref.invalidate(profileProvider);
                if (context.mounted) context.go('/home');
              }),
            ]),
    );
  }

  Widget _profileInput(TextEditingController controller, String hint, IconData icon, {TextInputType? keyboard}) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        child: TextField(controller: controller, keyboardType: keyboard, decoration: InputDecoration(border: InputBorder.none, prefixIcon: Icon(icon), hintText: hint)),
      );
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {'seller' => 'فرۆشیار', 'driver' => 'شۆفێر', 'admin' => 'بەڕێوەبەر', _ => 'کڕیار'};
    return ClayInsetContainer(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), radius: 99, child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.clayAccent)));
  }
}
