/// `ui-15`'s own start screen: "Open file", "New project" with a profile,
/// and the recent list, each pressable choice landing back as a distinct
/// [StartChoice].
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_modeler/src/ui/start_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Future<StartChoice?> _open(
  WidgetTester tester, {
  List<String> recentPaths = const <String>[],
}) async {
  StartChoice? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () async {
            result = await showStartScreen(context, recentPaths: recentPaths);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('Open file returns OpenFileChoice', (WidgetTester tester) async {
    await _open(tester);
    await tester.tap(find.text('Open file'));
    await tester.pumpAndSettle();
    expect(find.text('Open file'), findsNothing);
  });

  testWidgets(
    'the two profiles are both offered under New project',
    (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('desktop'), findsOneWidget);
      expect(find.text('mobile'), findsOneWidget);
    },
  );

  testWidgets(
    'picking a profile closes the dialog with that choice',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () async {
                await showStartScreen(context, recentPaths: const <String>[]);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('mobile'));
      await tester.pumpAndSettle();
      expect(find.text('mobile'), findsNothing);
    },
  );

  testWidgets(
    'with no recent files, the section is not shown at all',
    (WidgetTester tester) async {
      await _open(tester);
      expect(find.text('Recent'), findsNothing);
    },
  );

  testWidgets(
    'a recent path is offered by its own last segment',
    (WidgetTester tester) async {
      await _open(
        tester,
        recentPaths: const <String>['/Users/dmitrii/models/teapot.f3dproj'],
      );
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('teapot.f3dproj'), findsOneWidget);
    },
  );

  testWidgets('Cancel returns null', (WidgetTester tester) async {
    StartChoice? result = const OpenFileChoice();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              result = await showStartScreen(
                context,
                recentPaths: const <String>[],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
