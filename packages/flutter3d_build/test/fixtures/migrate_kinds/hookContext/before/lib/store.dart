import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final class Disk extends Depot {
  const Disk();

  @override
  Future<int> read() async => 1;
}

Future<int> twice(Depot store) async {
  final first = await store.read();
  return first + await store.read();
}
