import 'level_light.dart';

/// Lux or candela in one unit of the pre-1.0 level intensity, `π × 1843.2`:
/// a light's default strength, which is one such unit.
///
/// **Frozen with the format, not read from the renderer, and not exported**:
/// it is the unit a level of format 4 or older was written in, and what a
/// file on disk meant does not move when the renderer's constants do. Two
/// things read it: the lift to format 5, which multiplies a light's strength
/// by it, and the lightmap, whose texels and staleness hash are still in
/// that unit so every lightmap baked before stays the level's.
const double legacyLightUnit = LevelLight.defaultIntensity;
