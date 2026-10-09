/// What a package's own build hook needs to compile its materials, and
/// nothing else: [compileMaterial] for one material source, the compilers it
/// runs ([MaterialCompilers]), the typed accessors a package commits beside
/// them ([generateMaterialAccessors]), and [MaterialBuildException] when a
/// material does not build.
///
/// **A light package on purpose.** A build hook runs for every application
/// that depends on its package, so what the hook imports is resolved into
/// every game. `flutter3d_build`, the converter and the command line, also
/// brings the MCP servers and their protocol; a hook that only compiles a
/// material needs none of it. `flutter3d_build` exports this library, so a
/// project's hook that already depends on it sees the same names.
library;

export 'src/material_accessors.dart';
export 'src/material_compile.dart';
