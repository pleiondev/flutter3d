/// A decision written down as data: a behaviour tree, with utility choices
/// among its nodes.
///
/// ## Data, read once, shared
///
/// A tree is a JSON document — `{"kind": "selector", "children": [...]}` —
/// read by [BehaviorTree.read] against a [BehaviorKinds] that says what each
/// leaf kind is. A level, a mod or an agent can write one without compiling
/// anything, and two actors running the same tree share it: everything that
/// differs between them is on their [Blackboard], which is a component and is
/// therefore in every snapshot.
///
/// Nodes are numbered in the order the document lists them, and the number is
/// what a blackboard remembers. That is why a board carries the digest of the
/// tree it was ticked by ([Blackboard.tree]): under an edited tree the numbers
/// name other nodes, and resuming there would run something nobody chose.
///
/// ## The composites, and the one that is missing
///
/// * `sequence` — children in order until one does not succeed. **It
///   remembers** which child was running and resumes there, so a sequence
///   that walked somewhere and is now waiting does not walk there again.
/// * `selector` — the first child that does not fail. **It does not
///   remember**: every tick asks again from the first child, so a higher
///   priority that becomes true takes over from a lower one that is running.
///   Remembering here is the classic way to write a guard that never fires
///   until the patrol it interrupts happens to finish.
/// * `utility` — scores every option and runs the best (see [_Utility]).
/// * `invert`, `alwaysSucceed` and `cooldown` — one child each.
/// * whatever a game or a plugin registers with [BehaviorKinds.composite]:
///   a [BehaviorComposite] over `children`, or over one `child`. These six
///   are the reader's own and cannot be replaced; a registered one is read
///   after them and before the leaves.
///
/// No `parallel`. An actor has one body and it walks one way: two running
/// leaves would both steer and the last one would win, decided by the order of
/// a list. A condition that must hold while something runs is a `selector`
/// with the condition's branch first, which is checked every tick anyway.
library;

import 'package:vector_math/vector_math.dart';

import '../save/state_digest.dart';
import 'actor.dart';
import 'actor_system.dart';
import 'behaviour_kinds.dart';
import 'blackboard.dart';
import 'brain.dart';

export 'behaviour_kinds.dart';
export 'blackboard.dart';

/// What a leaf may look at while it ticks or acts.
///
/// One per tree and reused, because a tick happens for every thinking actor
/// on every thinking step and allocating one each time is garbage in the step.
final class BehaviorContext {
  BehaviorContext._();

  /// The actor's mind: its body, its focus, and what it may ask for.
  late Mind mind;

  late Blackboard board;

  /// Which node is ticking, by its number in the tree.
  int node = 0;

  /// Seconds the actor has been acting. See [Blackboard.clock].
  double get clock => board.clock;

  /// This node's own memory, kept while it is on the running path and
  /// forgotten when it leaves it. JSON-shaped, like everything on the board.
  Object? get memory => board.memory[node];
  set memory(Object? value) {
    if (value == null) {
      board.memory.remove(node);
    } else {
      board.memory[node] = value;
    }
  }
}

/// What the overlay may look at outside a step, when there is no mind.
typedef BehaviorView = ({Actor actor, ActorSystem system, Blackboard board});

/// One node on the running path, for whoever draws or prints it.
typedef BehaviorPathStep = ({
  int node,
  String kind,
  String label,
  BehaviorStatus status,
});

/// What [BehaviorTree.read] made of a document: a tree, or why not.
final class BehaviorTreeRead {
  const BehaviorTreeRead._(this.tree, this.problems);

  /// The tree, when the document had no problems.
  final BehaviorTree? tree;

  /// Every problem, each naming where in the document it is — all of them,
  /// rather than the first, so that a document is fixed in one pass.
  final List<String> problems;
}

/// The children of a registered [BehaviorComposite], as it may tick them.
///
/// One per composite node in a tree, made when the tree is read, so a tick
/// allocates nothing.
final class BehaviorChildren {
  BehaviorChildren._(this._tree, this._node);

