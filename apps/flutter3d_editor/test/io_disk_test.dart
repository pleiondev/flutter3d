/// The desktop's disk behind `EditorDisk`: the same writes the editor made
/// before there was a seam, against a temporary directory.
///
/// Each test names the mutation it was written against.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_editor/src/disk/disk_io.dart';
import 'package:flutter3d_editor/src/disk/editor_disk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  const disk = IoDisk();

  setUp(() => temp = Directory.systemTemp.createTempSync('io_disk_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('a VM build gets the disk, and a save writes in place', () {
    // Broken by the conditional import picking the page's disk on the VM,
    // which would turn every desktop save into a download nobody sees.
    expect(editorDisk, isA<IoDisk>());
    expect(editorDisk.savesInPlace, isTrue);
  });

  test('a document is written over itself and the bar says where', () async {
    final path = '${temp.path}/level.json';
    File(path).writeAsStringSync('old');

    final said = await disk.writeDocument(path, 'new');

    expect(File(path).readAsStringSync(), 'new');
    expect(said, 'written to $path');
    // Through a temporary and a rename, which leaves nothing beside it.
    expect(temp.listSync().map((e) => e.path), <String>[path]);
  });

  test('a project is written into directories that did not exist', () async {
    // Broken by dropping `createSync(recursive: true)`: the first file under
    // `assets/levels/` throws and the project is half written.
    final root = '${temp.path}/cellar';
    expect(disk.hasFilesUnder(root), isFalse);

    await disk.writeProject(root, <String, Uint8List>{
      'pubspec.yaml': Uint8List.fromList('name: cellar'.codeUnits),
      'assets/levels/first.json': Uint8List.fromList('{}'.codeUnits),
    });

    expect(File('$root/assets/levels/first.json').readAsStringSync(), '{}');
    expect(disk.hasFilesUnder(root), isTrue);
    expect(disk.hasDirectory('$root/assets'), isTrue);
    expect(await disk.readText('$root/pubspec.yaml'), 'name: cellar');
  });

  test('an empty directory is not in the way of a new project', () {
    // A folder somebody made by hand and left empty is where they meant the
    // project to go; refusing it would be the template being fussy.
    final root = Directory('${temp.path}/empty')..createSync();
    expect(disk.hasFilesUnder(root.path), isFalse);
  });

  test('a new project lands beside the define\'s project, not inside', () {
    // The rule `_create` had inline before the seam.
    expect(
      disk.newProjectRoot('/work/apps/game/assets/levels/a.json', 'cellar'),
      '/work/apps/cellar',
    );
  });

  test('the working directory is searched before the executable', () {
    final roots = disk.searchFrom();
    expect(roots.first, Directory.current.path);
  });
}
