import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../data_event.dart';
import '../world_fields.dart';

/// What runs a level script or a mod written in Dart while the game runs.
///
/// **An interface with no implementation in this release, on purpose.**
/// Decision 4 of `tasks/0.9-plugins.md` names interpreted Dart as the third
/// kind of plugin loaded at run time, and `dart_eval` was the candidate: a
/// pure Dart interpreter, BSD-3-Clause, maintained (0.8.5, May 2026). It was
/// not adopted, for two reasons written down there. Its compiler depends on
/// `analyzer ^8`, and this workspace resolves one lock file around
/// `analyzer` 13, so it cannot be added at all without splitting the
/// workspace. And what it would ship to every player is the compiler and the
/// analyzer behind it, to run a script a build could have compiled.
///
/// So this is the seam, held to the same rules as a Wasm module, and an
/// application or a later package provides the runtime:
///
/// * a script is a step system, named `<plugin id>.<system>`, in a step
///   phase, so it is replayed and checked like any other;
/// * it reaches the world only through the [WorldFields] it declared, reads
///   and writes as declared, and publishes only the events its plugin
///   declared — see [ScriptContext];
/// * it gets no network and no files: a script's sources are read by the
///   loader, through the same doors and the same `PluginGrants` as the rest
///   of its plugin, before anything runs;
/// * its arithmetic must be `Portable`'s: a runtime that hands a script the
///   platform's `dart:math` gives it the machine's answer, and a replay on
///   another machine diverges.
///
/// An engine without a runtime refuses a plugin that brings a script, by
/// name, at install.
abstract base class ScriptRuntime extends PluginRegistry {
  const ScriptRuntime();

  /// What it is, for a sentence: `dart_eval 0.8`.
  String get name;

  /// Compiles [source]. Throws a [ScriptException] with the line that is
  /// wrong.
  ScriptProgram compile(String source, {required String from});

  /// A runtime keeps nothing per plugin: every plugin's programs are its own.
  @override
  ScriptRuntime forPlugin(PluginScope scope) => this;
}

/// One compiled script.
abstract base class ScriptProgram {
  const ScriptProgram();

  /// Runs one step.
  void step(ScriptContext context);

  /// The script's own state, as a snapshot holds it: `null`, `bool`, `num`,
  /// `String`, and lists and maps of those.
  Object? save();

  /// Puts back what [save] returned.
  void restore(Object? state);
}

/// Everything a script is handed in a step, and nothing else.
abstract base class ScriptContext {
  const ScriptContext();

  /// The step being run.
  int get step;

  /// Seconds one step covers.
  double get dt;

  /// How many values [field] holds. Throws a [ScriptException] for a field the
  /// script did not declare.
  int length(String field);

  /// The value of [field] at [index].
  double read(String field, int index);

  /// Writes [value] to [field] at [index]. Throws a [ScriptException] for a
  /// field the script did not declare writable.
  void write(String field, int index, double value);

  /// Publishes `<plugin id>.<event>` with [values]. Throws a
  /// [ScriptException] for an event the plugin did not declare.
  void publish(String event, List<int> values);
}

/// A script that cannot be compiled, or reached for what it was not given.
final class ScriptException extends PluginException {
  const ScriptException(super.message);

  @override
  String toString() => 'ScriptException: $message';
}

/// One script in a plugin, as its document declares it.
final class ScriptSystemSpec {
  const ScriptSystemSpec({
    required this.source,
    required this.system,
    required this.phase,
    this.after = const <String>[],
    this.before = const <String>[],
    this.reads = const <String>[],
    this.writes = const <String>[],
    this.events = const <String>[],
  });

  /// The script, relative to the plugin's own directory.
  final String source;

  /// The system's name; the loop has it as `<plugin id>.<system>`.
  final String system;

  /// A step phase.
  final String phase;

  final List<String> after;
  final List<String> before;

  /// World fields it reads, and those it may also write.
  final List<String> reads;
  final List<String> writes;

  /// Events it may publish, without the plugin's prefix.
  final List<String> events;

  /// Reads a declaration, or throws a [ScriptFormatException] saying why not.
  factory ScriptSystemSpec.fromJson(Map<String, Object?> json) {
    String text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => throw ScriptFormatException('a script names no "$key"'),
    };
    List<String> names(String key) => switch (json[key]) {
      null => const <String>[],
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw ScriptFormatException(
        'a script\'s "$key" is not a list of names',
      ),
    };
    return ScriptSystemSpec(
      source: text('source'),
      system: text('system'),
      phase: text('phase'),
      after: names('after'),
      before: names('before'),
      reads: names('reads'),
      writes: names('writes'),
      events: names('events'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'source': source,
    'system': system,
    'phase': phase,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
    if (reads.isNotEmpty) 'reads': reads,
    if (writes.isNotEmpty) 'writes': writes,
    if (events.isNotEmpty) 'events': events,
  };
}

/// A script installed as a step system; kept so its state can be saved.
final class ScriptSystem {
  ScriptSystem._(this.name, this._program);