  final BehaviorTree _tree;
  final _Custom _node;

  /// How many children the node has: its `children`, or one for a `child`.
  int get length => _node.children.length;

  /// The label of child [index] — its `name`, or its kind — for a composite
  /// that reports which branch it chose.
  String labelOf(int index) => _node.children[index].label;

  /// Ticks child [index] and answers its status.
  ///
  /// Afterwards [context] addresses the composite again — its
  /// [BehaviorContext.node] is the composite's — so the composite's own
  /// [BehaviorContext.memory] is what it reads and writes next, whatever
  /// the child below it did.
  BehaviorStatus tick(BehaviorContext context, int index) {
    final status = _tree._tick(_node.children[index], context);
    context.node = _node.index;
    return status;
  }
}

final class BehaviorTree {
  BehaviorTree._(this._root, this._nodes, this.digestHex, this.json)
    : _statusOf = List<BehaviorStatus?>.filled(_nodes.length, null) {
    for (final node in _nodes) {
      if (node is _Custom) node.view = BehaviorChildren._(this, node);
    }
  }

  /// Reads [json] against [kinds].
  ///
  /// A refusal is an answer here rather than an exception: a tree arrives
  /// from a file, an editor or an agent, and each of them wants every problem
  /// listed with where it is — `root.children[2]: no leaf kind "fly"; known:
  /// …` — rather than a stack trace about the first.
  static BehaviorTreeRead read(Object? json, BehaviorKinds kinds) {
    final reader = _Reader(kinds);
    final root = reader.node(json, 'root');
    final digest = reader.digestOf(json);
    if (root == null || reader.problems.isNotEmpty || digest == null) {
      return BehaviorTreeRead._(
        null,
        List<String>.unmodifiable(reader.problems),
      );
    }
    return BehaviorTreeRead._(
      BehaviorTree._(root, reader.nodes, digest, json! as Map<String, Object?>),
      const <String>[],
    );
  }

  final _Node _root;
  final List<_Node> _nodes;

  /// The document this was read from.
  final Map<String, Object?> json;

  /// The document's [StateDigest], which is how a board knows whether it was
  /// ticked by this tree.
  final String digestHex;

  /// How many nodes there are.
  int get length => _nodes.length;

  final BehaviorContext _context = BehaviorContext._();
  final List<int> _stack = <int>[];
  final List<int> _lastPath = <int>[];
  final List<BehaviorStatus?> _statusOf;

  /// Makes [board] belong to this tree, starting its decision again if it
  /// was ticked by another one.
  void prepare(Blackboard board) {
    if (board.tree == digestHex) return;
    board
      ..restart()
      ..tree = digestHex;
  }

  /// Decides: runs the tree from the root, records the path it took on
  /// [board], and forgets the memory of every node that is no longer running.
  BehaviorStatus tick(Mind mind, Blackboard board) {
    prepare(board);
    final context = _context
      ..mind = mind
      ..board = board;
    _stack.clear();
    _lastPath.clear();
    _statusOf.fillRange(0, _statusOf.length, null);

    final status = _tick(_root, context);

    board.path
      ..clear()
      ..addAll(_lastPath);
    board.statuses
      ..clear()
      ..addAll(<BehaviorStatus>[
        for (final node in _lastPath) _statusOf[node]!,
      ]);
    if (status == BehaviorStatus.running) {
      board.memory.removeWhere((node, _) => !_lastPath.contains(node));
    } else {
      board.memory.clear();
    }
    return status;
  }

  /// Moves: the running leaf's [BehaviorLeaf.act], every step, between the
  /// decisions [tick] makes on the steps the system thinks on.
  void act(Mind mind, Blackboard board) {
    final leaf = _runningLeaf(board);
    if (leaf == null) return;
    leaf.leaf.act(
      _context
        ..mind = mind
        ..board = board
        ..node = leaf.index,
    );
  }

