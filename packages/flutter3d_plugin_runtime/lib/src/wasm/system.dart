import 'dart:typed_data';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

import '../data_event.dart';
import '../world_fields.dart';
import 'abi.dart';
import 'module.dart';

/// One world field a Wasm system names: by name, read-only unless it says it
/// writes, with the unit its numbers are in and the precision they cross
/// into the module at.
///
/// **The scale is declared, because Q16.16 holds ±32 768.** That is enough
/// for a temperature or a depth and not for a world position: a body a few
/// kilometres from the origin is off the end. A field declares
/// [fractionBits] — 16 by default, Q16.16 as ABI 1 always used — and fewer
/// widen the range: 8 holds ±8 388 608 m at 4 mm. Values cross as
/// `round(value × 2^fractionBits)` in a 32-bit integer, exact on every
/// platform. A field declared with anything but 16 needs a module written
/// for ABI 2, which can ask `f3d.field_frac` what it was given; an ABI-1
/// module assumes 16 and is refused such a field at install.
final class WasmFieldSpec {
  const WasmFieldSpec(
    this.name, {
    this.writable = false,
    this.unit,
    this.fractionBits = defaultFractionBits,
  }) : assert(
         fractionBits >= 0 && fractionBits <= 30,
         'a field crosses with 0 to 30 fraction bits',
       );

  /// What a field crosses at when its declaration does not say: Q16.16.
  static const int defaultFractionBits = 16;

  /// Reads `"heat"` or `{"name": "x", "write": true, "unit": "m",
  /// "fraction": 8}`.
  factory WasmFieldSpec.fromJson(Object? json) => switch (json) {
    final String name => WasmFieldSpec(name),
    final Map<String, Object?> map => WasmFieldSpec(
      switch (map['name']) {
        final String name => name,
        _ => throw const WasmFormatException('a field names no "name"'),
      },
      writable: switch (map['write']) {
        null || false => false,
        true => true,
        _ => throw const WasmFormatException('"write" is not true or false'),
      },
      unit: switch (map['unit']) {
        null => null,
        final String unit when unit.isNotEmpty => unit,
        _ => throw const WasmFormatException(
          '"unit" is a name, such as "m" or "K"',
        ),
      },
      fractionBits: switch (map['fraction']) {
        null => defaultFractionBits,
        final int bits when bits >= 0 && bits <= 30 => bits,
        final other => throw WasmFormatException(
          '"fraction" is a whole number of bits from 0 to 30, not $other',
        ),
      },
    ),
    _ => throw const WasmFormatException(
      'a field is a name or {"name", "write", "unit", "fraction"}',
    ),
  };

  /// The [WorldField]'s name.
  final String name;

  /// Whether the module may call `field_set` on it.
  final bool writable;

  /// The unit the field's numbers are in — `m`, `K`, `m/s` — as
  /// `docs/CONTRACTS.md` names them, or null when the declaration does not
  /// say. Read by people and tools; the host converts nothing by it.
  final String? unit;

  /// How many fraction bits a value crosses with: 16 is Q16.16.
  final int fractionBits;

  Object toJson() =>
      !writable && unit == null && fractionBits == defaultFractionBits
      ? <String, Object?>{'name': name}
      : <String, Object?>{
          'name': name,
          if (writable) 'write': true,
          if (unit != null) 'unit': unit,
          if (fractionBits != defaultFractionBits) 'fraction': fractionBits,
        };
}

/// What a Wasm system is: the module, where it runs, the fields and events
/// it uses by index, and its limits.
///
/// **The indices are the ABI.** A module calls `field_get(0, i)` for the
/// first entry of [fields] and `publish(1, a, b)` for the second of
/// [events]; the names live here, in the declaration a person reads, and
/// never inside the module.
final class WasmSystemSpec {
  const WasmSystemSpec({
    required this.module,
    required this.system,
    required this.phase,
    this.after = const <String>[],
    this.before = const <String>[],
    this.fields = const <WasmFieldSpec>[],
    this.events = const <String>[],
    this.limits = const WasmLimits(),
  });

