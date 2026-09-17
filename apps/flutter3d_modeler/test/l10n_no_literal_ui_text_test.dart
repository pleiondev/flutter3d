/// `ux-22`'s own guard: a file that has been through the translation pass
/// may not grow a new English literal where a widget will show it.
///
/// **A list of files rather than the whole of `lib/`, and it grows.** The
/// pass is not finished — the rows below say exactly where it has reached —
/// and a check that failed on every file the pass has not touched yet would
/// be a check somebody turns off. What it does hold is the thing worth
/// holding: a screen already translated cannot quietly go back, because the
/// next literal added to one of these files turns this red.
///
/// **What the allow-list is for.** Some strings are the same in every
/// language (an axis, a file extension), and some are not language at all
/// (a key an agent passes, a fallback a lookup falls to). Those are named
/// here, one by one, so that adding to them is a decision somebody makes
/// rather than a hole that opens by itself.
///
///     dart test test/l10n_no_literal_ui_text_test.dart
library;

import 'dart:io';

import 'package:test/test.dart';

/// The files whose words have been moved into `app_en.arb`/`app_ru.arb`.
///
/// Add a file here the moment its last literal goes, and this stops it
/// coming back.
const List<String> translated = <String>[
  'lib/main.dart',
  'lib/src/animation_wiring.dart',
  'lib/src/app_config.dart',
  'lib/src/autorig_markers.dart',
  'lib/src/autosaving.dart',
  'lib/src/backend.dart',
  'lib/src/brush_hit.dart',
  'lib/src/cabinet_link.dart',
  'lib/src/churn_run.dart',
  'lib/src/close_beforeunload.dart',
  'lib/src/close_beforeunload_io.dart',
  'lib/src/close_beforeunload_web.dart',
  'lib/src/close_guard.dart',
  'lib/src/console_log.dart',
  'lib/src/crash_handling.dart',
  'lib/src/display_modes.dart',
  'lib/src/element_picker_cache.dart',
  'lib/src/element_picking.dart',
  'lib/src/environment_summary.dart',
  'lib/src/files/cabinet_save.dart',
  'lib/src/files/cabinet_save_io.dart',
  'lib/src/files/cabinet_save_outcome.dart',
  'lib/src/files/cabinet_save_web.dart',
  'lib/src/files/fetch_model.dart',
  'lib/src/files/fetch_model_io.dart',
  'lib/src/files/fetch_model_web.dart',
  'lib/src/files/file_drop.dart',
  'lib/src/files/file_drop_io.dart',
  'lib/src/files/file_drop_web.dart',
  'lib/src/files/gltf_siblings.dart',
  'lib/src/files/linked_materials.dart',
  'lib/src/files/linked_materials_io.dart',
  'lib/src/files/linked_materials_web.dart',
  'lib/src/files/picked_file.dart',
  'lib/src/files/preview_capture.dart',
  'lib/src/files/preview_capture_io.dart',
  'lib/src/files/preview_capture_web.dart',
  'lib/src/files/project_files.dart',
  'lib/src/files/project_files_io.dart',
  'lib/src/files/project_files_web.dart',
  'lib/src/files/sandbox_probe.dart',
  'lib/src/files/sandbox_probe_io.dart',
  'lib/src/files/sandbox_probe_web.dart',
  'lib/src/gallery/gallery_insert.dart',
  'lib/src/gallery/gallery_item.dart',
  'lib/src/gallery/outside_sources.dart',
  'lib/src/gallery/recipe_source.dart',
  'lib/src/gallery/remote_source.dart',
  'lib/src/game_preview_settings.dart',
  'lib/src/geometry_snap.dart',
  'lib/src/gizmo_handles.dart',
  'lib/src/ground_grid.dart',
  'lib/src/import_plan.dart',
  'lib/src/input_policy.dart',
  'lib/src/job_runner.dart',
  'lib/src/joint_picking.dart',
  'lib/src/legal/legal_document.dart',
  'lib/src/legal/legal_library.dart',
  'lib/src/legal/legal_view.dart',
  'lib/src/local_data.dart',
  'lib/src/lod_screen_fraction.dart',
  'lib/src/material_editing.dart',
  'lib/src/material_file_writer.dart',
  'lib/src/material_pool.dart',
  'lib/src/mcp_bootstrap.dart',
  'lib/src/mcp_bootstrap_io.dart',
  'lib/src/mcp_bootstrap_web.dart',
  'lib/src/mcp_ui_actions.dart',
  'lib/src/mcp_ui_tools.dart',
  'lib/src/measurement_runs.dart',
  'lib/src/mesh_overlay_builder.dart',
  'lib/src/modeler_cubit.dart',
  'lib/src/modeler_state.dart',
  'lib/src/modeler_ui_actions.dart',
  'lib/src/modeler_viewport.dart',
  'lib/src/mouse_hints.dart',
  'lib/src/object_picking.dart',
  'lib/src/open_report.dart',
  'lib/src/opening.dart',
  'lib/src/orbit_gestures.dart',
  'lib/src/orbit_run.dart',
  'lib/src/orientation_dial.dart',
  'lib/src/paint_session.dart',
  'lib/src/paint_upload.dart',
  'lib/src/play/play_control.dart',
  'lib/src/play/play_session.dart',
  'lib/src/play/play_template.dart',
  'lib/src/profile_editing.dart',
  'lib/src/recent_projects.dart',
  'lib/src/render_snapshot_run.dart',
  'lib/src/report_problem.dart',
  'lib/src/scene_light_picking.dart',
  'lib/src/scene_mode.dart',
  'lib/src/scene_sync.dart',
  'lib/src/screen/animation.dart',
  'lib/src/screen/app_wiring.dart',
  'lib/src/screen/autorig_wiring.dart',
  'lib/src/screen/close_and_recovery.dart',
  'lib/src/screen/device.dart',
  'lib/src/screen/files.dart',
  'lib/src/screen/game_preview_wiring.dart',
  'lib/src/screen/interactions.dart',
  'lib/src/screen/morphs_wiring.dart',
  'lib/src/screen/pro_modes_wiring.dart',
  'lib/src/screen/ready_parts.dart',
  'lib/src/screen/retarget_wiring.dart',
  'lib/src/screen/sculpt_wiring.dart',
  'lib/src/screen/weight_paint_wiring.dart',
  'lib/src/sculpt_budget.dart',
  'lib/src/sculpt_session.dart',
  'lib/src/sculpt_upload.dart',
  'lib/src/selection_box.dart',
  'lib/src/selection_rules.dart',
  'lib/src/settings.dart',
  'lib/src/shape_key_state.dart',
  'lib/src/shape_points_overlay.dart',
  'lib/src/simulation_collision_draw.dart',
  'lib/src/simulation_playback.dart',
  'lib/src/staging.dart',
  'lib/src/texture_slot.dart',
  'lib/src/timeline_playback.dart',
  'lib/src/timeline_preview_wiring.dart',
  'lib/src/tool_commands.dart',
  'lib/src/transform_dispatch.dart',
  'lib/src/transform_fields.dart',
  'lib/src/transform_gizmo.dart',
  'lib/src/transform_modal.dart',
  'lib/src/transform_session.dart',
  'lib/src/ui/actions_list.dart',
  'lib/src/ui/agent_session_panel.dart',
  'lib/src/ui/animation_bottom.dart',
  'lib/src/ui/animation_panel.dart',
  'lib/src/ui/animation_screen.dart',
  'lib/src/ui/autorig_dialog.dart',
  'lib/src/ui/bake_panel.dart',
  'lib/src/ui/bend_slider_bar.dart',
  'lib/src/ui/bone_map_table.dart',
  'lib/src/ui/budget_bars.dart',
  'lib/src/ui/clip_library.dart',
  'lib/src/ui/clip_tracks_bar.dart',
  'lib/src/ui/command_palette.dart',
  'lib/src/ui/console_panel.dart',
  'lib/src/ui/constraints_list.dart',
  'lib/src/ui/curve_editor.dart',
  'lib/src/ui/dock_layout.dart',
  'lib/src/ui/export_anyway_dialog.dart',
  'lib/src/ui/export_screen.dart',
  'lib/src/ui/gallery_screen.dart',
  'lib/src/ui/game_preview_screen.dart',
  'lib/src/ui/import_screen.dart',
  'lib/src/ui/job_button.dart',
  'lib/src/ui/keymap.dart',
  'lib/src/ui/lathe_dialog.dart',
  'lib/src/ui/layout_class.dart',
  'lib/src/ui/legal_screen.dart',
  'lib/src/ui/lod_screen.dart',
  'lib/src/ui/lod_zone_bar.dart',
  'lib/src/ui/material_panel.dart',
  'lib/src/ui/material_preview_panel.dart',
  'lib/src/ui/material_studio_dialog.dart',
  'lib/src/ui/measurement_report_overlay.dart',
  'lib/src/ui/mesh_health_panel.dart',
  'lib/src/ui/metrics_overlay.dart',
  'lib/src/ui/modeler_keys.dart',
  'lib/src/ui/modifier_fields.dart',
  'lib/src/ui/modifier_stack_panel.dart',
  'lib/src/ui/morphs_panel.dart',
  'lib/src/ui/named_button.dart',
  'lib/src/ui/no_mesh_banner.dart',
  'lib/src/ui/operation_card.dart',
  'lib/src/ui/paint_panel.dart',
  'lib/src/ui/play_screen.dart',
  'lib/src/ui/profile_editor.dart',
  'lib/src/ui/properties/label_value_row.dart',
  'lib/src/ui/properties/name_field.dart',
  'lib/src/ui/properties/object_row.dart',
  'lib/src/ui/properties/outliner.dart',
  'lib/src/ui/properties/pivot_space_chips.dart',
  'lib/src/ui/properties/properties_panel.dart',
  'lib/src/ui/properties/transform_rows.dart',
  'lib/src/ui/properties_sections.dart',
  'lib/src/ui/quick_setup_screen.dart',
  'lib/src/ui/recovery_dialog.dart',
  'lib/src/ui/render_panel.dart',
  'lib/src/ui/restore_autosave_dialog.dart',
  'lib/src/ui/retarget_panel.dart',
  'lib/src/ui/retarget_viewports.dart',
  'lib/src/ui/retopo_overlay.dart',
  'lib/src/ui/roomy_dialog.dart',
  'lib/src/ui/save_as_dialog.dart',
  'lib/src/ui/scene_environment_panel.dart',
  'lib/src/ui/scene_post_panel.dart',
  'lib/src/ui/scene_shadows_panel.dart',
  'lib/src/ui/scene_source_panel.dart',
  'lib/src/ui/screen_parts.dart',
  'lib/src/ui/sculpt_panel.dart',
  'lib/src/ui/selection_key_bindings.dart',
  'lib/src/ui/settings_screen.dart',
  'lib/src/ui/shell.dart',
  'lib/src/ui/shell_for_width.dart',
  'lib/src/ui/shell_phone.dart',
  'lib/src/ui/shell_tablet.dart',
  'lib/src/ui/shortcut_help.dart',
  'lib/src/ui/shortcut_help_screen.dart',
  'lib/src/ui/simulation_cache_strip.dart',
  'lib/src/ui/simulation_panel.dart',
  'lib/src/ui/skeleton_tree.dart',
  'lib/src/ui/split_viewports.dart',
  'lib/src/ui/start_screen.dart',
  'lib/src/ui/status_line.dart',
  'lib/src/ui/texture_graph_panel.dart',
  'lib/src/ui/theme.dart',
  'lib/src/ui/timeline_panel.dart',
  'lib/src/ui/tool_strings.dart',
  'lib/src/ui/top_bar_actions.dart',
  'lib/src/ui/transform_readout.dart',
  'lib/src/ui/transport_bar.dart',
  'lib/src/ui/undo_redo_buttons.dart',
  'lib/src/ui/unsaved_changes_dialog.dart',
  'lib/src/ui/uv_layout_view.dart',
  'lib/src/ui/uv_screen.dart',
  'lib/src/ui/uv_unwrap_panel.dart',
  'lib/src/ui/weight_legend.dart',
  'lib/src/ui/weight_paint_panel.dart',
  'lib/src/ui/window_chrome.dart',
  'lib/src/uv_seam_overlay.dart',
  'lib/src/uv_unwrap_layout.dart',
  'lib/src/value_drag.dart',
  'lib/src/viewport_metrics.dart',
  'lib/src/weight_gradient.dart',
  'lib/src/weight_mirror.dart',
  'lib/src/weight_paint_session.dart',
];

