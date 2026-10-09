/// The build's steps: the engine's three in their order, a project's own
/// placed among them by name, what each read declared, and a failure named.
///
///     dart test test/build_steps_test.dart
///
/// Against a bare temporary directory — no sources, no materials, no
/// pubspec — so the engine's steps run and do nothing, and what is under
/// test is the scheduler. Each test was written by breaking what it covers;
/// the mutation is named.
library;

import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ConstraintCycleException;
import 'package:test/test.dart';

/// A step that writes down that it ran, and reads and writes one file each.
final class _Step extends BuildStep {
  _Step(
    this.name,
    this.journal, {
    this.after = const <String>[],
    this.before = const <String>[],
    this.fails = false,
  });

  @override
  final String name;

  @override
  final List<String> after;

  @override
  final List<String> before;

  final List<String> journal;
  final bool fails;

  @override
  void run(BuildStepContext context) {
    if (fails) throw StateError('the terrain has no heights');
    journal.add(name);
  }

  @override
  List<String> inputs(BuildStepContext context) => <String>[
    '${context.projectRoot.path}/$name.in',
  ];

  @override
  List<String> outputs(BuildStepContext context) => <String>[
    '${context.layout.generatedDir.path}/$name.out',
  ];
}

void main() {
  late Directory project;

  setUp(() => project = Directory.systemTemp.createTempSync('f3d_steps_'));
  tearDown(() => project.deleteSync(recursive: true));

  test('with no steps of its own, the build runs the engine\'s three in the '
      'order it always did', () async {
    final report = await runBuildSteps(project, log: _Silent());

    // Mutation: list the built-ins as plugins, models, materials. The
    // plugin list would be written before the materials compiled.
    expect(report.ran, <String>['models', 'materials', 'plugins']);
    expect(report.dependencies, isEmpty);
  });

  test('a step that says nothing runs last, in the order given; one that '
      'names a built-in moves up to it', () async {
    final journal = <String>[];
    final steps = <BuildStep>[
      _Step('bake', journal),
      _Step('terrain', journal, before: const <String>['materials']),
      _Step(
        'atlas',
        journal,
        after: const <String>['models'],
        before: const <String>['plugins'],
      ),
    ];

    // Mutation: drop `before` from the scheduler's call. "terrain" would
    // run after the materials it is meant to feed.
    expect(buildStepOrder(steps), <String>[
      'models',
      'terrain',
      'materials',
      'atlas',
      'plugins',
      'bake',
    ]);
    final report = await runBuildSteps(project, steps: steps, log: _Silent());
    expect(report.ran, buildStepOrder(steps));
    expect(journal, <String>['terrain', 'atlas', 'bake']);
  });

  test('what each step read is declared, in run order', () async {
    final journal = <String>[];
    final report = await runBuildSteps(
      project,
      steps: <BuildStep>[
        _Step('bake', journal),
        _Step('terrain', journal, before: const <String>['models']),
      ],
      log: _Silent(),
    );

    // Mutation: collect outputs into dependencies. The hook would rerun on
    // its own outputs, and a build would never be current.
    expect(report.dependencies, <String>[
      '${project.path}/terrain.in',
      '${project.path}/bake.in',
    ]);
    expect(report.outputs, <String>[
      '${project.path}/flutter3d_generated/terrain.out',
      '${project.path}/flutter3d_generated/bake.out',
    ]);
  });

  test('a step that throws fails the build with its name', () async {
    final journal = <String>[];
    // Mutation: let the error through unwrapped. The hook would report "the
    // terrain has no heights" with nothing saying which step said it.
    await expectLater(
      runBuildSteps(
        project,
        steps: <BuildStep>[
          _Step('terrain', journal, fails: true),
          _Step('bake', journal, after: const <String>['terrain']),
        ],
        log: _Silent(),
      ),
      throwsA(
        isA<BuildStepException>()
            .having((e) => e.step, 'step', 'terrain')
            .having((e) => e.message, 'message', contains('"terrain"')),
      ),
    );
    expect(journal, isEmpty, reason: 'nothing after the failure ran');
  });

  test('a step may not take a built-in\'s name or another step\'s', () {
    final journal = <String>[];
    // Mutation: skip the name check. A second "materials" would be an
    // anchor two steps answer to, and ordering around it a guess.
    expect(
      () => buildStepOrder(<BuildStep>[_Step('materials', journal)]),
      throwsArgumentError,
    );
    expect(
      () => buildStepOrder(<BuildStep>[
        _Step('bake', journal),
        _Step('bake', journal),
      ]),
      throwsArgumentError,
    );
    // And the hook refuses them when it is written, not on its first build.
    expect(
      () => buildAssetsWith(<BuildStep>[_Step('plugins', journal)]),
      throwsArgumentError,
    );
  });

  test('a cycle among the steps names them', () {
    final journal = <String>[];
    // Mutation: hold the built-ins in order by registration alone. A step
    // asking to run after plugins and before models would then slip in
    // somewhere instead of being refused.
    expect(
      () => buildStepOrder(<BuildStep>[
        _Step(
          'loop',
          journal,
          after: const <String>['plugins'],
          before: const <String>['models'],
        ),
      ]),
      throwsA(
        isA<ConstraintCycleException>().having(
          (e) => e.cycle,
          'cycle',
          contains('loop'),
        ),
      ),
    );
  });
}

/// A log nobody reads.
final class _Silent implements IOSink {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
