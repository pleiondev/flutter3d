/// `S2`'s own `AnimationBottom`: the transport bar plus the `Keys`/`Curves`
/// toggle's own choice of `TimelinePanel`/`CurveEditor`, and the
/// `ValueNotifier<int>` split that keeps a playing clip from rebuilding a
/// screen sixty times a second.
///
///     flutter test test/ui/animation_bottom_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/timeline_playback.dart';
import 'package:flutter3d_modeler/src/ui/animation_bottom.dart';
import 'package:flutter3d_modeler/src/ui/curve_editor.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter3d_modeler/src/ui/timeline_panel.dart';
import 'package:flutter3d_modeler/src/ui/transport_bar.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectClip _clip() => ProjectClip(
  name: 'walk',
  tracks: <ProjectTrack>[
    ProjectTrack(
      objectId: 1,
      track: AnimationTrack(
        nodeIndex: 0,
        path: AnimationPath.translation,
        interpolation: AnimationInterpolation.linear,
        times: Float32List.fromList(<double>[0.0, 1.0]),
        values: Float32List.fromList(<double>[0, 0, 0, 1, 0, 0]),
        componentCount: 3,
      ),
    ),
  ],
);

void main() {
  testWidgets('advancing the frame notifier moves the transport bar without '
      'rebuilding the widget that owns it', (tester) async {
    var hostBuilds = 0;
    final frame = ValueNotifier<int>(0);
    addTearDown(frame.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) {
              hostBuilds++;
              return SizedBox(
                height: ModelerMetrics.timeline,
                child: AnimationBottom(
                  clipIndex: 0,
                  clip: _clip(),
                  frame: frame,
                  fps: 30.0,
                  playback: const Playback(),
                  editMode: TimelineEditMode.keys,
                  onEditMode: (_) {},
                  onPlayPause: () {},
                ),
              );
            },
          ),
        ),
      ),
    );
    final buildsAfterFirstPump = hostBuilds;
    expect(find.text('0'), findsOneWidget);

    // Sixty of these is a whole second of playback; the point of the
    // `ValueNotifier` is that not one of them touches `hostBuilds`.
    for (var f = 1; f <= 60; f++) {
      frame.value = f;
      await tester.pump();
    }

    // Mutation: rebuild the host on every frame tick instead of scoping
    // the rebuild to the `ValueListenableBuilder`s inside `AnimationBottom`.
    expect(hostBuilds, buildsAfterFirstPump);
    expect(find.text('60'), findsOneWidget);
  });

  testWidgets('the Keys/Curves toggle actually swaps which widget renders', (
    tester,
  ) async {
    final frame = ValueNotifier<int>(0);
    addTearDown(frame.dispose);

    Future<void> pump(TimelineEditMode mode) => tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Scaffold(
          body: SizedBox(
            height: ModelerMetrics.timeline,
            child: AnimationBottom(
              clipIndex: 0,
              clip: _clip(),
              frame: frame,
              fps: 30.0,
              playback: const Playback(),
              editMode: mode,
              onEditMode: (_) {},
              onPlayPause: () {},
              selectedTrack: 0,
            ),
          ),
        ),
      ),
    );

    await pump(TimelineEditMode.keys);
    expect(find.byType(TimelinePanel), findsOneWidget);
    expect(find.byType(CurveEditor), findsNothing);

    await pump(TimelineEditMode.curves);
    expect(find.byType(TimelinePanel), findsNothing);
    expect(find.byType(CurveEditor), findsOneWidget);
  });

  testWidgets('no open clip shows the transport bar over a placeholder', (
    tester,
  ) async {
    final frame = ValueNotifier<int>(0);
    addTearDown(frame.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Scaffold(
          body: SizedBox(
            height: ModelerMetrics.timeline,
            child: AnimationBottom(
              frame: frame,
              fps: 30.0,
              playback: const Playback(),
              editMode: TimelineEditMode.keys,
              onEditMode: (_) {},
              onPlayPause: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TransportBar), findsOneWidget);
    expect(find.byType(TimelinePanel), findsNothing);
    expect(find.byType(CurveEditor), findsNothing);
  });
}
