/// `anim-18`'s own left column: the search box, the card grid, and the "no
/// skin" warning card.
///
///     flutter test test/clip_library_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:flutter3d_modeler/src/ui/clip_library.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

RetargetSource _source({String? warning}) => RetargetSource(
  name: 'mocap.fbx',
  project: ModelProject(
    clips: <ProjectClip>[
      ProjectClip(name: 'Walk', tracks: <ProjectTrack>[]),
      ProjectClip(name: 'Run', tracks: <ProjectTrack>[]),
    ],
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(joints: <int>[], inverseBindMatrices: []),
    ],
  ),
  skeletonIndex: 0,
  warning: warning,
);

Future<void> _pump(
  WidgetTester tester, {
  RetargetSource? source,
  int? selectedClipIndex,
  ValueChanged<int>? onSelectClip,
  VoidCallback? onImport,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 230,
        height: 400,
        child: ClipLibrary(
          source: source,
          selectedClipIndex: selectedClipIndex,
          onSelectClip: onSelectClip ?? (_) {},
          onImport: onImport ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('no source: the import prompt shows, no cards', (tester) async {
    await _pump(tester);

    expect(find.text('No source imported yet'), findsOneWidget);
    expect(find.text('Import a source clip'), findsOneWidget);
  });

  testWidgets('a source with clips draws one card per clip', (tester) async {
    await _pump(tester, source: _source());

    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    // Neither clip carries a key, so both read as zero-length.
    expect(find.text('0.0s'), findsNWidgets(2));
  });

  testWidgets('the warning card shows only when the source carries one', (
    tester,
  ) async {
    await _pump(tester, source: _source());
    expect(find.textContaining('mapped by node names only'), findsNothing);

    await _pump(
      tester,
      source: _source(
        warning:
            'Imported without a skin — mapped by node '
            'names only.',
      ),
    );
    expect(find.textContaining('mapped by node names only'), findsOneWidget);
  });

  testWidgets('the search box narrows the card list by name', (tester) async {
    await _pump(tester, source: _source());

    await tester.enterText(find.byType(TextField), 'wa');
    await tester.pump();

    expect(find.text('Walk'), findsOneWidget);
    expect(find.text('Run'), findsNothing);
  });

  testWidgets('tapping a card reports its own index', (tester) async {
    final tapped = <int>[];
    await _pump(tester, source: _source(), onSelectClip: tapped.add);

    await tester.tap(find.text('Run'));

    expect(tapped, <int>[1]);
  });

  testWidgets('the import button is reachable a second way from here', (
    tester,
  ) async {
    var imported = 0;
    await _pump(tester, onImport: () => imported++);

    await tester.tap(find.text('Import a source clip'));

    expect(imported, 1);
  });
}
