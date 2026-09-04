import 'package:flutter/widgets.dart';

import 'package:flutter3d_sim/flutter3d_sim.dart';

/// One numbered slot, as the row draws it.
final class TouchSlot {
  const TouchSlot(this.label, {this.owned = true});

  /// What the slot holds, short enough to read at a glance under a thumb.
  final String label;

  /// Whether the player has this one yet.
  ///
  /// Shown rather than hidden. A row that grows as things are picked up is a
  /// row whose third button is a different weapon every ten minutes, and the
  /// whole value of a numbered slot is that it does not move — the same reason
  /// [Arsenal] indexes what the game has rather than what the player owns.
  final bool owned;
}

/// The numbered slots, as buttons for a thumb.
///
/// **A keyboard has a number row and a phone does not.** [InputState] has
/// carried [InputState.requestSlot] since before there was a touch build, the
/// pad reaches it through the d-pad, and the only way to ask for it with a
/// finger was not to. In the crypt that was three of its four weapons
/// unreachable on the device the touch controls exist for: the shotgun, the
/// rocket launcher and the fists, which is the one you fall back to having run
/// out of everything.
///
/// A tap and not a hold, unlike [TouchButton]: choosing is an event, and
/// `slotRequest` is read once per step and cleared.
class TouchSlots extends StatelessWidget {
  const TouchSlots({
    super.key,
    required this.state,
    required this.slots,
    required this.current,
    this.width = 62.0,
    this.height = 34.0,
    this.spacing = 8.0,
  });

  final InputState state;

  /// Every slot this game has, in the order its keys select them.
  final List<TouchSlot> slots;

  /// Which of them is in hand, so the row can say where the player is.
  final int current;

  final double width;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      for (var slot = 0; slot < slots.length; slot++) ...<Widget>[
        if (slot > 0) SizedBox(height: spacing),
        _Slot(
          slot: slots[slot],
          held: slot == current,
          width: width,
          height: height,
          // Unowned still asks. The alternative is a button that does nothing
          // and says nothing, which is a button a player decides is broken —
          // and the arsenal already refuses a slot it does not own, in one
          // place, for every device.
          onTap: () => state.requestSlot(slot),
        ),
      ],
    ],
  );
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.slot,
    required this.held,
    required this.width,
    required this.height,
    required this.onTap,
  });

  final TouchSlot slot;
  final bool held;
  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = held
        ? const Color(0xE6FFFFFF)
        : slot.owned
        ? const Color(0x33FFFFFF)
        : const Color(0x14FFFFFF);
    return Semantics(
      button: true,
      selected: held,
      enabled: slot.owned,
      label: slot.label,
      // The `Text` below says the same word, and a reader that merged the two
      // would announce it twice.
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colour,
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Center(
              child: Text(
                slot.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: held
                      ? const Color(0xFF101010)
                      : slot.owned
                      ? const Color(0xCCFFFFFF)
                      : const Color(0x55FFFFFF),
                  fontSize: 12.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
