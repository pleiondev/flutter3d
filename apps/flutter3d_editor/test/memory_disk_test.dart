/// The web build's disk, on the VM: every decision `MemoryDisk` makes, with
/// the browser's two jobs — keeping a write past a reload, and handing bytes
/// to the person — replaced by lists.
///
/// Each test names the mutation it was written against.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart' show XTypeGroup;
import 'package:flutter3d_editor/src/disk/memory_disk.dart';
import 'package:flutter3d_editor/src/documents.dart';
import 'package:flutter3d_editor_core/flutter3d_editor_core.dart'
    show projectAt;
import 'package:flutter_test/flutter_test.dart';

const XTypeGroup _levels = XTypeGroup(extensions: <String>['json']);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  late List<(String, Uint8List)> delivered;
  late Map<String, Uint8List> persisted;
  PickedBytes? picked;

  MemoryDisk disk({Map<String, Uint8List> restored = const {}}) => MemoryDisk(
    deliver: (String name, Uint8List bytes) => delivered.add((name, bytes)),
    persist: (String path, Uint8List bytes) => persisted[path] = bytes,
    pick: (_) async => picked,
    restored: restored,
  );

  setUp(() {
    delivered = <(String, Uint8List)>[];
    persisted = <String, Uint8List>{};
    picked = null;
  });

  test(
    'a picked level is read into the page, and kept past a reload',
    () async {
      // Broken by `choose` answering a path without storing the bytes: the
      // editor's `_openAt` then reads nothing at the path it was handed.
      picked = (name: 'crypt.json', bytes: _bytes('{"brushes":[]}'));
      final memory = disk();

      final path = await memory.choose(_levels);

      expect(path, '${MemoryDisk.opened}/crypt.json');
      expect(memory.exists(path!), isTrue);
      expect(await memory.readText(path), '{"brushes":[]}');
      expect(persisted.keys, <String>[path]);
      expect(delivered, isEmpty, reason: 'opening is not a download');
    },
  );

  test('a dismissed dialogue opens nothing', () async {
    final memory = disk();
    expect(await memory.choose(_levels), isNull);
    expect(memory.paths, isEmpty);
  });

  test('saving downloads the level by its own name, and keeps it', () async {
    // Broken by delivering the whole path as the name, which a browser turns
    // into `_browser_opened_crypt.json` — or by not keeping the write, so
    // reopening it from the recent list gives back the level before the save.
    picked = (name: 'crypt.json', bytes: _bytes('old'));
    final memory = disk();
    final path = (await memory.choose(_levels))!;

    final said = await memory.writeDocument(path, 'new');

    expect(delivered.single.$1, 'crypt.json');
    expect(utf8.decode(delivered.single.$2), 'new');
    expect(await memory.readText(path), 'new');
    expect(utf8.decode(persisted[path]!), 'new');
    expect(said, contains('downloaded crypt.json'));
    expect(memory.savesInPlace, isFalse);
  });

  test(
    'a new project is kept file by file and downloaded as one zip',
    () async {
      // Broken by zipping the files at the archive's root (unpacking scatters
      // `lib/` into Downloads), or by not keeping them — then `_openAt` on the
      // project's level finds nothing.
      final memory = disk();
      final root = memory.newProjectRoot('anything', 'cellar');
      final files = <String, Uint8List>{
        'pubspec.yaml': _bytes('name: cellar'),
        'assets/levels/first.json': _bytes('{}'),
        'assets/models/key.glb': Uint8List.fromList(<int>[0, 1, 2, 255]),
      };

      final said = await memory.writeProject(root, files);

      expect(root, '${MemoryDisk.projects}/cellar');
      expect(memory.exists('$root/assets/levels/first.json'), isTrue);
      expect(persisted.length, files.length);
      expect(delivered.single.$1, 'cellar.zip');
      final zip = ZipDecoder().decodeBytes(delivered.single.$2);
      expect(
        <String, List<int>>{
          for (final file in zip.files) file.name: file.content as List<int>,
        },
        <String, List<int>>{
          for (final MapEntry(:key, :value) in files.entries)
            'cellar/$key': value,
        },
      );
      expect(said, contains('cellar.zip'));
    },
  );

  test('a project in the page has an asset root, a lone level has none', () {
    // `Documents.assetRootFor` climbing a page's paths the way it climbs a
    // disk's. Broken by `hasDirectory` answering only for exact file paths:
    // the project's models are then never found and every gizmo is a box.
    final memory = disk(
      restored: <String, Uint8List>{
        '${MemoryDisk.projects}/cellar/assets/levels/first.json': _bytes('{}'),
        '${MemoryDisk.projects}/cellar/assets/editor.json': _bytes('{}'),
        '${MemoryDisk.opened}/crypt.json': _bytes('{}'),
      },
    );

    expect(
      Documents.assetRootFor(
        '${MemoryDisk.projects}/cellar/assets/levels/first.json',
        hasAssets: memory.hasDirectory,
      ),
      '${MemoryDisk.projects}/cellar',
    );
    expect(
      Documents.assetRootFor(
        '${MemoryDisk.opened}/crypt.json',
        hasAssets: memory.hasDirectory,
      ),
      isNull,
    );
  });

  test('a directory is a whole path segment, not a prefix of a name', () {
    // Broken by `startsWith(path)` without the slash: a project called
    // `cell` would be refused because `cellar` exists.
    final memory = disk(
      restored: <String, Uint8List>{
        '${MemoryDisk.projects}/cellar/pubspec.yaml': _bytes(''),
      },
    );
    expect(memory.hasFilesUnder('${MemoryDisk.projects}/cellar'), isTrue);
    expect(memory.hasFilesUnder('${MemoryDisk.projects}/cell'), isFalse);
  });

  test('what a reload restored is there to be opened again', () async {
    final memory = disk(
      restored: <String, Uint8List>{
        '${MemoryDisk.opened}/crypt.json': _bytes('kept'),
      },
    );
    expect(memory.exists('${MemoryDisk.opened}/crypt.json'), isTrue);
    expect(await memory.readText('${MemoryDisk.opened}/crypt.json'), 'kept');
    expect(persisted, isEmpty, reason: 'restoring is not writing');
  });

  test('a path the page does not hold is an error, not an empty file', () {
    expect(disk().readText('/browser/nothing.json'), throwsStateError);
  });

  test('the define resolves against the page, and finds nothing there', () {
    // The default `level=` names the crypt beside the editor's checkout,
    // which a page has no copy of — so the editor falls through to the
    // chooser rather than to a "could not find" screen.
    final memory = disk();
    const define = '../flutter3d_demo_dungeon/assets/levels/crypt.json';
    expect(
      Documents.find(define, from: memory.searchFrom(), exists: memory.exists),
      isNull,
    );
    expect(projectAt(memory.absolute('assets/levels/a.json')).root, '/browser');
  });

  test('a bug report is downloaded under the name it was offered', () async {
    final memory = disk();
    expect(await memory.saveAs('bugreport.json', '{}', _levels), isTrue);
    expect(delivered.single.$1, 'bugreport.json');
  });
}
