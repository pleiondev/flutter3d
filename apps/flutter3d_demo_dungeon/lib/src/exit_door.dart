import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:vector_math/vector_math.dart';

import 'way_out_glow.dart';

/// The doorway a level ends at.
///
/// Written by `tool/make_models.py` as `exit_arch`: an iron frame round a dark
/// opening, 1.8 by 2.6 by 0.4.
const String kExitModel = 'assets/models/exit.glb';

/// Draws the way out of [level], which nothing used to.
///
/// **An exit was a trigger and nothing else.** `ExitKind` places a collider the
/// player walks into and no geometry at all, so the end of every level was an
/// invisible box in a wall — the editor drew the arch and the game did not,
/// which is the wrong way round for the two of them.
///
/// The model was already here and already credited; it was written for the
/// editor's marks and is the right shape for both, being built to the size the
/// crypt's own editor entry gives a doorway.
///
/// **Placed at the entity's position, unshifted.** An exit is authored at the
/// middle of the opening rather than at its threshold — the crypt's is at
/// `y = 1.3`, which is half of the arch's 2.6 — so the model's origin and the
/// entity's position mean the same point. That is not true of a monster, whose
/// position is its feet, and the difference is worth naming here because the
/// two conventions live one file apart.
///
/// Never throws. A level whose doorway will not load is a level that still ends
/// where it always did: the trigger is the simulation's and this is only what
/// can be seen.
///
/// Returns the uploaded asset — or null when there was nothing to draw or the
/// file would not read — so the level that asked for it can release it in
/// `RunSession.close`. The asset used to be dropped here after instantiating,
/// which left its mesh and maps on the device once per level with nothing
/// holding a name for them.
Future<ModelAsset?> addExitsTo(
  Scene scene,
  Level level, {
  required GraphicsDevice device,
}) async {
  final exits = level.ofType(EntityTypes.exit).toList();
  if (exits.isEmpty) return null;

  try {
    final document = await decodeModelInIsolate(
      ModelLoadRequest(source: const BundleAssetSource(kExitModel)),
    );
    // One asset for every way out, of which levels have one today and could
    // have several — a vault with two doors is a level document, not a change
    // here.
    final asset = await ModelAsset.fromDocument(
      document,
      device: device,
      name: kExitModel,
    );
    for (final exit in exits) {
      final instance = asset.instantiate(
        scene,
        name: 'exit-${exit.name ?? 'way'}',
        // Own materials, because [lightTheWayOut] writes into them and the
        // editor draws this same asset as one of its marks.
        shareMaterials: false,
      );
      lightTheWayOut(instance.meshes);
      instance.root
        ..setPositionFrom(exit.position)
        ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), exit.yaw));
    }
    return asset;
  } catch (error) {
    debugPrint('exit: no doorway drawn ($error)');
    return null;
  }
}