  /// Reads the keys [toJson] writes. Throws a [WasmFormatException] saying which
  /// key is wrong.
  factory WasmSystemSpec.fromJson(Map<String, Object?> json) {
    String text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => throw WasmFormatException('a Wasm system names no "$key"'),
    };
    List<String> names(String key) => switch (json[key]) {
      null => const <String>[],
      final List<Object?> list when list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw WasmFormatException('"$key" is not a list of names'),
    };
    final fields = json['fields'];
    final limits = json['limits'];
    return WasmSystemSpec(
      module: text('module'),
      system: text('system'),
      phase: text('phase'),
      after: names('after'),
      before: names('before'),
      fields: switch (fields) {
        null => const <WasmFieldSpec>[],
        final List<Object?> list => List<WasmFieldSpec>.unmodifiable(
          list.map(WasmFieldSpec.fromJson),
        ),
        _ => throw WasmFormatException('"fields" is not a list'),
      },
      events: names('events'),
      limits: switch (limits) {
        null => const WasmLimits(),
        final Map<String, Object?> map => WasmLimits.fromJson(map),
        _ => throw WasmFormatException('"limits" is not an object'),
      },
    );
  }

  /// The `.wasm`, relative to the plugin's own directory.
  final String module;

  /// The system's name; the loop knows it as `<plugin id>.<system>`.
  final String system;

  /// The step phase it runs in: the engine's or one the plugin added.
  final String phase;

  /// Systems it runs after and before, as `addSystem` takes them.
  final List<String> after;
  final List<String> before;

  /// The fields it reaches, by ABI index.
  final List<WasmFieldSpec> fields;

  /// The events it publishes, by ABI index; each goes out as
  /// `<plugin id>.<event>`.
  final List<String> events;

  final WasmLimits limits;

  Map<String, Object?> toJson() => <String, Object?>{
    'module': module,
    'system': system,
    'phase': phase,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
    if (fields.isNotEmpty)
      'fields': <Object>[for (final field in fields) field.toJson()],
    if (events.isNotEmpty) 'events': events,
    'limits': limits.toJson(),
  };
}

/// Published once, on the step channel, when a Wasm system traps.
///
/// **The trap is the run's, not the machine's.** Fuel is counted, not timed,
/// so a module that runs out does so at the same instruction in every replay
/// and this event lands at the same step in each.
final class WasmTrapped extends BusEvent {
  const WasmTrapped({
    required this.plugin,
    required this.system,
    required this.step,
    required this.message,
  });

  /// The plugin's id.
  final String plugin;

  /// The system's name in the loop.
  final String system;

  final int step;

  /// What the module did.
  final String message;

  /// The name it is published and declared under.
  static const String eventName = 'wasm.trapped';

  /// How it is written: the plugin, the system, the step and the message.
  static final EventCodec<WasmTrapped> codec = EventCodec<WasmTrapped>.of(
    encode: (event) => <Object?>[
      event.plugin,
      event.system,
      event.step,
      event.message,
    ],
    decode: (data, _) => switch (data) {
      [
        final String plugin,
        final String system,
        final int step,
        final String message,
      ] =>
        WasmTrapped(
          plugin: plugin,
          system: system,
          step: step,
          message: message,
        ),
      _ => null,
    },
  );

  @override
  String get name => eventName;

  @override
  void digestInto(EventDigestSink sink) => sink
    ..add(plugin)
    ..add(system)
    ..add(step);
}

/// One Wasm module stepped as a system of the loop.
///
/// **A trap switches the module off, and the switch is state.** After a trap
/// the module is not called again, and [WasmTrapped] says so on the bus. The
/// latch is in [save], so a rollback to before the trap starts the module
/// again from the state it had then, and a replay traps at the same step.
final class WasmSystem {
  WasmSystem._(this.name, this._plugin, this._spec, this._fields);

  /// The system's name in the loop: `<plugin id>.<system>`.
  final String name;

  final String _plugin;
  final WasmSystemSpec _spec;
  final List<WorldField> _fields;
  late final WasmInstance _instance;
  LoopContext? _context;
  String? _trapped;

  /// What the module did when it trapped, or null while it runs.
  String? get trapped => _trapped;

  /// The module's memory and globals, and whether it has trapped — what a
  /// snapshot of the run keeps of this system.
  Map<String, Object?> save() => <String, Object?>{
    'trapped': _trapped,
    'module': _instance.save(),
  };

  /// Puts back what [save] wrote.
  void restore(Map<String, Object?> state) {
    final module = state['module'];
    final trapped = state['trapped'];
    if (module is! Map<String, Object?> ||
        (trapped != null && trapped is! String)) {
      throw const WasmFormatException('not the state of a Wasm system');
    }
    _instance.restore(module);
    _trapped = trapped as String?;
  }

  void _run(LoopContext context) {
    if (_trapped != null) return;
    _context = context;
    try {
      _instance.step(context.step, Fixed16.fromDouble(context.dt));
    } on WasmTrapException catch (trap) {
      _trapped = trap.message;
      context.publish(
        WasmTrapped(
          plugin: _plugin,
          system: name,
          step: context.step,
          message: trap.message,
        ),
      );
    } finally {
      _context = null;
    }
  }

  WorldField _field(int index) {
    if (index < 0 || index >= _fields.length) {
      throw WasmTrapException(
        'the module asked for field $index and declares ${_fields.length}',
      );
    }
    return _fields[index];
  }

  int _at(WorldField field, int index) {
    if (index < 0 || index >= field.length) {
      throw WasmTrapException(
        'the module reached ${field.name}[$index], which holds '
        '${field.length}',
      );
    }
    return index;
  }
}

final class _Imports extends WasmImports {
  const _Imports(this._system);

  final WasmSystem _system;

  @override
  int fieldLength(int field) => _system._field(field).length;

  @override
  int fieldGet(int field, int index) {
    final f = _system._field(field);
    return FixedPoint.fromDouble(
      f[_system._at(f, index)],
      fractionBits: _system._spec.fields[field].fractionBits,
    );
  }

