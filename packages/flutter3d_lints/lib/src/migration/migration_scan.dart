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
  scan.finishInternal();
  return List<MigrationFinding>.unmodifiable(scan.found);
}

final class _Scan extends RecursiveAstVisitor<void> {
  _Scan(this.unit, this.source, List<MigrationRule> rules) {
    void into(
      Map<String, List<MigrationRule>> map,
      String key,
      MigrationRule r,
    ) => (map[key] ??= <MigrationRule>[]).add(r);
    for (final r in rules) {
      switch (r.kind) {
        case MigrationKind.internal:
          if (r.library) {
            internalByUri[r.type] = r;
          } else {
            into(internalByName, r.type, r);
          }
          continue;
        case MigrationKind.regroup:
          into(regroups, r.member ?? r.type, r);
          continue;
        case MigrationKind.enumToClass:
          into(openedSwitches, r.switchOver ?? r.type, r);
          continue;
        case MigrationKind.recordToClass:
          into(records, r.type, r);
          recordFields.addAll(r.fields.keys);
          continue;
        case MigrationKind.nullToThrow:
          into(throwers, r.member ?? r.type, r);
          continue;
        case MigrationKind.rewrite ||
            MigrationKind.implementsToWith ||
            MigrationKind.manual:
          break;
      }
      if (r.member != null) {
        into(byMember, r.member!, r);
      } else {
        into(byType, r.type, r);
      }
      if (r.switchOver case final over?) into(bySwitch, over, r);
      for (final m in r.members) {
        into(byListedMember, m, r);
      }
    }
  }

  final CompilationUnit unit;
  final String source;
  final Map<String, List<MigrationRule>> byMember =
      <String, List<MigrationRule>>{};
  final Map<String, List<MigrationRule>> byType =
      <String, List<MigrationRule>>{};
  final Map<String, List<MigrationRule>> bySwitch =
      <String, List<MigrationRule>>{};
  final Map<String, List<MigrationRule>> byListedMember =
      <String, List<MigrationRule>>{};

  /// `internal` rules by the name they stand for, and by library URI.
  final Map<String, List<MigrationRule>> internalByName =
      <String, List<MigrationRule>>{};
  final Map<String, MigrationRule> internalByUri = <String, MigrationRule>{};

  /// `regroup` rules by the name of what is called: a function, a method,
  /// or the class of a constructor.
  final Map<String, List<MigrationRule>> regroups =
      <String, List<MigrationRule>>{};

  /// `enumToClass` rules by the type switched over.
  final Map<String, List<MigrationRule>> openedSwitches =
      <String, List<MigrationRule>>{};

  /// `recordToClass` rules by the class, and every record field they map.
  final Map<String, List<MigrationRule>> records =
      <String, List<MigrationRule>>{};
  final Set<String> recordFields = <String>{};

  /// `nullToThrow` rules by the name of what is called.
  final Map<String, List<MigrationRule>> throwers =
      <String, List<MigrationRule>>{};

