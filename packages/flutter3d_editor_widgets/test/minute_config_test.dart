/// The guard on `test/flutter_test_config.dart`, which every suite with a
/// widget test carries byte for byte (the structure rule "a test runs in a
/// minute unless its reason is listed" holds them identical, and holds this
/// file to being here).
///
/// **What it guards is an order inside flutter_test.** The configuration gives
/// widget tests the package's minute by setting
/// `PaintingBinding.shaderWarmUp`, which the binding calls while it is being
/// built — after its ten-minute `defaultTestTimeout` is set and before a
/// `testWidgets` reads it. A Flutter upgrade that moved either would put the
/// ten minutes back with nothing failing, so this fails instead. And because
/// the configuration must not change anything else, it also asks that the
/// binding still installed its HTTP client that answers every request with
/// 400 and opens no socket.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a widget test is held to the minute, and keeps its HTTP stub', (
    WidgetTester tester,
  ) async {
    final binding = TestWidgetsFlutterBinding.instance;
    // Mutation: drop the `shaderWarmUp` line from flutter_test_config.dart and
    // this is the binding's own ten minutes.
    expect(binding, isA<AutomatedTestWidgetsFlutterBinding>());
    expect(
      (binding as AutomatedTestWidgetsFlutterBinding).defaultTestTimeout,
      const Timeout.factor(1),
      reason:
          'the configuration no longer reaches the binding before testWidgets '
          'reads its timeout; widget tests have ten minutes again',
    );

    // Port 1 on loopback: nothing listens there, so a real client fails to
    // connect, and only the stub answers.
    final status = await tester.runAsync(() async {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse('http://127.0.0.1:1/'));
        final response = await request.close();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    });
    expect(
      status,
      400,
      reason: 'the binding no longer installs its HTTP stub for widget tests',
    );
  });
}
