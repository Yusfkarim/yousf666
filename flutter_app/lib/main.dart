import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    runApp(const ConfigurationRequiredApp());
    return;
  }
  try {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    runApp(const ProviderScope(child: MarketplaceApp()));
  } catch (error) {
    runApp(ConfigurationRequiredApp(error: error));
  }
}
