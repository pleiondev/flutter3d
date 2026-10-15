// Writes `test/fixtures/material_language_read.txt`, the record of how every
// `.f3dmat` in the repository reads, emits and evaluates; `--check` only
// says whether the committed record is what the language reads today.
//
//     dart run tool/material_record.dart [--check]
//
// Only ever right to write when the language changes on purpose or a
// source joins the record: a record written over a regression pins it.
import 'dart:io';

import '../test/formats/material_record.dart';

void main(List<String> args) {
  final file = File(materialRecordPath);
  final text = materialLanguageRecord();
  if (args.contains('--check')) {
    if (file.readAsStringSync() != text) {
      stderr.writeln('${file.path} is not what the language reads today');
      exit(1);
    }
    return;
  }
  file.writeAsStringSync(text);
  stdout.writeln('wrote ${file.path}');
}