  /// `<plugin id>.<system>`.
  final String name;

  final ScriptProgram _program;

  /// The program's state, for a snapshot.
  Object? save() => _program.save();

  /// Puts back what [save] returned.
  void restore(Object? state) => _program.restore(state);
}

/// Compiles [source] with the engine's [ScriptRuntime] and installs it as
/// [spec]'s step system in the plugin [host] is installing.
///
/// Throws a [PluginException] naming the plugin when the engine has no
/// runtime, when a field it declares is not among the [WorldFields], or when
/// a view plugin declares a field it writes.
ScriptSystem installScriptSystem(
  PluginHost host,
  ScriptSystemSpec spec,
  String source,
) {
  final id = host.manifest.id;
  final runtime = host.maybeRegistry<ScriptRuntime>();
  if (runtime == null) {
    throw PluginException(
      'plugin "$id" brings the script ${spec.source}, and this engine has no '
      'ScriptRuntime to run it. None ships with flutter3d 1.0 '
      '(tasks/0.9-plugins.md, step 7); hand one to the engine among its '
      'registries, or leave the script out',
    );
  }
  if (spec.writes.isNotEmpty && !host.manifest.touches.simulates) {
    throw PluginException(
      'plugin "$id" declares that it touches only the view, and its script '
      '${spec.source} writes ${spec.writes.join(', ')}',
    );
  }
  final fields = <String, WorldField>{};
  final declared = <String>[...spec.reads, ...spec.writes];
  if (declared.isNotEmpty) {
    final world = host.maybeRegistry<WorldFields>();
    for (final name in declared) {
      final field = world?[name];
      if (field == null) {
        throw PluginException(
          'plugin "$id"\'s script ${spec.source} reads the world field '
          '"$name", which ${world == null ? 'this engine has no WorldFields '
                    'to find' : 'is not among ${world.names.join(', ')}'}',
        );
      }
      fields[name] = field;
    }
  }
  final ScriptProgram program;
  try {
    program = runtime.compile(source, from: spec.source);
  } on ScriptException catch (refused) {
    throw PluginException(
      'plugin "$id"\'s script ${spec.source} does not compile under '
      '${runtime.name}: ${refused.message}',
    );
  }
  final system = ScriptSystem._('$id.${spec.system}', program);
  final context = _ScriptContext(id, spec, fields);
  host.loop.addSystem(
    system.name,
    LoopPhase.step(spec.phase),
    (loop) {
      context.loop = loop;
      program.step(context);
    },
    after: spec.after,
    before: spec.before,
  );
  return system;
}

final class _ScriptContext extends ScriptContext {
  _ScriptContext(this._plugin, this._spec, this._fields);

  final String _plugin;
  final ScriptSystemSpec _spec;
  final Map<String, WorldField> _fields;
  late LoopContext loop;

  @override
  int get step => loop.step;

  /// The loop's fixed step, in seconds.
  @override
  double get dt => loop.dt;

  WorldField _field(String name) =>
      _fields[name] ??
      (throw ScriptException(
        '${_spec.source} reached for the field "$name", which it did not '
        'declare',
      ));

  @override
  int length(String field) => _field(field).length;

  @override
  double read(String field, int index) => _field(field)[index];

  @override
  void write(String field, int index, double value) {
    if (!_spec.writes.contains(field)) {
      throw ScriptException(
        '${_spec.source} wrote the field "$field", which it declared '
        '${_spec.reads.contains(field) ? 'read-only' : 'not at all'}',
      );
    }
    _field(field)[index] = value;
  }

  @override
  void publish(String event, List<int> values) {
    if (!_spec.events.contains(event)) {
      throw ScriptException(
        '${_spec.source} published "$event", which it did not declare',
      );
    }
    loop.publish(
      PluginDataEvent('$_plugin.$event', List<int>.unmodifiable(values)),
    );
  }
}

/// A script declaration in a `.f3dplugin` that cannot be read, with the
/// sentence that says which key is wrong.
final class ScriptFormatException extends Flutter3dFormatException {
  const ScriptFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'ScriptFormatException: $message';
}
