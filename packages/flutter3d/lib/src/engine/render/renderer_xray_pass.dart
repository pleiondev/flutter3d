/// The x-ray stage: silhouettes of the nodes a layer names, wherever the
/// scene hides them.
///
/// A `part` of `renderer.dart` — see `renderer_shadow_pass.dart` for why.
///
/// Two draws per marked node, inside the scene pass, after everything else
/// that writes or blends. The first **marks**: the node is drawn again with
/// no colour — [BlendState.keepDestination] — no depth write, a depth test
/// of `lessEqual`, and a stencil that stores one wherever a fragment passes.
/// After the opaque half those fragments are exactly the node's visible
/// pixels, because the node itself wrote the depth they are equal to. The
/// second **paints**: the node is drawn a third time as a flat colour with
/// a depth test of `greater` — only where something in the buffer is nearer
/// — and a stencil test of `notEqual` one, only where no marked node's
/// visible part is.
///
/// **The stencil is what the second test is for, and it is not decorative.**
/// A depth test of `greater` alone paints a silhouette over every pixel a
/// node's hidden fragments reach, and a node's hidden fragments reach its own
/// visible ones: a far limb behind a near one, the back of a cube behind its
/// front. Without the mark, a monster half behind a wall would have its
/// visible half painted flat by its own hidden half, and a monster behind
/// another monster would paint through the one in front. With every mark
/// written before any paint, the visible parts of all of them are held.
///
/// The two draws go through `_encodeNode` with an override, so a skinned
/// monster is skinned in both, an instanced batch is drawn as a batch, and
/// the mesh's own culling and winding are what they were — the only things
/// that change are the material, the blend and the stencil.
part of 'renderer.dart';

extension _XrayPass on Renderer {
  /// Marks and paints every node of this view's render list that the
  /// settings' layer mask names. Nothing is emitted — not one stencil call —
  /// when the mask is zero, the device has no stencil, or no visible node is
  /// on the layer, which is what keeps every picture without silhouettes the
  /// bytes it was.
  ///
  /// **Two ways a marked node draws no silhouette and says nothing about
  /// it.** Both are the stage working as built rather than faults, and both
  /// are the sort of thing that gets reported as one.
  ///
  /// The list read here is `_renderList`, which is what survived culling. A
  /// marked node the frustum test dropped, or one a level's precomputed
  /// visibility dropped — `flutter3d_sim`'s `visibility_culler`, which the
  /// dungeon uses — is not in it and contributes nothing. So a sensor does
  /// not show a monster the level says cannot be seen from here, which reads
  /// as a bug from a corridor away and is the culler's answer, not this
  /// stage's. Nothing shorter than "draw the marked nodes from an unculled
  /// list" changes it, and that is a per-frame cost for a per-app decision.
  ///
  /// **Only opaque geometry hides anything**, because only opaque geometry
  /// writes depth, and the paint's `greater` test is against the depth
  /// buffer. A monster behind glass, or behind a particle sheet, is in front
  /// of everything the buffer knows about and gets no silhouette — which is
  /// right, since it can be seen through them, and worth stating because the
  /// picture and the reason are far apart. A marked node whose *own* material
  /// is transparent is unaffected: both draws take their depth state from the
  /// override material rather than from the node's, so a transparent monster
  /// behind a wall gets exactly the silhouette an opaque one would.
  void _encodeXray({
    required PassEncoder encoder,
    required Scene scene,
    required RenderSettings settings,
    required vm.Matrix4 viewProjection,
    required SceneShadows shadows,
    required LightBuffer lights,
    required Float32List shadowSlots,
    required FramePassState state,
  }) {
    final xray = settings.xray;
    // Asked, not assumed. A device that answers false is not offered a
    // stencil test to ignore; it draws no silhouettes, and the frame is the
    // frame it would have drawn before this stage existed.
    if (!xray.enabled || !device.supportsStencil) return;

    _xrayNodes.clear();
    for (var i = 0; i < _renderList.length; i++) {
      final node = _renderList.itemAt(i).requireNode;
      if ((node.layerMask & xray.layerMask) != 0) _xrayNodes.add(node);
    }
    if (_xrayNodes.isEmpty) return;

    final colour = xray.resolvedColor;
    _xraySilhouette.baseColor.setValues(colour.x, colour.y, colour.z, 1.0);

    void drawAll(_DrawOverride override) {
      for (final node in _xrayNodes) {
        // The node's own answer to which faces exist, so a cape drawn from
        // both sides is marked and painted from both sides too.
        override.material.doubleSided = node.material.doubleSided;
        _encodeNode(
          encoder: encoder,
          node: node,
          scene: scene,
          settings: settings,
          viewProjection: viewProjection,
          shadows: shadows,
          lights: lights,
          shadowSlots: shadowSlots,
          state: state,
          override: override,
        );
      }
    }

    encoder.setStencilReference(Renderer._kXrayReference);
    encoder.setStencil(Renderer._kXrayMarkStencil);
    drawAll(
      _DrawOverride(material: _xrayMark, blend: BlendState.keepDestination),
    );
    encoder.setStencil(Renderer._kXraySilhouetteStencil);
    drawAll(_DrawOverride(material: _xraySilhouette, blend: null));
    // Off, said out loud, for the backend whose setters are context state:
    // the contributors that follow and the next view's meshes are not part
    // of this. Depth compare is left to the tracker, which the next mesh
    // reads and re-establishes exactly as it does after the sky.
    encoder.setStencil(StencilState.disabled);
  }
}
