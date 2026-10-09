import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// What code a fixed step runs may not reach for, found in one compilation
/// unit.
///
/// **The same four questions `tool/structure.dart` asks of this repository,
/// asked of anybody's code.** Rules 7 and 34 there — "a step reaches for no
/// clock and no loose dice" and "a step asks no machine for an answer" — hold
/// the engine's own packages, and they read text, because the structure scan
/// runs before `pub get` and has no analyzer to ask. A plugin author has an
/// analyzer open all day; this is the same list, put where they will see it.
///
/// **Stronger than the text scan where a resolver can say more.** On a
/// resolved unit the question is what a name *is*, not how it is spelled:
/// `m.sin(x)` under `import 'dart:math' as m;` is the platform's libm whatever
/// the prefix, a bare `sin(x)` under an unprefixed import is too, and a class
/// of the author's own that happens to be called `Random` is not the one from
/// `dart:math`. On an unresolved unit — a test handing in `parseString`'s
/// result, a tool with no resolver — it falls back to the spelling the
/// structure rules match, plus whatever the unit's own imports say about its
/// prefixes.
///
/// **Code only, and the difference from the text scan is deliberate.** A
/// comment explaining why `DateTime.now()` would be wrong is not a call, and
/// neither is a string that spells one — the structure scan reads string
/// literals as code (it keeps what is between quotes), which this does not.
/// A message quoting a forbidden call is a sentence about the rule, not a
/// breach of it.
List<SimulationFinding> scanSimulationCode(CompilationUnit unit) {
  final visitor = _Scan(unit);
  unit.accept(visitor);
  return List<SimulationFinding>.unmodifiable(visitor.found);
}

/// One thing a step may not do, where it was found.
final class SimulationFinding {
  const SimulationFinding({
    required this.rule,
    required this.offset,
    required this.length,
    required this.what,
  });

  /// The rule's name: one of [SimulationRules.all].
  final String rule;

  /// Where in the source the offending node starts, and how long it is.
  final int offset;
  final int length;

  /// What was reached for, in a few words: `DateTime.now()`, `math.sin`.
  final String what;

  @override
  String toString() => '$rule at $offset: $what';
}

/// The names of the four rules, which are also their diagnostic codes.
abstract final class SimulationRules {
  /// `DateTime.now()` or a `Stopwatch`: the wall clock.
  static const String clock = 'step_reads_no_clock';

  /// `Random()` with no seed, or `Random.secure()`.
  static const String seededRandom = 'step_takes_seeded_random';

  /// A transcendental from `dart:math`, whose answer is the platform's libm.
  static const String portableMath = 'step_uses_portable_math';

  /// `import 'dart:math';` with no prefix.
  static const String prefixedMath = 'step_prefixes_dart_math';

  /// Every rule, in the order they are registered.
  static const List<String> all = <String>[
    clock,
    seededRandom,
    portableMath,
    prefixedMath,
  ];
}

/// The `dart:math` functions a step may not call, because their answer is
/// the host's libm on the VM and the browser's own routine on the web.
///
/// **`sqrt` is the one left out, and it belongs left out.** IEEE 754 requires
/// a correctly rounded square root, so there is one right answer and every
/// platform is obliged to give it. `pow` is in: it agreed on the VM and in a
/// browser on one machine, which looked like a guarantee and was two runtimes
/// sharing one host's libm — a third machine answered differently. The list
/// is `tool/structure/rules.dart`'s, and `mirrors_structure_test.dart` holds
/// the two together.
const Set<String> machineArithmetic = <String>{
  'sin',
  'cos',
  'tan',
  'asin',
  'acos',
  'atan2',
  'atan',
  'exp',
  'log',
  'pow',
};

const String _dartMath = 'dart:math';

bool _from(Element? element, String library) =>
    element?.library?.uri.toString() == library;

bool _fromCore(Element? element) => element?.library?.isDartCore ?? false;

