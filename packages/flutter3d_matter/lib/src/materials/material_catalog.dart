/// The materials an engine knows, by id: the engine's own and its plugins'.
library;

import 'dart:math' as math;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show PluginException, Registration;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginRegistry, PluginScope;

import 'material_json.dart';
import 'materials.dart';
import 'physical_material.dart';

/// How two materials meet when the catalogue holds a measurement of the pair
/// itself, in place of [MaterialCatalog.contact]'s rule.
///
/// Friction, bounce and wetting belong to a pair — rubber on dry concrete,
/// water on clean glass — and a material's own numbers are only it against
/// itself. A pair is unordered: rubber on concrete is concrete on rubber.
final class MaterialPair {
  const MaterialPair(
    this.first,
    this.second, {
    this.friction,
    this.restitution,
    this.rollingResistance,
    this.contactAngle,
    required this.source,
  });

  /// The two materials' ids.
  final String first, second;

  /// The coefficient of friction between them: the one μ the engine's
  /// solvers use (see `MechanicalProperties.friction`). No unit; null to
  /// combine the two materials' own.
  final double? friction;

  /// The coefficient of restitution between them. No unit, nought to one;
  /// null to combine the two materials' own.
  final double? restitution;

  /// The coefficient of rolling resistance of one rolling on the other. No
  /// unit; null to combine the two materials' own.
  final double? rollingResistance;

  /// For a liquid on a solid, the angle its surface meets the solid at,
  /// through the liquid, radians: nought wets completely, past a quarter
  /// turn does not wet. Null when not known.
  final double? contactAngle;

  /// Where the numbers come from.
  final String source;

  /// The pair's key, the same either way round.
  String get key => keyOf(first, second);

  /// The key of the pair of [a] and [b], either way round.
  static String keyOf(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  /// Whether [id] is one of the two.
  bool involves(String id) => first == id || second == id;

  /// The pair as JSON: `first`, `second`, the numbers it says, `source` —
  /// what a data plugin's `materialPairs` list holds.
  Map<String, Object?> toJson() => <String, Object?>{
    'first': first,
    'second': second,
    'friction': ?friction,
    'restitution': ?restitution,
    'rollingResistance': ?rollingResistance,
    'contactAngle': ?contactAngle,
    'source': source,
  };

  /// The pair [json] describes. Throws a [MaterialFormatException] for a
  /// side that is not a material's id, a number that is not one, or no
  /// source; [problems] judges whether the numbers are plausible.
  factory MaterialPair.fromJson(Map<String, Object?> json) {
    String side(String key) => switch (json[key]) {
      final String id when id.contains('.') => id,
      final other => throw MaterialFormatException(
        'a material pair\'s "$key" must be a material\'s id, not $other',
      ),
    };
    final first = side('first'), second = side('second');
    double? number(String key) => switch (json[key]) {
      null => null,
      final num value when value.isFinite => value.toDouble(),
      final other => throw MaterialFormatException(
        'the pair of "$first" and "$second": "$key" must be a finite number, '
        'not $other',
      ),
    };
    return MaterialPair(
      first,
      second,
      friction: number('friction'),
      restitution: number('restitution'),
      rollingResistance: number('rollingResistance'),
      contactAngle: number('contactAngle'),
      source: switch (json['source']) {
        final String said when said.trim().isNotEmpty => said,
        _ => throw MaterialFormatException(
          'the pair of "$first" and "$second" has no "source": a measured '
          'pair names where it was measured',
        ),
      },
    );
  }

  /// What is implausible about this pair, one sentence each: a friction
  /// outside 0…5, a restitution or rolling resistance outside 0…1, a contact
  /// angle outside 0…π, an empty source.
  List<String> problems() {
    final found = <String>[];
    void range(String what, double? value, double low, double high) {
      if (value != null && !(value >= low && value <= high)) {
        found.add('$key: $what $value is outside $low…$high');
      }
    }

    range('friction', friction, 0.0, 5.0);
    range('restitution', restitution, 0.0, 1.0);
    range('rolling resistance', rollingResistance, 0.0, 1.0);
    range('contact angle, rad', contactAngle, 0.0, math.pi);
    if (source.trim().isEmpty) found.add('$key: no source');
    return found;
  }

  @override
  String toString() => 'MaterialPair($first, $second)';
}

/// What two bodies meeting do: what a solver reads at a contact.
typedef ContactProperties = ({
  /// The one coefficient of friction. No unit.
  double friction,

  /// The coefficient of restitution. No unit, nought to one.
  double restitution,

  /// The coefficient of rolling resistance. No unit.
  double rollingResistance,
});

/// A material or a pair a [MaterialCatalog] would not take: an id already
/// taken, a plugin's id outside its namespace, an entry whose numbers
/// [PhysicalMaterial.problems] finds implausible.
///
/// **A [PluginException]**, as `FormatRegistrationException` is, because
/// materials come from plugins and a plugin manager reports it as the
/// install that failed.
final class MaterialRegistrationException extends PluginException {
  const MaterialRegistrationException(super.message);

