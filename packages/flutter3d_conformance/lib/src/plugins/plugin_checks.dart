import 'dart:convert';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'harness.dart';

/// One plugin check: a name, and what it finds — one outcome, or one per
/// backend for the backends check.
typedef PluginCheck = ({
  String name,
  List<PluginCheckOutcome> Function(PluginSession session) run,
});

/// The plugin checks, in the order they are reported.
///
/// **Records like the backend suite's**, so `tool/structure.dart` counts
/// them the way it counts those — apart from them, since a plugin check
/// never sees a device.
final List<PluginCheck> pluginChecks = <PluginCheck>[
  (name: 'manifest', run: _manifest),
  (name: 'switch', run: _switch),
  (name: 'determinism', run: _determinism),
  (name: 'backends', run: _backends),
  (name: 'budget', run: _budget),
  (name: 'materials', run: _materials),
];

/// The backends a plugin that names none is installed on: no backend at all
/// (a server, a test), then each of the engine's four by `GraphicsDevice`
/// name.
const List<String?> everyBackend = <String?>[
  null,
  'cpu',
  'webgl',
  'webgpu',
  'impeller',
];

/// The permissions this engine knows how to grant and refuse.
final Set<PluginPermission> _knownPermissions = <PluginPermission>{
  PluginPermission.network,
  PluginPermission.files,
  PluginPermission.tools,
};

/// How many steps a backend's run takes: enough to step every system a few
/// times, few enough that five backends cost less than one determinism run.
const int _backendSteps = 30;

/// One conformance run of one plugin: the factory, the harness, and the
/// world as it was before the first check, so every check starts from it.
///
/// Made by `checkPluginConformance` and `runPluginConformance`; each check
/// builds the loops it needs through [build], never sharing one with
/// another check.
final class PluginSession {
  PluginSession(this.create, this.harness);

  /// Makes the plugin under test, fresh each call.
  final Flutter3dPlugin Function() create;

  final PluginHarness harness;

  Snapshot? _start;

  /// The manifest, read from one instance made for the purpose.
  late final PluginManifest manifest = create().manifest;

  /// Whether [loop]'s snapshots hold a world to compare: something in its
  /// world, or a part beside it — what `PluginHarness.setUp` put there.
  bool hasWorld(EngineLoop loop) => !loop.snapshots.holdsNothing;

  /// Puts [loop]'s state where the first loop of the session began, through
  /// the loop's own snapshots, so a check does not inherit the steps the
  /// previous one ran on anything the loops share. The first loop's capture
  /// is the start; a loop whose snapshots hold nothing is left alone.
  void rewindWorld(EngineLoop loop) {
    if (!hasWorld(loop)) return;
    final start = _start;
    if (start == null) {
      _start = loop.capture();
      return;
    }
    loop.restore(start);
  }

  /// A loop with the dependencies, [withPlugin]'s plugin unless false, the
  /// harness's registries for [backend] and the application's set-up.
  ///
  /// Throws what the loop throws: a [PluginException] for a plugin refused
  /// at install.
  EngineLoop build({
    String? backend,
    bool withPlugin = true,
    DeterminismCheck? check,
  }) {
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[
        ...?harness.dependencies?.call(),
        if (withPlugin) create(),
      ],
      registries: harness.registries?.call(backend) ?? const <PluginRegistry>[],
      backend: backend,
      determinismCheck: check,
    );
    harness.setUp?.call(loop);
    rewindWorld(loop);
    return loop;
  }
}

/// What a loop is made of, as names: its phases of both kinds, the systems
/// in each, and the events declared on its bus. What switching a plugin off
/// must give back exactly.
///
/// Phases and systems in the order they run, since that order is part of
/// what a step does; declared events sorted, since a declaration has no
/// place in a step and one made again on enable is appended at the end.
List<String> _shape(EngineLoop loop) => <String>[
  for (final kind in <PhaseKind>[PhaseKind.step, PhaseKind.frame])
    for (final phase in loop.phases(kind)) ...<String>[
      '${kind.name} phase ${phase.name}',
      for (final system in loop.systemsIn(phase))
        '  system $system in ${phase.name}',
    ],
  ...<String>[
    for (final declared in loop.events.declared) 'event ${declared.name}',
  ]..sort(),
];

