## 1.0.0-rc.1

- **Breaking: `TouchDrive`'s labels come from the player's language.**
  `throttleLabel`, `brakeLabel` and `handbrakeLabel` are nullable, null for
  `Flutter3dGameLocalizations`'s words; a game's own still override.

- **The controls bind to actions of every kind.** `SteeringBand.axis` and
  `TouchDrive.steer` write the wheel as one `AxisAction` beside the two
  magnitudes, and `TouchCluster.stickAction` puts the stick on any
  `DualAxisAction`.

- **Breaking: `SteeringBand`, `TouchCluster`, `TouchDrive`** as the snapshot
  counts it: a new optional field on each. No caller changes.

- **An analogue axis under a thumb.** `SteeringBand` writes how far left or
  right of centre the thumb is as two actions' magnitudes, sets the idle side
  to nought so a key held on the same machine cannot steer against it, and
  withdraws both on release so the keyboard has them back.

- **A pedal is a held button with a name.** `Pedal` presses its action while
  one finger is on it, lets go on lift, cancel or unmount, and says its label
  to a screen reader.

- **Two layouts, each for a kind of game.** `TouchDrive` is a band and pedals
  with one button in the far corner, never wanted mid-corner. `TouchCluster`
  is a stick, a cluster of buttons, numbered slots and a switch, placed by how
  often each is wanted and how bad it is to press by mistake.

- **Out of the demos.** The racing demo's band, pedals and layout, and the
  dungeon demo's cluster, moved here; each demo keeps only which of its
  actions go where.
