/// The layers the dungeon draws on.
///
/// Bit zero is the default every node is born on and every view draws. Bit
/// one is what walks: the actors' meshes are put on it as well, so a render
/// setting can name them without naming the walls — which is what the sensor
/// power-up does through `RenderSettings.xray`.
abstract final class DungeonLayers {
  /// Everything: the level, its furniture, and the actors too.
  static const int world = 1;

  /// The actors alone, beside [world].
  static const int actors = 1 << 1;
}