  @override
  int fieldFractionBits(int field) {
    _system._field(field);
    return _system._spec.fields[field].fractionBits;
  }

  @override
  void fieldSet(int field, int index, int value) {
    final f = _system._field(field);
    if (!_system._spec.fields[field].writable) {
      throw WasmTrapException(
        'the module wrote ${f.name}, which its declaration reads only',
      );
    }
    f[_system._at(f, index)] = FixedPoint.toDouble(
      value,
      fractionBits: _system._spec.fields[field].fractionBits,
    );
  }

  @override
  void publish(int event, int a, int b) {
    final events = _system._spec.events;
    if (event < 0 || event >= events.length) {
      throw WasmTrapException(
        'the module published event $event and declares ${events.length}',
      );
    }
    final context = _system._context;
    if (context == null) {
      throw const WasmTrapException('the module published outside a step');
    }
    context.publish(
      PluginDataEvent('${_system._plugin}.${events[event]}', <int>[a, b]),
    );
  }
}

/// Installs one Wasm system into the plugin being installed through [host].
///
/// **Checked before anything is added.** Every field [spec] names must be in
/// the engine's [WorldFields], and a field it writes is refused to a plugin
/// that declares it touches only the view — each with a [PluginException]
/// naming the field and the plugin. The module is instantiated here, so a
/// plugin switched off and on again starts its module from the beginning,
/// as any plugin's `install` starts it.
WasmSystem installWasmSystem(
  PluginHost host,
  WasmSystemSpec spec,
  WasmModule module, {
  WasmRuntime runtime = WasmRuntime.interpreter,
}) {
  final manifest = host.manifest;
  final id = manifest.id;
  if (!host.events.declared.any((d) => d.name == WasmTrapped.eventName)) {
    host.events.declare<WasmTrapped>(
      WasmTrapped.eventName,
      description: 'A Wasm system trapped and was switched off.',
      codec: WasmTrapped.codec,
    );
  }
  final fields = <WorldField>[];
  if (spec.fields.isNotEmpty) {
    final registry = host.maybeRegistry<WorldFields>();
    if (registry == null) {
      throw PluginException(
        'plugin "$id" runs a Wasm system over the world field '
        '"${spec.fields.first.name}", and this engine has no WorldFields; '
        'hand the engine one with the fields it may reach',
      );
    }
    for (final declared in spec.fields) {
      final field = registry[declared.name];
      if (field == null) {
        final known = registry.names;
        throw PluginException(
          'plugin "$id" runs a Wasm system over the world field '
          '"${declared.name}", which this engine does not have '
          '(${known.isEmpty ? 'it has none' : 'it has ${known.join(', ')}'})',
        );
      }
      if (declared.writable && !manifest.touches.simulates) {
        throw PluginException(
          'plugin "$id" declares that it touches only the view, and its Wasm '
          'system writes the world field "${declared.name}". Declare touches: '
          'simulation, or read it only',
        );
      }
      fields.add(field);
    }
  }
  final system = WasmSystem._('$id.${spec.system}', id, spec, fields);
  system._instance = runtime.instantiate(module, _Imports(system), spec.limits);
  final wide = spec.fields
      .where(
        (WasmFieldSpec f) =>
            f.fractionBits != WasmFieldSpec.defaultFractionBits,
      )
      .firstOrNull;
  if (wide != null && system._instance.abi < 2) {
    throw WasmException(
      'plugin "$id" declares the world field "${wide.name}" with '
      '${wide.fractionBits} fraction bits, and its module was written for '
      'ABI ${system._instance.abi}, which reads every field as Q16.16; '
      'build the module for ABI 2 and ask f3d.field_frac, or declare the '
      'field with 16',
    );
  }
  host.loop.addSystem(
    system.name,
    LoopPhase.step(spec.phase),
    system._run,
    after: spec.after,
    before: spec.before,
  );
  return system;
}

/// A plugin that is one Wasm system, for code that loads a module without a
/// `.f3dplugin` document around it.
///
/// The module is decoded here, so bytes that are not ABI 1 are refused with
/// [WasmException] before the plugin reaches an engine. `install` declares
/// each event as `<id>.<event>` and installs the system.
final class WasmPlugin extends Flutter3dPlugin {
  WasmPlugin({
    required this.manifest,
    required this.spec,
    required Uint8List bytes,
    this.runtime = WasmRuntime.interpreter,
  }) : module = WasmModule.decode(bytes);

  @override
  final PluginManifest manifest;

  final WasmSystemSpec spec;

  /// The decoded module.
  final WasmModule module;

  final WasmRuntime runtime;

  WasmSystem? _system;

  /// The installed system — what a snapshot saves and restores — or null
  /// while the plugin is off.
  WasmSystem? get system => _system;

  @override
  void install(PluginHost host) {
    for (final event in spec.events) {
      host.events.declare<PluginDataEvent>(
        '${manifest.id}.$event',
        codec: PluginDataEvent.codecFor('${manifest.id}.$event'),
      );
    }
    _system = installWasmSystem(host, spec, module, runtime: runtime);
  }

  @override
  void uninstall(PluginHost host) => _system = null;
}