final class _Scan extends RecursiveAstVisitor<void> {
  _Scan(CompilationUnit unit) {
    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      if (directive.uri.stringValue != _dartMath) continue;
      final prefix = directive.prefix;
      if (prefix == null) {
        _bareMath = true;
      } else {
        _mathPrefixes.add(prefix.name);
      }
    }
  }

  final List<SimulationFinding> found = <SimulationFinding>[];

  /// The prefixes `dart:math` is imported under in this unit, plus `math`,
  /// which is the spelling the structure rule reads when it knows nothing.
  final Set<String> _mathPrefixes = <String>{'math'};

  /// Whether `dart:math` is imported with no prefix, so a bare `sin(x)` is
  /// its `sin`.
  bool _bareMath = false;

  void _add(String rule, AstNode node, String what) => found.add(
    SimulationFinding(
      rule: rule,
      offset: node.offset,
      length: node.length,
      what: what,
    ),
  );

  @override
  void visitImportDirective(ImportDirective node) {
    // The structure rule refuses the exact text `import 'dart:math';`: an
    // import with a `show` or `hide` list is a different line, and one that
    // shows only `max` lets no transcendental in by a bare name anyway.
    if (node.uri.stringValue == _dartMath &&
        node.prefix == null &&
        node.combinators.isEmpty) {
      _add(SimulationRules.prefixedMath, node, "import 'dart:math';");
    }
    super.visitImportDirective(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final constructor = node.constructorName;
    final type = constructor.type;
    final className = type.name.lexeme;
    final named = constructor.name?.name;
    final element = type.element;
    final noArguments = node.argumentList.arguments.isEmpty;

    switch (className) {
      case 'DateTime' when named == 'now':
        if (element == null || _fromCore(element)) {
          _add(SimulationRules.clock, node, 'DateTime.now()');
        }
      case 'Stopwatch':
        if (element == null || _fromCore(element)) {
          _add(SimulationRules.clock, node, 'Stopwatch()');
        }
      case 'Random' when named == null && noArguments:
        if (element == null || _from(element, _dartMath)) {
          _add(SimulationRules.seededRandom, node, 'Random()');
        }
      case 'Random' when named == 'secure':
        if (element == null || _from(element, _dartMath)) {
          _add(SimulationRules.seededRandom, node, 'Random.secure()');
        }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final element = node.methodName.element;
    final target = node.target;
    final targetName = switch (target) {
      SimpleIdentifier(:final name) => name,
      _ => null,
    };
    final noArguments = node.argumentList.arguments.isEmpty;

    if (element != null) {
      // Resolved: what the name is decides, not how it was written. A
      // constructor call resolves to an instance creation instead, so only
      // the functions are left to ask about here.
      if (machineArithmetic.contains(name) &&
          element is TopLevelFunctionElement &&
          _from(element, _dartMath)) {
        _add(SimulationRules.portableMath, node, 'math.$name');
      }
    } else {
      // Unresolved: the spellings the structure rule matches. `DateTime.now`
      // and the two constructors parse as invocations until a resolver says
      // they are not.
      if (name == 'now' && targetName == 'DateTime' && noArguments) {
        _add(SimulationRules.clock, node, 'DateTime.now()');
      } else if (name == 'Stopwatch' &&
          (target == null || targetName != null)) {
        _add(SimulationRules.clock, node, 'Stopwatch()');
      } else if (name == 'Random' &&
          (target == null || targetName != null) &&
          noArguments) {
        _add(SimulationRules.seededRandom, node, 'Random()');
      } else if (name == 'secure' && targetName == 'Random') {
        _add(SimulationRules.seededRandom, node, 'Random.secure()');
      } else if (machineArithmetic.contains(name) &&
          ((targetName != null && _mathPrefixes.contains(targetName)) ||
              (target == null && _bareMath))) {
        _add(SimulationRules.portableMath, node, 'math.$name');
      }
    }
    super.visitMethodInvocation(node);
  }
}
