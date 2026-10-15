/// A light type of a plugin's own in the light loop: how it is packed, and
/// the code a lit stage tells it apart by (D22).
library;

import 'dart:typed_data';
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        NameTakenException,
        PluginException,
        PluginRegistry,
        PluginScope,
        Registration;

import '../scene/light_node.dart';

/// What a [LightTypeHook] is handed for one light: the light, and the row
/// the lit stages read it from, to fill.
///
/// One object that can gain members — the view, the light's place in the
/// list — rather than a list of parameters that grows.
final class LightPackContext {
  LightPackContext._(this.light, this.row, this.code);

  /// The light being packed.
  final LightNode light;

  /// Its sixteen floats, as `lib/surface.glsl` reads a light: four `vec4`s,
  /// already filled the way the light's [LightType.base] is packed —
  ///
  /// | Floats | xyz | w |
  /// |---|---|---|
  /// | 0–3 | position, the scene's space | the type code |
  /// | 4–7 | linear colour | intensity, in the engine's unit |
  /// | 8–11 | the direction it points | range, nought for unbounded |
  /// | 12–15 | the base's cone or half-height | free |
  ///
  /// A hook rewrites what its falloff reads — the cone row, the range, a
  /// parameter in a free component. The type code (float 3) is [code]
  /// whatever the hook writes there.
  final Float32List row;

  /// The code the lit stages read this type by, in the row's float 3:
  /// [LightTypes.firstPluginCode] or above, given at registration.
  final int code;
}

/// A light type of a plugin's own, in the light loop (D22).
///
/// **How a torch that flickers by its own law, a light shaped like a tube or
/// a lamp with a measured profile becomes a light the scene draws.** The
/// plugin makes a [LightType.custom] (named in its namespace,
/// `acme_lamps.tube`, based on the built-in shape it is closest to), and
/// registers a hook for it with the renderer's [LightTypes]
/// (`host.registry<LightTypes>()`). From then on every light of that type is
/// packed by [pack], with the code the registry gave it, so:
///
/// - a lighting model of the plugin's own reads the code and the row in its
///   `light` block and computes its own falloff (`lightKind`,
///   `lightParams` — "The shader ABI" in `docs/CONTRACTS.md`);
/// - the engine's own lit stages skip a light whose code they do not know,
///   rather than drawing it as something it is not.
///
/// A [LightType.custom] with no hook registered is drawn as its base, as it
/// always was. Extendable outside this package, and stays so through 1.x.
abstract base class LightTypeHook {
  const LightTypeHook();

  /// The type this hook packs.
  LightType get type;

  /// Fills [context]'s row for one light of [type]. By default the row is
  /// left as the base packed it.
  void pack(LightPackContext context) {}
}

/// The light types of plugins' own a renderer packs, each with its code
/// (D22). Reached by a plugin as `host.registry<LightTypes>()`, beside the
/// render steps it comes with.
final class LightTypes extends PluginRegistry {
  /// A renderer's, empty.
  LightTypes() : _store = _LightTypeStore(), _scope = null;

  LightTypes._scoped(this._store, this._scope);

  final _LightTypeStore _store;
  final PluginScope? _scope;

  /// The first code a plugin's light type is given; the engine's are below
  /// it (directional nought, point one, spot two, area three) and a later
  /// minor's will be too.
  static const int firstPluginCode = 16;

  /// The hooks registered, in the order they were.
  List<LightTypeHook> get hooks => List<LightTypeHook>.unmodifiable(
    <LightTypeHook>[for (final entry in _store.entries) entry.hook],
  );

  /// The hook that packs [type], or null when none is registered.
  LightTypeHook? hookOf(LightType type) => _entryOf(type)?.hook;

  /// The code [type] is packed with: its registered code, or its base's.
  int codeOf(LightType type) =>
      _entryOf(type)?.code ??
      switch (type.base) {
        LightType.directional => 0,
        LightType.point => 1,
        LightType.spot => 2,
        _ => 3,
      };

  /// The code the light type called [name] (`acme.tube`) is packed with,
  /// or null when no hook packs one of that name: what a material's
  /// `lighttype` declaration is filled with.
  int? codeNamed(String name) {
    for (final entry in _store.entries) {
      if (entry.hook.type.name == name) return entry.code;
    }
    return null;
  }

  _LightTypeEntry? _entryOf(LightType type) {
    for (final entry in _store.entries) {
      if (identical(entry.hook.type, type)) return entry;
    }
    return null;
  }

  /// Makes [hook] pack every light of its type, with a code of its own,
  /// until the result is cancelled.
  ///
  /// Throws a [NameTakenException] for a built-in type and for a type
  /// another hook packs; through a plugin's view, a [PluginException] for a
  /// type named outside the plugin's namespace.
  Registration register(LightTypeHook hook) {
    final type = hook.type;
    if (LightType.values.contains(type)) {
      throw NameTakenException(
        type.name,
        what: 'the light type',
        owner: 'the engine',
        detail: 'a hook packs a LightType.custom of its own',
      );
    }
    final problem = _scope?.manifest.nameProblem(
      type.name,
      what: 'the light type',
    );
    if (problem != null) throw PluginException(problem);
    if (_entryOf(type) != null) {
      throw NameTakenException(
        type.name,
        what: 'the light type',
        detail: 'another hook packs it',
      );
    }
    final entry = _LightTypeEntry(hook, firstPluginCode + _store.issued++);
    _store.entries.add(entry);
    final registration = Registration(() => _store.entries.remove(entry));
    _scope?.track(registration);
    return registration;
  }

  @override
  LightTypes forPlugin(PluginScope scope) => LightTypes._scoped(_store, scope);
}

/// What the light buffers the renderer packs need from [LightTypes], and
/// nobody else. Not exported by `flutter3d_core.dart`.
extension LightTypesInternals on LightTypes {
  /// The context [light]'s hook is handed for [row], with [code].
  LightPackContext packContext(LightNode light, Float32List row, int code) =>
      LightPackContext._(light, row, code);
}

final class _LightTypeStore {
  final List<_LightTypeEntry> entries = <_LightTypeEntry>[];

  /// Codes handed out so far: never handed out twice, so a type switched off
  /// and on again does not take another's code.
  int issued = 0;
}

final class _LightTypeEntry {
  _LightTypeEntry(this.hook, this.code);

  final LightTypeHook hook;
  final int code;
}
