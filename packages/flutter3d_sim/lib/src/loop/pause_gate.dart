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
bool shouldPause({
  required bool ready,
  required bool menuOpen,
  required bool pointerIsTheGate,
  required bool pointerHeld,
  required bool padConnected,
}) {
  // Nothing to run yet: the level is still loading, or failed to.
  if (!ready) return true;

  // A menu is the clearest statement of attention there is, and it does not
  // depend on any device. This is the clause that was missing.
  if (menuOpen) return true;

  // Where the pointer can be captured, not having it means the player is
  // somewhere else — that is what Escape does and what clicking back in undoes.
  // A controller is a second way of being here, and it is enough on its own.
  if (!pointerIsTheGate) return false;
  return !pointerHeld && !padConnected;
}
