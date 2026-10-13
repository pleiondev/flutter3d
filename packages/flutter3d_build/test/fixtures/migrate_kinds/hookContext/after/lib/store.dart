import 'package:flutter3d_kinds/flutter3d_kinds.dart';

final class Disk extends Store {
  const Disk();

  @override
  Future<int> read(Reading reading) async => 1;
}

Future<int> twice(Store store) async {
  final first = await store.read(const Reading());
  return first + await store.read(const Reading());
}
