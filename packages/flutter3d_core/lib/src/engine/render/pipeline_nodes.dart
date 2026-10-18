/// The kinds of node a pipeline document names, and the registry they are
/// found in (D44).
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show PluginException, PluginRegistry, PluginScope, Registration;

import '../../formats/pipeline_document.dart';
import 'render_node.dart';

/// What a [PipelineNodeKind] is handed to make one node: one object that
/// can gain members.
final class PipelineNodeContext {
  /// What a kind is handed to make [node].
  const PipelineNodeContext(this.node);

  /// The node as the document wrote it: its name, where it stands, what it
  /// touches and its [PipelineNode.options].
  final PipelineNode node;
}

/// A kind of node a pipeline document can name (D44): what turns a node
/// written as data — a name, an anchor, its options — into a [RenderNode].
///
/// **How a pipeline of one's own reaches nodes of a plugin's own.** A Dart
/// plugin registers its kinds with the renderer's [PipelineNodeKinds]
/// (`host.registry<PipelineNodeKinds>()`); a document — a project's, or a
/// data plugin's `pipeline:` section — names a node's kind, and
/// `RendererSteps.fromDocument` makes it with [create]. Extendable outside
/// this package, and stays so through 1.x.
abstract base class PipelineNodeKind {
  /// Lets a subclass be const.
  const PipelineNodeKind();

  /// The kind's name, in its plugin's namespace: `acme_glow.glow`.
  String get name;

  /// The node [context] describes. Its [RenderNode.name] is the document
  /// node's name.
  RenderNode create(PipelineNodeContext context);

  @override
  String toString() => 'PipelineNodeKind($name)';
}

/// The kinds of node a renderer's pipeline documents may name (D44): a
/// companion of the render steps.
final class PipelineNodeKinds extends PluginRegistry {
  /// A renderer's, empty.
  PipelineNodeKinds() : _kinds = <PipelineNodeKind>[], _scope = null;

  PipelineNodeKinds._scoped(this._kinds, this._scope);

  final List<PipelineNodeKind> _kinds;
  final PluginScope? _scope;

  /// Every kind, in the order it was added.
  List<PipelineNodeKind> get kinds =>
      List<PipelineNodeKind>.unmodifiable(_kinds);

  /// The kind called [name], or null.
  PipelineNodeKind? kindNamed(String name) {
    for (final kind in _kinds) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  /// Makes [kind] one a document may name, until the result is cancelled.
  /// Through a plugin's view, a [PluginException] for a kind outside its
  /// namespace; an [ArgumentError] for a name another kind has.
  Registration add(PipelineNodeKind kind) {
    final problem = _scope?.manifest.nameProblem(
      kind.name,
      what: 'the node kind',
    );
    if (problem != null) throw PluginException(problem);
    if (kindNamed(kind.name) != null) {
      throw ArgumentError.value(
        kind.name,
        'kind',
        'another node kind has this name',
      );
    }
    _kinds.add(kind);
    final registration = Registration(() => _kinds.remove(kind));
    _scope?.track(registration);
    return registration;
  }

  @override
  PipelineNodeKinds forPlugin(PluginScope scope) =>
      PipelineNodeKinds._scoped(_kinds, scope);
}
