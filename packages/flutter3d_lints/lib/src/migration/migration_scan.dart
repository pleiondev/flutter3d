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
            // The names it listed are gone with it: each use gets its TODO.
            for (final m in r.members) {
              into(goneLibraryNames, m, r);
            }
          } else {
            into(internalByName, r.type, r);
          }
          continue;
        case MigrationKind.regroup:
          into(regroups, r.member ?? r.type, r);
          continue;
        case MigrationKind.enumToClass:
          into(openedSwitches, r.switchOver ?? r.type, r);
          if (r.renamedTo case final renamed?) {
            into(openedSwitches, renamed, r);
          }
          continue;
        case MigrationKind.recordToClass:
          into(records, r.type, r);
          recordFields.addAll(r.fields.keys);
          continue;
        case MigrationKind.nullToThrow:
          into(throwers, r.member ?? r.type, r);
          continue;
        case MigrationKind.argument:
          for (final m in r.members) {
            into(arguments, m, r);
          }
          continue;
        case MigrationKind.rename:
          if (r.member case final member?) {
            into(memberRenames, member, r);
          } else {
            into(classRenames, r.type, r);
          }
          continue;
        case MigrationKind.moved:
          into(movedNames, r.type, r);
          continue;
        case MigrationKind.parameters:
          into(toNamedCreations, r.type, r);
          into(toNamedCalls, r.member ?? r.type, r);
          continue;
        case MigrationKind.rewrite when r.member == null && r.receiver != null:
          into(valueConversions, r.receiver!, r);
          continue;
        case MigrationKind.manual when r.type.contains(':'):
          for (final m in r.members) {
            into(goneLibraryNames, m, r);
          }
        case MigrationKind.rewrite ||
            MigrationKind.implementsToWith ||
            MigrationKind.manual:
          break;
      }
      if (r.member != null) {
        into(byMember, r.member!, r);
      } else {
        into(byType, r.type, r);
        if (r.renamedTo case final renamed?
            when r.kind == MigrationKind.manual) {
          into(byType, renamed, r);
        }
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

  /// `manual` and `internal` rules about a library gone whole, by each name
  /// it exported that the rule lists: a use of one the resolver cannot
  /// find.
  final Map<String, List<MigrationRule>> goneLibraryNames =
      <String, List<MigrationRule>>{};

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

  /// `argument` rules by each parameter or field they rewrite.
  final Map<String, List<MigrationRule>> arguments =
      <String, List<MigrationRule>>{};

  /// `rename` rules of a class, by its old name.
  final Map<String, List<MigrationRule>> classRenames =
      <String, List<MigrationRule>>{};

  /// `rewrite` rules that turn a value of a type the engine hands out now
  /// into the one a project's own parameter still takes, by that type.
  final Map<String, List<MigrationRule>> valueConversions =
      <String, List<MigrationRule>>{};

  /// `moved` rules by the name that moved.
  final Map<String, List<MigrationRule>> movedNames =
      <String, List<MigrationRule>>{};

  /// `rename` rules of a member, by its old name: what `dart fix` leaves
  /// where the file does not import the library its entry names (the class
  /// reached through the project's own code).
  final Map<String, List<MigrationRule>> memberRenames =
      <String, List<MigrationRule>>{};

  /// `parameters` rules by the class whose constructor they are about, and
  /// by the name of what is called (the class for its unnamed constructor).
  final Map<String, List<MigrationRule>> toNamedCreations =
      <String, List<MigrationRule>>{};
  final Map<String, List<MigrationRule>> toNamedCalls =
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
    var start = anchor.offset;
    // A use further down a statement that spans lines gets its TODO on the
    // line above its own, where the reader of the error finds it: a line
    // comment may stand between any two tokens, so long as the line starts
    // with a token rather than inside a string. A use on the declaration's
    // own first line keeps the TODO above its doc comment.
    final code = anchor is AnnotatedNode
        ? anchor.firstTokenAfterCommentAndMetadata
        : anchor.beginToken;
    if (_lineStart(at.offset) != _lineStart(code.offset)) {
      final line = _lineStart(at.offset);
      final first = line + _indentOf(at.offset).length;
      for (
        Token? t = code;
        t != null && t.offset <= at.offset && !t.isEof;
        t = t.next
      ) {
        if (t.offset == first) {
          start = first;
          break;
        }
      }
    }
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
      if (goneLibraryNames[name] case final rules?
          when node.element == null && !_isQualifiedMember(node)) {
        _add(rules.first, node);
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
        for (final rule in toNamedCalls[name] ?? const <MigrationRule>[]) {
          if (_callMatches(node, rule)) _toNamed(argumentList, rule);
        }
      }
      // `Old()` with no `new` or `const`, where `Old` is no name at all.
      if (node.parent case MethodInvocation(
        :final methodName,
        target: null,
      ) when methodName == node && node.element == null) {
        _renameClass(node.token, node);
      }
      // `engine.Old()`, the same under an import prefix.
      if (node.parent case MethodInvocation(
        :final methodName,
        target: SimpleIdentifier(element: final PrefixElement prefix),
      ) when methodName == node && node.element == null) {
        _renameClass(node.token, node, prefix: prefix.name);
      }
      if (arguments[name] case final rules?) _readOfOldType(node, rules);
      if (memberRenames[name] case final rules?) {
        if (node.element == null) {
          _renameMember(node, rules);
        } else {
          _renameOverridingUse(node, rules);
        }
      }
      if (movedNames[name] case final rules?
          when node.element == null && !_isQualifiedMember(node)) {
        _moved(node.token, node, rules.first);
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
        if (rule.kind == MigrationKind.rewrite) {
          if (_isTopLevelCall(node, rule)) _member(node, rule);
          continue;
        }
        if (rule.kind != MigrationKind.manual ||
            rule.match != MigrationMatch.uses ||
            rule.members.isNotEmpty) {
          continue;
        }
        if (element is InterfaceElement || element is TypeAliasElement) {
          if (_ownedAs(element, rule)) _add(rule, node);
        } else if (element == null && !_isQualifiedMember(node)) {
          // Gone: a function or a class nothing declares any more, named
          // where a value is.
          _add(rule, node);
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// Whether [node] is the name of a call of the top-level function [rule]
  /// is about: the engine's, or one nothing declares any more.
  bool _isTopLevelCall(SimpleIdentifier node, MigrationRule rule) {
    if (rule.member != null) return false;
    final parent = node.parent;
    if (parent is! MethodInvocation || parent.methodName != node) return false;
    final target = parent.target;
    if (target != null &&
        !(target is SimpleIdentifier && target.element is PrefixElement)) {
      return false;
    }
    final element = node.element;
    return element == null ||
        (element.enclosingElement is LibraryElement && _ownedAs(element, rule));
  }

  bool _ownedAs(Element? element, MigrationRule? rule) {
    final package = _packageOf(element);
    return package != null && ownedPackage(package);
  }

  /// Whether [node] names member [MigrationRule.member] (or one of
  /// [MigrationRule.members]) of [MigrationRule.type].
  bool _isMemberOf(SimpleIdentifier node, MigrationRule rule) {
    final element = node.element;
    final receiver = _receiverType(node);
    // An extension's member that is gone: matched on what it extended.
    if (rule.receiver case final on?) {
      return element == null && receiver != null && _isOrExtends(receiver, on);
    }
    if (element != null) {
      if (!_ownedAs(element, rule)) return false;
      final enclosing = element.enclosingElement;
      if (enclosing is InterfaceElement &&
          _isOfRule(enclosing.thisType, rule)) {
        return true;
      }
      if (element is ConstructorElement &&
          _named(element.enclosingElement.name, rule) &&
          _named(node.name, rule)) {
        return true;
      }
      return receiver != null && _isOfRule(receiver, rule);
    }
    // Gone: a member nothing declares any more, on a receiver that still
    // resolves to the type, or a static one named through the class.
    final on = _classNamed(node) ?? receiver;
    return on != null && _isOfRule(on, rule) && _ownedAs(on.element, rule);
  }

  /// The class [node] is named through as a static member:
  /// `DesktopInput` in `DesktopInput.defaultBindings()`.
  static InterfaceType? _classNamed(SimpleIdentifier node) {
    final target = switch (node.parent) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier == node =>
        prefix,
      PropertyAccess(:final target?, :final propertyName)
          when propertyName == node =>
        target,
      MethodInvocation(:final target?, :final methodName)
          when methodName == node =>
        target,
      _ => null,
    };
    final element = switch (target) {
      SimpleIdentifier(:final element) => element,
      PrefixedIdentifier(:final element) => element,
      _ => null,
    };
    return element is InterfaceElement ? element.thisType : null;
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

  /// Whether [type] is [rule]'s class, by its name at either release.
  static bool _isOfRule(InterfaceType type, MigrationRule rule) =>
      _isOrExtends(type, rule.type) ||
      (rule.renamedTo != null && _isOrExtends(type, rule.renamedTo!));

  /// Whether [name] is [rule]'s class, by its name at either release.
  static bool _named(String? name, MigrationRule rule) =>
      name != null && (name == rule.type || name == rule.renamedTo);

  static bool _isOrExtends(InterfaceType type, String name) =>
      type.element.name == name ||
      type.allSupertypes.any((InterfaceType s) => s.element.name == name);

  void _member(SimpleIdentifier node, MigrationRule rule) {
    if (rule.kind != MigrationKind.rewrite) {
      if (rule.kind == MigrationKind.manual &&
          rule.match == MigrationMatch.uses) {
        switch (rule.awaits ? _awaited(node) : null) {
          case (true, _, _):
            break;
          case (false, final List<MigrationEdit> edits, final bool todo):
            _add(rule, node, edits: edits);
            if (todo) _addTodo(rule, node);
          case null:
            _add(rule, node);
            if (rule.awaits) _readsOfHeldFuture(node, rule);
        }
      }
      return;
    }
    // A static that is an instance's member now: a use through an instance
    // is 1.0 code already.
    if (rule.throughClass && _classNamed(node) == null) return;
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
      ArgumentList? argumentList,
      TypeArgumentList? typeArguments,
    ) = switch (parent) {
      PrefixedIdentifier(:final prefix, :final identifier)
          when identifier == node =>
        (
          parent,
          prefix.element is PrefixElement ? null : prefix,
          false,
          const <AstNode>[],
          null,
          null,
        ),
      PropertyAccess(:final target, :final propertyName, :final operator)
          when propertyName == node && target != null =>
        (
          parent,
          target,
          operator.type == TokenType.QUESTION_PERIOD,
          const <AstNode>[],
          null,
          null,
        ),
      MethodInvocation(
        :final target,
        :final methodName,
        :final argumentList,
        :final operator,
        :final typeArguments,
      )
          when methodName == node =>
        (
          parent,
          target is SimpleIdentifier && target.element is PrefixElement
              ? null
              : target,
          operator?.type == TokenType.QUESTION_PERIOD,
          <AstNode>[...argumentList.arguments],
          argumentList,
          typeArguments,
        ),
      _ => (node, null, false, const <AstNode>[], null, null),
    };
    // A call whose parameter changed type is rewritten only where it still
    // passes the old one: the rewritten call passes the new one, and a
    // later pass must leave it alone.
    if (rule.types.isNotEmpty) {
      final first = args
          .whereType<Argument>()
          .where((Argument a) => a is! NamedArgument)
          .firstOrNull;
      if (first == null || !_typeFits(first.argumentExpression, rule)) {
        return;
      }
    }
    var text = rule.template!;
    // A cascade's receiver is not written where the rewrite needs it, and
    // a null-aware access changes the type the rewrite would produce.
    // `{0}` names an argument by its place, which a named one has not.
    if (nullAware ||
        (whole is PropertyAccess && whole.isCascaded) ||
        (whole is MethodInvocation && whole.isCascaded) ||
        (RegExp(r'\{\d+\}').hasMatch(text) &&
            args.any((AstNode a) => a is NamedArgument)) ||
        (text.contains('{typeArguments}') && typeArguments == null)) {
      _add(rule, node);
      return;
    }
    if (argumentList != null) {
      text = text.replaceAll(
        '{arguments}',
        source.substring(
          argumentList.leftParenthesis.end,
          argumentList.rightParenthesis.offset,
        ),
      );
    }
    if (typeArguments != null) {
      text = text.replaceAll(
        '{typeArguments}',
        source.substring(
          typeArguments.leftBracket.end,
          typeArguments.rightBracket.offset,
        ),
      );
    }
    if (target == null) {
      text = text.replaceAll('{target}.', '').replaceAll('{target}', 'this');
    } else {
      text = text.replaceAll('{target}', _operand(target));
    }
    for (var i = 0; i < args.length; i++) {
      // An argument written more than once is evaluated more than once:
      // only a name or a chain of field reads may be.
      if ('{$i}'.allMatches(text).length > 1 &&
          !(args[i] is Expression && _isPath(args[i] as Expression))) {
        _add(rule, node);
        return;
      }
      text = text.replaceAll('{$i}', _text(args[i]));
    }
    if (RegExp(r'\{(\d+|arguments|typeArguments)\}').hasMatch(text)) {
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

  /// A call named by [node] of a member that answers a `Future` now: (true,
  /// no edits) where it is awaited already, (false, the edits) that await
  /// it inside an `async` body, null where that is not this scan's to write
  /// (a body that is not `async`, a cascade).
  (bool, List<MigrationEdit>, bool)? _awaited(SimpleIdentifier node) {
    final call = node.parent;
    if (call is! MethodInvocation || call.methodName != node) return null;
    final type = call.staticType;
    if (type is! InterfaceType || !type.isDartAsyncFuture) return null;
    if (call.parent is AwaitExpression) {
      return (true, const <MigrationEdit>[], false);
    }
    if (call.isCascaded) return null;
    final body = call.thisOrAncestorOfType<FunctionBody>();
    if (body == null) return null;
    // A test's own callback may become `async`: the runner awaits what it
    // returns.
    // A function that returns nothing may too, but what follows the await
    // now runs later: that keeps its TODO.
    final test = !body.isAsynchronous && _isTestCallback(body);
    final void_ = !body.isAsynchronous && !test && _returnsVoid(body);
    final makeAsync = test || void_;
    if (!body.isAsynchronous && !makeAsync) return null;
    final parent = call.parent;
    final operand = switch (parent) {
      PropertyAccess(:final target) => target == call,
      MethodInvocation(:final target) => target == call,
      IndexExpression(:final target) => target == call,
      _ => false,
    };
    return (
      false,
      <MigrationEdit>[
        if (makeAsync) MigrationEdit(body.offset, 0, 'async '),
        ...operand
            ? <MigrationEdit>[
                MigrationEdit(call.offset, 0, '(await '),
                MigrationEdit(call.end, 0, ')'),
              ]
            : <MigrationEdit>[MigrationEdit(call.offset, 0, 'await ')],
      ],
      void_,
    );
  }

  /// Whether [body] is the body of a function or a method declared to
  /// return `void`, which an `async` keeps returning nothing a caller reads.
  static bool _returnsVoid(FunctionBody body) {
    if (body.star != null) return false;
    final returnType = switch (body.parent) {
      FunctionExpression(parent: FunctionDeclaration(:final returnType)) =>
        returnType,
      MethodDeclaration(:final returnType, :final propertyKeyword) =>
        propertyKeyword == null ? returnType : null,
      _ => null,
    };
    return returnType?.type is VoidType;
  }

  /// A TODO at [at] beside an edit made there already, for a rewrite that
  /// a person still has to read.
  void _addTodo(MigrationRule rule, AstNode at) {
    if (!_seen.add(('${rule.id}#todo', at.offset))) return;
    found.add(
      MigrationFinding(
        rule: rule,
        offset: at.offset,
        length: at.length,
        edits: const <MigrationEdit>[],
        todo: _todoFor(rule, at),
      ),
    );
  }

  /// A call that answers a `Future` now, held in a local variable where it
  /// cannot be awaited: each read of the variable carries the TODO too,
  /// since the error stands on the read (`device.shaders`, `return
  /// device`), not on the call.
  void _readsOfHeldFuture(SimpleIdentifier node, MigrationRule rule) {
    final call = node.parent;
    final variable = call?.parent;
    if (call is! MethodInvocation ||
        variable is! VariableDeclaration ||
        variable.initializer != call) {
      return;
    }
    final element = variable.declaredFragment?.element;
    final body = variable.thisOrAncestorOfType<FunctionBody>();
    if (element == null || body == null) return;
    body.accept(_ReadsOf(element, (SimpleIdentifier read) => _add(rule, read)));
  }

  /// Whether [body] is a block of a closure passed straight to `test`,
  /// `testWidgets`, `setUp`, `tearDown`, `setUpAll` or `tearDownAll`.
  static bool _isTestCallback(FunctionBody body) {
    if (body is! BlockFunctionBody || body.star != null) return false;
    final closure = body.parent;
    if (closure is! FunctionExpression) return false;
    final call = closure.parent?.parent;
    return call is MethodInvocation &&
        call.target == null &&
        const <String>{
          'test',
          'testWidgets',
          'setUp',
          'tearDown',
          'setUpAll',
          'tearDownAll',
        }.contains(call.methodName.name);
  }

  String _text(AstNode node) => source.substring(node.offset, node.end);

  /// [target]'s text, in parentheses when it is not a primary.
  String _operand(Expression target) {
    final text = _text(target);
    final primary =
        target is Identifier ||
        target is Literal ||
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
    // An import may carry a `show` list (`dart:math show pi`): what it
    // shows is named too, lower case or not.
    final shown = <String>{
      for (final i in rule.imports)
        if (i.indexOf(' show ') case final at when at > 0)
          ...i.substring(at + 6).split(',').map((String n) => n.trim()),
    };
    final names =
        named ??
        <String>{
          ...RegExp(r'\b([A-Z][\w$]*)\b')
              .allMatches(rule.template!.replaceAll(RegExp(r'\{[^}]*\}'), ''))
              .map((Match m) => m.group(1)!),
          ...shown.where((String n) => rule.template!.contains(n)),
        };
    final missing =
        scope != null &&
        names.any((String n) => scope.lookup(n).getter == null);
    if (!missing) return const <MigrationEdit>[];
    // Only an import without a prefix brings the bare names a template
    // writes.
    final already = <String?>{
      for (final d in unit.directives.whereType<ImportDirective>())
        if (d.prefix == null) d.uri.stringValue,
    };
    final directives = unit.directives;
    // After the last import or export: an import after a `part` is an error.
    final before = directives.where(
      (Directive d) => d is! PartDirective && d is! PartOfDirective,
    );
    final at = before.isEmpty ? 0 : before.last.end;
    return <MigrationEdit>[
      for (final spec in rule.imports)
        if (!already.contains(spec.split(' ').first))
          MigrationEdit(
            at,
            0,
            "${before.isEmpty ? '' : '\n'}${_importDirective(spec)}"
            "${before.isEmpty ? '\n' : ''}",
          ),
    ];
  }

  /// `import '<uri>';` for [spec], a URI with an optional `show` list.
  static String _importDirective(String spec) {
    final space = spec.indexOf(' ');
    return space < 0
        ? "import '$spec';"
        : "import '${spec.substring(0, space)}'${spec.substring(space)};";
  }

  // ---------------------------------------------------------------- types

  @override
  void visitNamedType(NamedType node) {
    if (internalByName[node.name.lexeme] case final rules?
        when node.element == null) {
      _useInternal(rules.first, node.name.lexeme, node);
    }
    if (goneLibraryNames[node.name.lexeme] case final rules?
        when node.element == null && node.importPrefix == null) {
      _add(rules.first, node);
    }
    if (movedNames[node.name.lexeme] case final rules?
        when node.element == null && node.importPrefix == null) {
      _moved(node.name, node, rules.first);
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
              if (wanted) {
                _add(rule, node);
                if (inClause) _overridesOf(node, rule);
              }
            // Only the three above are kept by type; the rest have maps of
            // their own.
            case MigrationKind.rewrite ||
                MigrationKind.regroup ||
                MigrationKind.enumToClass ||
                MigrationKind.recordToClass ||
                MigrationKind.nullToThrow ||
                MigrationKind.argument ||
                MigrationKind.internal ||
                MigrationKind.rename ||
                MigrationKind.parameters ||
                MigrationKind.moved:
              break;
          }
        }
      }
    }
    _shadowedRename(node);
    _renameOverrides(node);
    // A renamed class in a type, as in a creation: before `dart fix`, which
    // picks one rename by name where two classes had it.
    if (node.element == null) {
      _renameClass(node.name, node, prefix: node.importPrefix?.name.lexeme);
    }
    super.visitNamedType(node);
  }

  /// A TODO at each member of the class [type] is a supertype in that
  /// overrides one of [type]'s, since the signature it overrides is what
  /// changed: the analyzer's error stands on that member, not on the clause.
  void _overridesOf(NamedType type, MigrationRule rule) {
    final element = type.element;
    final declaration = type.parent?.parent;
    if (element is! InterfaceElement || declaration is! ClassDeclaration) {
      return;
    }
    final body = declaration.body;
    if (body is! BlockClassBody) return;
    for (final member in body.members.whereType<MethodDeclaration>()) {
      final name = member.name.lexeme;
      if (element.getMethod(name) != null ||
          element.getGetter(name) != null ||
          element.getSetter(name) != null) {
        _add(rule, member);
      }
    }
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

  /// An operator the left operand's type no longer has, which a rule
  /// about that type lists: `a - b` of two colours that were vectors.
  @override
  void visitBinaryExpression(BinaryExpression node) {
    final type = node.leftOperand.staticType;
    if (node.element == null && type is InterfaceType) {
      final op = node.operator.lexeme;
      for (final rule in <MigrationRule>[
        ...?byMember[op],
        ...?byListedMember[op],
      ]) {
        final on = rule.receiver ?? rule.renamedTo ?? rule.type;
        if (rule.kind == MigrationKind.manual && _isOrExtends(type, on)) {
          _add(rule, node);
          break;
        }
      }
    }
    super.visitBinaryExpression(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    // A library gone whole, re-exported by the project's own barrel.
    if (node.uri.stringValue case final uri?) {
      for (final rule in byType[uri] ?? const <MigrationRule>[]) {
        if (rule.kind == MigrationKind.manual) _add(rule, node);
      }
      if (internalByUri[uri] case final rule?) _add(rule, node);
    }
    super.visitExportDirective(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    final uri = node.uri.stringValue;
    if (uri != null) {
      for (final rule in byType[uri] ?? const <MigrationRule>[]) {
        _add(rule, node);
      }
    }
    _renameCombinators(node);
    super.visitImportDirective(node);
  }

  /// A class renamed since the release, named in a `show` or `hide` of an
  /// engine library that exports it under its new name only: `dart fix`
  /// renames every use and leaves the combinator, which then hides the
  /// class it renamed the uses to.
  void _renameCombinators(ImportDirective node) {
    final library = node.libraryImport?.importedLibrary;
    final uri = node.uri.stringValue ?? '';
    if (library == null || !uri.startsWith('package:')) return;
    if (!ownedPackage(uri.substring(8).split('/').first)) return;
    for (final combinator in node.combinators) {
      final names = switch (combinator) {
        ShowCombinator(:final shownNames) => shownNames,
        HideCombinator(:final hiddenNames) => hiddenNames,
      };
      for (final name in names) {
        if (library.exportNamespace.get2(name.name) != null) continue;
        for (final rule in classRenames[name.name] ?? const <MigrationRule>[]) {
          final to = rule.to;
          if (to == null || library.exportNamespace.get2(to) == null) continue;
          _add(
            rule,
            name,
            edits: <MigrationEdit>[MigrationEdit(name.offset, name.length, to)],
          );
          break;
        }
      }
    }
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
    if (at is! Directive) {
      (_internalUseNodes[rule.package] ??= <AstNode>[]).add(at);
    }
  }

  /// Each use of a package's internal names, by package: where the
  /// analyzer's error stands, so the TODO stands there too.
  final Map<String, List<AstNode>> _internalUseNodes =
      <String, List<AstNode>>{};

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
      for (final node in <AstNode>[
        ...at.isEmpty ? <AstNode>[_firstInternalUse[package]!] : at,
        ...?_internalUseNodes[package],
      ]) {
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
    if (name.type case NamedType(
      element: null,
      importPrefix: null,
      name: final token,
    )) {
      _renameClass(token, name.type);
    }
    for (final rule
        in regroups[name.type.name.lexeme] ?? const <MigrationRule>[]) {
      if (name.name?.name == rule.member && _ownedAs(name.type.element, rule)) {
        _regroup(node.argumentList, rule);
      }
    }
    for (final rule
        in toNamedCreations[name.type.name.lexeme] ?? const <MigrationRule>[]) {
      if (name.name?.name == rule.member && _ownedAs(name.type.element, rule)) {
        _toNamed(node.argumentList, rule);
      }
    }
    _manualCreation(node);
    super.visitInstanceCreationExpression(node);
  }

  /// The positional arguments of [arguments] at the places
  /// [MigrationRule.fields] names, each passed by its new name where it
  /// stands: `Gauge(r, 2)` is `Gauge(r, scale: 2)`. A call that also passes
  /// one of those names already is a person's to untangle.
  void _toNamed(ArgumentList arguments, MigrationRule rule) {
    _renameArguments(arguments, rule);
    final positional = <Argument>[
      for (final a in arguments.arguments)
        if (a is! NamedArgument) a,
    ];
    final moved = <(Argument, String)>[
      for (final (i, a) in positional.indexed)
        if (rule.fields['$i'] case final name?) (a, name),
    ];
    if (moved.isEmpty) return;
    final passed = <String>{
      for (final a in arguments.arguments)
        if (a is NamedArgument) a.name.lexeme,
    };
    if (moved.any(((Argument, String) m) => passed.contains(m.$2))) {
      _add(rule, moved.first.$1);
      return;
    }
    _add(
      rule,
      moved.first.$1,
      edits: <MigrationEdit>[
        for (final (a, name) in moved) MigrationEdit(a.offset, 0, '$name: '),
      ],
    );
  }

  /// The named arguments of [arguments] the call has no parameter for any
  /// more whose parameter [rule] renamed (its [MigrationRule.fields] by
  /// name): `Brush(centre: c)` is `Brush(center: c)` where `dart fix` did
  /// not reach the call.
  void _renameArguments(ArgumentList arguments, MigrationRule rule) {
    final edits = <MigrationEdit>[
      for (final a in arguments.arguments)
        if (a is NamedArgument && a.correspondingParameter == null)
          if (rule.fields[a.name.lexeme] case final to?)
            MigrationEdit(a.name.offset, a.name.length, to),
    ];
    if (edits.isNotEmpty) _add(rule, arguments, edits: edits);
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
      // A field the class keeps under its own name reads as it did.
      if (getter == null ||
          getter == node.name ||
          !_ownedAs(type.element, rule)) {
        continue;
      }
      _add(
        rule,
        node,
        edits: <MigrationEdit>[MigrationEdit(node.offset, node.length, getter)],
      );
    }
  }

  /// A record built where the class it became is expected — returned from
  /// a function that answers it, assigned to a variable of it, passed for
  /// a parameter of it — with the class's own fields: a creation of it.
  @override
  void visitRecordLiteral(RecordLiteral node) {
    final type = node.staticType;
    if (type is RecordType &&
        type.positionalFields.isEmpty &&
        type.namedFields.isNotEmpty &&
        !node.isConst) {
      final names = <String>{for (final f in type.namedFields) f.name};
      final expected = _expectedType(node);
      if (expected is RecordType) _renameRecordLabels(node, expected);
      if (expected is InterfaceType) {
        for (final rule
            in records[expected.element.name] ?? const <MigrationRule>[]) {
          final same =
              rule.fields.length == names.length &&
              rule.fields.entries.every(
                (MapEntry<String, String> f) =>
                    f.key == f.value && names.contains(f.key),
              );
          if (same && _ownedAs(expected.element, rule)) {
            _add(
              rule,
              node,
              edits: <MigrationEdit>[
                MigrationEdit(node.offset, 0, expected.element.name ?? ''),
              ],
            );
            break;
          }
        }
      }
    }
    super.visitRecordLiteral(node);
  }

  /// The type the place [node] stands in asks for, a `Future`'s unwrapped:
  /// a function's return type, a variable's, a parameter's.
  DartType? _expectedType(Expression node) {
    AstNode at = node;
    while (at.parent is ParenthesizedExpression) {
      at = at.parent!;
    }
    final parent = at.parent;
    final DartType? type = switch (parent) {
      ReturnStatement() || ExpressionFunctionBody() => switch (at
          .thisOrAncestorOfType<FunctionBody>()
          ?.parent) {
        FunctionExpression(parent: FunctionDeclaration(:final returnType?)) =>
          returnType.type,
        MethodDeclaration(:final returnType?) => returnType.type,
        // A closure: the return type of the function type its place asks
        // for (a builder passed for a `FrameSubject Function()`).
        final FunctionExpression closure =>
          switch (closure.correspondingParameter?.type) {
            final FunctionType function => function.returnType,
            _ => null,
          },
        _ => null,
      },
      VariableDeclaration(:final declaredFragment?) =>
        declaredFragment.element.type,
      // An element of a list literal: the list's element type.
      ListLiteral(:final staticType) => switch (staticType) {
        final InterfaceType list when list.typeArguments.length == 1 =>
          list.typeArguments.single,
        _ => null,
      },
      _ when at is Expression => at.correspondingParameter?.type,
      _ => null,
    };
    if (type is InterfaceType &&
        (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
        type.typeArguments.isNotEmpty) {
      return type.typeArguments.first;
    }
    return type;
  }

  /// A field of an object pattern a member rename renamed:
  /// `PerspectiveProjection(:final fovYRadians)` is
  /// `PerspectiveProjection(fovY: final fovYRadians)`, the variable kept.
  @override
  void visitPatternField(PatternField node) {
    final pattern = node.parent;
    final name = node.effectiveName;
    if (pattern is ObjectPattern && node.element == null && name != null) {
      final type = pattern.type.type;
      for (final rule in memberRenames[name] ?? const <MigrationRule>[]) {
        final to = rule.to;
        if (to == null || type is! InterfaceType || !_isOfRule(type, rule)) {
          continue;
        }
        final label = node.name;
        _add(
          rule,
          node,
          edits: <MigrationEdit>[
            if (label?.name case final written?)
              MigrationEdit(written.offset, written.length, to)
            else if (label != null)
              MigrationEdit(label.colon.offset, 1, '$to: '),
          ],
        );
        break;
      }
    }
    super.visitPatternField(node);
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

  // ---------------------------------------------- manual calls, by place

  /// The `manual` rules about the call [list] is the arguments of: its
  /// class's or function's own, or the member of its class it calls (a
  /// constructor is the member named as the class, `Type.Type`).
  List<MigrationRule> _manualRulesOfCall(ArgumentList list) {
    final (
      String? type,
      String? member,
      Element? element,
    ) = switch (list.parent) {
      // Through a typedef, the class it names (`ModelPictureTool(…)` makes
      // an `OfferedTool`).
      InstanceCreationExpression(:final constructorName) =>
        switch (constructorName.type.type) {
          final InterfaceType created => (
            created.element.name,
            constructorName.name?.name ?? created.element.name,
            created.element,
          ),
          _ => (
            constructorName.type.name.lexeme,
            constructorName.name?.name ?? constructorName.type.name.lexeme,
            constructorName.type.element,
          ),
        },
      MethodInvocation(:final methodName, :final realTarget) =>
        switch (methodName.element?.enclosingElement) {
          final InterfaceElement owner => (owner.name, methodName.name, owner),
          LibraryElement() => (methodName.name, null, methodName.element),
          _ => switch (realTarget?.staticType) {
            final InterfaceType t => (
              t.element.name,
              methodName.name,
              t.element,
            ),
            _ => (null, null, null),
          },
        },
      _ => (null, null, null),
    };
    if (type == null || element == null) return const <MigrationRule>[];
    bool manual(MigrationRule r) =>
        r.kind == MigrationKind.manual &&
        r.match == MigrationMatch.uses &&
        _named(type, r) &&
        _ownedAs(element, r);
    return <MigrationRule>[
      for (final r in byType[type] ?? const <MigrationRule>[])
        if (manual(r) && r.members.isEmpty) r,
      if (member != null)
        for (final r in byMember[member] ?? const <MigrationRule>[])
          if (manual(r)) r,
    ];
  }

  /// An argument of a type the engine hands out now (a `LinearColor`) passed
  /// for a parameter of the project's own that takes the old one (a
  /// `Vector3`): converted, as a rule's template says, to the old type.
  void _convertValues(ArgumentList node) {
    for (final argument in node.arguments) {
      _convertValue(
        argument.argumentExpression,
        argument.correspondingParameter?.type,
      );
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final value = node.initializer;
    final list = node.parent;
    if (value != null &&
        valueConversions.isNotEmpty &&
        list is VariableDeclarationList &&
        list.type != null) {
      _convertValue(value, node.declaredFragment?.element.type);
    }
    super.visitVariableDeclaration(node);
  }

  /// [value] converted where [wants], the type its place takes, is one a
  /// conversion rule turns its type into.
  void _convertValue(Expression value, DartType? wants) {
    final type = value.staticType;
    if (type is! InterfaceType || wants is! InterfaceType) return;
    for (final rule
        in valueConversions[type.element.name] ?? const <MigrationRule>[]) {
      final name = wants.element.name;
      if (name == null || !rule.types.contains(name)) continue;
      _add(
        rule,
        value,
        edits: <MigrationEdit>[
          MigrationEdit(
            value.offset,
            value.length,
            rule.template!
                .replaceAll('{target}', _operand(value))
                .replaceAll('{type}', name),
          ),
        ],
      );
      return;
    }
  }

  /// A named argument the call no longer has a parameter for, of a call a
  /// `manual` rule is about: the TODO stands on that argument, where the
  /// analyzer's error does, and not only above the statement.
  void _manualArguments(ArgumentList node) {
    final unmatched = <NamedArgument>[
      for (final a in node.arguments)
        if (a is NamedArgument && a.correspondingParameter == null) a,
    ];
    // And an argument the call still has a parameter for, of a type that
    // parameter no longer takes (a callback whose shape changed).
    final typeSystem = unit.declaredFragment?.element.library.typeSystem;
    final mistyped = <Argument>[
      if (typeSystem != null)
        for (final a in node.arguments)
          if ((a.argumentExpression.staticType, a.correspondingParameter?.type)
              case (final DartType given?, final DartType wanted?)
              when given is! InvalidType &&
                  given is! DynamicType &&
                  !typeSystem.isAssignableTo(given, wanted))
            a,
    ];
    if (unmatched.isEmpty && mistyped.isEmpty) return;
    final rules = <MigrationRule>[
      ..._manualRulesOfCall(node),
      // A rule about the parameter itself, `RunTimeline.stepSim`.
      for (final a in unmatched)
        for (final r in <MigrationRule>[
          ...?byMember[a.name.lexeme],
          ...?byListedMember[a.name.lexeme],
        ])
          if (r.kind == MigrationKind.manual &&
              _named(_manualRulesOfCallType(node), r))
            r,
    ];
    if (rules.isEmpty) return;
    for (final a in <Argument>[...unmatched, ...mistyped]) {
      _add(rules.first, a);
    }
    // And on the call's name, where the analyzer names a parameter it now
    // requires.
    switch (node.parent) {
      case InstanceCreationExpression(:final constructorName):
        _add(rules.first, constructorName);
      case MethodInvocation(:final methodName):
        _add(rules.first, methodName);
    }
  }

  /// The class whose constructor or method [list] is passed to, by name.
  static String? _manualRulesOfCallType(ArgumentList list) =>
      switch (list.parent) {
        InstanceCreationExpression(:final constructorName) =>
          constructorName.type.name.lexeme,
        MethodInvocation(:final methodName) =>
          switch (methodName.element?.enclosingElement) {
            final InterfaceElement owner => owner.name,
            _ => null,
          },
        _ => null,
      };

  /// A creation of a class whose constructor a `manual` rule is about
  /// (`Type.Type`, `Type.named`): the analyzer resolves it, so no use of a
  /// name stands for it elsewhere.
  void _manualCreation(InstanceCreationExpression node) {
    final name = node.constructorName;
    final type = name.type.name.lexeme;
    final member = name.name?.name ?? type;
    for (final r in byMember[member] ?? const <MigrationRule>[]) {
      if (r.kind == MigrationKind.manual &&
          r.match == MigrationMatch.uses &&
          _named(type, r) &&
          _ownedAs(name.type.element, r)) {
        _add(r, name);
      }
    }
  }

  // -------------------------------------------------------------- rename

  /// A class renamed since the release, named by [name] where the analyzer
  /// finds no type ([at] is the creation's type, or the bare call): the new
  /// name, when exactly one rule's new name is in scope here, or a TODO
  /// naming them.
  /// A class renamed since the release whose old name is also one of the
  /// Dart SDK's (`Match`): at the release, the import of the engine's
  /// library shadowed the SDK's name, so in a file that still imports that
  /// package without a prefix every bare use meant the engine's class. Now
  /// the analyzer finds the SDK's, and `dart fix` sees nothing to rename.
  void _shadowedRename(NamedType node) {
    final rules = classRenames[node.name.lexeme];
    final element = node.element;
    if (rules == null ||
        node.importPrefix != null ||
        element == null ||
        element.library?.uri.scheme != 'dart') {
      return;
    }
    final scope = unit.declaredFragment?.scope;
    for (final rule in rules) {
      final to = rule.to;
      if (to == null || scope?.lookup(to).getter is! InterfaceElement) {
        continue;
      }
      final imported = unit.directives.whereType<ImportDirective>().any(
        (ImportDirective d) =>
            d.prefix == null &&
            (d.uri.stringValue ?? '').startsWith('package:${rule.package}/') &&
            !d.combinators.any(
              (Combinator c) =>
                  (c is HideCombinator &&
                      c.hiddenNames.any(
                        (SimpleIdentifier n) => n.name == node.name.lexeme,
                      )) ||
                  (c is ShowCombinator &&
                      !c.shownNames.any(
                        (SimpleIdentifier n) => n.name == node.name.lexeme,
                      )),
            ),
      );
      if (!imported) continue;
      _add(
        rule,
        node,
        edits: <MigrationEdit>[
          MigrationEdit(node.name.offset, node.name.length, to),
        ],
      );
      return;
    }
  }

  void _renameClass(Token name, AstNode at, {String? prefix}) {
    final rules = classRenames[name.lexeme];
    if (rules == null) return;
    final scope = unit.declaredFragment?.scope;
    // Under an import prefix, what the prefixed libraries export (their
    // `show` is renamed with the class).
    bool inScope(String to) => prefix == null
        ? scope?.lookup(to).getter is InterfaceElement
        : unit.directives.whereType<ImportDirective>().any(
            (ImportDirective d) =>
                d.prefix?.name == prefix &&
                d.libraryImport?.importedLibrary?.exportNamespace.get2(to)
                    is InterfaceElement,
          );
    final fits = <MigrationRule>[
      for (final r in rules)
        if (r.to case final to?
            when inScope(to) &&
                (prefix != null || !_hiddenFrom(name.lexeme, to)))
          r,
    ];
    if (fits case [final rule]) {
      _add(
        rule,
        at,
        edits: <MigrationEdit>[
          MigrationEdit(name.offset, name.length, rule.to!),
        ],
      );
      return;
    }
    for (final rule in rules) {
      _add(rule, at);
    }
  }

  /// The members a class declares under an old name of a member of [type],
  /// which it extends, implements or mixes in: renamed with it, since
  /// `dart fix` renames the uses and leaves an implementer's declaration,
  /// which then no longer implements anything.
  void _renameOverrides(NamedType type) {
    final clause = type.parent;
    if (clause is! ExtendsClause &&
        clause is! ImplementsClause &&
        clause is! WithClause) {
      return;
    }
    final declaration = clause?.parent;
    if (declaration is! ClassDeclaration) return;
    final body = declaration.body;
    if (body is! BlockClassBody) return;
    final element = type.element;
    if (element is! InterfaceElement || !_ownedAs(element, null)) return;
    // Each name the class declares, a getter, a method or a field, by its
    // token.
    final names = <(Token, AstNode)>[
      for (final m in body.members)
        ...switch (m) {
          MethodDeclaration(:final name) => <(Token, AstNode)>[(name, m)],
          FieldDeclaration(:final fields) => <(Token, AstNode)>[
            for (final v in fields.variables) (v.name, v),
          ],
          _ => const <(Token, AstNode)>[],
        },
    ];
    final declared = <String>{for (final (n, _) in names) n.lexeme};
    for (final (name, node) in names) {
      for (final rule
          in memberRenames[name.lexeme] ?? const <MigrationRule>[]) {
        final to = rule.to;
        if (to == null ||
            declared.contains(to) ||
            !_isOfRule(element.thisType, rule)) {
          continue;
        }
        _add(
          rule,
          node,
          edits: <MigrationEdit>[
            MigrationEdit(name.offset, name.length, to),
            // A field's `this.x` in the class's constructors goes with it.
            if (node is VariableDeclaration)
              for (final formal in _fieldFormals(body, name.lexeme))
                MigrationEdit(formal.offset, formal.length, to),
          ],
        );
        break;
      }
    }
  }

  /// The names of the `this.[field]` parameters of [body]'s constructors.
  static List<Token> _fieldFormals(BlockClassBody body, String field) {
    final found = <FieldFormalParameter>[];
    for (final c in body.members.whereType<ConstructorDeclaration>()) {
      c.parameters.accept(_FieldFormals(found));
    }
    return <Token>[
      for (final f in found)
        if (f.name.lexeme == field) f.name,
    ];
  }

  /// Whether an engine import that brings [to] hides [old] (or [to]): two
  /// classes renamed from one old name (`Pose`, the animation's and the
  /// simulation's), and the file hid the one it did not mean.
  bool _hiddenFrom(String old, String to) {
    for (final d in unit.directives.whereType<ImportDirective>()) {
      final library = d.libraryImport?.importedLibrary;
      final uri = d.uri.stringValue ?? '';
      if (library == null ||
          !uri.startsWith('package:') ||
          !ownedPackage(uri.substring(8).split('/').first) ||
          library.exportNamespace.get2(to) == null) {
        continue;
      }
      final hides = d.combinators.whereType<HideCombinator>().any(
        (HideCombinator c) => c.hiddenNames.any(
          (SimpleIdentifier n) => n.name == old || n.name == to,
        ),
      );
      if (hides) return true;
    }
    return false;
  }

  /// A name that moved to another library, met where the analyzer finds
  /// none: imported from there, under its new name where it has one.
  void _moved(Token name, AstNode at, MigrationRule rule) {
    final to = rule.to ?? name.lexeme;
    _add(
      rule,
      at,
      edits: <MigrationEdit>[
        if (to != name.lexeme) MigrationEdit(name.offset, name.length, to),
        ..._importsFor(rule, <String>{to}),
      ],
    );
  }

  /// A member renamed since the release, met where the analyzer finds
  /// nothing of its old name on its class: the new name.
  void _renameMember(SimpleIdentifier node, List<MigrationRule> rules) {
    for (final rule in rules) {
      final to = rule.to;
      // Or a member of the project's own subtype of the class, whose
      // declaration `_renameOverrides` renamed (a setter's target, which the
      // analyzer leaves unresolved).
      final receiver = _receiverType(node);
      final ofOwnSubtype =
          receiver != null &&
          !_ownedAs(receiver.element, rule) &&
          _isOfRule(receiver, rule);
      if (to == null ||
          !(_isMemberOf(node, rule) ||
              _isFieldOfRecordAlias(node, rule) ||
              ofOwnSubtype)) {
        continue;
      }
      _add(
        rule,
        node,
        edits: <MigrationEdit>[MigrationEdit(node.offset, node.length, to)],
      );
      return;
    }
  }

  /// A use of the project's own member that overrides a renamed one (a
  /// fake's `grounded`, which [_renameOverrides] renames to `isGrounded`):
  /// renamed with its declaration, in the same pass.
  void _renameOverridingUse(SimpleIdentifier node, List<MigrationRule> rules) {
    // A named argument for a `this.x` parameter names the field.
    final element = switch (node.element) {
      final FieldFormalParameterElement formal => formal.field,
      final other => other,
    };
    final owner = element?.enclosingElement;
    if (owner is! InterfaceElement || _ownedAs(owner, null)) return;
    for (final rule in rules) {
      final to = rule.to;
      if (to == null ||
          !_isOfRule(owner.thisType, rule) ||
          owner.getGetter(to) != null ||
          owner.getMethod(to) != null) {
        continue;
      }
      _add(
        rule,
        node,
        edits: <MigrationEdit>[MigrationEdit(node.offset, node.length, to)],
      );
      return;
    }
  }

  /// A named argument for a `this.x` parameter of the project's own class
  /// whose field `x` overrides a renamed member: renamed with the field.
  void _renameOverridingArguments(ArgumentList node) {
    for (final a in node.arguments) {
      if (a is! NamedArgument) continue;
      final parameter = a.correspondingParameter;
      if (parameter is! FieldFormalParameterElement) continue;
      final owner = parameter.field?.enclosingElement;
      if (owner is! InterfaceElement || _ownedAs(owner, null)) continue;
      for (final rule
          in memberRenames[a.name.lexeme] ?? const <MigrationRule>[]) {
        final to = rule.to;
        if (to == null || !_isOfRule(owner.thisType, rule)) continue;
        _add(
          rule,
          a,
          edits: <MigrationEdit>[
            MigrationEdit(a.name.offset, a.name.length, to),
          ],
        );
        break;
      }
    }
  }

  /// Whether [node] reads a field of a record typedef named as [rule]'s
  /// type (`ModelCredit`, a record whose `licence` is `license`).
  bool _isFieldOfRecordAlias(SimpleIdentifier node, MigrationRule rule) {
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
    return type is RecordType && _named(type.alias?.element.name, rule);
  }

  /// The labels of [node], a record literal built where a record typedef
  /// is expected, that a member rename of that typedef renamed.
  void _renameRecordLabels(RecordLiteral node, RecordType expected) {
    final alias = expected.alias?.element.name;
    if (alias == null) return;
    for (final (label, at) in _labelsOf(node)) {
      for (final rule in memberRenames[label] ?? const <MigrationRule>[]) {
        final to = rule.to;
        if (to == null || !_named(alias, rule)) continue;
        _add(
          rule,
          node,
          edits: <MigrationEdit>[MigrationEdit(at, label.length, to)],
        );
        break;
      }
    }
  }

  /// Each named field's label of [node] with its offset: an identifier
  /// right after the opening parenthesis or a comma at the literal's own
  /// depth, followed by a colon.
  static List<(String, int)> _labelsOf(RecordLiteral node) {
    final labels = <(String, int)>[];
    var depth = 0;
    Token? previous;
    for (
      Token? t = node.leftParenthesis;
      t != null && t != node.rightParenthesis.next;
      t = t.next
    ) {
      final type = t.type;
      if (type == TokenType.OPEN_PAREN ||
          type == TokenType.OPEN_SQUARE_BRACKET ||
          type == TokenType.OPEN_CURLY_BRACKET) {
        depth++;
      } else if (type == TokenType.CLOSE_PAREN ||
          type == TokenType.CLOSE_SQUARE_BRACKET ||
          type == TokenType.CLOSE_CURLY_BRACKET) {
        depth--;
      } else if (depth == 1 &&
          t.isIdentifier &&
          t.next?.type == TokenType.COLON &&
          (previous == node.leftParenthesis ||
              previous?.type == TokenType.COMMA)) {
        labels.add((t.lexeme, t.offset));
      }
      previous = t;
    }
    return labels;
  }

  // ------------------------------------------------------------ argument

  @override
  void visitArgumentList(ArgumentList node) {
    _manualArguments(node);
    if (memberRenames.isNotEmpty) _renameOverridingArguments(node);
    if (valueConversions.isNotEmpty) _convertValues(node);
    if (arguments.isNotEmpty) {
      for (final argument in node.arguments) {
        final name = switch (argument) {
          NamedArgument(:final name) => name.lexeme,
          _ => argument.correspondingParameter?.name,
        };
        for (final rule in arguments[name] ?? const <MigrationRule>[]) {
          if (_invokes(node, rule)) _argument(argument, rule);
        }
      }
    }
    super.visitArgumentList(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (arguments.isNotEmpty && node.operator.type == TokenType.EQ) {
      final (
        SimpleIdentifier? field,
        DartType? on,
      ) = switch (node.leftHandSide) {
        PropertyAccess(:final propertyName, :final realTarget) => (
          propertyName,
          realTarget.staticType,
        ),
        PrefixedIdentifier(:final identifier, :final prefix) => (
          identifier,
          prefix.staticType,
        ),
        // A field of the class the code is in, or of what it mixes in.
        final SimpleIdentifier name
            when node.writeElement?.enclosingElement is InterfaceElement =>
          (name, _enclosingThis(name)),
        _ => (null, null),
      };
      if (field != null && on is InterfaceType) {
        for (final rule in arguments[field.name] ?? const <MigrationRule>[]) {
          final aboutAField =
              rule.member == null || rule.members.contains(rule.member);
          if (aboutAField &&
              _isOfRule(on, rule) &&
              _ownedAs(on.element, rule)) {
            _assigned(node, field, rule);
          }
        }
      }
    }
    super.visitAssignmentExpression(node);
  }

  /// Whether [list] is the arguments of a call [rule] is about: a creation
  /// of [MigrationRule.type] or a subclass, a method of it — only the one
  /// named [MigrationRule.member] when that is no parameter it rewrites —
  /// or the top-level function of that name.
  bool _invokes(ArgumentList list, MigrationRule rule) {
    final member = rule.members.contains(rule.member) ? null : rule.member;
    switch (list.parent) {
      case InstanceCreationExpression(:final constructorName):
        final element = constructorName.type.element;
        return element is InterfaceElement &&
            _ownedAs(element, rule) &&
            _isOfRule(element.thisType, rule) &&
            (member == null ||
                member == (constructorName.name?.name ?? rule.type) ||
                member == constructorName.name?.name);
      case MethodInvocation(:final methodName, :final realTarget):
        final element = methodName.element;
        final enclosing = element?.enclosingElement;
        if (enclosing is LibraryElement) {
          return rule.member == null &&
              methodName.name == rule.type &&
              _ownedAs(element, rule);
        }
        if (member != null && methodName.name != member) return false;
        final on = enclosing is InterfaceElement
            ? enclosing.thisType
            : _classNamed(methodName) ??
                  switch (realTarget?.staticType ??
                      _enclosingThis(methodName)) {
                    final InterfaceType type => type,
                    _ => null,
                  };
        return on != null && _isOfRule(on, rule) && _ownedAs(on.element, rule);
    }
    return false;
  }

  /// [argument] renamed and its value rewritten as [rule] says, when the
  /// value is of a type the rule rewrites.
  void _argument(Argument argument, MigrationRule rule) {
    final value = argument.argumentExpression;
    final values = _valuesOfOldType(value, rule);
    if (values.isEmpty) return;
    final edits = <MigrationEdit>[
      if ((rule.to, argument) case (final to?, NamedArgument(:final name)))
        MigrationEdit(name.offset, name.length, to),
    ];
    if (rule.template case final template?) {
      for (final v in values) {
        final text = _valueText(template, v);
        if (text == null) {
          _add(rule, v);
          return;
        }
        edits.add(MigrationEdit(v.offset, v.length, text));
      }
      edits.addAll(_importsFor(rule));
    }
    if (edits.isNotEmpty) _add(rule, argument, edits: edits);
  }

  /// The parts of [value] [rule] rewrites: [value] itself when it is of an
  /// old type, or the branches of a `??` or a `?:` that are, where the
  /// others are of the new type already (`old?.glow ?? Vector4(…)`).
  List<Expression> _valuesOfOldType(Expression value, MigrationRule rule) {
    if (_typeFits(value, rule)) return <Expression>[value];
    if (rule.types.isEmpty) return const <Expression>[];
    return switch (value) {
      BinaryExpression(:final operator, :final leftOperand, :final rightOperand)
          when operator.type == TokenType.QUESTION_QUESTION =>
        <Expression>[
          ..._valuesOfOldType(leftOperand, rule),
          ..._valuesOfOldType(rightOperand, rule),
        ],
      ConditionalExpression(:final thenExpression, :final elseExpression) =>
        <Expression>[
          ..._valuesOfOldType(thenExpression, rule),
          ..._valuesOfOldType(elseExpression, rule),
        ],
      ParenthesizedExpression(:final expression) => _valuesOfOldType(
        expression,
        rule,
      ),
      _ => const <Expression>[],
    };
  }

  /// `x.field = value` with [field] renamed and the value rewritten.
  void _assigned(
    AssignmentExpression node,
    SimpleIdentifier field,
    MigrationRule rule,
  ) {
    final value = node.rightHandSide;
    final values = _valuesOfOldType(value, rule);
    if (values.isEmpty) return;
    final edits = <MigrationEdit>[
      if (rule.to case final to?) MigrationEdit(field.offset, field.length, to),
    ];
    if (rule.template case final template?) {
      for (final v in values) {
        final text = _valueText(template, v);
        if (text == null) {
          _add(rule, v);
          return;
        }
        edits.add(MigrationEdit(v.offset, v.length, text));
      }
      edits.addAll(_importsFor(rule));
    }
    if (edits.isNotEmpty) _add(rule, node, edits: edits);
  }

  /// A read of a field [rules] retyped whose value is then used as the old
  /// type — `lamp.glow.x`, `view.clearColor.setValues(…)` — which no
  /// rewrite of a value reaches: a TODO.
  void _readOfOldType(SimpleIdentifier node, List<MigrationRule> rules) {
    final AstNode whole = switch (node.parent) {
      final PrefixedIdentifier p when p.identifier == node => p,
      final PropertyAccess p when p.propertyName == node => p,
      _ => node,
    };
    final outer = whole.parent;
    final used = switch (outer) {
      PropertyAccess(:final target) => target == whole,
      MethodInvocation(:final target) => target == whole,
      PrefixedIdentifier(:final prefix) => prefix == whole,
      _ => false,
    };
    if (!used) return;
    // `.x` of the old type, which the new one names otherwise: renamed
    // where the analyzer finds no such member on the new type.
    final SimpleIdentifier? read = switch (outer) {
      PropertyAccess(:final propertyName) => propertyName,
      PrefixedIdentifier(:final identifier) => identifier,
      _ => null,
    };
    for (final rule in rules) {
      if (rule.types.isEmpty || !_isMemberOf(node, rule)) continue;
      if (read != null && read.element == null) {
        if (rule.fields[read.name] case final renamed?) {
          _add(
            rule,
            read,
            edits: <MigrationEdit>[
              MigrationEdit(read.offset, read.length, renamed),
            ],
          );
          continue;
        }
      }
      _add(rule, node);
    }
  }

  /// Whether [value] is of a type [rule] rewrites.
  static bool _typeFits(Expression value, MigrationRule rule) {
    if (rule.types.isEmpty) return true;
    final type = value.staticType;
    return type is InterfaceType &&
        rule.types.any((String t) => _isOrExtends(type, t));
  }

  /// [template] with [value] in it: `{components}` the components as a
  /// vector's creation lists them (or `v.x, v.y, …` of a name), `{value}`
  /// the value itself, bare where the template hands it on as an argument
  /// and in parentheses where it is an operand. Null where [value] has no
  /// components this can write without evaluating it twice.
  String? _valueText(String template, Expression value) {
    // A colour turned into a vector only to be passed on as one, where the
    // template makes it a colour again with the same numbers: the colour.
    if (template == 'LinearColor({components})' &&
        value is MethodInvocation &&
        (value.methodName.name == 'toVector3' ||
            value.methodName.name == 'toVector4') &&
        value.argumentList.arguments.isEmpty) {
      final target = value.realTarget;
      final type = target?.staticType;
      if (target != null &&
          type is InterfaceType &&
          type.element.name == 'LinearColor') {
        return _text(target);
      }
    }
    final parts = template.contains('{components}') ? _components(value) : '';
    if (parts == null) return null;
    final text = template.replaceAll('{components}', parts);
    return text.replaceAllMapped('{value}', (Match m) {
      final before = text.substring(0, m.start).trimRight();
      final after = text.substring(m.end).trimLeft();
      final handedOn =
          (before.isEmpty ||
              before.endsWith('(') ||
              before.endsWith(',') ||
              before.endsWith(':') ||
              before.endsWith('[')) &&
          (after.isEmpty ||
              after.startsWith(')') ||
              after.startsWith(',') ||
              after.startsWith(']'));
      return handedOn ? _text(value) : _operand(value);
    });
  }

  /// [value]'s components, comma-separated: a vector made right there
  /// gives its own arguments as written, a name of a vector its fields.
  String? _components(Expression value) {
    if (value
        case InstanceCreationExpression(
          constructorName: ConstructorName(name: null),
          argumentList: ArgumentList(:final arguments),
        )
        when arguments.isNotEmpty &&
            arguments.every((Argument a) => a is! NamedArgument)) {
      return arguments.map(_text).join(', ');
    }
    final type = value.staticType;
    final fields = switch (type is InterfaceType ? type.element.name : null) {
      'Vector2' => const <String>['x', 'y'],
      'Vector3' => const <String>['x', 'y', 'z'],
      'Vector4' => const <String>['x', 'y', 'z', 'w'],
      _ => null,
    };
    if (fields == null || !_isPath(value)) return null;
    final name = _text(value);
    return fields.map((String f) => '$name.$f').join(', ');
  }

  /// Whether [e] is a name or a chain of field reads, which reads the same
  /// value however many times it is written.
  static bool _isPath(Expression e) => switch (e) {
    Identifier() || ThisExpression() => true,
    PropertyAccess(:final target?) => _isPath(target),
    _ => false,
  };

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

/// Calls [found] with each read of [element] under the node it visits.
final class _ReadsOf extends RecursiveAstVisitor<void> {
  _ReadsOf(this.element, this.found);
  final Element element;
  final void Function(SimpleIdentifier read) found;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == element && !node.inDeclarationContext()) found(node);
  }
}

/// Collects the `this.x` parameters under the node it visits, whether or
/// not they carry a default.
final class _FieldFormals extends RecursiveAstVisitor<void> {
  _FieldFormals(this.found);
  final List<FieldFormalParameter> found;

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    found.add(node);
    super.visitFieldFormalParameter(node);
  }
}