  @override
  String toString() => 'MaterialRegistrationException: $message';
}

/// A material asked for by an id no material in the catalogue has: a level,
/// a world or a save naming a substance a plugin brings, with that plugin
/// not installed.
///
/// **Names the plugin that is missing** ([plugin], the id's namespace), so a
/// player is told what to install rather than that a number is wrong.
final class UnknownMaterialException extends PluginException {
  UnknownMaterialException(this.id)
    : plugin = _namespaceOf(id),
      super(
        _namespaceOf(id) == 'f3d'
            ? 'no material "$id": it is a flutter3d material this build does '
                  'not have — update flutter3d to open it'
            : 'no material "$id": it is the "${_namespaceOf(id)}" plugin\'s — '
                  'install and enable that plugin to open it',
      );

  /// The id asked for.
  final String id;

  /// The plugin whose material it is: the id's part before its last dot,
  /// `f3d` for the engine's own.
  final String plugin;

  static String _namespaceOf(String id) {
    final dot = id.lastIndexOf('.');
    return dot <= 0 ? id : id.substring(0, dot);
  }

  @override
  String toString() => 'UnknownMaterialException: $message';
}

/// The physical materials one engine knows, by id, and the pairs measured
/// between them: the engine's own ([Materials], under `f3d.*`) and every
/// plugin's.
///
/// **A [PluginRegistry]**, as `FormatRegistry` is: one per engine, nothing
/// global. `Flutter3dView` and `EngineLoop` install one holding the
/// built-ins, and a plugin reaches it with `host.registry<MaterialCatalog>()`
/// and adds its own under its id (`<pluginId>.<name>`); a data plugin's
/// `physicalMaterials` list goes through the same door. Each [add] returns the
/// [Registration] that takes it out again, so switching the plugin off takes
/// its materials with it.
///
/// **Everything that needs a substance reads it here by id** — a world's
/// medium, a collider's material, a liquid's preset — so a plugin's honey or
/// a plugin's basalt is used exactly as water is. The C core holds the
/// built-ins' numbers in a generated header; a plugin's reach it as a view
/// (`NativeLiquidProperties.of`, `NativeMaterial.of`) passes them when the
/// thing that needs them is made, and [watch] tells whoever keeps a copy that
/// one arrived.
base class MaterialCatalog extends PluginRegistry {
  /// A catalogue of [materials] and [pairs], each registered as the
  /// application's. Throws a [MaterialRegistrationException] as [add] does.
  MaterialCatalog({
    Iterable<PhysicalMaterial> materials = const <PhysicalMaterial>[],
    Iterable<MaterialPair> pairs = const <MaterialPair>[],
  }) {
    for (final material in materials) {
      _add(material, owner: null);
    }
    for (final pair in pairs) {
      _addPair(pair, owner: null);
    }
  }

  /// A catalogue holding the engine's own: [Materials.all] and
  /// [Materials.pairs]. What `Flutter3dView` and `EngineLoop` install.
  factory MaterialCatalog.builtIn() =>
      MaterialCatalog(materials: Materials.all, pairs: Materials.pairs);

  final Map<String, PhysicalMaterial> _byId = <String, PhysicalMaterial>{};
  final Map<String, String?> _owners = <String, String?>{};
  final Map<String, MaterialPair> _pairs = <String, MaterialPair>{};
  final List<void Function(PhysicalMaterial material)> _watchers =
      <void Function(PhysicalMaterial material)>[];

  /// Every material registered, in the order it was added.
  Iterable<PhysicalMaterial> get materials => _byId.values;

  /// Every pair registered, in the order it was added.
  Iterable<MaterialPair> get pairs => _pairs.values;

  /// The material [id] names; null when none does.
  PhysicalMaterial? byId(String id) => _byId[id];

  /// The material [id] names. Throws an [UnknownMaterialException] naming
  /// the plugin it needs when none does.
  PhysicalMaterial require(String id) =>
      _byId[id] ?? (throw UnknownMaterialException(id));

  /// The pair measured between [a] and [b], either way round; null when the
  /// catalogue has none.
  MaterialPair? pairOf(String a, String b) => _pairs[MaterialPair.keyOf(a, b)];

  /// What two bodies of [a] and [b] do where they meet.
  ///
  /// **A pair the catalogue holds wins**, field by field; what it leaves out
  /// is combined from the two materials' own (their mechanical group) by the
  /// engine's rule, the one both solvers use:
  ///
  /// * friction, the geometric mean √(μ_a μ_b), so either surface being
  ///   slippery makes the contact slippery, and a material on itself keeps
  ///   its own μ;
  /// * restitution, the larger, so either can make it bounce;
  /// * rolling resistance, the larger, so either a soft tyre or soft ground
  ///   holds a wheel back.
  ///
  /// A material that does not say takes [defaultFriction], no bounce and no
  /// rolling resistance.
  ContactProperties contact(PhysicalMaterial a, PhysicalMaterial b) {
    final pair = pairOf(a.id, b.id);
    final ma = a.mechanical, mb = b.mechanical;
    return (
      friction:
          pair?.friction ??
          math.sqrt(
            (ma?.friction ?? defaultFriction) *
                (mb?.friction ?? defaultFriction),
          ),
      restitution:
          pair?.restitution ??
          math.max(ma?.restitution ?? 0.0, mb?.restitution ?? 0.0),
      rollingResistance:
          pair?.rollingResistance ??
          math.max(ma?.rollingResistance ?? 0.0, mb?.rollingResistance ?? 0.0),
    );
  }

  /// The coefficient of friction of a body whose material says none: 0.6,
  /// what a `RigidBody` is made with. No unit.
  static const double defaultFriction = 0.6;

  /// Calls [added] with every material added from now on, until the
  /// returned registration is cancelled: how a keeper of copies — the
  /// physics core's own table, an editor's list — hears of a plugin's.
  Registration watch(void Function(PhysicalMaterial material) added) {
    _watchers.add(added);
    return Registration(() => _watchers.remove(added));
  }

  /// Adds [material] for the application. Throws a
  /// [MaterialRegistrationException] when its id is taken or
  /// [PhysicalMaterial.problems] finds anything.
  Registration add(PhysicalMaterial material) => _add(material, owner: null);

  /// Adds [pair] for the application. Throws a
  /// [MaterialRegistrationException] when the pair is already measured.
  Registration addPair(MaterialPair pair) => _addPair(pair, owner: null);

  Registration _add(PhysicalMaterial material, {required String? owner}) {
    final held = _byId[material.id];
    if (held != null) {
      final by = _owners[material.id];
      throw MaterialRegistrationException(
        'material "${material.id}" is already registered'
        '${by == null ? '' : ' by $by'}',
      );
    }
    final problems = material.problems();
    if (problems.isNotEmpty) {
      throw MaterialRegistrationException(
        'material "${material.id}" is not plausible: ${problems.join('; ')}',
      );
    }
    _byId[material.id] = material;
    _owners[material.id] = owner;
    for (final watcher in List.of(_watchers)) {
      watcher(material);
    }
    return Registration(() {
      if (identical(_byId[material.id], material)) {
        _byId.remove(material.id);
        _owners.remove(material.id);
      }
    });
  }

  Registration _addPair(MaterialPair pair, {required String? owner}) {
    final problems = pair.problems();
    if (problems.isNotEmpty) {
      throw MaterialRegistrationException(
        'the pair of "${pair.first}" and "${pair.second}" is not plausible: '
        '${problems.join('; ')}',
      );
    }
    if (_pairs.containsKey(pair.key)) {
      throw MaterialRegistrationException(
        'the pair of "${pair.first}" and "${pair.second}" is already measured',
      );
    }
    _pairs[pair.key] = pair;
    return Registration(() {
      if (identical(_pairs[pair.key], pair)) _pairs.remove(pair.key);
    });
  }

  @override
  MaterialCatalog forPlugin(PluginScope scope) => _PluginMaterials(this, scope);
}

/// [MaterialCatalog] as one plugin sees it: ids in its namespace, every
/// registration tracked so switching the plugin off takes its materials out.
final class _PluginMaterials extends MaterialCatalog {
  _PluginMaterials(this._inner, this._scope);

