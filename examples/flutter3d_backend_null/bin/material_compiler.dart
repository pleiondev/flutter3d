// The null backend's material compiler as the build runs it: a project
// that depends on this package has its engine bundle and every plugin
// material compiled with `NullMaterialCompiler` too, because the pubspec's
// `flutter3d_backend:` names this file. The build hands it a request and a
// path, and reads the section back from there.
//
//     dart run flutter3d_backend_null:material_compiler <request.json> <out>
import 'dart:io';

import 'package:flutter3d_backend_null/flutter3d_backend_null.dart';
import 'package:flutter3d_shaders/compile.dart' show runMaterialCompiler;

void main(List<String> arguments) =>
    exit(runMaterialCompiler(const NullMaterialCompiler(), arguments));
