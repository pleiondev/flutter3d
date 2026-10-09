import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter3d_sim/flutter3d_sim.dart' show Level;

/// Loads the level document at [asset] from [bundle], the application's own
/// asset bundle unless another is given.
///
/// What a first game does before anything else, in one call: read the
/// asset's text and [Level.parse] it. Throws what `parse` throws for a
/// document that is not a level, and what the bundle throws for an asset that
/// is not there.
Future<Level> loadLevelAsset(String asset, {AssetBundle? bundle}) async =>
    Level.parse(await (bundle ?? rootBundle).loadString(asset));
