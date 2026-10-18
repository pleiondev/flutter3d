/// How the window is divided, and which workspace divided it that way —
/// `ux-38`.
///
/// **Per workspace, because a workspace is what a layout is for.** Essential
/// opens a model, paints it and exports it, and wants the panel wide enough
/// to read a material in; Full is where somebody retargets a clip and wants
/// two viewports and a narrow panel. Making that one setting shared between
/// them means switching workspace and then rebuilding the layout by hand,
/// every time, which is how people end up never switching.
///
/// **Values, not a controller.** The layout is three numbers and a flag; the
/// widget that draws it is `split_viewports.dart`, and the store that keeps
/// it is `ModelerSettings`. Nothing here knows about either.
library;

import '../settings.dart' show Workspace;

/// How wide the properties panel is and whether the viewport is split, for
/// one workspace.
final class DockLayout {
  /// A layout; the defaults are a 250-pixel panel and one unsplit viewport.
  ///
  /// [viewportSplit] is held between [smallestSplit] and [largestSplit]
  /// here, the one way every layout is made, so a layout from code, from
  /// [copyWith] and from a settings file all keep the same promise.
  const DockLayout({
    this.propertiesWidth = 250,
    this.splitViewport = false,
    double viewportSplit = 0.5,
  }) : viewportSplit = viewportSplit < smallestSplit
           ? smallestSplit
           : viewportSplit > largestSplit
           ? largestSplit
           : viewportSplit;

  /// What [json] says, with the default standing in for anything it does not
  /// say or says wrongly — `settings.dart`'s own rule, and for its reason: a
  /// preference file a newer build or a hand edit has made odd costs one
  /// preference, never the launch.
  factory DockLayout.fromJson(Map<String, Object?> json) {
    const DockLayout fallback = DockLayout();
    double number(String key, double otherwise) {
      final Object? value = json[key];
      return value is num ? value.toDouble() : otherwise;
    }

    return DockLayout(
      propertiesWidth: number('propertiesWidth', fallback.propertiesWidth),
      splitViewport: json['splitViewport'] is bool
          ? json['splitViewport']! as bool
          : fallback.splitViewport,
      // Out of range is held in range by the constructor, whatever the file
      // says.
      viewportSplit: number('viewportSplit', fallback.viewportSplit),
    );
  }

  /// The least of the width the left view may take: a view of nothing is
  /// not a layout anybody asked for.
  static const double smallestSplit = 0.15;

  /// The most of the width the left view may take, for the right one's
  /// sake.
  static const double largestSplit = 0.85;

  /// In logical pixels — `ux-27`'s own number, moved in here so the two
  /// halves of "how this window is arranged" are one value.
  final double propertiesWidth;

  /// Whether the viewport is drawn as two views of the same document.
  final bool splitViewport;

  /// Where the divide between them sits, as the left view's own share of the
  /// width. Clamped on the way in rather than on the way out, so neither a
  /// hand-edited settings file nor a caller can produce a view of no pixels.
  final double viewportSplit;

  /// This layout with the given fields replaced.
  DockLayout copyWith({
    double? propertiesWidth,
    bool? splitViewport,
    double? viewportSplit,
  }) => DockLayout(
    propertiesWidth: propertiesWidth ?? this.propertiesWidth,
    splitViewport: splitViewport ?? this.splitViewport,
    viewportSplit: viewportSplit ?? this.viewportSplit,
  );

  /// The three fields under their own names, as [DockLayout.fromJson] reads
  /// them.
  Map<String, Object?> toJson() => <String, Object?>{
    'propertiesWidth': propertiesWidth,
    'splitViewport': splitViewport,
    'viewportSplit': viewportSplit,
  };

  @override
  bool operator ==(Object other) =>
      other is DockLayout &&
      other.propertiesWidth == propertiesWidth &&
      other.splitViewport == splitViewport &&
      other.viewportSplit == viewportSplit;

  @override
  int get hashCode =>
      Object.hash(propertiesWidth, splitViewport, viewportSplit);
}

/// Every workspace's own layout, by [Workspace.id].
///
/// A map keyed by the id rather than by the enum, because that is what a
/// settings file holds and what a build that has since added a workspace can
/// still read: an id it does not know is carried through untouched rather
/// than dropped.
typedef DockLayouts = Map<String, DockLayout>;

/// [layouts]' own entry for [workspace], or the default.
DockLayout layoutFor(DockLayouts layouts, Workspace workspace) =>
    layouts[workspace.id] ?? const DockLayout();

/// [layouts] with [workspace]'s own entry replaced.
DockLayouts withLayout(
  DockLayouts layouts,
  Workspace workspace,
  DockLayout layout,
) => <String, DockLayout>{...layouts, workspace.id: layout};
