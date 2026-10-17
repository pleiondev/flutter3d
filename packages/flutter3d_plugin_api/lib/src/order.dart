import 'package:flutter3d_foundation/flutter3d_foundation.dart';

/// Thrown when `after`/`before` constraints, or plugin dependencies, go
/// round in a circle.
///
/// [cycle] names every member, in the order the constraints chain them, so
/// the message reads `a → b → c → a` and the person reading it knows which
/// three declarations to look at.
///
/// **A [PluginException], not an `Error`**: the constraints come from
/// plugins and a project's own systems — data a correct program can be
/// handed — so a caller that installs plugins catches this as it catches
/// any other refusal to install, rather than treating it as a bug.
final class ConstraintCycleException extends PluginException {
  ConstraintCycleException({required this.what, required this.cycle})
    : super(
        'the $what are ordered in a circle: '
        '${[...cycle, cycle.first].join(' → ')}. Remove one of these '
        'constraints; nothing can run first.',
      );

  /// What was being ordered: `'systems in physics'`, `'plugins'`.
  final String what;

  /// The members of the cycle, first repeated at the end left out.
  final List<String> cycle;

  @override
  String toString() => 'ConstraintCycleException: $message';
}

/// Orders [items] so every `after` comes before and every `before` after,
/// keeping the given order wherever the constraints leave a choice.
///
/// **The one sort behind phases, systems and plugins**, so the three agree
/// about what a tie is: [items] arrive in registration order, and the
/// constraints move only what they name. Whenever more than one item could
/// go next, this takes the one that the earliest registered item still to be
/// placed is waiting for (itself, if nothing waits). It never consults
/// a hash map's order, so two runs order the same registrations the same
/// way.
///
/// A constraint naming nothing in [items] goes to [onUnknown], which may
/// throw — a plugin's missing dependency is an error, a system's "before
/// fire" without the fire plugin is not — and is otherwise ignored.
///
/// Throws a [ConstraintCycleException] naming the cycle when there is no order.
List<T> orderByConstraints<T>(
  List<T> items, {
  required String Function(T item) nameOf,
  Iterable<String> Function(T item)? after,
  Iterable<String> Function(T item)? before,
  required String what,
  void Function(T item, String missing)? onUnknown,
}) {
  final count = items.length;
  final index = <String, int>{};
  for (var i = 0; i < count; i++) {
    final name = nameOf(items[i]);
    if (index.containsKey(name)) {
      throw ArgumentError.value(name, 'items', 'two $what are named "$name"');
    }
    index[name] = i;
  }
  // Successors as sorted index lists, so the walk is independent of how any
  // set iterates.
  final next = List<Set<int>>.generate(count, (_) => <int>{});
  void edge(int from, int to) => next[from].add(to);
  for (var i = 0; i < count; i++) {
    final item = items[i];
    for (final name in after?.call(item) ?? const <String>[]) {
      final at = index[name];
      if (at == null) {
        onUnknown?.call(item, name);
      } else {
        edge(at, i);
      }
    }
    for (final name in before?.call(item) ?? const <String>[]) {
      final at = index[name];
      if (at == null) {
        onUnknown?.call(item, name);
      } else {
        edge(i, at);
      }
    }
  }
  final waiting = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    for (final to in next[i]) {
      waiting[to]++;
    }
  }
  // Each item's rank is the earliest registration among itself and
  // everything that must come after it. An item something early waits for
  // is as urgent as that early thing, so "sweep before integrate" moves
  // sweep up to integrate's place instead of letting an unrelated item
  // registered between them slip ahead. Relaxed to a fixed point, which a
  // cycle cannot stop: ranks only fall, and never below zero.
  final rank = List<int>.generate(count, (i) => i);
  for (var changed = true; changed;) {
    changed = false;
    for (var from = 0; from < count; from++) {
      for (final to in next[from]) {
        if (rank[to] < rank[from]) {
          rank[from] = rank[to];
          changed = true;
        }
      }
    }
  }
  final placed = List<bool>.filled(count, false);
  final ordered = <T>[];
  while (ordered.length < count) {
    // Of the items nothing is waiting on, the lowest rank, ties by
    // registration. Quadratic, and the lists are a dozen phases or a few
    // dozen systems sorted at a boundary.
    var pick = -1;
    for (var i = 0; i < count; i++) {
      if (!placed[i] && waiting[i] == 0 && (pick < 0 || rank[i] < rank[pick])) {
        pick = i;
      }
    }
    if (pick < 0) {
      throw ConstraintCycleException(
        what: what,
        cycle: <String>[
          for (final i in _findCycle(next, placed)) nameOf(items[i]),
        ],
      );
    }
    placed[pick] = true;
    ordered.add(items[pick]);
    for (final to in next[pick]) {
      waiting[to]--;
    }
  }
  return ordered;
}

/// One cycle among the unplaced items: every unplaced item still waits on
/// another unplaced one, so walking predecessors from any of them must come
/// back round. Walked from the lowest index, following the lowest-indexed
/// edge, so the same graph names the same cycle every time.
List<int> _findCycle(List<Set<int>> next, List<bool> placed) {
  final count = next.length;
  final previous = List<List<int>>.generate(count, (_) => <int>[]);
  for (var from = 0; from < count; from++) {
    if (placed[from]) continue;
    for (final to in next[from]) {
      if (!placed[to]) previous[to].add(from);
    }
  }
  for (final list in previous) {
    list.sort();
  }
  var at = placed.indexOf(false);
  final seen = <int, int>{};
  final path = <int>[];
  while (!seen.containsKey(at)) {
    seen[at] = path.length;
    path.add(at);
    at = previous[at].first;
  }
  // `path` walks backwards along the edges; the cycle is its tail from the
  // first repeat, turned round to read in the direction things run.
  return path.sublist(seen[at]!).reversed.toList();
}