String _difference(List<String> want, List<String> got) {
  final missing = want.where((s) => !got.contains(s)).toList();
  final extra = got.where((s) => !want.contains(s)).toList();
  if (missing.isEmpty && extra.isEmpty) {
    return 'the same names in another order';
  }
  return <String>[
    if (extra.isNotEmpty)
      'left behind: ${extra.map((s) => s.trim()).join('; ')}',
    if (missing.isNotEmpty)
      'missing: ${missing.map((s) => s.trim()).join('; ')}',
  ].join('; ');
}

bool _sameShape(List<String> a, List<String> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

String _describe(Object error) => switch (error) {
  PluginException(:final message) => message,
  _ => '$error',
};

// ------------------------------------------------------------------ manifest

List<PluginCheckOutcome> _manifest(PluginSession session) {
  final problems = <String>[];
  final PluginManifest manifest;
  try {
    manifest = session.manifest;
  } on Object catch (error) {
    return <PluginCheckOutcome>[
      PluginCheckOutcome(
        check: 'manifest',
        passed: false,
        says: 'the plugin could not be made: $error',
      ),
    ];
  }
  final idProblem = manifest.idProblem;
  if (idProblem != null) problems.add(idProblem);
  final refusal = manifest.apiVersion.refusalOn(PluginApiVersion.current);
  if (refusal != null) problems.add(refusal);
  for (final permission in manifest.permissions) {
    if (_knownPermissions.contains(permission)) continue;
    problems.add(
      'it asks for the permission "${permission.name}", which this engine '
      'does not know and so can neither grant nor refuse; ask for network, '
      'files or simulation',
    );
  }
  final budget = budgetProblemOf(manifest);
  if (budget != null) problems.add(budget);

  try {
    final written = jsonEncode(manifest.toJson());
    final read = PluginManifest.fromJson(
      jsonDecode(written) as Map<String, Object?>,
    );
    final lost = <String>[
      if (read.id != manifest.id) 'id',
      if (read.apiVersion != manifest.apiVersion) 'apiVersion',
      if (!_sameShape(read.dependsOn, manifest.dependsOn)) 'dependsOn',
      if (read.backends.length != manifest.backends.length ||
          !read.backends.containsAll(manifest.backends))
        'backends',
      if (read.touches.name != manifest.touches.name) 'touches',
      if (read.permissions.length != manifest.permissions.length ||
          !read.permissions.containsAll(manifest.permissions))
        'permissions',
      if (read.description != manifest.description) 'description',
      if (jsonEncode(_sorted(read.extra)) !=
          jsonEncode(_sorted(manifest.extra)))
        'its open keys',
    ];
    if (lost.isNotEmpty) {
      problems.add(
        'written out and read back, the manifest changes its '
        '${lost.join(', ')}; a tool that reads and writes it would change '
        'the plugin',
      );
    }
  } on Object catch (error) {
    problems.add(
      'the manifest does not survive being written as JSON and read back: '
      '$error. Its open keys hold plain values only',
    );
  }

  try {
    session.build();
  } on Object catch (error) {
    problems.add('it is refused at install: ${_describe(error)}');
  }

  return <PluginCheckOutcome>[
    PluginCheckOutcome(
      check: 'manifest',
      passed: problems.isEmpty,
      says: problems.isEmpty
          ? '${manifest.id} (plugin API ${manifest.apiVersion}, touches '
                '${manifest.touches.name}) reads, writes back and installs'
          : problems.join('. '),
    ),
  ];
}

Object? _sorted(Object? value) => switch (value) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final key in map.keys.map((k) => '$k').toList()..sort())
      key: _sorted(map[key]),
  },
  final List<Object?> list => <Object?>[for (final item in list) _sorted(item)],
  _ => value,
};

