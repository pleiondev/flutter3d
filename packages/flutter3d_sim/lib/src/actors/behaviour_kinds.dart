/// What a leaf kind in a behaviour tree document means, and the ones every
/// game gets.
///
/// ## Registered by kind, and why not by type
///
/// A document says `{"kind": "goTo", "key": "post"}`, and something has to
/// turn that string into code. A table from name to builder is that something,
/// and it is the same table whoever wrote the document — a level designer, a
/// mod, an agent over MCP. A game adds its own kinds to it next to the
/// standard ones, and a document naming a kind nobody registered is refused
/// with the list of kinds that are, rather than failing at the first tick.
///
/// ## What is standard
///
/// Only what the engine's [Mind] can already do: walk to the focus or to a
/// point, wait, look, jump, and read and write the board. What any of it is
/// *for* — an attack, a pickup, a conversation — is the game's, registered
/// beside these.
///
/// Walking to a point is [Mind.steerTowards]: along a route over the
/// system's navigation mesh when it has one, straight and sliding off walls
/// when it does not; walking to the focus goes round corners on the level's
/// flow field.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:vector_math/vector_math.dart';

import 'behaviour_tree.dart';
import 'brain.dart';

/// One leaf kind's code.
///
/// **Shared by every actor running the tree, so it keeps no state of its
/// own.** What a leaf needs to remember while it runs goes in
/// [BehaviorContext.memory], which is on the actor's board and in its
/// snapshot; a field here would be one value for every actor at once and
/// gone on a restore.
abstract base class BehaviorLeaf {
  const BehaviorLeaf();

  /// Decides, on the steps the actor thinks on.
  BehaviorStatus tick(BehaviorContext context);

  /// Moves, every step this leaf is the one running. Thinking is throttled
  /// for an actor far from the focus and moving is not; a leaf that only
  /// steered in [tick] would stutter out there.
  void act(BehaviorContext context) {}

  /// Where this leaf is taking the actor, for the debug overlay.
  Vector3? goal(BehaviorView view) => null;
}

/// How much one consideration likes an option, from nought to one.
typedef Consideration = double Function(BehaviorContext context);

/// A composite kind's code: what to do with its children.
///
/// **The six composites the reader owns stay its own**, and every tree that
/// names them runs exactly as before. A game or a plugin that needs another
/// — a race between two branches, a retry, a "first success, remembered" —
/// writes one of these and registers it with [BehaviorKinds.composite]. A
/// document names it as it names the built-in ones: `{"kind": "retry",
/// "children": [...]}`, or with one `"child"` for a decorator.
///
/// **Shared by every actor running the tree, so it keeps no state of its
/// own**, for the reason [BehaviorLeaf] gives. What it must remember while a
/// child runs — which child, how many tries — goes in
/// [BehaviorContext.memory], which is the composite's own slot on the
/// actor's board while [tick] runs, is JSON-shaped, and is in every
/// snapshot. It is forgotten when the composite leaves the running path.
abstract base class BehaviorComposite {
  const BehaviorComposite();

  /// Decides, ticking whichever [children] it chooses, in the order it
  /// chooses. [BehaviorChildren.tick] gives the child's status and leaves
  /// [context] addressing this composite again, so [BehaviorContext.memory]
  /// read or written after it is still this composite's.
  BehaviorStatus tick(BehaviorContext context, BehaviorChildren children);
}

typedef LeafBuilder = BehaviorLeaf Function(BehaviorParameters params);
typedef ConsiderationBuilder =
    Consideration Function(BehaviorParameters params);
typedef CompositeBuilder =
    BehaviorComposite Function(BehaviorParameters params);

/// A node's own fields, read with the problems written down rather than
/// thrown, so that a document is checked in one pass.
final class BehaviorParameters {
  BehaviorParameters(this._row, this._where, this._problems);

  final Map<Object?, Object?> _row;
  final String _where;
  final List<String> _problems;

  /// The number [name], or [fallback] when it is absent. Absent with no
  /// fallback, or not a number, is a problem, and the answer is nought.
  double number(String name, [double? fallback]) {
    final value = _row[name];
    if (value is num) return value.toDouble();
    if (value == null && fallback != null) return fallback;
    _problems.add(
      value == null
          ? '$_where: ${_row['kind']} needs a number "$name"'
          : '$_where: "$name" is a number, not $value',
    );
    return 0.0;
  }

  /// The number [name], or null when it is absent.
  double? optionalNumber(String name) {
    final value = _row[name];
    if (value == null) return null;
    return number(name);
  }

