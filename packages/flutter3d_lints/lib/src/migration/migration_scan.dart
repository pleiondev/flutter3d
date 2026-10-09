import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

import 'migration_rule.dart';

/// One replacement in a file's text.
final class MigrationEdit {
  const MigrationEdit(this.offset, this.length, this.replacement);
  final int offset;
  final int length;
  final String replacement;

  @override
  String toString() => 'at $offset replace $length with "$replacement"';
}

/// One use of the code that a [MigrationRule] matches.
final class MigrationFinding {
  const MigrationFinding({
    required this.rule,
    required this.offset,
    required this.length,
    required this.edits,
    required this.todo,
  });

  final MigrationRule rule;

  /// Where the use is: what the diagnostic underlines.
  final int offset;
  final int length;

  /// What carries the migration out, in this file; empty for a rule a
  /// person has to carry out, or a rewrite this scan will not risk.
  final List<MigrationEdit> edits;

  /// The `// TODO(flutter3d-1.0)` line the batch migrator inserts above the
  /// use when [edits] is empty: an insertion at the start of its line.
  final MigrationEdit todo;

  /// Whether the migration is done by [edits] alone.
  bool get automatic => edits.isNotEmpty;

  @override
  String toString() =>
      '${rule.id} at $offset${automatic ? ' (automatic)' : ''}';
}

/// The packages a rule's name may come from: this repository's.
bool ownedPackage(String package) =>
    package == 'flutter3d' ||
    package.startsWith('flutter3d_') ||
    package.startsWith('flame_flutter3d') ||
    package.startsWith('flame_multiplayer') ||
    package == 'pad_input' ||
    package == 'pointer_lock';

String? _packageOf(Element? element) {
  final uri = element?.library?.uri;
  if (uri == null || uri.scheme != 'package') return null;
  return uri.pathSegments.first;
}

/// Every use in [unit] — resolved, with its text [source] — that one of
/// [rules] matches.
///
/// **What the resolver buys.** `device.supportsWireframe` is a deprecated
/// capability getter only when `device` is a `GraphicsDevice`; a class of
/// the project's own that happens to have a `supportsWireframe` is left
/// alone. A name the resolver could not find — something 1.0 removed — is
/// matched by its spelling, because that is all that is left of it.
List<MigrationFinding> scanForMigrations(
  CompilationUnit unit,
  String source,
  List<MigrationRule> rules,
) {
  final scan = _Scan(unit, source, rules);
  unit.accept(scan);
  return List<MigrationFinding>.unmodifiable(scan.found);
}

final class _Scan extends RecursiveAstVisitor<void> {
  _Scan(this.unit, this.source, List<MigrationRule> rules)
    : byMember = <String, List<MigrationRule>>{
        for (final r in rules)
          if (r.member != null) r.member!: <MigrationRule>[],
      },
      byType = <String, List<MigrationRule>>{} {
    for (final r in rules) {
      if (r.member != null) {
        byMember[r.member!]!.add(r);
      } else {
        (byType[r.type] ??= <MigrationRule>[]).add(r);
      }
      if (r.switchOver case final over?) {
        (bySwitch[over] ??= <MigrationRule>[]).add(r);
      }
      for (final m in r.members) {
        (byListedMember[m] ??= <MigrationRule>[]).add(r);
      }
    }
  }

  final CompilationUnit unit;
  final String source;
  final Map<String, List<MigrationRule>> byMember;
  final Map<String, List<MigrationRule>> byType;
  final Map<String, List<MigrationRule>> bySwitch =
      <String, List<MigrationRule>>{};
  final Map<String, List<MigrationRule>> byListedMember =
      <String, List<MigrationRule>>{};
  final List<MigrationFinding> found = <MigrationFinding>[];
  final Set<(String, int)> _seen = <(String, int)>{};

  // ------------------------------------------------------------- findings

  void _add(
    MigrationRule rule,
    AstNode at, {
    List<MigrationEdit> edits = const <MigrationEdit>[],
  }) {
    if (!_seen.add((rule.id, at.offset))) return;
    found.add(
      MigrationFinding(
        rule: rule,
        offset: at.offset,
        length: at.length,
        edits: edits,
        todo: _todoFor(rule, at),
      ),
    );
  }

