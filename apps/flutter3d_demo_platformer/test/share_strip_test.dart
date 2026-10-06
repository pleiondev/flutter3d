/// The strip a finished run is shared from and a friend's run is raced
/// from. Apart from `share_ghost_test.dart`, whose real network a widget
/// test's binding would answer with 400s.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_demo_platformer/src/share_strip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the strip shares what was played and races a code', (
    WidgetTester tester,
  ) async {
    final raced = <String>[];
    Widget strip({Future<String> Function()? share}) => MaterialApp(
      home: Scaffold(
        body: ShareStrip(
          onShare: share,
          onRace: (String code) async {
            raced.add(code);
            return 'Racing $code.';
          },
        ),
      ),
    );
    // Nothing played, nothing to share: no button that cannot work.
    await tester.pumpWidget(strip());
    expect(find.byKey(const ValueKey<String>('share:run')), findsNothing);

    await tester.pumpWidget(strip(share: () async => 'Your code is K7Q2.'));
    await tester.tap(find.byKey(const ValueKey<String>('share:run')));
    await tester.pumpAndSettle();
    expect(find.text('Your code is K7Q2.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('share:code')),
      ' K7Q2 ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('share:race')));
    await tester.pumpAndSettle();
    expect(raced, <String>['K7Q2']);
    expect(find.text('Racing K7Q2.'), findsOneWidget);
  });
}
