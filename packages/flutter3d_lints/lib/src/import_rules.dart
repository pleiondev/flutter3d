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

import 'import_scan.dart';

/// An import of an engine package's `internal.dart`, `builtin.dart` or
/// `src/` from a project's own code.
///
/// **Outside semver, so outside a project.** The engine's packages share
/// those libraries with each other and change them within a minor; the API
/// snapshot marks them so, and nothing a game builds on them survives an
/// upgrade it was promised would be safe.
final class AvoidEngineInternalImports extends AnalysisRule {
  /// The rule, under [EngineImportRules.internalImports].
  AvoidEngineInternalImports()
    : super(
        name: EngineImportRules.internalImports,
        description:
            'A project imports an engine package by its public library, not '
            'by internal.dart, builtin.dart or src/: those change in a minor.',
      );

  /// The diagnostic, with the URI as its one argument.
  static const LintCode code = LintCode(
    EngineImportRules.internalImports,
    '{0} is the engine\'s own, outside semver: it may change in any minor.',
    correctionMessage:
        'Import the package\'s public library; if what you need is only '
        'there, file an issue asking for it.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(this, _Reporter(this, context));
}

/// Flutter's `Matrix4` and the engine's meeting in one file, neither hidden.
///
/// **Two classes, one name.** `widgets.dart` exports `vector_math_64`'s
/// double-precision `Matrix4`; the engine's signatures take `vector_math`'s
/// single-precision one, which the `flutter3d` facade exports. A file that
/// imports both and writes `Matrix4` gets an ambiguous import, and a file
/// that hid the wrong one gets a type error between two `Matrix4`s. The fix
/// hides Flutter's, because in a file that talks to the engine the engine's
/// is the one a matrix is passed to; `toFlutter()` crosses back for a
/// `Transform`.
final class HideFlutterMatrix4 extends AnalysisRule {
  /// The rule, under [EngineImportRules.flutterMatrix4].
  HideFlutterMatrix4()
    : super(
        name: EngineImportRules.flutterMatrix4,
        description:
            'A file that imports Flutter and the engine hides Flutter\'s '
            'Matrix4, so Matrix4 names the single-precision one the engine '
            'takes.',
      );

  /// The diagnostic, with the Flutter library's URI as its one argument.
  static const LintCode code = LintCode(
    EngineImportRules.flutterMatrix4,
    '{0} exports Flutter\'s Matrix4, a different class from the one the '
    'engine takes.',
    correctionMessage:
        'Add `hide Matrix4` to this import, and convert with toFlutter() '
        'where a widget wants Flutter\'s.',
    severity: DiagnosticSeverity.WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) => registry.addCompilationUnit(this, _Reporter(this, context));
}

/// Runs the import scan once per unit and reports what carries [rule]'s
/// name.
final class _Reporter extends SimpleAstVisitor<void> {
  _Reporter(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    for (final finding in scanEngineImports(
      node,
      ownPackage: _packageName(context),
    )) {
      if (finding.rule != rule.name) continue;
      rule.reportAtOffset(
        finding.offset,
        finding.length,
        arguments: <Object>[finding.what],
      );
    }
  }
}

/// The name in the `pubspec.yaml` of the package [context]'s file is in,
/// or null when there is none to read.
String? _packageName(RuleContext context) {
  final pubspec = context.package?.root.getFile('pubspec.yaml');
  if (pubspec == null || !pubspec.exists) return null;
  final match = RegExp(
    r'^name:\s*([\w]+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  return match?.group(1);
}

/// The quick fix for [HideFlutterMatrix4]: `hide Matrix4` on the import the
/// diagnostic is on.
final class HideFlutterMatrix4Fix extends ResolvedCorrectionProducer {
  /// A fix producer for one diagnostic, as the plugin registry builds it.
  HideFlutterMatrix4Fix({required super.context});

  static const FixKind _kind = FixKind(
    'flutter3d.fix.hideFlutterMatrix4',
    DartFixKindPriority.standard,
    'Hide Flutter\'s Matrix4',
  );

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.acrossFiles;

  @override
  FixKind get fixKind => _kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final offset = diagnosticOffset;
    if (offset == null) return;
    final edits = scanEngineImports(unit)
        .where(
          (ImportFinding f) =>
              f.rule == EngineImportRules.flutterMatrix4 && f.offset == offset,
        )
        .map((ImportFinding f) => f.edit)
        .nonNulls;
    if (edits.isEmpty) return;
    final edit = edits.first;
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleInsertion(edit.offset, edit.text);
    });
  }
}