  /// The path [board] last took through this tree, root first; empty when it
  /// was ticked by another tree or not yet at all.
  List<BehaviorPathStep> pathOf(Blackboard board) => board.tree != digestHex
      ? const <BehaviorPathStep>[]
      : <BehaviorPathStep>[
          for (var i = 0; i < board.path.length; i++)
            if (board.path[i] case final int node when node < _nodes.length)
              (
                node: node,
                kind: _nodes[node].kind,
                label: _nodes[node].label,
                status: board.statuses[i],
              ),
        ];

  /// Where the running leaf is taking the actor, for the overlay; null when
  /// nothing is running or the leaf is not going anywhere.
  Vector3? goalOf(BehaviorView view) =>
      _runningLeaf(view.board)?.leaf.goal(view);

  _Leaf? _runningLeaf(Blackboard board) {
    if (board.tree != digestHex || !board.isRunning) return null;
    return switch (_nodes.elementAtOrNull(board.path.last)) {
      final _Leaf leaf => leaf,
      _ => null,
    };
  }

  BehaviorStatus _tick(_Node node, BehaviorContext context) {
    _stack.add(node.index);
    final status = switch (node) {
      _Leaf() => _leaf(node, context),
      _Sequence() => _sequence(node, context),
      _Selector() => _selector(node, context),
      _Utility() => _utility(node, context),
      _Invert() => switch (_tick(node.child, context)) {
        BehaviorStatus.success => BehaviorStatus.failure,
        BehaviorStatus.failure => BehaviorStatus.success,
        BehaviorStatus.running => BehaviorStatus.running,
      },
      _AlwaysSucceed() => switch (_tick(node.child, context)) {
        BehaviorStatus.running => BehaviorStatus.running,
        _ => BehaviorStatus.success,
      },
      _Cooldown() => _cooldown(node, context),
      _Custom() => node.composite.tick(context..node = node.index, node.view),
    };
    _stack.removeLast();
    _statusOf[node.index] = status;
    return status;
  }

  BehaviorStatus _leaf(_Leaf node, BehaviorContext context) {
    // The path is the stack at the last leaf ticked: whatever comes out
    // running returns at once, so no leaf is ticked after the running one.
    _lastPath
      ..clear()
      ..addAll(_stack);
    context.node = node.index;
    return node.leaf.tick(context);
  }

  BehaviorStatus _sequence(_Sequence node, BehaviorContext context) {
    context.node = node.index;
    final from = switch (context.memory) {
      final num at => at.toInt(),
      _ => 0,
    };
    for (var i = from; i < node.children.length; i++) {
      final status = _tick(node.children[i], context);
      if (status == BehaviorStatus.success) continue;
      context.node = node.index;
      context.memory = status == BehaviorStatus.running ? i : null;
      return status;
    }
    context.node = node.index;
    context.memory = null;
    return BehaviorStatus.success;
  }

  BehaviorStatus _selector(_Selector node, BehaviorContext context) {
    for (final child in node.children) {
      final status = _tick(child, context);
      if (status != BehaviorStatus.failure) return status;
    }
    return BehaviorStatus.failure;
  }

  BehaviorStatus _utility(_Utility node, BehaviorContext context) {
    context.node = node.index;
    final last = switch (context.memory) {
      final num at => at.toInt(),
      _ => -1,
    };
    final best = node.choose(context, last);
    if (best < 0) {
      context.memory = null;
      return BehaviorStatus.failure;
    }
    final status = _tick(node.options[best].child, context);
    context.node = node.index;
    context.memory = status == BehaviorStatus.running ? best : null;
    return status;
  }

  BehaviorStatus _cooldown(_Cooldown node, BehaviorContext context) {
    final board = context.board;
    final readyAt = board.readyAt[node.index];
    if (readyAt != null && board.clock < readyAt) {
      return BehaviorStatus.failure;
    }
    final status = _tick(node.child, context);
    if (status != BehaviorStatus.running) {
      board.readyAt[node.index] = board.clock + node.seconds;
    }
    return status;
  }
}

