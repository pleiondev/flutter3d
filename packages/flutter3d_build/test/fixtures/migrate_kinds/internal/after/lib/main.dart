// TODO(flutter3d-1.0): `OldStage` and `oldHelper` were flutter3d_kinds's own and are not exported since 1.0.0-rc.1. A stage of your own is written with `Kit`. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#internal-flutter3d_kinds
import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final Object stage = OldStage();

double shade(double x) => oldHelper(x) + oldHelper(x * 2);

const Kit kit = Kit();