  /// The string [name]. Absent, or not a string, is a problem.
  String text(String name) {
    final value = _row[name];
    if (value is String) return value;
    _problems.add('$_where: ${_row['kind']} needs a string "$name"');
    return '';
  }

  /// Whatever [name] holds, unread.
  Object? value(String name) => _row[name];
}

final class BehaviorKinds {
  /// The standard kinds, which a game adds its own to.
  BehaviorKinds() {
    _standardLeaves();
    _standardConsiderations();
  }

  /// No kinds at all, for a game that wants none of the standard ones.
  BehaviorKinds.none();

  /// The kinds the tree reader handles itself, which no leaf may take.
  static const Set<String> composites = <String>{
    'sequence',
    'selector',
    'utility',
    'invert',
    'alwaysSucceed',
    'cooldown',
  };

  final Map<String, LeafBuilder> _leaves = <String, LeafBuilder>{};
  final Map<String, ConsiderationBuilder> _considerations =
      <String, ConsiderationBuilder>{};
  final Map<String, CompositeBuilder> _composites =
      <String, CompositeBuilder>{};

  /// Says what the leaf kind [kind] is.
  ///
  /// Throws for a composite's name, built in or registered, and for a kind
  /// already registered unless [replace] says that is meant — a game
  /// swapping the standard `goTo` for one that routes is the case for it.
  /// Thrown, because this is a game's own setup and a clash there is a
  /// mistake in the code, not in a document.
  void leaf(String kind, LeafBuilder build, {bool replace = false}) {
    if (composites.contains(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is a composite the reader owns');
    }
    if (_composites.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is already a composite kind');
    }
    if (!replace && _leaves.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is already a leaf kind');
    }
    _leaves[kind] = build;
  }

  /// Says what the composite kind [kind] is: a node with `children` (or one
  /// `child`) that [build]'s [BehaviorComposite] ticks.
  ///
  /// Throws for the name of a composite the reader owns — those six are not
  /// replaced, so a tree naming them means the same in every game — for a
  /// leaf kind's name, and for a composite already registered unless
  /// [replace] says that is meant.
  void composite(String kind, CompositeBuilder build, {bool replace = false}) {
    if (composites.contains(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is a composite the reader owns');
    }
    if (_leaves.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is already a leaf kind');
    }
    if (!replace && _composites.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is already a composite kind');
    }
    _composites[kind] = build;
  }

  CompositeBuilder? compositeBuilder(String kind) => _composites[kind];

  /// Says what the consideration kind [kind] is. See [leaf] for [replace].
  void consideration(
    String kind,
    ConsiderationBuilder build, {
    bool replace = false,
  }) {
    if (!replace && _considerations.containsKey(kind)) {
      throw ArgumentError.value(kind, 'kind', 'is already a consideration');
    }
    _considerations[kind] = build;
  }

  LeafBuilder? leafBuilder(String kind) => _leaves[kind];

  ConsiderationBuilder? considerationBuilder(String kind) =>
      _considerations[kind];

  /// The leaf kinds and composites, built in and registered, sorted, for a
  /// refusal to list.
  String describeKnown() => (<String>[
    ...composites,
    ..._composites.keys,
    ..._leaves.keys,
  ]..sort()).join(', ');

  String describeKnownConsiderations() =>
      (_considerations.keys.toList()..sort()).join(', ');

  void _standardLeaves() {
    leaf('wait', (p) => _Wait(p.number('seconds')));
    leaf('goToFocus', (p) => _GoToFocus(p.number('within', 1.0)));
    leaf('goTo', (p) => _GoTo(p.text('key'), p.number('within', 0.5)));
    leaf('seesFocus', (p) => const _SeesFocus());
    leaf('focusWithin', (p) => _FocusWithin(p.number('distance')));
    leaf(
      'check',
      (p) => _Check(
        p.text('key'),
        p.optionalNumber('above'),
        p.optionalNumber('below'),
      ),
    );
    leaf('set', (p) => _Set(p.text('key'), p.value('value')));
    leaf('markFocus', (p) => _MarkFocus(p.text('key')));
    leaf('jump', (p) => const _Jump());
  }

  void _standardConsiderations() {
    consideration('constant', (p) {
      final value = p.number('value');
      return (_) => value;
    });
    consideration('focusDistance', (p) {
      final from = p.number('from');
      final to = p.number('to');
      return (c) => ramp(c.mind.distance, from, to);
    });
    consideration(
      'seesFocus',
      (p) =>
          (c) => c.mind.canSee() ? 1.0 : 0.0,
    );
    consideration('health', (p) {
      final from = p.number('from', 0.0);
      final to = p.number('to', 1.0);
      return (c) {
        final health = c.mind.actor.health;
        if (health == null || health.maximum <= 0.0) return 1.0;
        return ramp(health.current / health.maximum, from, to);
      };
    });
    consideration('blackboard', (p) {
      final key = p.text('key');
      final from = p.number('from');
      final to = p.number('to');
      return (c) => switch (c.board.number(key)) {
        final double value => ramp(value, from, to),
        null => 0.0,
      };
    });
    consideration('since', (p) {
      final key = p.text('key');
      final from = p.number('from');
      final to = p.number('to');
      return (c) => switch (c.board.number(key)) {
        final double at => ramp(c.clock - at, from, to),
        null => 0.0,
      };
    });
  }
}

/// A [BehaviorKinds] as the plugin host hands it out: a plugin's leaves,
/// considerations and composites, withdrawn when the plugin is switched off.
///
/// **The behaviour-tree vocabulary's half of the plugin host.** One per
/// engine, around the [kinds] its trees are read against, handed to the loop
/// among its registries: `EngineLoop(registries: [BehaviorKindsRegistry(
/// kinds)], plugins: …)`. A plugin asks for it in `install`,
/// `host.registry<BehaviorKindsRegistry>()`, and registers through it what
/// it would have registered on [kinds]; every call answers a [Registration]
/// the host keeps, so switching the plugin off takes the kinds out again.
///
/// A kind registered with `replace` puts back the one it replaced when it is
/// withdrawn, so a plugin that swapped the standard `goTo` leaves the
/// standard one behind it. **A tree already read keeps what it was read
/// with**: withdrawing a kind refuses it to the next document, not to the
/// actors already running one.
///
/// The clashes [BehaviorKinds] refuses are refused here the same way, with
/// the plugin's id in front of the reason.
final class BehaviorKindsRegistry extends PluginRegistry {
  /// The registry around [kinds], for the application.
  BehaviorKindsRegistry(this.kinds) : _scope = null;

  BehaviorKindsRegistry._scoped(this.kinds, PluginScope this._scope);

  /// What trees are read against.
  final BehaviorKinds kinds;

  final PluginScope? _scope;

  String get _owner =>
      _scope == null ? 'the application' : 'plugin "${_scope.manifest.id}"';

  /// [BehaviorKinds.leaf], withdrawn by the answer.
  Registration leaf(String kind, LeafBuilder build, {bool replace = false}) =>
      _add(
        kinds._leaves,
        kind,
        build,
        () => kinds.leaf(kind, build, replace: replace),
      );

  /// [BehaviorKinds.consideration], withdrawn by the answer.
  Registration consideration(
    String kind,
    ConsiderationBuilder build, {
    bool replace = false,
  }) => _add(
    kinds._considerations,
    kind,
    build,
    () => kinds.consideration(kind, build, replace: replace),
  );

  /// [BehaviorKinds.composite], withdrawn by the answer.
  Registration composite(
    String kind,
    CompositeBuilder build, {
    bool replace = false,
  }) => _add(
    kinds._composites,
    kind,
    build,
    () => kinds.composite(kind, build, replace: replace),
  );

  Registration _add<B extends Object>(
    Map<String, B> table,
    String kind,
    B build,
    void Function() register,
  ) {
    final previous = table[kind];
    try {
      register();
    } on ArgumentError catch (error) {
      throw ArgumentError.value(kind, 'kind', '${error.message} ($_owner)');
    }
    final registration = Registration(() {
      // Only when it is still this one: a later replacement owns the name.
      if (!identical(table[kind], build)) return;
      if (previous == null) {
        table.remove(kind);
      } else {
        table[kind] = previous;
      }
    });
    _scope?.track(registration);
    return registration;
  }

  @override
  BehaviorKindsRegistry forPlugin(PluginScope scope) =>
      BehaviorKindsRegistry._scoped(kinds, scope);
}

/// [value] mapped onto nought to one: nought at [from], one at [to], clamped
/// outside. [from] above [to] turns it round, so "near is good" is
/// `from: 10, to: 2`. Equal ends are a step at that value.
double ramp(double value, double from, double to) {
  if (from == to) return value >= to ? 1.0 : 0.0;
  final t = (value - from) / (to - from);
  return t <= 0.0 ? 0.0 : (t >= 1.0 ? 1.0 : t);
}

void _faceHeading(Mind it) {
  final heading = it.heading;
  it.turnTowards(heading.x, heading.z);
}

final class _Wait extends BehaviorLeaf {
  const _Wait(this.seconds);

  /// How long to wait, in seconds of [BehaviorContext.clock].
  final double seconds;

  @override
  BehaviorStatus tick(BehaviorContext context) {
    final start = switch (context.memory) {
      final num at => at.toDouble(),
      _ => context.clock,
    };
    context.memory = start;
    return context.clock - start >= seconds
        ? BehaviorStatus.success
        : BehaviorStatus.running;
  }
}

final class _GoToFocus extends BehaviorLeaf {
  const _GoToFocus(this.within);

  /// Near enough to the focus to succeed, in metres.
  final double within;

  @override
  BehaviorStatus tick(BehaviorContext context) =>
      context.mind.distance <= within
      ? BehaviorStatus.success
      : BehaviorStatus.running;

  @override
  void act(BehaviorContext context) {
    context.mind.steerTowardsFocus();
    _faceHeading(context.mind);
  }

  @override
  Vector3? goal(BehaviorView view) => view.system.focus.clone();
}

final class _GoTo extends BehaviorLeaf {
  _GoTo(this.key, this.within);
  final String key;

  /// Near enough to the point, across the ground, to succeed, in metres.
  final double within;

  /// Scratch, which is safe to share: the step is single-threaded and the
  /// point is read and used inside one call.
  final Vector3 _at = Vector3.zero();

  @override
  BehaviorStatus tick(BehaviorContext context) {
    final position = context.mind.actor.position;
    if (position == null || !context.board.point(key, _at)) {
      return BehaviorStatus.failure;
    }
    final dx = _at.x - position.x;
    final dz = _at.z - position.z;
    return dx * dx + dz * dz <= within * within
        ? BehaviorStatus.success
        : BehaviorStatus.running;
  }

  @override
  void act(BehaviorContext context) {
    if (!context.board.point(key, _at)) return;
    context.mind.steerTowards(_at);
    _faceHeading(context.mind);
  }

  @override
  Vector3? goal(BehaviorView view) {
    final at = Vector3.zero();
    return view.board.point(key, at) ? at : null;
  }
}

final class _SeesFocus extends BehaviorLeaf {
  const _SeesFocus();

  @override
  BehaviorStatus tick(BehaviorContext context) =>
      context.mind.canSee() ? BehaviorStatus.success : BehaviorStatus.failure;
}

final class _FocusWithin extends BehaviorLeaf {
  const _FocusWithin(this.distance);

  /// How near the focus has to be, in metres.
  final double distance;

  @override
  BehaviorStatus tick(BehaviorContext context) =>
      context.mind.distance <= distance
      ? BehaviorStatus.success
      : BehaviorStatus.failure;
}

/// Succeeds when [key] holds something other than `false` — or, given
/// [above] or [below], a number past them.
final class _Check extends BehaviorLeaf {
  const _Check(this.key, this.above, this.below);
  final String key;

  /// The board number has to be past this, in that number's own units.
  final double? above;

  /// The board number has to be under this, in its own units, as [above].
  final double? below;

  @override
  BehaviorStatus tick(BehaviorContext context) {
    final board = context.board;
    final holds = switch ((above, below)) {
      (null, null) => board.flag(key),
      _ => switch (board.number(key)) {
        null => false,
        final double value =>
          (above == null || value > above!) &&
              (below == null || value < below!),
      },
    };
    return holds ? BehaviorStatus.success : BehaviorStatus.failure;
  }
}

final class _Set extends BehaviorLeaf {
  const _Set(this.key, this.value);
  final String key;
  final Object? value;

  @override
  BehaviorStatus tick(BehaviorContext context) {
    context.board.set(key, value);
    return BehaviorStatus.success;
  }
}

/// Writes where the focus is now, for a search of where it was last seen.
final class _MarkFocus extends BehaviorLeaf {
  const _MarkFocus(this.key);
  final String key;

  @override
  BehaviorStatus tick(BehaviorContext context) {
    context.board.setPoint(key, context.mind.focus);
    return BehaviorStatus.success;
  }
}

final class _Jump extends BehaviorLeaf {
  const _Jump();

  @override
  BehaviorStatus tick(BehaviorContext context) {
    context.mind.jump();
    return BehaviorStatus.success;
  }
}