sealed class _Node {
  _Node(this.index, this.kind, this.label);
  final int index;
  final String kind;
  final String label;
}

final class _Leaf extends _Node {
  _Leaf(super.index, super.kind, super.label, this.leaf);
  final BehaviorLeaf leaf;
}

final class _Sequence extends _Node {
  _Sequence(super.index, super.kind, super.label);
  final List<_Node> children = <_Node>[];
}

final class _Selector extends _Node {
  _Selector(super.index, super.kind, super.label);
  final List<_Node> children = <_Node>[];
}

final class _Invert extends _Node {
  _Invert(super.index, super.kind, super.label);
  late final _Node child;
}

final class _AlwaysSucceed extends _Node {
  _AlwaysSucceed(super.index, super.kind, super.label);
  late final _Node child;
}

final class _Cooldown extends _Node {
  _Cooldown(super.index, super.kind, super.label, this.seconds);

  /// How long the child is refused after it finishes, in seconds.
  final double seconds;
  late final _Node child;
}

/// A composite a game or plugin registered.
final class _Custom extends _Node {
  _Custom(super.index, super.kind, super.label, this.composite);
  final BehaviorComposite composite;
  final List<_Node> children = <_Node>[];
  late final BehaviorChildren view;
}

typedef _Option = ({
  double weight,
  List<Consideration> considerations,
  _Node child,
});

/// Scores every option and runs the best one.
///
/// **A score is the product of its considerations, times the option's
/// weight**, so any consideration at zero vetoes the option — "only when the
/// focus is in sight" is a consideration that answers nought otherwise — and
/// an option scoring nought is never chosen even when it is the only one.
///
/// **The option already running gets [inertia] added**, and that is what
/// stops an actor dithering on the line between two options whose scores
/// cross back and forth with every step. Ties go to the earlier option, so
/// the document's order is the tie-break and two runs agree on it.
final class _Utility extends _Node {
  _Utility(super.index, super.kind, super.label, this.inertia);

  /// The score added to the option already running, a unitless score in
  /// the options' own scale.
  final double inertia;
  final List<_Option> options = <_Option>[];

  int choose(BehaviorContext context, int last) {
    var best = -1;
    var bestScore = 0.0;
    for (var i = 0; i < options.length; i++) {
      final option = options[i];
      final score =
          option.considerations.fold(
            option.weight,
            (double product, consider) => product * consider(context),
          ) +
          (i == last ? inertia : 0.0);
      if (score > bestScore) {
        best = i;
        bestScore = score;
      }
    }
    return best;
  }
}

/// Builds nodes from a document, numbering them as it goes.
final class _Reader {
  _Reader(this.kinds);

  final BehaviorKinds kinds;
  final List<_Node> nodes = <_Node>[];
  final List<String> problems = <String>[];

  String? digestOf(Object? json) {
    try {
      return contentDigestHex((json! as Map).cast<String, Object?>());
    } on Object {
      // Already reported by [node]: a root that is not a JSON object.
      return null;
    }
  }

