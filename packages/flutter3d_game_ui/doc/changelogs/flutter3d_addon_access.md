## 1.0.0-rc.1

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `GameConfig` is `GameSettings`. Every settings class is `final`
  with a `const` constructor and a `copyWith` over every field; a nullable
  field is reset with `copyWith(clearX: true)`. `dart fix` carries the
  renames.
- **Breaking: `announceTo` and `announceToImplicitView` speak in the
  platform's direction.** Their `direction` defaulted to left to right, so a
  sentence in Arabic or Hebrew was read in the wrong order; null now asks
  the platform's language (`platformTextDirection`), and `announceIn(context)`
  speaks on the context's view in its ambient `Directionality`. A caller that
  passed a direction is unchanged.

- **Rings in the colour a player chose.** `RoleRings` gives the
  high-contrast look's ring colour for a role, read from the settings on
  every call, so a change in the panel is the ring's colour on the next
  frame. The dungeon's rings are built on it; which things are worth a ring
  stays the game's question.

- **Roles moved apart for the player's eyes.** `RolesApart.choicesFor` says
  which palette colour each colliding role should take for the deficiency
  the player named, and `apply` writes it into the settings. With none named
  it moves nothing.

- **What happens, said to a screen reader.** `SpokenEvents` is a view plugin
  on the bus's frame channel: a table of event types and sentences, said as
  announcements through Flutter's semantics. The same sentence waits a number
  of steps before it is said again; the limit is counted in steps, so it
  needs no clock. Nothing is written back, so the game is the same with it
  installed.
