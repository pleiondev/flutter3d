# Heat and fire

Every body in a world of the physics core has a material and a temperature.
It loses heat to the air by convection and radiation, takes heat from what it
touches and from hot bodies near it, and can carry water, which holds it at the boiling point until it has
boiled away. Wood, paper and rubber catch at their ignition temperature, burn
their fuel at a rate per square metre of surface, keep part of the fire's heat
and give the rest off as hot gas. A burning body gets lighter.

This page puts a wooden board and a steel one either side of a block of stone
at a thousand degrees Celsius. The wood catches and burns, the steel only
warms, and water on the wood puts it out. The page runs twenty times faster
than real time, so the wait to catch is about fifteen seconds rather than five
minutes.

## Step 1: A heater and two boards

All three are fixed bodies: nothing here needs to move to burn. A fixed body's
mass is its thermal mass, and it is what burns away. The heater is given no
mass at all, which makes it a reservoir: whatever heat it gives, it stays at
the temperature it was set to. The boards are twenty centimetres square and
four thick, one pine at 500 kg/m³ and one steel at 7800, each with the core's
preset for its material.

{{code bench}}

## Step 2: The heat the heater throws

Nothing on the page passes heat from the heater to the boards: the core
does. Every body gives the room εσA(T⁴ − Tₐ⁴) above what it would at the
air's temperature, and each body near it catches its solid angle's share of
that, as much as nothing stands in the way. A burning body also sends its
material's radiant share of its fire's heat, and anything standing in its
flame is heated by the flame's gas. Both boards get the same. The steel, with fifteen times the wood's mass, warms
slowly; it has no ignition temperature in its preset, so it never catches
however hot it gets.

## Step 3: Wind

The air has a wind, uniform and from a grid. This grid has two samples, still
air at the floor and a metre and a half a second a metre up, read trilinearly
between them, and the slider adds a uniform wind on top. Wind past a body
cools it faster, so a strong enough wind keeps the wood from catching at all.
The flames in Step 5 are carried by the same field, read with `windAt`.

{{code wind}}

## Step 4: Step, and listen

Each frame steps the world a third of a second. `readEvents` says what
happened in it; this page keeps the fire's events: `ignited`, `extinguished`
and `burntOut`. A minute after the wood catches, half a litre of water goes
on it and the heater is let cool to the air. The water holds the board at
100 °C, below where wood burns, so the next step puts the fire out. The
switch beside the viewport pours it sooner.

{{code step}}

{{code douse}}

## Step 5: Flames

`readFires` lists every burning body with its position and the watts its fire
gives off as hot gas, which is what a smoke grid would take as its sources.
Here it seeds a pool of small glowing particles that rise and drift with the
wind where they are. The boards themselves glow from dull red to orange with
their temperature.

{{code flames}}

## Step 6: What has to happen

From cold, a second a step: the wood has to catch, which it does after about
three hundred steps, and say so with an `ignited` event. Twenty seconds later it has
to be still burning and lighter by more than ten grams; it loses about
twenty-five. The steel has to have warmed, to about 350 K, and never caught.
Then water goes on, and the next step has to put the fire out with an
`extinguished` event.

{{code check}}

> **Note.** A body is one temperature throughout, which is right for a crate
> or a board but not for a log whose outside chars while its middle is cold.
> Radiation sees every body as a ball of its own surface, and five rays
> decide how much of it a wall hides. A crate stacked on a burning one
> catches in its flame; one beside it catches when the fire is big enough or
> the wind lays the flame over it, and one a few metres off only warms. Heat across a contact is
> modest by design. Wood is an insulator, and a burning block warms the one it
> touches without lighting it.
