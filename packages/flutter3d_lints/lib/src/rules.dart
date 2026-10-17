import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import 'simulation_scan.dart';

/// The four rules, as the analysis server takes them: each reports the
/// findings of [scanSimulationCode] that carry its name.
///
/// **One scan, four doors.** Each rule is a code of its own so that a line
/// can silence one of them — `// ignore: flutter3d_lints/step_reads_no_clock`
/// on the profiler that times a step from outside it — and keep the others.
/// Read by the plugin in `main.dart`, and by a tool that runs the rules
/// itself.
List<AnalysisRule> simulationRules() => <AnalysisRule>[
  StepReadsNoClock(),
  StepTakesSeededRandom(),
  StepUsesPortableMath(),
  StepPrefixesDartMath(),
];

/// `DateTime.now()` and `Stopwatch` in code a fixed step runs.
///
/// **A step reads no clock.** The wall clock reaches a step only as a count
/// of steps; a system that reads it computes something else on every run,
/// and a replay of a recorded run stops being the run.
final class StepReadsNoClock extends AnalysisRule {
  StepReadsNoClock()
    : super(
        name: SimulationRules.clock,
        description:
            'Code a fixed step runs reads no wall clock: DateTime.now() and '
            'Stopwatch are different on every run.',
      );

  static const LintCode code = LintCode(
    SimulationRules.clock,
    '{0} reads the wall clock, which a step may not: a replay of the run '
    'would read another time.',
    correctionMessage:
        'Use the step count and the step\'s dt from the LoopContext, or move '
        'this out of the step.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(this, _Reporter(this));
}

/// `Random()` with no seed, and `Random.secure()`, in code a fixed step runs.
///
/// **A step takes its dice from a generator it was handed.** A seeded
/// `Random(n)` is written down and comes back the same, so it is not on
/// trial; an unseeded one is seeded from the machine, and a secure one from
/// the operating system, and neither comes back.
final class StepTakesSeededRandom extends AnalysisRule {
  StepTakesSeededRandom()
    : super(
        name: SimulationRules.seededRandom,
        description:
            'Code a fixed step runs takes randomness from a seeded generator: '
            'GameRandom, or Random(seed).',
      );

  static const LintCode code = LintCode(
    SimulationRules.seededRandom,
    '{0} is seeded by the machine, so a replay rolls other dice.',
    correctionMessage:
        'Use a GameRandom the step was handed and that the snapshot saves, '
        'or a Random with a seed that is written down.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(this, _Reporter(this));
}

/// A `dart:math` transcendental in code a fixed step runs.
///
/// **A step asks no machine for an answer.** `sin`, `exp` and the rest are
/// the host's libm on the VM and the browser's routine on the web, and they
/// give different last bits; a car built from them diverged at twenty-three
/// of forty checkpoints between two platforms. `Portable` answers the same
/// questions out of the arithmetic IEEE 754 pins.
final class StepUsesPortableMath extends AnalysisRule {
  StepUsesPortableMath()
    : super(
        name: SimulationRules.portableMath,
        description:
            'Code a fixed step runs calls Portable, not dart:math, for a '
            'transcendental: dart:math answers with the platform\'s libm.',
      );

  static const LintCode code = LintCode(
    SimulationRules.portableMath,
    '{0} answers with the platform\'s libm, so two platforms step to '
    'different worlds.',
    correctionMessage:
        'Call the Portable function of the same name from flutter3d_sim.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(this, _Reporter(this));
}

/// `import 'dart:math';` with no prefix.
///
/// **Kept to mirror the structure rule, which needs it more than this does.**
/// A text scan cannot see a bare `sin(x)` for what it is, so this repository
/// refuses the unprefixed import outright. With a resolver,
/// [StepUsesPortableMath] already knows a bare `sin` is `dart:math`'s; what
/// this adds is that a reader of the file can see it too.
final class StepPrefixesDartMath extends AnalysisRule {
  StepPrefixesDartMath()
    : super(
        name: SimulationRules.prefixedMath,
        description:
            'Code a fixed step runs imports dart:math with a prefix, so every '
            'call into it reads as one.',
      );

  static const LintCode code = LintCode(
    SimulationRules.prefixedMath,
    "dart:math is imported without a prefix, so a bare sin(x) does not read "
    'as the platform\'s.',
    correctionMessage: "Import it as math: import 'dart:math' as math;",
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(this, _Reporter(this));
}

/// Runs the scan once per unit and reports what carries [rule]'s name.
final class _Reporter extends SimpleAstVisitor<void> {
  _Reporter(this.rule);

  final AnalysisRule rule;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    for (final finding in scanSimulationCode(node)) {
      if (finding.rule != rule.name) continue;
      rule.reportAtOffset(
        finding.offset,
        finding.length,
        arguments: <Object>[finding.what],
      );
    }
  }
}
