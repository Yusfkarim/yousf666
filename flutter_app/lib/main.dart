import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/marketplace_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appClient.auth.restore();
  runApp(const ProviderScope(child: MarketplaceApp()));
}
