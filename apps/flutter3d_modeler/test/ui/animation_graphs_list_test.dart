/// N1's panel: the project's animation graphs, listed, opened, set and
/// removed — over a real `ModelHistory`, so what lands is what
/// `SetAnimationGraph` takes and what is refused is its own sentence.
///
///     flutter test test/ui/animation_graphs_list_test.dart
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Key;
import 'package:flutter3d_modeler/l10n/app_localizations.dart';
import 'package:flutter3d_modeler/src/ui/animation_graphs_list.dart';
import 'package:flutter_test/flutter_test.dart';

const Map<String, Object?> _walker = <String, Object?>{
  'parameters': <Object?>[
    <String, Object?>{'name': 'speed', 'type': 'float'},
  ],
  'states': <Object?>[
    <String, Object?>{'name': 'idle', 'clip': 'idle'},
    <String, Object?>{'name': 'walk', 'clip': 'walk'},
  ],
  'transitions': <Object?>[
    <String, Object?>{
      'from': 'idle',
      'to': 'walk',
      'conditions': <Object?>[
        <String, Object?>{
          'parameter': 'speed',
          'compare': 'greater',
          'value': 0.1,
        },
      ],
    },
  ],
};

/// The panel over [history], rebuilt as it changes.
Future<void> _pump(WidgetTester tester, ModelHistory history) =>
    tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => AnimationGraphsList(
                graphs: history.project.animationGraphs,
                onSet: (name, graph) {
                  final refused = history.run(
                    SetAnimationGraph(graphName: name, graph: graph),
                  );
                  setState(() {});
                  return refused;
                },
                onRemove: (name) {
                  history.run(RemoveAnimationGraph(graphName: name));
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );

ModelHistory _clipped() => ModelHistory(
  const ModelProject(
    clips: <ProjectClip>[
      ProjectClip(name: 'idle', tracks: <ProjectTrack>[]),
      ProjectClip(name: 'walk', tracks: <ProjectTrack>[]),
    ],
  ),
);

Future<void> _write(WidgetTester tester, String name, String json) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('animation graph name')),
    name,
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('animation graph json')),
    json,
  );
  await tester.tap(find.byKey(const ValueKey<String>('animation graph set')));
  await tester.pump();
}

void main() {
  testWidgets('a graph written as JSON is set, listed with its size, '
      'opened again and removed', (tester) async {
    final history = _clipped();
    await _pump(tester, history);
    expect(
      find.text('No graphs yet. Give a name and a graph in JSON.'),
      findsOneWidget,
    );

    await _write(tester, 'hero', jsonEncode(_walker));
    expect(history.project.animationGraphs.keys, <String>['hero']);
    expect(find.text('hero'), findsWidgets);
    expect(find.text('2 states · 1 transitions'), findsOneWidget);

    // Opened from the list, the text is the graph as it was kept.
    await tester.enterText(
      find.byKey(const ValueKey<String>('animation graph json')),
      '',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('animation graph hero')),
    );
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('animation graph json')),
    );
    expect(
      jsonDecode(field.controller!.text),
      history.project.animationGraphs['hero'],
    );

    await tester.tap(find.byTooltip('Remove graph'));
    await tester.pump();
    expect(history.project.animationGraphs, isEmpty);
  });

  testWidgets('a refusal is shown under the text, and nothing lands', (
    tester,
  ) async {
    final history = _clipped();
    await _pump(tester, history);
    final wrong = jsonDecode(jsonEncode(_walker)) as Map<String, Object?>;
    ((wrong['states']! as List<Object?>)[1]! as Map<String, Object?>)['clip'] =
        'run';
    await _write(tester, 'hero', jsonEncode(wrong));
    expect(find.textContaining('`run`, which is not among'), findsOneWidget);
    expect(history.project.animationGraphs, isEmpty);

    await _write(tester, 'hero', '{"states": [');
    expect(find.textContaining('Not JSON:'), findsOneWidget);
    expect(history.project.animationGraphs, isEmpty);
  });
}
