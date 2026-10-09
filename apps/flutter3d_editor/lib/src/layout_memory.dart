import 'dart:convert';

import 'package:flutter3d_app/flutter3d_app.dart'
    show Storage, StorageException, defaultStorage;
import 'package:flutter3d_editor_widgets/flutter3d_editor_widgets.dart'
    show DockArrangement;

import 'recent_projects.dart';

/// Where the docked panels were, kept between launches, per person.
///
/// Beside `recent.json` in the same [Storage], for the same reasons that file
/// gives: the directory is per platform and per user, a read that finds
/// nothing is a first launch, and a write goes through a rename. A layout is
/// a convenience; one that could not be read is the default layout, and one
/// that could not be written costs somebody a drag next time, so neither is
/// ever reported as a failure.
final class LayoutMemory {
  LayoutMemory({Storage? storage})
    : storage = storage ?? defaultStorage(RecentProjects.appName);

  static const String _name = 'layout.json';

  final Storage storage;

  Future<DockArrangement> read() async {
    final text = await storage.read(_name);
    if (text == null) return const DockArrangement();
    try {
      return DockArrangement.fromJson(jsonDecode(text));
    } on FormatException {
      return const DockArrangement();
    }
  }

  /// Writes [arrangement] down. A layout that could not be kept costs the
  /// panels' places next launch and nothing else, so a refusal is dropped.
  Future<void> write(DockArrangement arrangement) async {
    try {
      await storage.write(
        _name,
        const JsonEncoder.withIndent('  ').convert(arrangement.toJson()),
      );
    } on StorageException {
      return;
    }
  }
}
