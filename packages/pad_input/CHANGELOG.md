## 0.1.0

* Reads a gamepad as a snapshot the caller asks for, once per frame, rather than
  as a stream of events.
* Button identifiers are physical positions — `face.south`, not `a` — because
  they are written into a player's configuration file and have to mean the same
  thing on different hardware for ever.
* The dead zone is radial and rescaled, so a stick leaving it starts from nought
  rather than from the zone.
* A disconnection zeroes the snapshot before it announces itself.
* No platform implementation yet: `isSupported` answers false everywhere, and
  answers it without opening a channel.
