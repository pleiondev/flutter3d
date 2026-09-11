/// Which shell a width should draw as — `ui-05`'s own `LayoutClass.of(width)`.
///
/// **Three shells read the same tools from the same table.** `ModelerShell`
/// in `shell.dart` is already the desktop one, and its own doc comment
/// already says the tablet palette and the phone sheet are `ui-05`'s
/// remaining half — both still unbuilt. What every one of the three needs
/// first is this: which of them a given width is, decided once and the same
/// way everywhere, rather than each shell's caller guessing at its own
/// threshold.
///
/// **No Flutter import.** A width in logical pixels is a `double` whichever
/// widget measured it, and the boundary below is a fact about the design,
/// not about `MediaQuery` or `RenderBox` — so this stays checkable without a
/// `WidgetTester`.
library;

/// Which of the three shells a width falls into.
enum LayoutClass {
  /// Narrow enough for a `NavigationBar`, a FAB and a bottom sheet rather
  /// than a rail and a side panel — a phone held upright, and anything else
  /// this narrow.
  phone,

  /// Wide enough for a floating tool palette and a side sheet with a drag
  /// handle, not wide enough for the desktop shell's own fixed-width rail
  /// and properties panel.
  tablet,

  /// `ModelerShell`'s own width: a top bar, a rail, a viewport and a
  /// properties panel side by side.
  desktop;

  /// The class a shell of [width] logical pixels should draw as.
  ///
  /// **599, 600, 1199 and 1200 — `ui-05`'s own worked boundary**, in logical
  /// pixels. A width has to land on the same side of 600 and of 1200 no
  /// matter how many times it is asked, which is why the boundary is stated
  /// here as exact numbers rather than "around 600" — a shell that
  /// recalculated its class by feel during a window resize could answer
  /// differently for the same width from one frame to the next.
  static LayoutClass of(double width) {
    if (width < 600) return LayoutClass.phone;
    if (width < 1200) return LayoutClass.tablet;
    return LayoutClass.desktop;
  }
}
