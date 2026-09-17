/// `anim-18`'s own golden: `retarget-screen.png` — screen 14's own two
/// non-3D columns, the clip library and the retarget panel, side by side
/// with a source imported, a mixed bone map and a target ready to apply
/// onto. The two viewports in between are `retarget_frame_test.dart`'s own
/// `modeler-retarget.png` instead: a `ModelerViewport` draws through a real
/// `GraphicsDevice`, which a plain widget golden has none of, the same
/// split `frame_test.dart`'s own class comment draws between a picture and
/// a widget test everywhere else in this suite.
///
///     flutter test test/retarget_screen_golden_test.dart
///     flutter test test/retarget_screen_golden_test.dart --update-goldens
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/clip_library.dart';
import 'package:flutter3d_modeler/src/ui/retarget_panel.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

RetargetSource _source() => RetargetSource(
  name: 'mocap.fbx',
  project: ModelProject(
    clips: <ProjectClip>[
      ProjectClip(name: 'Walk', tracks: const <ProjectTrack>[]),
      ProjectClip(name: 'Run', tracks: const <ProjectTrack>[]),
    ],
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(joints: <int>[], inverseBindMatrices: []),
    ],
  ),
  skeletonIndex: 0,
);

void main() {
  testWidgets('the library and the retarget panel match their reference', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(530, 520)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: modelerTheme(),
        home: Scaffold(
          body: Row(
            key: const ValueKey<String>('retarget-screen'),
            children: <Widget>[
              SizedBox(
                width: 230,
                child: ClipLibrary(
                  source: _source(),
                  selectedClipIndex: 0,
                  onSelectClip: (_) {},
                  onImport: () {},
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: RetargetPanel(
                    sourceNames: const <String>[
                      'hips',
                      'leftShoulder',
                      'leftElbow',
                    ],
                    boneMap: const BoneMap(<String, String>{
                      'hips': 'hips',
                      'leftShoulder': 'leftShoulder',
                    }),
                    onAutoMap: () {},
                    rootMotion: RetargetRootMotion.inAnimation,
                    onRootMotionChanged: (_) {},
                    lockFeet: true,
                    onLockFeetChanged: (_) {},
                    groundY: 0.0,
                    onGroundYChanged: (_) {},
                    footTolerance: 1e-3,
                    onFootToleranceChanged: (_) {},
                    canApply: true,
                    onApply: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey<String>('retarget-screen')),
      matchesGoldenFile('goldens/retarget-screen.png'),
    );
  });
}
