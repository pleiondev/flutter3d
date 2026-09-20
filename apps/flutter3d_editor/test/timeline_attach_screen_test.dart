/// `TimelineAttachScreen` against a fake `TimelineClient` — the UI logic on
/// top of the real wire protocol
/// `flutter3d_session/test/run_timeline_extensions_test.dart` already
/// proves against an actual running process. This file is what stays fast
/// and deterministic; that one is what stays honest about the protocol.
///
///     flutter test test/timeline_attach_screen_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter3d_editor/src/timeline_attach_screen.dart';
import 'package:flutter3d_editor/src/timeline_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A save panel that never opens a real dialog — it answers with a path
/// under the test's own temporary directory, the way the real one would
/// answer with wherever a person clicked.
final class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this.path);

  final String path;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => FileSaveLocation(path);
}

final class _FakeTimelineClient implements TimelineClient {
  bool paused = false;
  final List<String> commands = <String>[];
  TimelinePreview? nextPreview;
  bool releaseSucceeds = true;
  Error? throwOnPause;
  StepCosts? nextFrameTimes;
  Map<String, Object?> nextBugReport = const <String, Object?>{};

  @override
  Future<bool> status() async => paused;

  @override
  Future<void> pause() async {
    if (throwOnPause != null) throw throwOnPause!;
    paused = true;
    commands.add('paused');
  }

  @override
  Future<void> resume() async {
    paused = false;
    commands.add('resumed');
  }

  @override
  Future<void> stepOnce() async {
    commands.add('stepped');
  }

  @override
  Future<TimelinePreview> preview(double secondsAgo) async =>
      nextPreview ?? (found: false, step: null);

  @override
  Future<bool> releaseAtStep(int step) async {
    if (releaseSucceeds) commands.add('branched:$step');
    return releaseSucceeds;
  }

  @override
  Future<List<String>> history() async => List<String>.of(commands);

  @override
  Future<StepCosts> frameTimes() async =>
      nextFrameTimes ?? (steps: const <int>[], millis: const <double>[]);

  @override
  Future<Map<String, Object?>> bugReport() async => nextBugReport;

  @override
  Future<void> dispose() async {}
}

Future<void> _pump(WidgetTester tester, TimelineClient client) async {
  await tester.pumpWidget(
    MaterialApp(home: TimelineAttachScreen(client: client)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Pause and a disabled Step when the run is live', (
    tester,
  ) async {
    await _pump(tester, _FakeTimelineClient());

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    final step = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Step'),
    );
    expect(step.onPressed, isNull, reason: 'stepping while live is refused');
  });

  testWidgets('starts already showing Resume when the remote is paused', (
    tester,
  ) async {
    await _pump(tester, _FakeTimelineClient()..paused = true);

    expect(find.text('Resume'), findsOneWidget);
    final step = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Step'),
    );
    expect(step.onPressed, isNotNull);
  });

  testWidgets('tapping Pause calls the client and flips the button to Resume', (
    tester,
  ) async {
    final client = _FakeTimelineClient();
    await _pump(tester, client);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(client.commands, <String>['paused']);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('preview shows the step it found and enables Release', (
    tester,
  ) async {
    final client = _FakeTimelineClient()
      ..nextPreview = (found: true, step: 118);
    await _pump(tester, client);

    final releaseBefore = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Release here'),
    );
    expect(releaseBefore.onPressed, isNull);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('at step 118'), findsOneWidget);
    final releaseAfter = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Release here'),
    );
    expect(releaseAfter.onPressed, isNotNull);
  });

  testWidgets('a preview that found nothing says so and Release stays off', (
    tester,
  ) async {
    final client = _FakeTimelineClient()
      ..nextPreview = (found: false, step: null);
    await _pump(tester, client);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('not far enough back'), findsOneWidget);
    final release = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Release here'),
    );
    expect(release.onPressed, isNull);
  });

  testWidgets('Release calls releaseAtStep with the previewed step and '
      'refreshes the history', (tester) async {
    final client = _FakeTimelineClient()..nextPreview = (found: true, step: 42);
    await _pump(tester, client);
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Release here'));
    await tester.pumpAndSettle();

    expect(client.commands, <String>['branched:42']);
    expect(
      find.text('branched:42'),
      findsOneWidget,
      reason: 'the history list should show it',
    );
  });

  testWidgets('an error from the client is shown rather than swallowed', (
    tester,
  ) async {
    final client = _FakeTimelineClient()
      ..throwOnPause = StateError('the socket closed');
    await _pump(tester, client);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(find.textContaining('the socket closed'), findsOneWidget);
    // And the button did not flip, because the action never went through.
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('says so when the running game reports no frame times', (
    tester,
  ) async {
    await _pump(tester, _FakeTimelineClient());

    expect(find.text('no frame times yet'), findsOneWidget);
  });

  testWidgets('draws one tappable bar per reported step', (tester) async {
    final client = _FakeTimelineClient()
      ..nextFrameTimes = (
        steps: <int>[1, 2, 3],
        millis: <double>[1.0, 4.0, 2.0],
      );
    await _pump(tester, client);

    expect(find.text('no frame times yet'), findsNothing);
    for (final step in [1, 2, 3]) {
      expect(find.byKey(ValueKey<int>(step)), findsOneWidget);
    }
  });

  testWidgets('tapping a frame-time bar releases the timeline at its step', (
    tester,
  ) async {
    final client = _FakeTimelineClient()
      ..nextFrameTimes = (steps: <int>[7], millis: <double>[1.0]);
    await _pump(tester, client);

    await tester.tap(find.byKey(const ValueKey<int>(7)));
    await tester.pumpAndSettle();

    expect(client.commands, <String>['branched:7']);
  });

  testWidgets(
    'Save bug report writes the client\'s report to the chosen file',
    (tester) async {
      // Sync I/O throughout this setup — under the package's own working
      // directory rather than the system temp one, and through the
      // Sync file APIs `replay_video_test.dart` and `posed_models_test.dart`
      // already rely on for one-off writes in a widget test.
      final dir = Directory('${Directory.current.path}/build/bugreport_test');
      dir.createSync(recursive: true);
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = '${dir.path}/report.json';
      final previous = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FakeFileSelector(target);
      addTearDown(() => FileSelectorPlatform.instance = previous);

      final client = _FakeTimelineClient()
        ..nextBugReport = <String, Object?>{'x': 3.0, 'step': 7};
      await _pump(tester, client);

      await tester.tap(find.text('Save bug report'));
      await tester.pumpAndSettle();

      final written = jsonDecode(File(target).readAsStringSync());
      expect(written, <String, Object?>{'x': 3.0, 'step': 7});

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Save bug report'),
      );
      expect(button.onPressed, isNotNull, reason: 'usable again once saved');
    },
  );
}
