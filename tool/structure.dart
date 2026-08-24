/// Every rule about how this repository is arranged, checked before a build.
///
///     dart run tool/structure.dart          check everything
///     dart run tool/structure.dart --list   name the rules and stop
///
/// **These were twenty-three Dart test files and two lines of `grep` in
/// `tool/ci.sh`.** That arrangement had three costs and they are the reason
/// this exists:
///
///  1. **A new package was covered only if somebody remembered.** The rules
///     arrived as a `boundaries_test.dart` per package, and thirteen of
///     twenty-one packages had none — every one of them clean, and none of them
///     checked. A runner that walks `packages/` covers a package the day it
///     exists.
///  2. **They needed a built workspace to say anything.** A rule about which
///     file imports what does not need `pub get`, a shader bundle, or a device,
///     and running it after all three means finding out late what could have
///     been known first. This is now the first step of CI and takes under a
///     second.
///  3. **Twenty-one dev dependencies on a package that held no code.**
///     `flutter3d_boundaries` existed to be depended on by every package it
///     policed, which is a dependency edge per rule per package to express a
///     fact about the repository rather than about any package in it.
///
/// What did *not* move: anything that tests behaviour. A test that steps a
/// simulation, draws a frame or reads a level document stays a test. The line
/// is whether the subject is the code's *arrangement* — who imports what, what
/// a name says, where a thing may live — or what the code *does*.
///
/// ## The one thing that had to survive the move
///
/// Rule 6.3 of `ARCHITECTURE.md`: a check is written by breaking what it covers,
/// and the mutation is named. A scan behind a detector nobody has seen fail is
/// a rule nobody is keeping — the genre scan once lived in two copies and one
/// of them had already lost the proof that it fired, so it passed whether or
/// not the rule held.
///
/// So [proveDetectorsWork] runs first, every time, and a broken detector stops
/// the run before a single scan is reported. A green scan behind a broken
/// detector is worse than a red one, because somebody believes it.
library;

import 'dart:io';

import 'structure/detectors.dart';
import 'structure/rules.dart';

const String _bold = '[1m';
const String _red = '[31m';
const String _green = '[32m';
const String _dim = '[2m';
const String _off = '[0m';

bool get _colour => stdout.supportsAnsiEscapes;

String _paint(String text, String colour) => _colour ? '$colour$text$_off' : text;

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    return;
  }

  if (args.contains('--list')) {
    for (final rule in allRules) {
      stdout.writeln(rule.name);
    }
    return;
  }

  final unknown = args.where((String a) => a.startsWith('-'));
  if (unknown.isNotEmpty) {
    stderr.writeln('unknown option: ${unknown.first}\n\n$_usage');
    exit(2);
  }

  // The detectors first, and on their own. If one of them cannot fire, every
  // scan below it is meaningless and reporting them green would be the lie this
  // arrangement exists to prevent.
  final broken = proveDetectorsWork();
  if (broken.isNotEmpty) {
    stdout.writeln(_paint('the detectors do not work', _red));
    for (final finding in broken) {
      stdout.writeln('  ${finding.where}: ${finding.what}');
    }
    stdout.writeln('\nNo rule was run. A scan behind a broken detector is a '
        'rule nobody is keeping.');
    exit(1);
  }

  final failed = <String, List<Finding>>{};
  final started = DateTime.now();

  for (final rule in allRules) {
    late final List<Finding> found;
    try {
      found = rule.run();
    } catch (error, stack) {
      // A rule that throws is a broken rule, and it is reported as one rather
      // than taking the whole run down with a stack trace and no context.
      failed[rule.name] = <Finding>[
        Finding('the rule itself', 'threw: $error\n$stack'),
      ];
      stdout.writeln('${_paint('✗', _red)} ${rule.name}');
      continue;
    }

    if (found.isEmpty) {
      stdout.writeln('${_paint('✓', _green)} ${_paint(rule.name, _dim)}');
    } else {
      failed[rule.name] = found;
      stdout.writeln('${_paint('✗', _red)} ${_bold_(rule.name)}');
    }
  }

  final elapsed = DateTime.now().difference(started).inMilliseconds;

  if (failed.isEmpty) {
    stdout.writeln('\n${allRules.length} rules, ${elapsed}ms, '
        '${_paint('all held', _green)}');
    return;
  }

  stdout.writeln('');
  for (final entry in failed.entries) {
    stdout.writeln(_paint(entry.key, _red));
    for (final finding in entry.value) {
      stdout.writeln('  ${finding.where}');
      stdout.writeln('    ${finding.what}');
    }
    stdout.writeln('');
  }
  stdout.writeln('${failed.length} of ${allRules.length} rules broken');
  exit(1);
}

String _bold_(String text) => _colour ? '$_bold$text$_off' : text;

const String _usage = '''
Every rule about how this repository is arranged.

  dart run tool/structure.dart          check everything
  dart run tool/structure.dart --list   name the rules and stop

Needs no `pub get`, no shader bundle and no device: every rule reads source
text. It is the first step of tool/ci.sh for that reason.

Where the rules and their exemptions live:

  tool/structure/detectors.dart   the detectors, and the proof each one fires
  tool/structure/repository.dart  what this repository is made of, and where
                                  each rule is relaxed — with the reason
  tool/structure/rules.dart       the rules themselves
''';
