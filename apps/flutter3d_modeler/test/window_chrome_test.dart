/// `ux-30`'s own window chrome: what the `NSWindow` is told, and when.
///
///     flutter test test/window_chrome_test.dart
///
/// The native half is four lines of Swift nothing here can run. What this
/// holds is the half that decides *whether* those four lines ever hear
/// anything — which is where the bug would be, since a message sent once at
/// startup and never again is exactly what the old title was.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter3d_modeler/src/ui/window_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `show` call made on [channel], in order.
List<Map<Object?, Object?>> listen(MethodChannel channel) {
  final calls = <Map<Object?, Object?>>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'show') {
          calls.add(call.arguments as Map<Object?, Object?>);
        }
        return null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  return calls;
}

Future<void> pump(
  WidgetTester tester, {
  required String name,
  required bool isDirty,
  required MethodChannel channel,
  bool native = true,
}) => tester.pumpWidget(
  MaterialApp(
    home: DocumentWindowTitle(
      name: name,
      isDirty: isDirty,
      channel: channel,
      native: native,
      child: const SizedBox(),
    ),
  ),
);

/// This widget's own `Title`, and not `MaterialApp`'s own one above it.
final Finder ourTitle = find.descendant(
  of: find.byType(DocumentWindowTitle),
  matching: find.byType(Title),
);

void main() {
  const MethodChannel channel = MethodChannel('flutter3d/window');

  testWidgets('the window is told the name and the unsaved mark', (
    WidgetTester tester,
  ) async {
    final List<Map<Object?, Object?>> calls = listen(channel);

    await pump(tester, name: 'teapot', isDirty: false, channel: channel);
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single['title'], 'teapot');
    expect(calls.single['edited'], isFalse);
  });

  testWidgets('a rename and a first edit each reach it', (
    WidgetTester tester,
  ) async {
    final List<Map<Object?, Object?>> calls = listen(channel);

    await pump(tester, name: 'teapot', isDirty: false, channel: channel);
    await pump(tester, name: 'teapot', isDirty: true, channel: channel);
    await pump(tester, name: 'robot', isDirty: true, channel: channel);
    await tester.pump();

    // The row's own acceptance: the macOS title follows a rename and a save.
    expect(
      calls.map((Map<Object?, Object?> it) => '${it['title']}/${it['edited']}'),
      <String>['teapot/false', 'teapot/true', 'robot/true'],
    );
  });

  testWidgets('and a rebuild that changed neither says nothing', (
    WidgetTester tester,
  ) async {
    final List<Map<Object?, Object?>> calls = listen(channel);

    await pump(tester, name: 'teapot', isDirty: true, channel: channel);
    for (var each = 0; each < 5; each++) {
      await pump(tester, name: 'teapot', isDirty: true, channel: channel);
    }
    await tester.pump();

    // **This screen rebuilds once a frame.** Mutation: send on every build,
    // and a title nobody renamed becomes sixty platform messages a second —
    // a channel used as a spin loop.
    expect(calls, hasLength(1));
  });

  testWidgets('a platform with no window of its own is never called', (
    WidgetTester tester,
  ) async {
    final List<Map<Object?, Object?>> calls = listen(channel);

    await pump(
      tester,
      name: 'teapot',
      isDirty: true,
      channel: channel,
      native: false,
    );
    await tester.pump();

    // A browser answers `MissingPluginException` to this and there is
    // nothing it could do with the answer: `Title` is the whole of what a
    // tab reads, and it is drawn either way.
    expect(calls, isEmpty);
    expect(ourTitle, findsOneWidget);
  });

  testWidgets('the title the rest of the world reads is drawn as well', (
    WidgetTester tester,
  ) async {
    listen(channel);

    await pump(tester, name: 'teapot', isDirty: true, channel: channel);

    final Title title = tester.widget<Title>(ourTitle);
    expect(title.title, '• teapot — flutter3d modeller');
  });
}
