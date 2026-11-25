import 'package:flutter_test/flutter_test.dart';

import 'package:local_marketplace/app.dart';

void main() {
  testWidgets('shows the configuration screen when Supabase env is missing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ConfigurationRequiredApp());

    expect(find.byType(ConfigurationRequiredApp), findsOneWidget);
  });
}
