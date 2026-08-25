/// The one place the engine's graphics vocabulary becomes flutter_gpu's.
///
/// Every translation between `graphics/formats.dart` and `flutter_gpu` lives
/// here and nowhere else. If two files translated [CullMode], one of them would
/// eventually be wrong, and a wrong mapping is the quietest defect in this
/// codebase: it compiles, it runs, and it renders wrong only for the values a
/// scene happens to use.
///
/// ## Every switch here is an expression with no `default`
///
/// That is not a style preference. A Dart `switch` *expression* over an enum
/// must be exhaustive, so the analyser refuses to compile a mapping that misses
/// a value — which turns "somebody added a value and forgot the mapping" from a
/// silent wrong render into a build error. A `default` clause, a wildcard `_`
/// pattern, or a `switch` *statement* would each restore the silence. Do not
/// add one.
///
/// The analyser guards our own enums gaining a value.
/// `test/gpu_formats_test.dart` guards the other direction — flutter_gpu
/// gaining one — by comparing counts, and guards the mapping itself by
/// asserting that each value lands on the flutter_gpu value of the same name.
///
/// ## Reverse mappings exist only where something reads state back
///
/// Textures carry their storage mode and format, and the opaque texture handle
/// this backend hands out has to answer questions about them without naming
/// flutter_gpu. Pipeline and pass state — cull,
/// blend, depth compare, load and store — is only ever written, so a reverse
/// mapping for it would be code with no reader.
///
/// ## Split by what is being translated
///
/// Storage modes, texture types and pixel formats are `gpu_formats_resources.dart`;
/// sampler filtering and addressing, plus the sampler cache, are
/// `gpu_formats_sampling.dart`; write-only pass and pipeline state — load and
/// store actions, rasteriser and blend settings — is
/// `gpu_formats_pass_state.dart`; index and vertex formats are
/// `gpu_formats_geometry.dart`. All four are re-exported from here.
library;

export 'gpu_formats_geometry.dart';
export 'gpu_formats_pass_state.dart';
export 'gpu_formats_resources.dart';
export 'gpu_formats_sampling.dart';
