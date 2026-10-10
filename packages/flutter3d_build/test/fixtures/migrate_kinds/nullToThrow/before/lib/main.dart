import 'package:flutter3d_kinds/flutter3d_kinds.dart';

String greeting(String path) {
  final text = loadText(path) ?? 'hello';
  return text.toUpperCase();
}

String? firstLine(String path) {
  final text = loadText(path);
  if (text == null) {
    return null;
  }
  return text.split('\n').first;
}

String title(String path) => loadText(path) ?? 'untitled';

void show(String path) {
  print(loadText(path) ?? '(none)');
}

final List<String?> cache = <String?>[];

void keep(String path) {
  cache.add(loadText(path));
}
