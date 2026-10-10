// Prints the `flutter3d` command's whole surface — the usage and every
// subcommand's help — as `api/flutter3d_build.cli` commits it.
//
//   dart tool/cli_surface.dart > api/flutter3d_build.cli
//
// The same text as `flutter3d help --surface`, from a file that imports
// nothing but the contract, so the repository's structure check can run it
// in a second without compiling the converters.
import 'dart:io';

import 'package:flutter3d_build/src/cli_contract.dart';

void main() => stdout.write(cliSurface());
