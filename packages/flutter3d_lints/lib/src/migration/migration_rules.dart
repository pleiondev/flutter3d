import 'package:analysis_server_plugin/edit/change_builder/change_builder.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analysis_server_plugin/edit/fix/fix.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';

import 'migration_rule.dart';
import 'migration_scan.dart';
import 'table.g.dart';

/// The code a migration diagnostic carries, and the name a project turns
/// it off by.
abstract final class MigrationCodes {
  /// A use the migration can rewrite: a quick fix is offered.
  static const String fixable = 'flutter3d_migrate';

  /// A use a person has to change, with the guide's line for it.
  static const String manual = 'flutter3d_migrate_by_hand';
}

/// Uses of what 1.0 changed that `dart fix` cannot carry out, from the
/// migration table: warnings with a quick fix where the change can be
/// written, and with the guide's link where it cannot.
///
/// **Why not `dart fix`.** A rename, a moved name and a parameter are data
/// `dart fix` applies from each package's `fix_data.yaml`. What is here
/// needs the resolved code: whether `device` in `device.supportsWireframe`
/// is a `GraphicsDevice`, which clauses a class already has. A plugin's
/// fixes are offered in the editor one at a time; `dart run
/// flutter3d_lints:migrate` applies all of them across a project, through
/// the same scan.
final class Flutter3dMigrationRule extends AnalysisRule {
  Flutter3dMigrationRule()
    : super(
        name: MigrationCodes.fixable,
        description:
            'Code written against flutter3d 0.8 that 1.0 changed, where the '
            'change can be written for you.',
      );

  static const LintCode code = LintCode(
    MigrationCodes.fixable,
    '{0}',
    correctionMessage:
        'Apply the quick fix, or run '
        '`dart run flutter3d_lints:migrate` for the whole project.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(
    this,
    _Reporter(this, context, automatic: true),
  );
}

/// The uses a person has to change: [Flutter3dMigrationRule]'s other half.
final class ManualMigrationRule extends AnalysisRule {
  ManualMigrationRule()
    : super(
        name: MigrationCodes.manual,
        description:
            'Code written against flutter3d 0.8 that 1.0 changed in a way a '
            'person has to decide.',
      );

  static const LintCode code = LintCode(
    MigrationCodes.manual,
    '{0}',
    correctionMessage: 'The migration guide has the details: {1}',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(
    this,
    _Reporter(this, context, automatic: false),
  );
}

final class _Reporter extends SimpleAstVisitor<void> {
  _Reporter(this.rule, this.context, {required this.automatic});

  final AnalysisRule rule;
  final RuleContext context;
  final bool automatic;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final source = context.currentUnit?.content;
    if (source == null) return;
    for (final finding in scanForMigrations(node, source, migrationRules)) {
      if (finding.automatic != automatic) continue;
      rule.reportAtOffset(
        finding.offset,
        finding.length,
        arguments: <Object>[finding.rule.message, finding.rule.link],
      );
    }
  }
}

/// The quick fix for [Flutter3dMigrationRule]: the scan's own edits for the use the
/// diagnostic is on.
final class ApplyMigration extends ResolvedCorrectionProducer {
  ApplyMigration({required super.context});

  static const FixKind _kind = FixKind(
    'flutter3d.fix.migrate',
    DartFixKindPriority.standard,
    'Apply the flutter3d 1.0 migration',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final offset = diagnosticOffset;
    if (offset == null) return;
    final finding = scanForMigrations(
      unit,
      unitResult.content,
      migrationRules,
    ).where((MigrationFinding f) => f.automatic && f.offset == offset);
    if (finding.isEmpty) return;
    final edits = finding.first.edits.toList()
      ..sort((MigrationEdit a, MigrationEdit b) => b.offset - a.offset);
    await builder.addDartFileEdit(file, (builder) {
      for (final edit in edits) {
        builder.addSimpleReplacement(
          SourceRange(edit.offset, edit.length),
          edit.replacement,
        );
      }
    });
  }
}

/// The table the rules check against, for tooling that runs the scan.
List<MigrationRule> get flutter3dMigrationRules => migrationRules;
