import 'package:flutter_test/flutter_test.dart';

import 'package:local_marketplace/app.dart';

void main() {
  testWidgets('shows the configuration screen when the API is unreachable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ConfigurationRequiredApp());

    expect(find.byType(ConfigurationRequiredApp), findsOneWidget);
  });
}
