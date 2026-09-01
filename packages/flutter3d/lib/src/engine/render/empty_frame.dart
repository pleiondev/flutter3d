/// Why a frame drew nothing, in a sentence.
///
/// **A black viewport is the least informative failure this engine has**, and
/// it has many causes that look identical: a scene with no meshes, a scene of
/// meshes that are all hidden, a layer mask matching none of them, a camera
/// pointing away from everything, a viewport of zero width. Each one is
/// obvious once named and indistinguishable until then, and the picture cannot
/// name any of them — it is the same black either way.
///
/// So the frame names it. This is separate from the renderer and free of any
/// GPU type on purpose: which of those five happened is a question about a
/// scene and a list of views, both of which a test can build with no device.
library;

import '../scene/mesh_node.dart';
import '../scene/scene.dart';
import 'render_view.dart';

/// Why [scene] drew nothing through [views], or null when something did draw.
///
/// Called only when the frame submitted no draws, so "nothing drew" is the
/// caller's measurement rather than this function's guess. The order of the
/// checks is the order of the causes' bluntness: a scene with no meshes at all
/// is a different mistake from one whose meshes are all behind the camera, and
/// reporting the blunter one first keeps the message about the first thing
/// worth fixing.
///
/// **What it deliberately does not do is cull.** Whether a given mesh is inside
/// a given frustum is the render list's answer, arrived at with the view
/// matrix and the frustum this does not have; repeating that work here would
/// be a second implementation of culling whose disagreement with the first is
/// exactly the bug it would be reporting. The last case is therefore phrased as
/// the elimination it is: meshes exist, they are visible, a mask matches them,
/// and the viewport has area — so what remains is where they are.
String? describeEmptyFrame(Scene scene, List<RenderView> views) {
  if (views.isEmpty) {
    return 'nothing drew: the frame was given no views to draw through.';
  }

  final meshes = scene.meshes;
  if (meshes.isEmpty) {
    return 'nothing drew: the scene holds no meshes. A mesh reaches the '
        'registry by being attached to the scene, so a node built and never '
        'added draws nothing and reports nothing.';
  }

  var visible = 0;
  var withGeometry = 0;
  for (var i = 0; i < meshes.length; i++) {
    final mesh = meshes[i];
    if (!mesh.visibleInHierarchy) continue;
    visible++;
    if (mesh.mesh.indexCount != 0) withGeometry++;
  }

  if (visible == 0) {
    return 'nothing drew: all ${meshes.length} meshes in the scene are '
        'hidden. Visibility is inherited, so one invisible ancestor hides a '
        'subtree whose own nodes all say they are visible.';
  }

  if (withGeometry == 0) {
    return 'nothing drew: all $visible visible meshes have empty geometry. '
        'A mesh with no indices is skipped, which is what an asset that '
        'failed to upload leaves behind.';
  }

  var matched = 0;
  for (var i = 0; i < meshes.length; i++) {
    final mesh = meshes[i];
    if (!mesh.visibleInHierarchy || mesh.mesh.indexCount == 0) continue;
    for (var v = 0; v < views.length; v++) {
      if ((mesh.layerMask & views[v].layerMask) != 0) {
        matched++;
        break;
      }
    }
  }

  if (matched == 0) {
    return 'nothing drew: no view\'s layer mask matches any visible mesh. '
        '${_maskSummary(views, meshes)}';
  }

  // A viewport of zero area is not a case here, and that is worth stating
  // rather than leaving as an omission: `ViewportRect` asserts a width and a
  // height above zero in its constructor, and this whole function runs under
  // an assert too. In any build that can read this message, a zero viewport
  // has already thrown at the point it was written — which is a better report
  // than one arriving a frame later from the renderer.

  return 'nothing drew: $matched visible meshes matched a view and none '
      'survived culling, so they are outside every view\'s frustum. A camera '
      'left at the origin looking down -Z, a near plane past the scene, or a '
      'model at a scale the frustum does not reach all look like this.';
}

/// The masks in play, since the numbers are what makes this fixable.
String _maskSummary(List<RenderView> views, List<MeshNode> meshes) {
  var meshBits = 0;
  for (var i = 0; i < meshes.length; i++) {
    if (meshes[i].visibleInHierarchy) meshBits |= meshes[i].layerMask;
  }
  var viewBits = 0;
  for (var v = 0; v < views.length; v++) {
    viewBits |= views[v].layerMask;
  }
  return 'The visible meshes are on layers 0x${meshBits.toRadixString(16)} '
      'and the views look at 0x${viewBits.toRadixString(16)}.';
}