// -------------------------------------------------------------------- switch

List<PluginCheckOutcome> _switch(PluginSession session) {
  List<PluginCheckOutcome> fail(String says) => <PluginCheckOutcome>[
    PluginCheckOutcome(check: 'switch', passed: false, says: says),
  ];
  try {
    final id = session.manifest.id;
    final baseline = _shape(session.build(withPlugin: false));
    final loop = session.build();
    if (!loop.plugins.isEnabled(id)) {
      return fail(
        'it was installed switched off: '
        '${loop.plugins.statuses.firstWhere((s) => s.id == id).reason}',
      );
    }
    final on = _shape(loop);
    loop.runSteps(3);

    final offAt = loop.step;
    loop.plugins.disable(id);
    loop.runSteps(1);
    final off = _shape(loop);
    if (!_sameShape(off, baseline)) {
      return fail(
        'switched off at step $offAt, the loop is not what it is without '
        'the plugin — ${_difference(baseline, off)}. Everything a plugin '
        'adds goes through its host, so switching it off takes it back',
      );
    }
    loop.runSteps(2);

    final onAt = loop.step;
    loop.plugins.enable(id);
    loop.runSteps(1);
    final again = _shape(loop);
    if (!_sameShape(again, on)) {
      return fail(
        'switched back on at step $onAt, the loop is not what it was with '
        'the plugin — ${_difference(on, again)}',
      );
    }
    loop.runSteps(3);

    final journal = loop.plugins.journal;
    final disabled = journal.any(
      (c) => c is PluginDisabled && c.plugin == id && c.step == offAt,
    );
    final enabled = journal.any(
      (c) => c is PluginEnabled && c.plugin == id && c.step == onAt,
    );
    if (!disabled || !enabled) {
      return fail(
        'the journal does not hold the switch at the steps it was made '
        '(off at $offAt, on at $onAt): ${journal.join(', ')}',
      );
    }
    return <PluginCheckOutcome>[
      PluginCheckOutcome(
        check: 'switch',
        passed: true,
        says:
            'off at step $offAt and on at step $onAt, each at a step '
            'boundary and journalled there; off, the loop is exactly what '
            'it is without the plugin',
      ),
    ];
  } on Object catch (error) {
    return fail('switching it threw: ${_describe(error)}');
  }
}

// --------------------------------------------------------------- determinism

