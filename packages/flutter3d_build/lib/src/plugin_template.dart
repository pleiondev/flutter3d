/// `flutter3d create plugin`: a new plugin package, as files, for each of the
/// five kinds decision 20 of `tasks/0.9-plugins.md` names.
///
/// **Text, not a directory copied off disk.** The game templates live in the
/// editor's asset bundle because a running editor reads them; a plugin
/// template is read by `dart run flutter3d_build:create` and by the
/// plugin-author MCP server, both plain Dart processes with no bundle, so the
/// files are strings here and a test reads exactly what a person gets.
///
/// **Every file compiles against today's API and installs as it says.** The
/// library is a `Flutter3dPlugin` written the way the engine's own are, the
/// pubspec carries the `flutter3d_plugins:` marker discovery reads, and the
/// tests are two: one that installs the plugin into an `EngineLoop` and looks
/// at what it registered, and one that runs `flutter3d_conformance`'s plugin
/// suite — the suite the badge is earned on.
library;

import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show packageName;

/// What a plugin is for, which decides what its template installs.
///
/// **A final class with constant instances rather than an enum**, for the
/// reason every open kind in this repository gives (ARCHITECTURE.md §13.1):
/// a sixth kind is a minor release, and a `switch` somebody wrote against
/// five would stop compiling on it.
final class PluginKind {
  const PluginKind._(this.name, this.about, {required this.simulates});

  /// A pass of its own at a render anchor, switched like the engine's steps.
  static const PluginKind renderStep = PluginKind._(
    'render-step',
    'a full-screen pass at a render anchor, switched like a built-in step',
    simulates: false,
  );

  /// Something seen or heard when something happens, aged once a frame.
  static const PluginKind effect = PluginKind._(
    'effect',
    'something seen when an event arrives, aged once a displayed frame',
    simulates: false,
  );

  /// A step phase of its own and the rules that run in it.
  static const PluginKind genre = PluginKind._(
    'genre',
    'a step phase of its own between physics and elements, with a rule '
        'that scores and an event it publishes',
    simulates: true,
  );

  /// A field of the world, stepped in the `elements` phase.
  static const PluginKind element = PluginKind._(
    'element',
    'a field of the world stepped in the elements phase with Portable '
        'arithmetic, saved and restored with the run',
    simulates: true,
  );

  /// A tool an agent calls, published under the plugin's id.
  static const PluginKind tool = PluginKind._(
    'tool',
    'an MCP tool published under the plugin\'s id',
    simulates: false,
  );

  /// The five, in the order `--list` prints them.
  static const List<PluginKind> values = <PluginKind>[
    renderStep,
    effect,
    genre,
    element,
    tool,
  ];

  /// The kind called [name], as `--kind` and `plugin.create` spell it.
  ///
  /// Throws an [ArgumentError] naming all five for any other word.
  static PluginKind named(String name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    throw ArgumentError.value(
      name,
      'kind',
      'a plugin is one of ${values.map((PluginKind k) => k.name).join(', ')}',
    );
  }

  /// The word on the command line: `render-step`, `effect`, `genre`,
  /// `element`, `tool`.
  final String name;

  /// One line, for `--list` and a tool's description.
  final String about;

  /// Whether the plugin's manifest says it touches the simulation. A view
  /// plugin is refused anything in the step, so this decides which template
  /// gets the `flutter3d_lints` analyzer plugin as well.
  final bool simulates;

  @override
  String toString() => name;
}

/// The files of a new plugin package called [name], of [kind], by the path
/// each is written to.
///
/// [name] is made a pub package name the way the editor's wizard makes one
/// ([packageName]): lower case, words joined by underscores. The plugin's id
/// is the package's name, which is what its tools and events are filed
/// under, and its class is the name in Pascal case with `Plugin` after it.
Map<String, String> pluginTemplate({
  required String name,
  required PluginKind kind,
}) {
  final package = packageName(name);
  final pascal = _pascal(package);
  final words = <String, String>{
    'name': package,
    'pascal': pascal,
    'class': '${pascal}Plugin',
    'camel': '${pascal[0].toLowerCase()}${pascal.substring(1)}',
    'kind': kind.name,
    'about': kind.about,
    // What the conformance harness casts a captured state back to.
    'state': kind == PluginKind.element
        ? 'List<Object?>'
        : 'Map<String, Object?>',
  };
  String fill(String text) => text.replaceAllMapped(
    RegExp(r'\{\{(\w+)\}\}'),
    (Match m) => words[m[1]] ?? m[0]!,
  );
  final (library, unitTest, conformanceTest) = switch (kind) {
    PluginKind.renderStep => (_renderLib, _renderTest, _renderConformance),
    PluginKind.effect => (_effectLib, _effectTest, _plainConformance),
    PluginKind.genre => (_genreLib, _genreTest, _stateConformance),
    PluginKind.element => (_elementLib, _elementTest, _stateConformance),
    _ => (_toolLib, _toolTest, _toolConformance),
  };
  return <String, String>{
    'pubspec.yaml': fill(_pubspec(kind)),
    'analysis_options.yaml': fill(
      kind.simulates ? _analysisOptionsSimulation : _analysisOptions,
    ),
    'lib/$package.dart': fill(library),
    'test/${package}_test.dart': fill(unitTest),
    'test/conformance_test.dart': fill(conformanceTest),
    'README.md': fill(_readme),
    'CHANGELOG.md': fill(_changelog),
    '.gitignore': _gitignore,
  };
}