  final MaterialCatalog _inner;
  final PluginScope _scope;

  @override
  Iterable<PhysicalMaterial> get materials => _inner.materials;

  @override
  Iterable<MaterialPair> get pairs => _inner.pairs;

  @override
  PhysicalMaterial? byId(String id) => _inner.byId(id);

  @override
  PhysicalMaterial require(String id) => _inner.require(id);

  @override
  MaterialPair? pairOf(String a, String b) => _inner.pairOf(a, b);

  @override
  ContactProperties contact(PhysicalMaterial a, PhysicalMaterial b) =>
      _inner.contact(a, b);

  @override
  Registration watch(void Function(PhysicalMaterial material) added) {
    final registration = _inner.watch(added);
    _scope.track(registration);
    return registration;
  }

  @override
  Registration add(PhysicalMaterial material) {
    final plugin = _scope.manifest.id;
    if (!material.id.startsWith('$plugin.')) {
      throw MaterialRegistrationException(
        'plugin "$plugin" registered material "${material.id}": a plugin\'s '
        'material ids start with its own id, "$plugin.<name>"',
      );
    }
    final registration = _inner._add(material, owner: plugin);
    _scope.track(registration);
    return registration;
  }

  /// A plugin may measure a pair of which one at least is its own: it may
  /// not say how two of the engine's, or of another plugin's, meet.
  @override
  Registration addPair(MaterialPair pair) {
    final plugin = _scope.manifest.id;
    if (!pair.first.startsWith('$plugin.') &&
        !pair.second.startsWith('$plugin.')) {
      throw MaterialRegistrationException(
        'plugin "$plugin" measured the pair of "${pair.first}" and '
        '"${pair.second}": a plugin\'s pair has one of its own materials in it',
      );
    }
    final registration = _inner._addPair(pair, owner: plugin);
    _scope.track(registration);
    return registration;
  }
}
