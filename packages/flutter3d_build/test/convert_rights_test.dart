import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_build/convert.dart';
import 'package:flutter3d_core/formats.dart' show F3dDocument;
import 'package:test/test.dart';

import 'convert_support.dart';

/// A model's licence and author reach the result of converting it, so a
/// server that converts an upload can show who made it and on what terms.
void main() {
  Future<ConvertReport> convert(String name, String path) async {
    final result = await convertFiles(<String, Uint8List>{
      name: File(path).readAsBytesSync(),
    }, to: ConversionTarget.everything);
    expect(result.isOk, isTrue, reason: result.reports.single.describe());
    return result.reports.single;
  }

  Future<ConvertReport> chair() =>
      convert('chair.gltf', '$fixtures/rights/chair.gltf');

  test(
    'the report carries the licence, the author and the copyright',
    () async {
      final report = await chair();
      expect(report.license, 'CC-BY-4.0');
      expect(report.author, 'Ada Modeller');
      expect(report.copyright, '© 2026 Ada Modeller');
    },
  );

  test('and writes them into its JSON', () async {
    final json = (await chair()).toJson();
    expect(json['license'], 'CC-BY-4.0');
    expect(json['author'], 'Ada Modeller');
    expect(json['copyright'], '© 2026 Ada Modeller');
  });

  test('and the .f3d it writes carries them too', () async {
    // Mutation: drop the rights section from `F3dWriter`. The report keeps
    // them and the file a game ships loses them, which the report used to
    // admit as a drop.
    final result = await convertFiles(<String, Uint8List>{
      'chair.gltf': File('$fixtures/rights/chair.gltf').readAsBytesSync(),
    }, to: ConversionTarget.everything);
    final f3d = result.files.entries.singleWhere(
      (MapEntry<String, Uint8List> e) => e.key.endsWith('.f3d'),
    );
    final asset = F3dDocument.parse(f3d.value).asset!;
    expect(asset.license, 'CC-BY-4.0');
    expect(asset.author, 'Ada Modeller');
    expect(asset.copyright, '© 2026 Ada Modeller');
    expect(
      result.reports.single.dropped,
      isNot(contains(startsWith('the author'))),
    );
  });

  test('a model that says nothing has no such keys', () async {
    final json = (await convert(
      'triangle.obj',
      'test/fixtures/triangle.obj',
    )).toJson();
    expect(json.containsKey('license'), isFalse);
    expect(json.containsKey('author'), isFalse);
    expect(json.containsKey('copyright'), isFalse);
  });
}
