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
/// ## The 6 render checks
///
/// * **render.nodes**: every node the plugin places runs in a frame, and
///   none once the plugin is switched off.
/// * **render.lit model**: a box drawn through the plugin's lit model is a
///   picture of its own, and every block and texture of its slot table
///   reaches the stage: moving a block's first member, or darkening a
///   texture, moves the picture (D21).
/// * **render.light type**: the type has a hook and a code of a plugin's
///   own, and a box lit by it alone is lit.
/// * **render.decal**: the decal pass runs with the plugin's stage and
///   paints the floor.
/// * **render.velocity**: the node reading the velocity runs after the
///   camera velocity, with neither of the engine's readers on.
/// * **render.shadows**: each producer the technique hands the frame, for
///   the directional map and for the cube atlas, is run.
///
/// A device that draws no picture (a recording fake) is held to the
/// structure: the parts that compare pictures are declined, saying so.
library;

import 'package:flutter3d_conformance/plugins.dart' show PluginCheckOutcome;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dPlugin;
import 'package:test/test.dart';

import 'src/render_checks.dart';

export 'src/render_checks.dart'
    show
        PluginRenderPoints,
        RenderCheckDevice,
        RenderCheckMaterials,
        checkPluginRender,
        pluginRenderCheckNames;

/// The render checks of [points] as tests, one a check, for the plugin
/// [create] makes on the devices [device] opens, named for [backend].
///
/// [materials] is [checkPluginRender]'s: the plugin's stages loaded for a
/// GPU backend. A declined check is reported as skipped with its reason.
void runPluginRenderConformance(
  Flutter3dPlugin Function() create, {
  required RenderCheckDevice device,
  required PluginRenderPoints points,
  required String backend,
  RenderCheckMaterials? materials,
}) {
  late final Future<List<PluginCheckOutcome>> outcomes = checkPluginRender(
    create,
    device: device,
    points: points,
    backend: backend,
    materials: materials,
  );
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
