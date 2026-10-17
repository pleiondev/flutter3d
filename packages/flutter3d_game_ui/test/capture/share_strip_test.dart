/// The strip a finished run is shared from and somebody else's is opened
/// from.
///
///     flutter test test/share_strip_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_game_ui/capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the strip shares what was played and opens a code', (
    WidgetTester tester,
  ) async {
    final opened = <String>[];
    Widget strip({Future<String> Function()? share}) => MaterialApp(
      home: Scaffold(
        body: ShareStrip(
          onShare: share,
          onOpen: (String code) async {
            opened.add(code);
            return 'Racing $code.';
          },
        ),
      ),
    );
    // Mutation: always show the share button. Nothing played, nothing to
    // share: a button that cannot work.
    await tester.pumpWidget(strip());
    expect(find.byKey(const ValueKey<String>('share:run')), findsNothing);

    await tester.pumpWidget(strip(share: () async => 'Your code is K7Q2.'));
    await tester.tap(find.byKey(const ValueKey<String>('share:run')));
    await tester.pumpAndSettle();
    // Mutation: drop the sentence. A share that failed silently is a code
    // read out to a friend that nobody can open.
    expect(find.text('Your code is K7Q2.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('share:code')),
      ' K7Q2 ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('share:open')));
    await tester.pumpAndSettle();
    // Mutation: hand over the field as typed — a code pasted with a space
    // round it opens nothing.
    expect(opened, <String>['K7Q2']);
    expect(find.text('Racing K7Q2.'), findsOneWidget);
  });

  testWidgets('the words are the game\'s', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareStrip(
            onShare: () async => '',
            onOpen: (String code) async => '',
            shareLabel: 'Share this replay',
            codeHint: 'A replay code',
            openLabel: 'Watch it',
          ),
        ),
      ),
    );
    // Mutation: the labels written into the widget, and every game asks to
    // race whatever it was given.
    expect(find.text('Share this replay'), findsOneWidget);
    expect(find.text('A replay code'), findsOneWidget);
    expect(find.text('Watch it'), findsOneWidget);
    expect(find.text('Race it'), findsNothing);
  });
}
