/// The types every flutter3d package shares, below the plugin contract and
/// below the simulation.
///
/// * [Flutter3dException] and its four families, the root of everything the
///   engine throws, [DocumentFormatException], and the two leaves every
///   backend and loader share, [ShaderCompileException] and [AssetNotFoundException];
/// * [WorldPosition], a place in the world in double precision, and
///   [LinearColor], the one colour type, with their crossings into
///   `vector_math`'s float32 vectors ([WorldPositionVector],
///   [Vector3Foundation], [Vector4Foundation], [LinearColorVector]);
/// * [Issue] and [IssueSink], how a library reports what it could not do;
/// * [FormatSpec] and [FormatDocument], the envelope every JSON file the
///   engine writes starts with, and the migrations that lift an old one;
/// * [Registration], what every registry hands back, and [PlacedEvent],
///   the shape of an event that says where it happened;
/// * [Portable], the transcendental functions a step may call, the same bits
///   on every platform.
///
/// **It depends on `vector_math` and nothing else**, so a package that reads
/// a file, throws, or speaks a position needs neither the plugin API nor the
/// physics. `docs/CONTRACTS.md` gives the units every one of these is in.
///
/// Until 1.0.0-rc.1 these lived in `flutter3d_plugin_api` (which still
/// re-exports the ones it had) and `flutter3d_physics` (the crossings and
/// [Portable]).
library;

export 'src/exceptions.dart';
export 'src/formats.dart';
export 'src/issues.dart';
export 'src/linear_color.dart';
export 'src/placed_event.dart';
export 'src/portable_math.dart';
export 'src/registration.dart';
export 'src/vectors.dart';
export 'src/world_position.dart';