/// `my_glow` as `MyGlow`.
String _pascal(String package) => package
    .split('_')
    .where((String part) => part.isNotEmpty)
    .map((String part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join();

String _pubspec(PluginKind kind) {
  final dependencies = <String>[
    '  flutter3d_plugin_api: ^1.0.0-rc.1',
    if (kind == PluginKind.renderStep || kind == PluginKind.effect)
      '  flutter3d_core: ^1.0.0-rc.1',
    if (kind == PluginKind.renderStep) '  flutter3d_hardware: ^1.0.0-rc.1',
    if (kind == PluginKind.element) '  flutter3d_foundation: ^1.0.0-rc.1',
    if (kind.simulates) '  flutter3d_sim: ^1.0.0-rc.1',
    if (kind == PluginKind.tool) '  flutter3d_mcp: ^1.0.0-rc.1',
  ];
  final devDependencies = <String>[
    '  flutter3d_conformance: ^1.0.0-rc.1',
    if (!kind.simulates) '  flutter3d_sim: ^1.0.0-rc.1',
    '  test: ^1.25.0',
  ];
  return '''
name: {{name}}
description: "A flutter3d plugin: {{about}}."
version: 0.1.0
# The topic the plugin catalogue on flutter3d.pleion.dev is read by.
topics:
  - flutter3d-plugin

environment:
  sdk: ">=3.12.0 <4.0.0"

dependencies:
${dependencies.join('\n')}

dev_dependencies:
${devDependencies.join('\n')}

# What `flutter3d_build`'s discovery reads: an application that depends on
# this package gets {{class}} in its `lib/plugins.g.dart`.
flutter3d_plugins:
  plugin: package:{{name}}/{{name}}.dart#{{class}}
''';
}

const String _analysisOptions = '''
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
''';

const String _analysisOptionsSimulation = '''
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true

# The determinism rules for code that runs inside a fixed step: no wall
# clock, no unseeded Random, Portable rather than dart:math's
# transcendentals. An analysis server plugin, resolved by the analysis server
# on its own, so it is not a dependency of this package.
plugins:
  flutter3d_lints: ^1.0.0-rc.1
''';

const String _readme = '''
# {{name}}

A flutter3d plugin ({{kind}}): {{about}}.

## Using it

An application that depends on this package finds the plugin through
discovery: `flutter3d_build` writes `lib/plugins.g.dart` from the
`flutter3d_plugins:` marker in this package's pubspec, and the application
hands `installedPlugins` to its `EngineLoop`. A list written in code works as
well:

```dart
EngineLoop(input: input, plugins: [{{class}}()]);
```

## Conformance

```bash
dart test test/conformance_test.dart
```

runs `flutter3d_conformance`'s plugin suite: the manifest, switching on and
off at a step boundary, determinism (every step run twice from a snapshot),
every backend the manifest declares, and the budget in the manifest's
`extra`. A plugin earns the conformance badge when every check passes on every
declared backend, with a world given to the determinism check and a budget
declared and kept — `flutter3d_conformance`'s README says it in full.

## Publishing

The pubspec's `flutter3d-plugin` topic is what the plugin catalogue on the
flutter3d site is read by. Keep it, and the catalogue lists the package after
its next build.
''';

const String _changelog = '''
## 0.1.0

- **The first release.** Created by `flutter3d create plugin --kind {{kind}}`.
''';

const String _gitignore = '''
.dart_tool/
build/
pubspec.lock
''';

// ------------------------------------------------------------- render step

const String _renderLib = r'''
/// {{name}}: a render step of its own, drawn over the scene's light after
/// bloom and before tone mapping.
///
/// Installed, it adds the step `{{name}}` to the renderer and places one
/// full-screen pass at `RenderAnchor.afterBloom`. `RenderSettings.without`
/// switches it off like a built-in step, and switching bloom off takes it
/// down too, because it needs bloom.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The step, as the renderer reports it in `FrameResult.skipped`.
const RenderStep {{camel}}Step = RenderStep(
  '{{name}}',
  needs: <RenderStep>{RenderStep.bloom},
);

/// The plugin: a view plugin, so switching it changes nothing a replay
/// checks.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'A full-screen pass after bloom.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<RendererSteps>()
      ..addStep({{camel}}Step)
      ..addNode(
        {{pascal}}Pass(),
        at: RenderAnchor.afterBloom,
        step: {{camel}}Step,
      );
  }
}

/// The pass: the fragment stage named `{{name}}`, drawn over the scene's
/// light.
///
/// The stage comes from the application's shader bundle, found by name on
/// the device the frame is drawn with. Until the bundle has one, the pass
/// leaves the picture as it found it.
final class {{pascal}}Pass extends RenderNode {
  {{pascal}}Pass();

  FullscreenEffect? _effect;

  @override
  String get name => '{{name}}';

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) {
    final effect = _effect ??= switch (frame.device.shaders['{{name}}']) {
      null => null,
      final ShaderHandle shader => FullscreenEffect.overlay(
        name: '{{name}}',
        shader: shader,
      ),
    };
    effect?.execute(frame);
  }
}
''';

const String _renderTest = r'''
/// {{name}} installs its step and its pass, and takes both out again.
library;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the step is the renderer\'s while the plugin is on', () {
    final renderer = Renderer.create(device: FakeBackend());
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[renderer.renderSteps],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    expect(renderer.renderSteps.added, contains({{camel}}Step));

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(renderer.renderSteps.added, isNot(contains({{camel}}Step)));
  });
}
''';

const String _renderConformance = r'''
/// flutter3d_conformance's plugin suite, over a renderer drawn with the
/// hardware layer's fake device: the step and the pass need a renderer to be
/// added to, and the fake needs no GPU.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[
        Renderer.create(device: FakeBackend()).renderSteps,
      ],
    ),
  );
}
''';

// ------------------------------------------------------------------ effect

const String _effectLib = r'''
/// {{name}}: something seen when an event arrives, aged once a displayed
/// frame.
///
/// A view plugin. It hears the frame channel — each event once, and a step
/// run again on a rollback is not heard twice — and ages what it spawned in
/// the `animate` phase. It never touches the step, so switching it on or off
/// changes nothing a replay checks.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The plugin. [watches] is the end of the event names it answers.
final class {{class}} extends Flutter3dPlugin {
  {{class}}({this.watches = 'landed', this.lifetime = 0.6});

  /// An event whose name ends with this spawns a puff: `landed` answers
  /// `runner.landed` and `crate.landed`.
  final String watches;

  /// How long a puff lasts, in seconds of the game's time.
  final double lifetime;

  final List<double> _ages = <double>[];

  /// How many puffs are alive: what a renderer draws.
  int get alive => _ages.length;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'A puff for every event it watches.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.events.onFrame<BusEvent>('{{name}}.spawn', (
      Delivered<BusEvent> heard,
    ) {
      if (heard.event.name.endsWith(watches)) _ages.add(0.0);
    });
    host.loop.addSystem('{{name}}.age', LoopPhase.animate, (
      LoopContext frame,
    ) {
      // The game's time, not the wall clock's: a paused game's puffs wait.
      for (var i = 0; i < _ages.length; i++) {
        _ages[i] += frame.dt;
      }
      _ages.removeWhere((double age) => age >= lifetime);
    });
  }

  @override
  void uninstall(PluginHost host) => _ages.clear();
}
''';

const String _effectTest = r'''
/// {{name}} spawns a puff for the event it watches and lets it go.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

final class _Landed extends BusEvent {
  const _Landed();

  @override
  String get name => 'test.landed';
}

void main() {
  test('a watched event spawns a puff, which lasts its lifetime', () {
    final plugin = {{class}}();
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    loop.events.publishFrame(const _Landed());
    loop.frame(1.0 / 60.0);
    expect(plugin.alive, 1);

    for (var i = 0; i < 3; i++) {
      loop.frame(0.25);
    }
    expect(plugin.alive, 0);
  });
}
''';

const String _plainConformance = r'''
/// flutter3d_conformance's plugin suite. A view plugin keeps nothing a step
/// reads, so the determinism check is given no world of its own.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance({{class}}.new);
}
''';

// ------------------------------------------------------------------- genre

const String _genreLib = r'''
/// {{name}}: a genre's rules, in a step phase of their own.
///
/// The phase sits after the bodies have moved and before the world's fields
/// (`physics` < `{{name}}.rules` < `elements`). Its one rule scores a point
/// every [{{class}}.pointsEvery] steps and publishes [{{pascal}}Scored] on
/// the step channel, so a replay digests it and a sound or a counter hears it
/// on the frame channel once.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// A point scored, with the score it made.
final class {{pascal}}Scored extends BusEvent {
  const {{pascal}}Scored(this.score);

  final int score;

  /// How it is written: the score. A step event is declared with its codec,
  /// so a replay digests what it carries and the view reads it encoded.
  static final EventCodec<{{pascal}}Scored> codec =
      EventCodec<{{pascal}}Scored>.of(
        encode: (event) => event.score,
        decode: (data, _) => data is int ? {{pascal}}Scored(data) : null,
      );

  @override
  String get name => '{{name}}.scored';
}

/// The genre's rules phase.
const LoopPhase {{camel}}Rules = LoopPhase.step('{{name}}.rules');

/// The plugin. It touches the simulation: its switch is journalled, and a
/// replay makes it at the same step.
final class {{class}} extends Flutter3dPlugin {
  {{class}}({this.pointsEvery = 60});

  /// Steps between two points.
  final int pointsEvery;

  int _score = 0;

  /// The score so far.
  int get score => _score;

  /// The state a snapshot keeps.
  Map<String, Object?> save() => <String, Object?>{'score': _score};

  /// Puts back what [save] wrote.
  void restore(Map<String, Object?> state) =>
      _score = (state['score'] as num?)?.toInt() ?? 0;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.simulation,
    description: 'A rules phase that scores.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 500, 'eventsPerStep': 8},
    },
  );

  @override
  void install(PluginHost host) {
    host.loop.addPhase(
      {{camel}}Rules,
      after: const <String>['physics'],
      before: const <String>['fields'],
    );
    host.events.declare<{{pascal}}Scored>(
      '{{name}}.scored',
      description: 'A point scored, with the score it made.',
      codec: {{pascal}}Scored.codec,
    );
    host.loop.addSystem('{{name}}.score', {{camel}}Rules, (
      LoopContext step,
    ) {
      if (step.step % pointsEvery != 0) return;
      _score += 1;
      step.publish({{pascal}}Scored(_score));
    });
  }
}
''';

const String _genreTest = r'''
/// {{name}}'s phase sits where it says, and its rule scores on the step.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the rules phase is between physics and fields', () {
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[{{class}}()],
    );
    final phases = loop
        .phases(PhaseKind.step)
        .map((LoopPhase p) => p.name)
        .toList();
    expect(phases.indexOf('{{name}}.rules'), phases.indexOf('physics') + 1);
    expect(phases.indexOf('fields'), phases.indexOf('{{name}}.rules') + 1);
  });

  test('a point every pointsEvery steps, each heard on the step channel', () {
    final plugin = {{class}}(pointsEvery: 60);
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    final heard = <int>[];
    loop.events.onStep<{{pascal}}Scored>(
      'test',
      (Delivered<{{pascal}}Scored> scored) => heard.add(scored.event.score),
    );
    loop.runSteps(120);
    expect(plugin.score, 2);
    expect(heard, <int>[1, 2]);
  });
}
''';

const String _stateConformance = r'''
/// flutter3d_conformance's plugin suite, with the plugin's own state as the
/// world: a part of the loop's snapshots, which the determinism check steps
/// each step twice from.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SnapshotPart;
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop;
import 'package:{{name}}/{{name}}.dart';

void main() {
  // The plugin the suite made last, whose state the part reads.
  late {{class}} plugin;
  runPluginConformance(
    () => plugin = {{class}}(),
    harness: PluginHarness(
      setUp: (EngineLoop loop) => loop.snapshots.add(
        SnapshotPart.of(
          id: '{{name}}.state',
          capture: () => plugin.save(),
          restore: (Object? state, int _) =>
              plugin.restore(state! as {{state}}),
        ),
      ),
    ),
  );
}
''';

// ----------------------------------------------------------------- element

const String _elementLib = r'''
/// {{name}}: a field of the world, stepped in the `elements` phase.
///
/// One value per cell, decaying towards nought with a half-life. The
/// arithmetic is `Portable`'s, never `dart:math`'s: a transcendental from the
/// platform's library gives different bits on the VM and in a browser, and a
/// replay checked on a server would part from the player's run.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart' show Portable;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The plugin. It touches the simulation, and [save] and [restore] put its
/// field in a run's snapshot.
final class {{class}} extends Flutter3dPlugin {
  {{class}}({int cells = 64, this.halfLife = 2.0})
    : values = Float64List(cells);

  static const double _ln2 = 0.6931471805599453;

  /// The field: one value per cell, written by whoever adds to it.
  final Float64List values;

  /// Seconds for a value to fall to half.
  final double halfLife;

  /// The state a snapshot keeps.
  List<double> save() => List<double>.of(values);

  /// Puts back what [save] wrote.
  void restore(List<Object?> state) {
    for (var i = 0; i < values.length && i < state.length; i++) {
      values[i] = (state[i]! as num).toDouble();
    }
  }

  @override
  PluginManifest get manifest => const PluginManifest(
    id: '{{name}}',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.simulation,
    description: 'A field that decays with a half-life.',
    extra: <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 500, 'eventsPerStep': 8},
    },
  );

  @override
  void install(PluginHost host) {
    host.loop.addSystem('{{name}}.decay', LoopPhase.fields, (
      LoopContext step,
    ) {
      final keep = Portable.exp(-step.dt * _ln2 / halfLife);
      for (var i = 0; i < values.length; i++) {
        values[i] *= keep;
      }
    });
  }
}
''';

const String _elementTest = r'''
/// {{name}}'s field halves in its half-life, stepped at the world's rate.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('a value halves in one half-life', () {
    final plugin = {{class}}(halfLife: 2.0);
    final loop = EngineLoop(
      input: InputState(),
      plugins: <Flutter3dPlugin>[plugin],
    );
    plugin.values[0] = 1.0;
    loop.runSteps((2.0 / loop.stepSeconds).round());
    expect(plugin.values[0], closeTo(0.5, 1e-9));
  });

  test('restore puts back what save wrote', () {
    final plugin = {{class}}()..values[3] = 4.0;
    final saved = plugin.save();
    plugin.values[3] = 0.0;
    plugin.restore(saved);
    expect(plugin.values[3], 4.0);
  });
}
''';

// -------------------------------------------------------------------- tool

const String _toolLib = r'''
/// {{name}}: a tool an agent calls, published as `{{name}}.hello`.
///
/// Every MCP server of the project offers it beside its own tools, and
/// switching the plugin off takes it out of the list; the server tells its
/// client the list changed.
library;

import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// The plugin: a view plugin, since a tool runs between frames, not in a
/// step.
final class {{class}} extends Flutter3dPlugin {
  const {{class}}();

  @override
  PluginManifest get manifest => PluginManifest(
    id: '{{name}}',
    apiVersion: const PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    permissions: <PluginPermission>{PluginPermission.tools},
    description: 'A tool that answers.',
    extra: const <String, Object?>{
      'budget': <String, Object?>{'stepMicroseconds': 250, 'eventsPerStep': 0},
    },
  );

  @override
  void install(PluginHost host) {
    host.registry<McpTools>()
      ..declareSchemaVersion('1.0.0')
      ..addTool(
        ToolSpec(
          name: 'hello',
          description: 'Says hello back, to show the tool is there.',
          inputSchema: const <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'who': <String, Object?>{
                'type': 'string',
                'description': 'Who to greet.',
              },
            },
          },
          hints: ToolHints.reads,
        ),
        (Map<String, Object?> arguments) =>
            ToolResult.text('hello, ${arguments['who'] ?? 'agent'}'),
      );
  }
}
''';

const String _toolTest = r'''
/// {{name}}'s tool is published under the plugin's id and answers.
library;

import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:{{name}}/{{name}}.dart';
import 'package:test/test.dart';

void main() {
  test('the tool is {{name}}.hello while the plugin is on', () async {
    final tools = McpTools();
    final loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[tools],
      plugins: const <Flutter3dPlugin>[{{class}}()],
    );
    final hello = tools.named('{{name}}.hello');
    expect(hello, isNotNull);
    final result = await hello!.run(<String, Object?>{'who': 'test'});
    expect(result.text, 'hello, test');

    loop.plugins.disable('{{name}}');
    loop.runSteps(1);
    expect(tools.named('{{name}}.hello'), isNull);
  });
}
''';

const String _toolConformance = r'''
/// flutter3d_conformance's plugin suite, with a project's tool registry for
/// the tool to be published in.
library;

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_mcp/kit.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry;
import 'package:{{name}}/{{name}}.dart';

void main() {
  runPluginConformance(
    () => const {{class}}(),
    harness: PluginHarness(
      registries: (String? backend) => <PluginRegistry>[McpTools()],
    ),
  );
}
''';
