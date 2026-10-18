/// A plugin's points in the frame, drawn on a backend: the render checks.
///
/// **The third part of the conformance suite, and a package of its own.**
/// `flutter3d_conformance` holds a backend to the hardware contract and,
/// through `plugins.dart`, a plugin to the loop's; this draws what a plugin
/// adds to the frame on a device, through the renderer, and checks that
/// each point does what it says on that backend. It is apart because it
/// needs the renderer (`flutter3d_core`), which neither the backends'
/// contract suite nor the loop's needs, so a backend that runs the contract
/// as a dev dependency does not pull the engine in. A plugin runs it from
/// its own suite once per backend it ships for:
///
/// ```dart
/// import 'package:flutter3d_conformance_render/flutter3d_conformance_render.dart';
///
/// void main() => runPluginRenderConformance(
///   HairPlugin.new,
///   backend: 'cpu',
///   device: () => CpuDevice(width: 32, height: 32, shaders: hairShaders()),
///   points: PluginRenderPoints(litModel: hairModel),
/// );
/// ```
///
/// ## The 12 render checks
///
/// * **render.nodes**: every node the plugin places runs in a frame, and
///   none once the plugin is switched off; and the points name every node
///   it places.
/// * **render.litModel**: a box drawn through the plugin's lit model is a
///   picture of its own, and every block and texture of its slot table
///   reaches the stage: moving a block's first member, or darkening a
///   texture, moves the picture (D21).
/// * **render.litModelDefaults**: a box drawn through the lit model by a
///   material that sets nothing is the box drawn with every member at the
///   default its source declares and every texture of its own white: no
///   slot is left unbound (D21).
/// * **render.lightType**: the type has a hook and a code of a plugin's
///   own, and a box lit by it alone is lit.
/// * **render.decal**: the decal pass runs with the plugin's stage and
///   paints the floor.
/// * **render.velocity**: the node reading the velocity runs after the
///   camera velocity, with neither of the engine's readers on.
/// * **render.shadows**: each producer the technique hands the frame, for
///   the directional map and for the cube atlas, is run.
/// * **render.drawList**: the draw-list hook is the renderer's while the
///   plugin is on, is asked of a frame's meshes, and is gone once it is
///   off.
/// * **render.lod**: the level-of-detail policy is among the renderer's, a
///   frame with a group in it asks the chain, and it goes with the plugin.
/// * **render.skinning**: the skinning hook is placed, and goes with the
///   plugin.
/// * **render.compute**: the compute step's node runs where the device
///   computes and is skipped with the typed refusal where it does not.
/// * **render.codec**: the image format is among the engine's codecs,
///   decodes its sample to the size given, and goes with the plugin.
///
/// A device that draws no picture (a recording fake) is held to the
/// structure: the parts that compare pictures are declined, saying so.
///
/// ## The badge
///
/// **For a plugin that draws, these are part of the badge.** The plugin
/// suite's `plugin.render` finds whether the plugin places nodes in the
/// frame; one that does earns `conformant@1.0` only with `render.nodes`
/// passed here on `cpu`. [runPluginRenderConformance] writes its outcomes
/// into the plugin's `<package>.conformance.json` beside the plugin
/// suite's, and a render check that failed on any backend keeps the badge
/// away.
library;

import 'package:flutter3d_conformance/plugins.dart'
    show PluginCheckOutcome, recordRenderOutcomes;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dPlugin;
import 'package:test/test.dart';

import 'src/render_checks.dart';

export 'src/render_checks.dart'
    show
        PluginCodecPoint,
        PluginRenderPoints,
        RenderCheckDevice,
        RenderCheckMaterials,
        RenderCheckRegistries,
        checkPluginRender,
        pluginRenderCheckNames;

/// The render checks of [points] as tests, one a check, for the plugin
/// [create] makes on the devices [device] opens, named for [backend].
///
/// [materials], [registries] and [engineBackend] are [checkPluginRender]'s:
/// the plugin's stages loaded for a GPU backend, what the application hands
/// the plugin beside the renderer, and the backend the engine says it draws
/// with. A declined check is reported as skipped with its reason.
void runPluginRenderConformance(
  Flutter3dPlugin Function() create, {
  required RenderCheckDevice device,
  required PluginRenderPoints points,
  required String backend,
  RenderCheckMaterials? materials,
  RenderCheckRegistries? registries,
  String? engineBackend,
}) {
  late final Future<List<PluginCheckOutcome>> outcomes = checkPluginRender(
    create,
    device: device,
    points: points,
    backend: backend,
    materials: materials,
    registries: registries,
    engineBackend: engineBackend,
  );
  // Into the plugin's report, beside the plugin suite's: the badge of a
  // plugin that draws is judged on both.
  tearDownAll(() async {
    recordRenderOutcomes(create().manifest.id, await outcomes);
  });
  for (final check in pluginRenderCheckNames) {
    test('$check on $backend', () async {
      final found = (await outcomes).where((o) => o.check == check).toList();
      if (found.isEmpty) {
        markTestSkipped('the plugin names no point for $check');
        return;
      }
      for (final outcome in found) {
        if (outcome.declined) {
          markTestSkipped(outcome.says);
        } else {
          expect(outcome.passed, isTrue, reason: '$outcome');
        }
      }
    });
  }
}
