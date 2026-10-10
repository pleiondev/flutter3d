import 'package:flutter3d_kinds/flutter3d_kinds.dart';

String greeting(String path) {
  // TODO(flutter3d-1.0): `loadText` throws `AssetNotFoundException` in 1.0.0-rc.1 where it returned null. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-loadText-throws
  late final String text;
  try {
    text = loadText(path);
  } on AssetNotFoundException {
    text = 'hello';
  }
  return text.toUpperCase();
}

String? firstLine(String path) {
  // TODO(flutter3d-1.0): `loadText` throws `AssetNotFoundException` in 1.0.0-rc.1 where it returned null. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-loadText-throws
  final String text;
  try {
    text = loadText(path);
  } on AssetNotFoundException {
    return null;
  }
  return text.split('\n').first;
}

String title(String path) {
  // TODO(flutter3d-1.0): `loadText` throws `AssetNotFoundException` in 1.0.0-rc.1 where it returned null. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-loadText-throws
  try {
    return loadText(path);
  } on AssetNotFoundException {
    return 'untitled';
  }
}

void show(String path) {
  // TODO(flutter3d-1.0): `loadText` throws `AssetNotFoundException` in 1.0.0-rc.1 where it returned null. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-loadText-throws
  try {
    print(loadText(path));
  } on AssetNotFoundException {
    print('(none)');
  }
}

final List<String?> cache = <String?>[];

void keep(String path) {
  // TODO(flutter3d-1.0): `loadText` throws `AssetNotFoundException` in 1.0.0-rc.1 where it returned null. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-loadText-throws
  cache.add(loadText(path));
}