  /// The internal names this unit uses, by package, in the order met, and
  /// the node of the first use of each package.
  final Map<String, Map<String, MigrationRule>> _internalUses =
      <String, Map<String, MigrationRule>>{};
  final Map<String, AstNode> _firstInternalUse = <String, AstNode>{};

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
    final lineStart = _lineStart(start);
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
    if (!node.inDeclarationContext()) {
      if (internalByName[name] case final rules?
          when node.element == null && !_isQualifiedMember(node)) {
        _useInternal(rules.first, name, node);
      }
      if (recordFields.contains(name)) _recordField(node);
      for (final rule in throwers[name] ?? const <MigrationRule>[]) {
        if (_callMatches(node, rule)) _nullToThrow(node, rule);
      }
      if (node.parent case MethodInvocation(
        :final methodName,
        :final argumentList,
      ) when methodName == node) {
        for (final rule in regroups[name] ?? const <MigrationRule>[]) {
          if (_callMatches(node, rule)) _regroup(argumentList, rule);
        }
      }
    }
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
  ///
  /// [named] are the names it brings in; a rewrite's are those of its
  /// template.
  List<MigrationEdit> _importsFor(MigrationRule rule, [Set<String>? named]) {
    if (rule.imports.isEmpty) return const <MigrationEdit>[];
    final scope = unit.declaredFragment?.scope;
    final names =
        named ??
        RegExp(r'\b([A-Z][\w$]*)\b')
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
    if (internalByName[node.name.lexeme] case final rules?
        when node.element == null) {
      _useInternal(rules.first, node.name.lexeme, node);
    }
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
            // Only the three above are kept by type; the rest have maps of
            // their own.
            case MigrationKind.rewrite ||
                MigrationKind.regroup ||
                MigrationKind.enumToClass ||
                MigrationKind.recordToClass ||
                MigrationKind.nullToThrow ||
                MigrationKind.internal:
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
      for (final rule in openedSwitches[over] ?? const <MigrationRule>[]) {
        if (!_ownedAs(type.element, rule)) continue;
        final edit = _wildcard(node, rule);
        _add(
          rule,
          scrutinee,
          edits: edit == null ? const <MigrationEdit>[] : <MigrationEdit>[edit],
        );
      }
    }
  }

  /// The wildcard that throws, with its TODO, after the last case of
  /// [node]; null for a switch with no case to put it after.
  MigrationEdit? _wildcard(AstNode node, MigrationRule rule) {
    switch (node) {
      case SwitchExpression(:final cases) when cases.isNotEmpty:
        final last = cases.last;
        final indent = _indentOf(last.offset);
        final comma = last.endToken.next;
        final hasComma = comma != null && comma.type == TokenType.COMMA;
        return MigrationEdit(
          hasComma ? comma.end : last.end,
          0,
          '${hasComma ? '' : ','}\n$indent${_todoText(rule)}\n'
          '${indent}_ => throw UnimplementedError(),',
        );
      case SwitchStatement(:final members) when members.isNotEmpty:
        final last = members.last;
        final indent = _indentOf(last.offset);
        return MigrationEdit(
          last.end,
          0,
          '\n$indent${_todoText(rule)}\n${indent}default:\n'
          '$indent  throw UnimplementedError();',
        );
    }
    return null;
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
  // ------------------------------------------------------------- internal

  /// Whether [node] is a member named through a receiver (`x.name`), which
  /// a top-level name gone internal cannot be; an import prefix is not one.
  static bool _isQualifiedMember(SimpleIdentifier node) =>
      switch (node.parent) {
        PrefixedIdentifier(:final prefix, :final identifier) =>
          identifier == node && prefix.element is! PrefixElement,
        PropertyAccess(:final propertyName) => propertyName == node,
        MethodInvocation(:final methodName, :final target) =>
          methodName == node &&
              target != null &&
              !(target is SimpleIdentifier && target.element is PrefixElement),
        _ => false,
      };

  void _useInternal(MigrationRule rule, String name, AstNode at) {
    (_internalUses[rule.package] ??= <String, MigrationRule>{})[name] ??= rule;
    _firstInternalUse[rule.package] ??= at;
  }

  /// One finding per import of each package whose internal names the unit
  /// used — or, with no import of it, per import of the engine's, which is
  /// how the names arrived through the facade — naming every name used.
  void finishInternal() {
    if (internalByUri.isNotEmpty) {
      for (final d in unit.directives.whereType<ImportDirective>()) {
        if (internalByUri[d.uri.stringValue] case final rule?) {
          _useInternal(rule, rule.type, d);
        }
      }
    }
    final imports = unit.directives.whereType<ImportDirective>().toList();
    String packageOf(ImportDirective d) {
      final uri = d.uri.stringValue ?? '';
      return uri.startsWith('package:')
          ? uri.substring(8).split('/').first
          : '';
    }

    for (final MapEntry(key: package, value: uses) in _internalUses.entries) {
      final names = uses.keys.toList();
      final first = uses.values.first;
      final since = RegExp(
        r'since (\S+)\.$',
      ).firstMatch(first.message)?.group(1);
      final instead = <String>{for (final r in uses.values) ?r.instead};
      final one = names.length == 1;
      final listed = one
          ? '`${names.single}`'
          : '${names.take(names.length - 1).map((String n) => '`$n`').join(', ')} '
                'and `${names.last}`';
      final rule = MigrationRule(
        id: 'internal-$package',
        kind: MigrationKind.internal,
        package: package,
        type: package,
        message:
            '$listed ${one ? 'was' : 'were'} $package\'s own and '
            '${one ? 'is' : 'are'} not exported'
            '${since == null ? '' : ' since $since'}.'
            '${instead.map((String i) => ' $i').join()}',
        link: first.link,
      );
      final own = imports.where((ImportDirective d) => packageOf(d) == package);
      final engine = imports.where(
        (ImportDirective d) => ownedPackage(packageOf(d)),
      );
      final at = <AstNode>[...(own.isNotEmpty ? own : engine)];
      for (final node
          in at.isEmpty ? <AstNode>[_firstInternalUse[package]!] : at) {
        _add(rule, node);
      }
    }
  }

  // -------------------------------------------------------------- regroup

  /// Whether [node], the name of a call, is the call [rule] is about: a
  /// top-level function of the engine's named [MigrationRule.type], or the
  /// member [MigrationRule.member] of that type.
  bool _callMatches(SimpleIdentifier node, MigrationRule rule) {
    if (rule.member == null) {
      final element = node.element;
      return node.name == rule.type &&
          element != null &&
          element.enclosingElement is LibraryElement &&
          _ownedAs(element, rule);
    }
    return node.name == rule.member && _isMemberOf(node, rule);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final name = node.constructorName;
    for (final rule
        in regroups[name.type.name.lexeme] ?? const <MigrationRule>[]) {
      if (name.name?.name == rule.member && _ownedAs(name.type.element, rule)) {
        _regroup(node.argumentList, rule);
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  /// The named arguments [MigrationRule.members] of [arguments] moved into
  /// one `into: Options(…)`, where the first of them was. A call that
  /// already passes `into` is a person's to merge.
  void _regroup(ArgumentList arguments, MigrationRule rule) {
    final all = arguments.arguments;
    final moved = <NamedArgument>[
      for (final a in all)
        if (a is NamedArgument && rule.members.contains(a.name.lexeme)) a,
    ];
    if (moved.isEmpty) return;
    final already = all.any(
      (Argument a) => a is NamedArgument && a.name.lexeme == rule.into,
    );
    if (already) {
      _add(rule, moved.first);
      return;
    }
    _add(
      rule,
      moved.first,
      edits: <MigrationEdit>[
        MigrationEdit(
          moved.first.offset,
          moved.first.length,
          '${rule.into}: ${rule.options}('
          '${moved.map(_text).join(', ')})',
        ),
        for (final m in moved.skip(1))
          MigrationEdit(
            all[all.indexOf(m) - 1].end,
            m.end - all[all.indexOf(m) - 1].end,
            '',
          ),
        ..._importsFor(rule, <String>{?rule.options}),
      ],
    );
  }

  // -------------------------------------------------------- recordToClass

  /// `.$1` of a value of a record that became a class: the getter the rule
  /// maps it to.
  void _recordField(SimpleIdentifier node) {
    final target = switch (node.parent) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier == node =>
        prefix,
      PropertyAccess(:final realTarget, :final propertyName)
          when propertyName == node =>
        realTarget,
      _ => null,
    };
    final type = target?.staticType;
    if (type is! InterfaceType) return;
    for (final rule in records[type.element.name] ?? const <MigrationRule>[]) {
      final getter = rule.fields[node.name];
      if (getter == null || !_ownedAs(type.element, rule)) continue;
      _add(
        rule,
        node,
        edits: <MigrationEdit>[MigrationEdit(node.offset, node.length, getter)],
      );
    }
  }

  @override
  void visitRecordPattern(RecordPattern node) {
    final type = node.matchedValueType;
    if (type is InterfaceType) {
      for (final rule
          in records[type.element.name] ?? const <MigrationRule>[]) {
        if (_ownedAs(type.element, rule)) _add(rule, node);
      }
    }
    super.visitRecordPattern(node);
  }

  // ---------------------------------------------------------- nullToThrow

  /// A call of [rule]'s, named by [name]: its null check right beside it
  /// made a `try … on` the exception, or a TODO where there is none or the
  /// shape around it is not one this writes.
  void _nullToThrow(SimpleIdentifier name, MigrationRule rule) {
    // The whole call, and what it is once awaited or parenthesised.
    final AstNode call = switch (name.parent) {
      final MethodInvocation m when m.methodName == name => m,
      final PrefixedIdentifier p when p.identifier == name => p,
      final PropertyAccess p when p.propertyName == name => p,
      _ => name,
    };
    var value = call;
    while (value.parent is ParenthesizedExpression ||
        value.parent is AwaitExpression) {
      value = value.parent!;
    }

    if (value.parent case final BinaryExpression b
        when b.operator.type == TokenType.QUESTION_QUESTION &&
            b.leftOperand == value) {
      final edits = _tryAroundCoalesce(b, rule);
      _add(rule, b, edits: edits ?? const <MigrationEdit>[]);
      return;
    }
    if (_tryAroundNullCheck(value, rule) case (final at, final edits)) {
      _add(rule, at, edits: edits);
      return;
    }
    _add(rule, call);
  }

  /// [coalesce], `call ?? fallback`, as a `try` with the call and an `on`
  /// with the fallback, around the statement or the `=>` body it is in.
  List<MigrationEdit>? _tryAroundCoalesce(
    BinaryExpression coalesce,
    MigrationRule rule,
  ) {
    String within(AstNode outer, String replacement) =>
        source.substring(outer.offset, coalesce.offset) +
        replacement +
        source.substring(coalesce.end, outer.end);
    final call = _text(coalesce.leftOperand);
    final fallback = _text(coalesce.rightOperand);
    final exception = rule.exception;
    AstNode? holder;
    for (AstNode? n = coalesce.parent; n != null; n = n.parent) {
      if (n is Statement || n is ExpressionFunctionBody) {
        holder = n;
        break;
      }
      if (n is FunctionBody) return null;
    }
    final imports = _importsFor(rule, <String>{?exception});
    switch (holder) {
      case final Statement holder
          when holder is ExpressionStatement || holder is ReturnStatement:
        final indent = _indentOf(holder.offset);
        return <MigrationEdit>[
          MigrationEdit(
            holder.offset,
            holder.length,
            '${_todoText(rule)}\n'
            '${indent}try {\n'
            '$indent  ${_reindent(within(holder, call), '  ')}\n'
            '$indent} on $exception {\n'
            '$indent  ${_reindent(within(holder, fallback), '  ')}\n'
            '$indent}',
          ),
          ...imports,
        ];
      case VariableDeclarationStatement(:final variables)
          when variables.variables.length == 1 &&
              variables.variables.single.initializer != null &&
              !variables.isConst &&
              variables.lateKeyword == null:
        final variable = variables.variables.single;
        final init = variable.initializer!;
        final type =
            _textOrNull(variables.type) ??
            variable.declaredFragment?.element.type.getDisplayString();
        if (type == null) return null;
        final name = variable.name.lexeme;
        final indent = _indentOf(holder.offset);
        return <MigrationEdit>[
          MigrationEdit(
            holder.offset,
            holder.length,
            '${_todoText(rule)}\n'
            '$indent${variables.isFinal ? 'late final ' : ''}$type $name;\n'
            '${indent}try {\n'
            '$indent  $name = ${_reindent(within(init, call), '  ')};\n'
            '$indent} on $exception {\n'
            '$indent  $name = ${_reindent(within(init, fallback), '  ')};\n'
            '$indent}',
          ),
          ...imports,
        ];
      case final ExpressionFunctionBody holder:
        final ExpressionFunctionBody(:functionDefinition, :expression) = holder;
        final indent = _indentOf(holder.offset);
        return <MigrationEdit>[
          MigrationEdit(
            functionDefinition.offset,
            holder.end - functionDefinition.offset,
            '{\n'
            '$indent  ${_todoText(rule)}\n'
            '$indent  try {\n'
            '$indent    return ${_reindent(within(expression, call), '    ')};\n'
            '$indent  } on $exception {\n'
            '$indent    return ${_reindent(within(expression, fallback), '    ')};\n'
            '$indent  }\n'
            '$indent}',
          ),
          ...imports,
        ];
    }
    return null;
  }

  /// `final v = call;` followed by `if (v == null) …` that leaves the
  /// block: the declaration and the check as a `try` that assigns and an
  /// `on` that does what the check did. The finding stands on the check.
  (AstNode, List<MigrationEdit>)? _tryAroundNullCheck(
    AstNode value,
    MigrationRule rule,
  ) {
    final variable = value.parent;
    if (variable is! VariableDeclaration || variable.initializer != value) {
      return null;
    }
    final list = variable.parent;
    final declaration = list?.parent;
    if (list is! VariableDeclarationList ||
        list.variables.length != 1 ||
        list.lateKeyword != null ||
        list.isConst ||
        declaration is! VariableDeclarationStatement) {
      return null;
    }
    final block = declaration.parent;
    if (block is! Block) return null;
    final at = block.statements.indexOf(declaration);
    if (at + 1 >= block.statements.length) return null;
    final check = block.statements[at + 1];
    if (check is! IfStatement || check.elseStatement != null) return null;
    final name = variable.name.lexeme;
    final condition = check.expression;
    bool isName(Expression e) => e is SimpleIdentifier && e.name == name;
    if (condition is! BinaryExpression ||
        condition.operator.type != TokenType.EQ_EQ ||
        !((isName(condition.leftOperand) &&
                condition.rightOperand is NullLiteral) ||
            (isName(condition.rightOperand) &&
                condition.leftOperand is NullLiteral))) {
      return null;
    }
    final then = check.thenStatement;
    final body = then is Block ? then.statements : <Statement>[then];
    if (body.isEmpty || !_leaves(body.last)) return null;
    final type =
        _textOrNull(list.type) ??
        variable.declaredFragment?.element.type.getDisplayString();
    if (type == null) return null;
    final indent = _indentOf(declaration.offset);
    final handled = then is Block
        ? source.substring(_lineStart(body.first.offset), body.last.end)
        : '$indent  ${_text(then)}';
    return (
      condition,
      <MigrationEdit>[
        MigrationEdit(
          declaration.offset,
          check.end - declaration.offset,
          '${_todoText(rule)}\n'
          '$indent${list.isFinal ? 'final ' : ''}$type $name;\n'
          '${indent}try {\n'
          '$indent  $name = ${_reindent(_text(value), '  ')};\n'
          '$indent} on ${rule.exception} {\n'
          '$handled\n'
          '$indent}',
        ),
        ..._importsFor(rule, <String>{?rule.exception}),
      ],
    );
  }

  /// Whether [s] never falls through to the statement after it.
  static bool _leaves(Statement s) =>
      s is ReturnStatement ||
      s is BreakStatement ||
      s is ContinueStatement ||
      (s is ExpressionStatement &&
          (s.expression is ThrowExpression ||
              s.expression is RethrowExpression));

  // ---------------------------------------------------------------- text

  String? _textOrNull(AstNode? node) => node == null ? null : _text(node);

  /// Where the line holding [offset] starts; the first line has nothing
  /// before it to search.
  int _lineStart(int offset) =>
      offset == 0 ? 0 : source.lastIndexOf('\n', offset - 1) + 1;

  /// The whitespace the line holding [offset] starts with.
  String _indentOf(int offset) => RegExp(
    r'^[ \t]*',
  ).stringMatch(source.substring(_lineStart(offset), offset))!;

  /// [text]'s lines after its first, moved right by [by].
  static String _reindent(String text, String by) =>
      text.replaceAll('\n', '\n$by');

  String _todoText(MigrationRule rule) =>
      '// TODO(flutter3d-1.0): ${rule.message} See ${rule.link}';
}
