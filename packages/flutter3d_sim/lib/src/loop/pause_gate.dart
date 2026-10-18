/// Whether the simulation should be standing still.
///
/// **One expression, wrong three times.** It began as "paused unless the mouse
/// is captured", which was true of the only build there was. Then:
///
/// * a **gamepad** arrived, and a player holding one never captures the pointer
///   — the game sat frozen while they pressed everything on it;
/// * a **phone and a browser** arrived, where there is no pointer to capture at
///   all — same freeze, for a different reason;
/// * and the **settings panel** turned out never to have paused anything. It
///   looked as though it did, because opening it released the mouse and the
///   mouse was the gate. The day a pad could hold the gate open instead, the
///   game carried on running behind the panel — and on the web and a phone it
///   always had.
///
/// So it has a name and a test now. It is a function of four facts and nothing
/// else, which is what makes it one: every previous version reached for a device
/// and answered a question about the *player's attention* with it.
///
/// [photoMode] is a fifth, and a separate one rather than a menu that happens
/// to be open: photo mode is the one state in which the player is looking hard
/// at the game and moving every stick — so every device clause below says
/// *run*, and a game that folded it into [menuOpen] would have to remember not
/// to close that "menu" when the pointer is captured again to fly the camera.
bool shouldPause({
  required bool ready,
  required bool menuOpen,
  required bool pointerIsTheGate,
  required bool pointerHeld,
  required bool padConnected,
  bool photoMode = false,
}) {
  // Nothing to run yet: the level is still loading, or failed to.
  if (!ready) return true;

  // A menu is the clearest statement of attention there is, and it does not
  // depend on any device. This is the clause that was missing.
  if (menuOpen) return true;

  // The picture is being framed, so the world holds still for it — whatever
  // the pointer and the pad say, since both are flying the camera.
  if (photoMode) return true;

  // Where the pointer can be captured, not having it means the player is
  // somewhere else — that is what Escape does and what clicking back in undoes.
  // A controller is a second way of being here, and it is enough on its own.
  if (!pointerIsTheGate) return false;
  return !pointerHeld && !padConnected;
}
