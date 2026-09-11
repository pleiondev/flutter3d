/// STL, binary and ASCII.
///
/// Same shape as the other decoders in this package: no dependency on a
/// graphics backend, `dart:io` or `dart:ui`, and the output is a
/// [ModelDocument] so it uploads through the same code path as glTF and OBJ.
/// There is no writer — nothing in the plan asks for one, and a triangle soup
/// with no materials, hierarchy or animation is already what every other
/// writer's simplest case degenerates to.
library;

export '../model_document.dart';
export 'stl_loader.dart';