List<PluginCheckOutcome> _determinism(PluginSession session) {
  final harness = session.harness;
  final steps = harness.steps;
  PluginCheckOutcome outcome({
    required bool passed,
    required String says,
    bool declined = false,
  }) => PluginCheckOutcome(
    check: 'determinism',
    passed: passed,
    says: says,
    declined: declined,
  );

  try {
    // (a) Each step run twice from one state, by the loop's own check.
    String? twice;
    var twiceDeclined = false;
    final divergences = <StepDivergence>[];
    final checked = session.build(
      check: DeterminismCheck(onDivergence: divergences.add),
    );
    final hasWorld = session.hasWorld(checked);
    if (hasWorld) {
      final loop = checked;
      if (!loop.checksDeterminism) {
        twiceDeclined = true;
        twice =
            'each step was not run twice: assertions are off; run under '
            '`dart test`, which enables them';
      } else {
        loop.runSteps(steps);
        if (divergences.isNotEmpty) {
          final first = divergences.first;
          return <PluginCheckOutcome>[
            outcome(
              passed: false,
              says:
                  'run twice from one state, step ${first.step} parted: '
                  '${first.reason}'
                  '${first.owner == null ? '' : ' (plugin "${first.owner}")'}',
            ),
          ];
        }
        twice = 'each of $steps steps run twice from one state agreed';
      }
    } else {
      twiceDeclined = true;
      twice =
          "the loop's snapshots hold nothing after setUp — no entity, no "
          'resource, no part — so no step was run twice and the world was '
          "not compared. Put the application's state in loop.world, or add "
          'a SnapshotPart for it (loop.snapshots.add), in setUp';
    }

    // (b) Two fresh loops, the same steps, the same events and world.
    List<(int, int?)> run() {
      final loop = session.build();
      final trace = <(int, int?)>[];
      loop.onStepEnd(
        (summary) =>
            trace.add((summary.digest, hasWorld ? loop.digest() : null)),
      );
      loop.runSteps(steps);
      return trace;
    }

    final first = run();
    final second = run();
    for (var i = 0; i < first.length && i < second.length; i++) {
      if (first[i].$1 != second[i].$1) {
        return <PluginCheckOutcome>[
          outcome(
            passed: false,
            says:
                'two fresh runs published different events at step $i: '
                'something the plugin reads is not in what it was given — '
                'a clock, an unseeded Random, a static it keeps between runs',
          ),
        ];
      }
      if (first[i].$2 != second[i].$2) {
        return <PluginCheckOutcome>[
          outcome(
            passed: false,
            says:
                'two fresh runs left different worlds after step $i: '
                'something the plugin reads is not in what it was given — '
                'a clock, an unseeded Random, a static it keeps between runs',
          ),
        ];
      }
    }
    final again =
        'two fresh runs of $steps steps published the same events'
        '${hasWorld ? ' and left the same world' : ''}';
    return <PluginCheckOutcome>[
      outcome(passed: true, declined: twiceDeclined, says: '$again; $twice'),
    ];
  } on Object catch (error) {
    return <PluginCheckOutcome>[
      outcome(passed: false, says: 'stepping it threw: ${_describe(error)}'),
    ];
  }
}

// ------------------------------------------------------------------ backends

List<PluginCheckOutcome> _backends(PluginSession session) {
  final manifest = session.manifest;
  final declared = manifest.backends.toList();
  final backends = declared.isEmpty ? everyBackend : declared;
  final out = <PluginCheckOutcome>[];
  for (final backend in backends) {
    final named = backend ?? 'no backend';
    try {
      final loop = session.build(backend: backend);
      if (!loop.plugins.isEnabled(manifest.id)) {
        final status = loop.plugins.statuses.firstWhere(
          (s) => s.id == manifest.id,
        );
        out.add(
          PluginCheckOutcome(
            check: 'backends',
            backend: backend,
            passed: false,
            says: 'on $named it was installed switched off: ${status.reason}',
          ),
        );
        continue;
      }
      loop.runSteps(_backendSteps);
      out.add(
        PluginCheckOutcome(
          check: 'backends',
          backend: backend,
          passed: true,
          says: 'on $named it installs on and steps $_backendSteps steps',
        ),
      );
    } on Object catch (error) {
      out.add(
        PluginCheckOutcome(
          check: 'backends',
          backend: backend,
          passed: false,
          says: 'on $named: ${_describe(error)}',
        ),
      );
    }
  }
  if (declared.isNotEmpty) {
    final other = everyBackend.firstWhere(
      (b) => b != null && !declared.contains(b),
      orElse: () => 'headless',
    );
    try {
      final loop = session.build(backend: other);
      final status = loop.plugins.statuses.firstWhere(
        (s) => s.id == manifest.id,
      );
      final off = !status.enabled && status.reason != null;
      out.add(
        PluginCheckOutcome(
          check: 'backends',
          backend: other,
          passed: off,
          says: off
              ? 'on $other, which it does not declare, it is installed '
                    'switched off: ${status.reason}'
              : 'on $other, which it does not declare, it was installed '
                    'switched on',
        ),
      );
    } on Object catch (error) {
      out.add(
        PluginCheckOutcome(
          check: 'backends',
          backend: other,
          passed: false,
          says:
              'on $other, which it does not declare, the loop threw rather '
              'than switching it off: ${_describe(error)}',
        ),
      );
    }
  }
  return out;
}