/// Strings a translated file may still name, and why each one is there.
const Map<String, String> allowed = <String, String>{
  'Box':
      'the English fallback `primitiveLabel` falls to, and the word an '
      'agent passes as `kind`',
  'Plane': 'the English fallback and the agent-facing kind, as Box',
  'Sphere': 'the English fallback and the agent-facing kind, as Box',
  'Cylinder': 'the English fallback and the agent-facing kind, as Box',
  'Torus': 'the English fallback and the agent-facing kind, as Box',
  'X': 'an axis is the same letter in both languages',
  'Y': 'an axis is the same letter in both languages',
  'Z': 'an axis is the same letter in both languages',
  'flutter3d modeller':
      'the application\'s own name, which is the same word in both languages '
      'and is what a window manager shows',
  'texture-bytes':
      'a widget key rather than a word: `_BudgetRow` takes the id it builds '
      'its own test keys from as `label` and the words a person reads as '
      '`title`',
};

/// Where a widget puts something a person reads.
///
/// **Matched over the whole file rather than line by line, and adjacent
/// literals joined.** Both of those were holes: a `Text(` whose string starts
/// on the next line is invisible to a per-line scan, and a sentence broken
/// across two quoted pieces — which is how every paragraph in this
/// application is written, because the formatter wraps at eighty — showed up
/// as the first piece alone or not at all. The settings screen's own helps
/// and subtitles were exactly that shape, and this check read none of them
/// until it stopped reading lines.
final RegExp _sites = RegExp(
  r"(?:Text\(\s*|SectionLabel\(\s*|message:\s*|label:\s*|tooltip:\s*"
  r"|title:\s*|labelText:\s*|hintText:\s*|helperText:\s*|semanticLabel:\s*)"
  r"(?:const\s+)?((?:'(?:\\.|[^'\\])*'\s*)+)",
  multiLine: true,
);

