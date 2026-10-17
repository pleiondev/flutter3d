/// Which systems of one phase touch the same state with nothing ordering
/// them: the pairs a replay cannot promise to run the same way twice.
///
/// **Declared rather than observed.** A system says what it reads and what
/// it writes (`LoopRegistry.addSystem`'s `reads:` and `writes:`), and the
/// check is arithmetic on those declarations and the `after`/`before`
/// constraints: no run, no world, no device. A system that declares nothing
/// is never named, so a loop written before the declarations existed is
/// checked the day one of its systems declares something.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// One system of a phase, as the check reads it: its name, its order
/// constraints and what it declares it touches.
final class SystemAccess {
  /// [name]'s declarations: [after]/[before] as `addSystem` was handed
  /// them, [reads] and [writes] the state it touches.
  const SystemAccess(
    this.name, {
    this.after = const <String>[],
    this.before = const <String>[],
    this.reads = const <String>[],
    this.writes = const <String>[],
  });

  /// The system's name, unique in its loop.
  final String name;

  /// The systems it runs after, by name.
  final List<String> after;

  /// The systems it runs before, by name.
  final List<String> before;

  /// The state it reads.
  final List<String> reads;

  /// The state it writes.
  final List<String> writes;

  /// Whether it declares anything at all.
  bool get declares => reads.isNotEmpty || writes.isNotEmpty;
}

/// Two systems of one phase that touch the same state with no order between
/// them: one of them writes it, and neither runs after the other through a
/// constraint or a chain of constraints.
final class UnorderedAccess {
  /// [first] and [second] of [phase], in registration order, sharing
  /// [state].
  const UnorderedAccess({
    required this.phase,
    required this.first,
    required this.second,
    required this.state,
  });

  /// The phase both run in.
  final LoopPhase phase;

  /// The one registered first.
  final String first;

  /// The one registered second.
  final String second;

  /// The names of the state both touch, at least one of them writing: what
  /// [first] writes, then what it only reads, each in its declared order.
  final List<String> state;

  @override
  bool operator ==(Object other) =>
      other is UnorderedAccess &&
      other.phase == phase &&
      other.first == first &&
      other.second == second &&
      _sameList(other.state, state);

  @override
  int get hashCode => Object.hash(phase, first, second, Object.hashAll(state));

  @override
  String toString() =>
      '"$first" and "$second" in ${phase.name} both touch '
      '${state.map((s) => '"$s"').join(', ')}, and neither is ordered '
      'against the other';
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Thrown by `EngineLoop.validateOrder`, and in a debug build when the loop
/// orders its systems, for a step phase with an [UnorderedAccess] in it.
///
/// **A [PluginException]**, like a constraint cycle: the declarations come
/// from plugins and a project's own systems, and a caller that installs
/// plugins catches it as it catches any other refusal.
final class UnorderedAccessException extends PluginException {
  /// The exception naming every pair of [pairs].
  UnorderedAccessException(this.pairs)
    : super(
        'systems that touch the same state run in an order nothing decides, '
        'so a replay can run them the other way round: '
        '${pairs.join('; ')}. Order each pair with after: or before:',
      );

  /// Every pair found, phase by phase in the order the phases run.
  final List<UnorderedAccess> pairs;

  @override
  String toString() => 'UnorderedAccessException: $message';
}

/// Every pair of [systems], all of [phase] and in registration order, that
/// touches one state with nothing ordering them; empty when there is none.
///
/// A constraint naming a system not in [systems] orders nothing, as it does
/// in the loop's own sort.
List<UnorderedAccess> unorderedAccessIn(
  LoopPhase phase,
  List<SystemAccess> systems,
) {
  final count = systems.length;
  final declaring = <int>[
    for (var i = 0; i < count; i++)
      if (systems[i].declares) i,
  ];
  if (declaring.length < 2) return const <UnorderedAccess>[];
  final index = <String, int>{
    for (var i = 0; i < count; i++) systems[i].name: i,
  };
  // Each system's successors, every system counted so a chain through one
  // that declares nothing still orders the two ends.
  final next = List<Set<int>>.generate(count, (_) => <int>{});
  for (var i = 0; i < count; i++) {
    for (final name in systems[i].after) {
      if (index[name] case final at?) next[at].add(i);
    }
    for (final name in systems[i].before) {
      if (index[name] case final at?) next[i].add(at);
    }
  }
  // What runs after each declaring system, by a walk from it.
  Set<int> reach(int from) {
    final seen = <int>{};
    final stack = <int>[from];
    while (stack.isNotEmpty) {
      for (final to in next[stack.removeLast()]) {
        if (seen.add(to)) stack.add(to);
      }
    }
    return seen;
  }

  final later = <int, Set<int>>{for (final i in declaring) i: reach(i)};
  return <UnorderedAccess>[
    for (var a = 0; a < declaring.length; a++)
      for (var b = a + 1; b < declaring.length; b++)
        if (_shared(systems[declaring[a]], systems[declaring[b]])
            case final state
            when state.isNotEmpty &&
                !later[declaring[a]]!.contains(declaring[b]) &&
                !later[declaring[b]]!.contains(declaring[a]))
          UnorderedAccess(
            phase: phase,
            first: systems[declaring[a]].name,
            second: systems[declaring[b]].name,
            state: state,
          ),
  ];
}

/// The state [a] and [b] both touch with at least one of them writing: what
/// [a] writes, then what it reads.
List<String> _shared(SystemAccess a, SystemAccess b) {
  final bTouches = <String>{...b.reads, ...b.writes};
  final bWrites = b.writes.toSet();
  return <String>{
    for (final name in a.writes)
      if (bTouches.contains(name)) name,
    for (final name in a.reads)
      if (bWrites.contains(name)) name,
  }.toList();
}