// -------------------------------------------------------------------- budget

/// How many timed batches each side of the step-time comparison takes; the
/// median of them is what is compared.
const int _batches = 7;

List<PluginCheckOutcome> _budget(PluginSession session) {
  PluginCheckOutcome outcome(
    String says, {
    bool passed = true,
    bool declined = false,
  }) => PluginCheckOutcome(
    check: 'budget',
    passed: passed,
    declined: declined,
    says: says,
  );
  final manifest = session.manifest;
  final problem = budgetProblemOf(manifest);
  if (problem != null) {
    return <PluginCheckOutcome>[outcome(problem, passed: false)];
  }
  final budget = PluginBudget.of(manifest);
  if (budget == null) {
    return <PluginCheckOutcome>[
      outcome(
        'it declares no budget: put {"stepMicroseconds": …, '
        '"eventsPerStep": …} under "budget" in its manifest',
        declined: true,
      ),
    ];
  }
  final steps = session.harness.steps;
  final said = <String>[];
  try {
    final events = budget.eventsPerStep;
    if (events != null) {
      final loop = session.build();
      var most = 0;
      var at = 0;
      loop.onStepEnd((summary) {
        if (summary.count > most) {
          most = summary.count;
          at = summary.step;
        }
      });
      loop.runSteps(steps);
      if (most > events) {
        return <PluginCheckOutcome>[
          outcome(
            'step $at published $most events, and the budget allows '
            '$events',
            passed: false,
          ),
        ];
      }
      said.add('at most $most events a step of $events allowed');
    }

    final micros = budget.stepMicroseconds;
    if (micros != null) {
      // Two loops stepped in alternating batches, so a machine slowing down
      // mid-run slows both sides. The median of each side, and nothing added
      // to the budget: a local measurement is noisy, and the median is the
      // answer to that rather than slack nobody declared.
      final per = steps ~/ _batches < 10 ? 10 : steps ~/ _batches;
      final withPlugin = session.build();
      final without = session.build(withPlugin: false);
      withPlugin.runSteps(per);
      without.runSteps(per);
      double time(EngineLoop loop) {
        final watch = Stopwatch()..start();
        loop.runSteps(per);
        watch.stop();
        return watch.elapsedMicroseconds / per;
      }

      final on = <double>[];
      final off = <double>[];
      for (var i = 0; i < _batches; i++) {
        on.add(time(withPlugin));
        off.add(time(without));
      }
      double median(List<double> xs) => (xs.toList()..sort())[xs.length ~/ 2];
      final cost = median(on) - median(off);
      final shown = cost.toStringAsFixed(1);
      if (cost > micros) {
        return <PluginCheckOutcome>[
          outcome(
            'it adds $shownµs to a step (the median of $_batches batches '
            'of $per), and the budget allows $microsµs',
            passed: false,
          ),
        ];
      }
      said.add('$shownµs a step of $microsµs allowed');
    }
    return <PluginCheckOutcome>[outcome('kept: ${said.join('; ')}')];
  } on Object catch (error) {
    return <PluginCheckOutcome>[
      outcome('stepping it threw: ${_describe(error)}', passed: false),
    ];
  }
}

// ----------------------------------------------------------------- materials

