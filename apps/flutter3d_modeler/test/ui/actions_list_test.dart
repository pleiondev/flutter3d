/// `anim-07`'s own `ActionsList`: rows over `ProjectClip`s, and the "Add"
/// link `AddClip` needs.
///
///     flutter test test/ui/actions_list_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_modeler/src/ui/actions_list.dart';
import 'package:flutter3d_modeler/src/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required List<ProjectClip> clips,
  int? selectedClip,
  ValueChanged<int>? onSelectClip,
  VoidCallback? onAddClip,
}) => tester.pumpWidget(
  MaterialApp(
    theme: modelerTheme(),
    home: Scaffold(
      body: ActionsList(
        clips: clips,
        selectedClip: selectedClip,
        onSelectClip: onSelectClip ?? (_) {},
        onAddClip: onAddClip ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('no clips says so, and the Add link still shows', (tester) async {
    await _pump(tester, clips: const <ProjectClip>[]);

    expect(find.text('No actions'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Add'), findsOneWidget);
  });

  testWidgets('a clip with no name falls back to its own index', (
    tester,
  ) async {
    await _pump(
      tester,
      clips: const <ProjectClip>[ProjectClip(tracks: <ProjectTrack>[])],
    );

    expect(find.text('clip 0'), findsOneWidget);
  });

  testWidgets('a named clip shows its own name', (tester) async {
    await _pump(
      tester,
      clips: const <ProjectClip>[
        ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
      ],
    );

    expect(find.text('walk'), findsOneWidget);
  });

  testWidgets('tapping a row reports its own index, not always zero', (
    tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      clips: const <ProjectClip>[
        ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
        ProjectClip(name: 'run', tracks: <ProjectTrack>[]),
      ],
      onSelectClip: selected.add,
    );

    await tester.tap(find.text('run'));
    await tester.pump();

    expect(selected, <int>[1]);
  });

  testWidgets('the Add link calls onAddClip', (tester) async {
    var added = 0;
    await _pump(
      tester,
      clips: const <ProjectClip>[
        ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
      ],
      onAddClip: () => added++,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pump();

    expect(added, 1);
  });
}
