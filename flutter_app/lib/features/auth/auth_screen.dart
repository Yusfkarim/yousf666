import '../../core/services/marketplace_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/state/app_state.dart';
import '../../core/theme/clay_widgets.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(apiProvider).auth;
      if (_registering) {
        final response = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'full_name': _name.text.trim()},
        );
        if (!mounted) return;
        if (response.session != null) {
          ref.invalidate(profileProvider);
          context.go('/home');
        } else {
          _showMessage('هەژمارەکەت دروست کرا؛ تکایە ئیمەیڵەکەت پشتڕاست بکەرەوە.');
        }
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
        if (!mounted) return;
        ref.invalidate(profileProvider);
        context.go('/home');
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('نەتوانرا پەیوەندی بکرێت: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).auth.signInWithOAuth(OAuthProvider.google);
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('چوونەژوورەوە بە گووگڵ سەرکەوتوو نەبوو: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 25, 22, 30),
                children: [
                  ClayCard(
                    padding: const EdgeInsets.all(18),
                    child: Row(children: [
                      const ClayIconBadge(icon: Icons.widgets_rounded, size: 50, tone: ClayTone.orange),
                      const SizedBox(width: 13),
                      Expanded(child: Text('بازاڕی یۆسف', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: context.clayAccent))),
                      IconButton(onPressed: () => context.go('/home'), icon: const Icon(Icons.close_rounded)),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  Text(_registering ? 'هەژمارێکی نوێ دروست بکە' : 'بەخێربێیتەوە', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 7),
                  Text('بۆ بازاڕکردن و داواکردنی کاڵا بە COD بچۆ ژوورەوە.', style: TextStyle(color: context.clayMuted)),
                  const SizedBox(height: 20),
                  ClayCard(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_registering) ...[
                            _input(_name, 'ناوی تەواو', Icons.person_outline_rounded, validator: (value) => (value == null || value.trim().length < 2) ? 'ناوت بنووسە' : null),
                            const SizedBox(height: 11),
                          ],
                          _input(_email, 'ئیمەیڵ', Icons.email_outlined, keyboardType: TextInputType.emailAddress, validator: (value) => (value == null || !value.contains('@')) ? 'ئیمەیڵێکی دروست بنووسە' : null),
                          const SizedBox(height: 11),
                          _input(
                            _password,
                            'وشەی نهێنی',
                            Icons.lock_outline_rounded,
                            obscureText: _hidePassword,
                            suffix: IconButton(
                              onPressed: () => setState(() => _hidePassword = !_hidePassword),
                              icon: Icon(_hidePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                            ),
                            validator: (value) => (value == null || value.length < 8) ? 'وشەی نهێنی لانیکەم ٨ پیت بێت' : null,
                          ),
                          const SizedBox(height: 18),
                          ClayPillButton(
                            label: _busy ? 'تکایە چاوەڕێ بکە...' : _registering ? 'دروستکردنی هەژمار' : 'چوونەژوورەوە',
                            icon: Icons.arrow_forward_rounded,
                            expand: true,
                            onPressed: _busy ? null : _submit,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _googleSignIn,
                            icon: Icon(Icons.g_mobiledata_rounded, size: 28, color: context.clayAccent),
                            label: const Text('بە گووگڵ بەردەوام بە'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.clayText,
                              side: const BorderSide(color: ClayColors.line),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: const StadiumBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _busy ? null : () => setState(() => _registering = !_registering),
                            child: Text(_registering ? 'هەژمارت هەیە؟ بچۆ ژوورەوە' : 'هەژمارت نییە؟ دروستی بکە'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('ژمارەی مۆبایلی عێراقی 07xxxxxxxxx لە بەشی هەژمار دابنێ بۆ ناردنی داواکاری.', textAlign: TextAlign.center, style: TextStyle(color: context.clayMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _input(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) => ClayInsetContainer(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        child: TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: label,
            prefixIcon: Icon(icon, color: context.clayMuted),
            suffixIcon: suffix,
          ),
        ),
      );
}
