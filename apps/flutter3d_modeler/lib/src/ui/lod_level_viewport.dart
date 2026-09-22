/// One third of screen 17, drawn for real — what `LodScreen`'s own
/// `LodViewportBuilder` answers with in the running application.
///
/// **A stage of its own per level, off the one device.** A simplified mesh is
/// not in the document — `LodMeshCache` makes it and nothing keeps it — so it
/// cannot be reached through the document's own `ModelerStage`, which draws
/// what the project says. `retarget_viewports.dart` is the precedent: a
/// second `ModelerStage.fromProject` on the renderer's own device, around a
/// project of one object that exists only to be looked at. Here the one
/// object is the level's `MeshData` as `ImportedGeometry`, which is what a
/// mesh with no topology to edit already is.
///
/// **Rebuilt when the mesh is a different object, and not otherwise.**
/// `LodMeshCache.meshFor` hands back the same `MeshData` until the object's
/// version moves, and this widget is rebuilt on every tick of the render
/// loop; comparing by identity is what makes those two facts add up to one
/// upload per edit rather than one per frame.
library;

import 'package:flutter/material.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_model_core/flutter3d_model_core.dart' hide Outcome;
import 'package:vector_math/vector_math.dart' as vm;

import '../../l10n/app_localizations.dart';
import '../modeler_viewport.dart';
import '../staging.dart';

/// [mesh] in a viewport of its own, turning with [leader].
class LodLevelViewport extends StatefulWidget {
  const LodLevelViewport({
    super.key,
    required this.renderer,
    required this.lodIndex,
    required this.mesh,
    required this.leader,
  });

  /// The one device every viewport in this application draws through.
  final Renderer renderer;

  /// Which level this is, for the sentence an empty third shows.
  final int lodIndex;

  /// The level's own simplified mesh, or null when the object has no such
  /// level yet — `LodMeshCache.meshFor`'s own answer, passed straight on.
  final MeshData? mesh;

  /// The document's own camera orbit. The three thirds are a comparison, and
  /// a comparison of one shape from three angles compares nothing: whichever
  /// third a person turns, this is turned with it, and the other two follow
  /// on the next frame.
  final OrbitController leader;

  @override
  State<LodLevelViewport> createState() => _LodLevelViewportState();
}

class _LodLevelViewportState extends State<LodLevelViewport> {
  ModelerStage? _stage;

  /// Which [MeshData] [_stage] was built for — by identity, see the file's
  /// own doc comment.
  MeshData? _builtFor;

  /// The angles this third was last set to, so that a difference on the next
  /// build can only be a person's own hand on it.
  double? _setYaw;
  double? _setPitch;

  void _rebuildStageIfNeeded() {
    final MeshData? mesh = widget.mesh;
    if (identical(mesh, _builtFor)) return;
    _builtFor = mesh;
    _setYaw = null;
    _setPitch = null;
    if (mesh == null) {
      _stage = null;
      return;
    }
    final ModelerStage stage = ModelerStage.fromProject(
      device: widget.renderer.device,
      project: const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'lod',
          // **Into the layout the stage draws.** The simplifier answers in
          // position, normal and UV — eight floats a vertex — whatever it
          // was handed, and `SceneSync` takes an imported mesh's layout on
          // trust as `VertexLayout.standard`, sixteen. Handed over as it
          // comes, the first pass to read a tangent reads past the end of
          // the vertex: `lod_mode_test.dart` found it as a `RangeError`
          // inside the shadow map. The tangents and colours it gains are
          // the neutral ones, which is right for a preview drawn in clay.
          geometry: ImportedGeometry(mesh.convertedTo(VertexLayout.standard)),
          transform: vm.Matrix4.identity(),
        ),
      ),
    );
    stage.frameSubject();
    _stage = stage;
  }

  /// Keeps this third's angles and [LodLevelViewport.leader]'s the same.
  ///
  /// Whichever moved is the one that is believed: a third whose angles are
  /// not what this last set them to was turned by a person since, so the
  /// leader takes them; otherwise the leader is the news and the third
  /// follows. Distance is left alone — each level is framed to its own
  /// bounds, and a simplified mesh's bounds are not quite the original's.
  void _followOrLead(OrbitController own) {
    final OrbitController leader = widget.leader;
    if (_setYaw != null && (own.yaw != _setYaw || own.pitch != _setPitch)) {
      leader
        ..yaw = own.yaw
        ..pitch = own.pitch
        ..apply();
    } else if (own.yaw != leader.yaw || own.pitch != leader.pitch) {
      own
        ..yaw = leader.yaw
        ..pitch = leader.pitch
        ..apply();
    }
    _setYaw = own.yaw;
    _setPitch = own.pitch;
  }

  @override
  Widget build(BuildContext context) {
    _rebuildStageIfNeeded();
    final ModelerStage? stage = _stage;
    if (stage == null) {
      return Center(
        child: Text(
          AppLocalizations.of(context).lodPaneEmpty(widget.lodIndex),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    _followOrLead(stage.orbit);
    return ModelerViewport(
      renderer: widget.renderer,
      stage: stage,
      onFrame: () {},
      grid: null,
      // No gizmo, no wireframe, no floor: there is nothing in a third to
      // pick or to edit, and four idle overlays apiece would be twelve.
      overlay: false,
    );
  }
}