  _Node? node(Object? json, String where) {
    if (json is! Map) {
      problems.add('$where: a node is an object with a "kind"');
      return null;
    }
    final row = json.cast<Object?, Object?>();
    final kind = row['kind'];
    if (kind is! String) {
      problems.add('$where: a node is an object with a "kind"');
      return null;
    }
    final label = switch (row['name']) {
      final String name => name,
      _ => kind,
    };
    final index = nodes.length;
    switch (kind) {
      case 'sequence':
        final made = _Sequence(index, kind, label);
        nodes.add(made);
        made.children.addAll(_children(row, where));
        return made;
      case 'selector':
        final made = _Selector(index, kind, label);
        nodes.add(made);
        made.children.addAll(_children(row, where));
        return made;
      case 'invert':
        final made = _Invert(index, kind, label);
        nodes.add(made);
        final child = node(row['child'], '$where.child');
        if (child == null) return null;
        return made..child = child;
      case 'alwaysSucceed':
        final made = _AlwaysSucceed(index, kind, label);
        nodes.add(made);
        final child = node(row['child'], '$where.child');
        if (child == null) return null;
        return made..child = child;
      case 'cooldown':
        final params = BehaviorParameters(row, where, problems);
        final made = _Cooldown(index, kind, label, params.number('seconds'));
        nodes.add(made);
        final child = node(row['child'], '$where.child');
        if (child == null) return null;
        return made..child = child;
      case 'utility':
        final params = BehaviorParameters(row, where, problems);
        final made = _Utility(
          index,
          kind,
          label,
          params.number('inertia', 0.0),
        );
        nodes.add(made);
        made.options.addAll(_options(row, where));
        return made;
    }
    if (kinds.compositeBuilder(kind) case final CompositeBuilder composite) {
      final made = _Custom(
        index,
        kind,
        label,
        composite(BehaviorParameters(row, where, problems)),
      );
      nodes.add(made);
      // A decorator names one `child`; anything else lists `children`.
      if (row['child'] != null && row['children'] == null) {
        final child = node(row['child'], '$where.child');
        if (child == null) return null;
        made.children.add(child);
      } else {
        made.children.addAll(_children(row, where));
      }
      return made;
    }
    final build = kinds.leafBuilder(kind);
    if (build == null) {
      problems.add(
        '$where: no leaf kind "$kind"; known: ${kinds.describeKnown()}',
      );
      return null;
    }
    final made = _Leaf(
      index,
      kind,
      label,
      build(BehaviorParameters(row, where, problems)),
    );
    nodes.add(made);
    return made;
  }

  List<_Node> _children(Map<Object?, Object?> row, String where) {
    final children = row['children'];
    if (children is! List) {
      problems.add('$where: a ${row['kind']} lists its "children"');
      return const <_Node>[];
    }
    return <_Node>[
      for (var i = 0; i < children.length; i++)
        ?node(children[i], '$where.children[$i]'),
    ];
  }

  List<_Option> _options(Map<Object?, Object?> row, String where) {
    final options = row['options'];
    if (options is! List || options.isEmpty) {
      problems.add('$where: a utility lists its "options"');
      return const <_Option>[];
    }
    final read = <_Option>[];
    for (var i = 0; i < options.length; i++) {
      final at = '$where.options[$i]';
      final option = options[i];
      if (option is! Map) {
        problems.add('$at: an option is an object with "do"');
        continue;
      }
      final params = BehaviorParameters(option, at, problems);
      final weight = params.number('weight', 1.0);
      final considerations = _considerations(option['considerations'], at);
      // Named by the option when the child is not, so the overlay says
      // "flee" rather than the leaf kind the option happens to run.
      final body = option['do'];
      final named =
          body is Map && body['name'] == null && option['name'] is String
          ? <Object?, Object?>{...body, 'name': option['name']}
          : body;
      final child = node(named, '$at.do');
      if (child == null) continue;
      read.add((weight: weight, considerations: considerations, child: child));
    }
    return read;
  }

  List<Consideration> _considerations(Object? json, String where) {
    if (json == null) return const <Consideration>[];
    if (json is! List) {
      problems.add('$where: "considerations" is a list');
      return const <Consideration>[];
    }
    final read = <Consideration>[];
    for (var i = 0; i < json.length; i++) {
      final at = '$where.considerations[$i]';
      final row = json[i];
      final kind = row is Map ? row['kind'] : null;
      if (row is! Map || kind is! String) {
        problems.add('$at: a consideration is an object with a "kind"');
        continue;
      }
      final build = kinds.considerationBuilder(kind);
      if (build == null) {
        problems.add(
          '$at: no consideration kind "$kind"; known: '
          '${kinds.describeKnownConsiderations()}',
        );
        continue;
      }
      read.add(build(BehaviorParameters(row, at, problems)));
    }
    return read;
  }
}