  MigrationEdit _todoFor(MigrationRule rule, AstNode at) {
    // Above the statement, member or directive the use is in, so the
    // comment does not split an expression.
    AstNode anchor = at;
    for (AstNode? n = at; n != null; n = n.parent) {
      if (n is Statement ||
          n is ClassMember ||
          n is Directive ||
          n is CompilationUnitMember) {
        anchor = n;
        if (n is! Block) break;
      }
    }
    // Above a declaration's doc comment, not inside it: a `//` line between
    // `///` and the declaration would part the comment from what it
    // documents.
    final start = anchor.offset;
    final lineStart = source.lastIndexOf('\n', start - 1) + 1;
    final indent = RegExp(
      r'^[ \t]*',
    ).stringMatch(source.substring(lineStart, start))!;
    return MigrationEdit(
      lineStart,
      0,
      '$indent// TODO(flutter3d-1.0): ${rule.message} See ${rule.link}\n',
    );
  }

  // -------------------------------------------------------------- members

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    final rules = <MigrationRule>[...?byMember[name], ...?byListedMember[name]];
    if (rules.isNotEmpty && !node.inDeclarationContext()) {
      for (final rule in rules) {
        if (_isMemberOf(node, rule)) _member(node, rule);
      }
    }
    // A type used as a value or a receiver: `GameLoop.x`, a tear-off.
    final typeRules = byType[name];
    if (typeRules != null &&
        !node.inDeclarationContext() &&
        node.parent is! NamedType) {
      final element = node.element;
      for (final rule in typeRules) {
        if (rule.kind != MigrationKind.manual ||
            rule.match != MigrationMatch.uses ||
            rule.members.isNotEmpty) {
          continue;
        }
        if (element is InterfaceElement || element is TypeAliasElement) {
          if (_ownedAs(element, rule)) _add(rule, node);
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  bool _ownedAs(Element? element, MigrationRule rule) {
    final package = _packageOf(element);
    return package != null && ownedPackage(package);
  }

  /// Whether [node] names member [MigrationRule.member] (or one of
  /// [MigrationRule.members]) of [MigrationRule.type].
  bool _isMemberOf(SimpleIdentifier node, MigrationRule rule) {
    final element = node.element;
    final receiver = _receiverType(node);
    if (element != null) {
      if (!_ownedAs(element, rule)) return false;
      final enclosing = element.enclosingElement;
      if (enclosing is InterfaceElement &&
          _isOrExtends(enclosing.thisType, rule.type)) {
        return true;
      }
      if (element is ConstructorElement &&
          element.enclosingElement.name == rule.type &&
          node.name == rule.type) {
        return true;
      }
      return receiver != null && _isOrExtends(receiver, rule.type);
    }
    // Gone: a member nothing declares any more, on a receiver that still
    // resolves to the type.
    return receiver != null &&
        _isOrExtends(receiver, rule.type) &&
        _ownedAs(receiver.element, rule);
  }

  InterfaceType? _receiverType(SimpleIdentifier node) {
    final parent = node.parent;
    final DartType? type = switch (parent) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier == node =>
        prefix.staticType,
      PropertyAccess(:final realTarget, :final propertyName)
          when propertyName == node =>
        realTarget.staticType,
      MethodInvocation(:final realTarget?, :final methodName)
          when methodName == node =>
        realTarget.staticType,
      _ => _enclosingThis(node),
    };
    return type is InterfaceType ? type : null;
  }

  DartType? _enclosingThis(AstNode node) {
    for (AstNode? n = node; n != null; n = n.parent) {
      if (n is ClassDeclaration) {
        return n.declaredFragment?.element.thisType;
      }
      if (n is MixinDeclaration) return n.declaredFragment?.element.thisType;
      if (n is EnumDeclaration) return n.declaredFragment?.element.thisType;
    }
    return null;
  }

  static bool _isOrExtends(InterfaceType type, String name) =>
      type.element.name == name ||
      type.allSupertypes.any((InterfaceType s) => s.element.name == name);

  void _member(SimpleIdentifier node, MigrationRule rule) {
    if (rule.kind != MigrationKind.rewrite) {
      if (rule.kind == MigrationKind.manual &&
          rule.match == MigrationMatch.uses) {
        _add(rule, node);
      }
      return;
    }
    final parent = node.parent;
    // An assignment is to a setter the rewrite does not describe.
    if (parent is AssignmentExpression ||
        (parent is PrefixedIdentifier &&
            parent.parent is AssignmentExpression &&
            (parent.parent! as AssignmentExpression).leftHandSide == parent) ||
        (parent is PropertyAccess &&
            parent.parent is AssignmentExpression &&
            (parent.parent! as AssignmentExpression).leftHandSide == parent)) {
      _add(rule, node);
      return;
    }
    final (
      AstNode whole,
      Expression? target,
      bool nullAware,
      List<AstNode> args,
    ) = switch (parent) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier == node =>
        (parent, prefix, false, const <AstNode>[]),
      PropertyAccess(:final target, :final propertyName, :final operator)
          when propertyName == node && target != null =>
        (
          parent,
          target,
          operator.type == TokenType.QUESTION_PERIOD,
          const <AstNode>[],
        ),
      MethodInvocation(
        :final target,
        :final methodName,
        :final argumentList,
        :final operator,
      )
          when methodName == node =>
        (
          parent,
          target,
          operator?.type == TokenType.QUESTION_PERIOD,
          <AstNode>[...argumentList.arguments],
        ),
      _ => (node, null, false, const <AstNode>[]),
    };
    // A cascade's receiver is not written where the rewrite needs it, and
    // a null-aware access changes the type the rewrite would produce.
    if (nullAware ||
        (whole is PropertyAccess && whole.isCascaded) ||
        (whole is MethodInvocation && whole.isCascaded) ||
        args.any((AstNode a) => a is NamedArgument)) {
      _add(rule, node);
      return;
    }
    var text = rule.template!;
    if (target == null) {
      text = text.replaceAll('{target}.', '').replaceAll('{target}', 'this');
    } else {
      text = text.replaceAll('{target}', _operand(target));
    }
    for (var i = 0; i < args.length; i++) {
      text = text.replaceAll('{$i}', _text(args[i]));
    }
    if (RegExp(r'\{\d+\}').hasMatch(text)) {
      _add(rule, node);
      return;
    }
    _add(
      rule,
      node,
      edits: <MigrationEdit>[
        MigrationEdit(whole.offset, whole.length, text),
        ..._importsFor(rule),
      ],
    );
  }

  String _text(AstNode node) => source.substring(node.offset, node.end);

  /// [target]'s text, in parentheses when it is not a primary.
  String _operand(Expression target) {
    final text = _text(target);
    final primary =
        target is Identifier ||
        target is PropertyAccess ||
        target is MethodInvocation ||
        target is ParenthesizedExpression ||
        target is ThisExpression ||
        target is SuperExpression ||
        target is IndexExpression ||
        target is InstanceCreationExpression ||
        target is FunctionExpressionInvocation;
    return primary ? text : '($text)';
  }

  /// The imports [rule]'s template needs that this library cannot see yet.
  List<MigrationEdit> _importsFor(MigrationRule rule) {
    if (rule.imports.isEmpty) return const <MigrationEdit>[];
    final scope = unit.declaredFragment?.scope;
    final names = RegExp(r'\b([A-Z][\w$]*)\b')
        .allMatches(rule.template!.replaceAll(RegExp(r'\{[^}]*\}'), ''))
        .map((Match m) => m.group(1)!)
        .toSet();
    final missing =
        scope != null &&
        names.any((String n) => scope.lookup(n).getter == null);
    if (!missing) return const <MigrationEdit>[];
    final already = unit.directives.whereType<ImportDirective>().map(
      (ImportDirective d) => d.uri.stringValue,
    );
    final directives = unit.directives;
    final at = directives.isEmpty ? 0 : directives.last.end;
    return <MigrationEdit>[
      for (final uri in rule.imports)
        if (!already.contains(uri))
          MigrationEdit(
            at,
            0,
            "${directives.isEmpty ? '' : '\n'}import '$uri';"
            "${directives.isEmpty ? '\n' : ''}",
          ),
    ];
  }

  // ---------------------------------------------------------------- types

  @override
  void visitNamedType(NamedType node) {
    final rules = byType[node.name.lexeme];
    if (rules != null) {
      final element = node.element;
      final resolved = element != null && _ownedAs(element, rules.first);
      final gone = element == null;
      if (resolved || gone) {
        final parent = node.parent;
        // A mixin brings its new members' bodies with it; an implementer
        // or a subclass is who writes them.
        final inClause = parent is ImplementsClause || parent is ExtendsClause;
        for (final rule in rules) {
          switch (rule.kind) {
            case MigrationKind.implementsToWith:
              if (parent is ImplementsClause && resolved) {
                _implementsToWith(node, parent, rule);
              }
            case MigrationKind.manual:
              final wanted = switch (rule.match) {
                MigrationMatch.uses =>
                  rule.members.isEmpty ||
                      (rule.members.contains(rule.type) &&
                          parent is ConstructorName),
                MigrationMatch.subtypes => inClause,
                MigrationMatch.switches => false,
              };
              if (wanted) _add(rule, node);
            case MigrationKind.rewrite:
              break;
          }
        }
      }
    }
    super.visitNamedType(node);
  }

  void _implementsToWith(
    NamedType type,
    ImplementsClause clause,
    MigrationRule rule,
  ) {
    final declaration = clause.parent;
    if (declaration is! ClassDeclaration && declaration is! EnumDeclaration) {
      // A mixin cannot mix in; what it needs is an `on` clause, a choice.
      _add(rule, type);
      return;
    }
    final edits = <MigrationEdit>[];
    final typeText = _text(type);
    // Out of `implements`.
    if (clause.interfaces.length == 1) {
      final start = clause.implementsKeyword.previous!.end;
      edits.add(MigrationEdit(start, clause.end - start, ''));
    } else {
      final index = clause.interfaces.indexOf(type);
      final start = index == 0 ? type.offset : clause.interfaces[index - 1].end;
      final end = index == 0 ? clause.interfaces[1].offset : type.end;
      edits.add(MigrationEdit(start, end - start, ''));
    }
    // Into `with`.
    final WithClause? withClause = switch (declaration) {
      ClassDeclaration(:final withClause) => withClause,
      EnumDeclaration(:final withClause) => withClause,
      _ => null,
    };
    if (withClause != null) {
      edits.add(MigrationEdit(withClause.end, 0, ', $typeText'));
    } else {
      final after = switch (declaration) {
        ClassDeclaration(:final extendsClause?) => extendsClause.end,
        ClassDeclaration(:final namePart) => namePart.end,
        EnumDeclaration(:final namePart) => namePart.end,
        _ => clause.offset,
      };
      edits.add(MigrationEdit(after, 0, ' with $typeText'));
    }
    // A class that mixes in a base mixin is base, final or sealed itself.
    if (declaration is ClassDeclaration &&
        declaration.baseKeyword == null &&
        declaration.finalKeyword == null &&
        declaration.sealedKeyword == null) {
      final keyword =
          declaration.interfaceKeyword ??
          declaration.mixinKeyword ??
          declaration.classKeyword;
      if (declaration.interfaceKeyword != null) {
        // `interface` and `base` together are `final` to outside code;
        // leave that decision to a person.
        _add(rule, type);
        return;
      }
      edits.add(MigrationEdit(keyword.offset, 0, 'base '));
    }
    _add(rule, type, edits: edits);
  }

  // ------------------------------------------------------------- switches

  @override
  void visitSwitchStatement(SwitchStatement node) {
    _switch(
      node,
      node.expression,
      node.members.any(
        (SwitchMember m) =>
            m is SwitchDefault ||
            (m is SwitchPatternCase &&
                m.guardedPattern.whenClause == null &&
                _catchAll(m.guardedPattern.pattern)),
      ),
    );
    super.visitSwitchStatement(node);
  }

  @override
  void visitSwitchExpression(SwitchExpression node) {
    _switch(
      node,
      node.expression,
      node.cases.any(
        (SwitchExpressionCase c) =>
            c.guardedPattern.whenClause == null &&
            _catchAll(c.guardedPattern.pattern),
      ),
    );
    super.visitSwitchExpression(node);
  }

  static bool _catchAll(DartPattern p) =>
      p is WildcardPattern && p.type == null ||
      p is DeclaredVariablePattern && p.type == null;

  void _switch(AstNode node, Expression scrutinee, bool hasDefault) {
    if (hasDefault) return;
    final type = scrutinee.staticType;
    if (type is! InterfaceType) return;
    for (final over in <String>{
      type.element.name ?? '',
      ...type.allSupertypes.map((InterfaceType s) => s.element.name ?? ''),
    }) {
      for (final rule in bySwitch[over] ?? const <MigrationRule>[]) {
        if (_ownedAs(type.element, rule)) _add(rule, scrutinee);
      }
    }
  }

  // -------------------------------------------------------------- imports

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      for (final rule in byType[uri] ?? const <MigrationRule>[]) {
        _add(rule, node);
      }
    }
    super.visitImportDirective(node);
  }
}