/// The physical materials a plugin declares, held to what the engine's own
/// are: every one under the plugin's id, every group naming its source, a
/// liquid or a gas saying its density and viscosity, every number in SI
/// within what anything real has ([PhysicalMaterial.problems]); every pair
/// with one of the plugin's own in it and a source; and all of it gone
/// again when the plugin is switched off.
///
/// A plugin that declares none passes: it has nothing to be held to.
List<PluginCheckOutcome> _materials(PluginSession session) {
  PluginCheckOutcome outcome({required bool passed, required String says}) =>
      PluginCheckOutcome(check: 'materials', passed: passed, says: says);
  try {
    final id = session.manifest.id;
    final without = session.build(withPlugin: false).materials;
    final known = <String>{for (final m in without.materials) m.id};
    final knownPairs = <String>{for (final p in without.pairs) p.key};
    final loop = session.build();
    final declared = <PhysicalMaterial>[
      for (final m in loop.materials.materials)
        if (!known.contains(m.id)) m,
    ];
    final pairs = <MaterialPair>[
      for (final p in loop.materials.pairs)
        if (!knownPairs.contains(p.key)) p,
    ];
    if (declared.isEmpty && pairs.isEmpty) {
      return <PluginCheckOutcome>[
        outcome(passed: true, says: 'it declares no physical materials'),
      ];
    }
    final problems = <String>[
      for (final m in declared) ...materialProblemsOf(m, plugin: id),
      for (final p in pairs) ...pairProblemsOf(p, plugin: id),
    ];
    loop.plugins.disable(id);
    loop.runSteps(1);
    final left = <String>[
      for (final m in declared)
        if (loop.materials.byId(m.id) != null) m.id,
      for (final p in pairs)
        if (loop.materials.pairOf(p.first, p.second) != null) p.key,
    ];
    if (left.isNotEmpty) {
      problems.add(
        'switched off, its ${left.join(', ')} stayed in the catalogue: a '
        'material goes in through host.registry<MaterialCatalog>(), whose '
        'registrations the host takes back',
      );
    }
    return <PluginCheckOutcome>[
      outcome(
        passed: problems.isEmpty,
        says: problems.isEmpty
            ? '${declared.length} physical material'
                  '${declared.length == 1 ? '' : 's'} and ${pairs.length} '
                  'pair${pairs.length == 1 ? '' : 's'}, each under "$id.", '
                  'cited and in SI, and gone when it is switched off'
            : problems.join('. '),
      ),
    ];
  } on Object catch (error) {
    return <PluginCheckOutcome>[
      outcome(passed: false, says: 'its materials threw: ${_describe(error)}'),
    ];
  }
}

/// What is wrong with [material] as plugin [plugin]'s, one sentence each:
/// an id outside its namespace, a group with an empty source, and whatever
/// [PhysicalMaterial.problems] finds.
List<String> materialProblemsOf(
  PhysicalMaterial material, {
  required String plugin,
}) => <String>[
  if (!material.id.startsWith('$plugin.'))
    '${material.id} is not under the plugin\'s id, "$plugin.<name>"',
  for (final (name, group) in <(String, PropertyGroup?)>[
    ('mechanical', material.mechanical),
    ('fluid', material.fluid),
    ('thermal', material.thermal),
    ('acoustic', material.acoustic),
    ('optical', material.optical),
    ('electrical', material.electrical),
  ])
    if (group != null && group.source.trim().isEmpty)
      '${material.id}: its $name group names no source',
  ...material.problems(),
];

/// What is wrong with [pair] as plugin [plugin]'s: none of its own in it, no
/// source, a number out of its range.
List<String> pairProblemsOf(MaterialPair pair, {required String plugin}) {
  final what = 'the pair of ${pair.first} and ${pair.second}';
  bool outside(double? value, double low, double high) =>
      value != null && !(value >= low && value <= high);
  return <String>[
    if (!pair.first.startsWith('$plugin.') &&
        !pair.second.startsWith('$plugin.'))
      '$what has none of the plugin\'s own materials in it',
    if (pair.source.trim().isEmpty) '$what names no source',
    if (outside(pair.friction, 0.0, 5.0)) '$what: friction ${pair.friction}',
    if (outside(pair.restitution, 0.0, 1.0))
      '$what: restitution ${pair.restitution}',
    if (outside(pair.rollingResistance, 0.0, 1.0))
      '$what: rolling resistance ${pair.rollingResistance}',
    if (outside(pair.contactAngle, 0.0, 3.1416))
      '$what: contact angle ${pair.contactAngle} rad',
  ];
}
