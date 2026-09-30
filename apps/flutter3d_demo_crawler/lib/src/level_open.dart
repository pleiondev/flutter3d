/// Reads a level document and builds the half of it that draws.
///
/// Apart from `staging.dart` because everything here needs a graphics device,
/// and that file exists to be callable without one.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_crawler/flutter3d_game_crawler.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'looks.dart';

/// Where a level named `next` in a document lives.
String levelAsset(String name) => 'assets/levels/$name.json';

/// The first level.
const String firstLevel = 'gatehouse';

Future<({EntityRegistry kinds, LoadedLevel loaded, FixtureVisuals fixtures})>
openLevel(String asset, {required GraphicsDevice device}) async {
  // One registry reads the document, validates it and — through `stage` —
  // spawns it, so what the loader accepted and what the crawl contains agree.
  final kinds = crawlerRegistry();
  final loaded = await LevelLoader().load(
    asset,
    device: device,
    registry: kinds,
    rules: crawlerRules(),
  );
  final fixtures = FixtureVisuals(
    loaded.scene,
    loaded,
    appearance: const CrawlerLooks(),
    device: device,
  )..bindLights();
  return (kinds: kinds, loaded: loaded, fixtures: fixtures);
}