/// [said] with every `${…}` and `$name` taken out, so what is left is the
/// words the file itself is putting on the screen.
String _outsideInterpolations(String said) => said
    .replaceAll(RegExp(r'\$\{[^}]*\}'), ' ')
    .replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), ' ');

/// A run of adjacent quoted pieces, as the one string Dart joins them into.
String _joined(String pieces) => RegExp(
  r"'((?:\\.|[^'\\])*)'",
).allMatches(pieces).map((RegExpMatch m) => m.group(1)!).join();

/// An id, a key or a field name — `materialSlot`, `mesh.extrude` — which is
/// vocabulary rather than language.
final RegExp _identifier = RegExp(r'^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$');

void main() {
  test('a translated file names no literal a widget would show', () {
    final offenders = <String>[];
    for (final String path in translated) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is not there');
      final String source = file.readAsStringSync();
      for (final RegExpMatch m in _sites.allMatches(source)) {
        final String said = _joined(m.group(1)!);
        if (said.length < 2) continue;
        if (!RegExp('[A-Za-z]{2}').hasMatch(said)) continue;
        if (_identifier.hasMatch(said)) continue;
        // **A string with no word of its own outside an interpolation is
        // whatever it interpolates** — a count, a file name, a label and a
        // shortcut already translated where they were built. What is left
        // after the interpolations come out is punctuation and spacing,
        // which is not language and has nowhere to go in an ARB file.
        if (!RegExp('[A-Za-z]{2}').hasMatch(_outsideInterpolations(said))) {
          continue;
        }
        if (allowed.containsKey(said)) continue;
        final int line = '\n'.allMatches(source.substring(0, m.start)).length;
        offenders.add('$path:${line + 1}: $said');
      }
    }

    // Mutation: put one of these strings back as a literal. The English
    // build looks identical and the Russian one shows an English word in
    // the middle of a Russian bar, which is exactly the state `ui-22` left
    // and `ux-22` is clearing.
    expect(
      offenders,
      isEmpty,
      reason:
          'route these through AppLocalizations, or name them in `allowed` '
          'with the reason they are not language:\n${offenders.join('\n')}',
    );
  });

  test('every allowed string carries a reason', () {
    for (final MapEntry<String, String> each in allowed.entries) {
      expect(
        each.value.length,
        greaterThan(12),
        reason: '${each.key} is allowed without saying why',
      );
    }
  });
}
