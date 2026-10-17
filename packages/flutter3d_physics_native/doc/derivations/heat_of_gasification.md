# The heat of gasification of oak, pine, cardboard and straw

`F3dMaterial.heat_of_gasification` is the *L* a burning surface divides its
net heat by to give off fuel gas, ṁ'' = *q*''/*L* (Tewarson). The core
already counts two things a measured *L* usually folds in: the char layer
that grows over wood and insulates it (`char_yield`), and the water a body
holds (the bus's `f3d_body_add_water`). So the presets need *L* for the dry
solid with no char over it. No open source gives that for these four
materials (gap G2 of the research notes). This derives it, and the mean
specific heat the presets carry with it.

## What is measured

- The specific heat of dry wood rises with temperature. Parker fitted, for
  virgin Douglas fir up to 300 °C,

  <math display="block"><mrow><msub><mi>c</mi><mi>w</mi></msub><mo>=</mo><mn>1.11</mn><mo>+</mo><mn>0.0037</mn><mspace width="0.2em"/><mi>T</mi><mspace width="1em"/><mtext>kJ/(kg K), </mtext><mi>T</mi><mtext> in °C</mtext></mrow></math>

  (Parker, "Prediction of the Heat Release Rate of Douglas Fir", *Fire
  Safety Science* 2, 1989, eq. 6), which Mell and colleagues take for grass
  too (*Int. J. Wildland Fire* 16, 2007, table 1). The Wood Handbook's
  correlation says the same: dry wood's specific heat is "practically
  independent of density or species" (FPL-GTR-190, ch. 4, eq. 4-16a).
- Where each catches, by a surface thermocouple in a calorimeter: red oak
  315 °C, southern pine 320 °C (Tran and White, *Fire and Materials* 16,
  1992, table 3); corrugated board 350 °C (Khan, de Ris and Ogden, *Fire
  Safety Science* 9, 2008, from its critical flux); straw 320 °C, the
  temperature Rothermel's model heats every wildland fuel to (USDA INT-115,
  1972, p. 4).
- The heat cellulose takes to break down into gas besides warming:
  430 kJ/kg for wood (the FDS User's Guide, NIST SP 1019, the core's
  `F3D_PYROLYSIS_HEAT`), 416 kJ/kg for grass (Mell and colleagues,
  table 1).
- For straw, Rothermel's heat of pre-ignition, the heat to bring a dry
  wildland fuel from 20 °C to 320 °C: 250 Btu/lb = 581 kJ/kg (INT-115,
  eq. 12).
- For corrugated board, the specific heat of its virgin layers,
  1800 J/(kg K) (Semmes and colleagues, *Fire Safety Science* 11, 2014,
  table 2).

## The derivation

At steady burning the front sits at the ignition temperature
*T*<sub>ig</sub>, and each kilogram that leaves it as gas has been warmed
there from the room's *T*<sub>a</sub> and then broken down:

<math display="block"><mrow><mi>L</mi><mo>=</mo><msubsup><mo>∫</mo><msub><mi>T</mi><mi>a</mi></msub><msub><mi>T</mi><mtext>ig</mtext></msub></msubsup><mi>c</mi><mo>(</mo><mi>T</mi><mo>)</mo><mspace width="0.2em"/><mi>d</mi><mi>T</mi><mo>+</mo><mi>Δ</mi><msub><mi>H</mi><mtext>pyr</mtext></msub></mrow></math>

With Parker's linear *c*, the integral from 20 °C to *T* (°C) is

<math display="block"><mrow><msubsup><mo>∫</mo><mn>20</mn><mi>T</mi></msubsup><msub><mi>c</mi><mi>w</mi></msub><mspace width="0.2em"/><mi>d</mi><mi>T</mi><mo>=</mo><mn>1.11</mn><mo>(</mo><mi>T</mi><mo>−</mo><mn>20</mn><mo>)</mo><mo>+</mo><mn>0.00185</mn><mo>(</mo><msup><mi>T</mi><mn>2</mn></msup><mo>−</mo><msup><mn>20</mn><mn>2</mn></msup><mo>)</mo><mspace width="1em"/><mtext>kJ/kg</mtext></mrow></math>

The core warms a body with one specific heat, so the preset takes the mean
of *c* over the same range, the integral over *T*<sub>ig</sub> −
*T*<sub>a</sub>: that is the *c* that gives the right heat to bring the
surface to where it catches.

| Material | *T*<sub>ig</sub> | Sensible heat to *T*<sub>ig</sub> | Mean *c* | Δ*H*<sub>pyr</sub> | *L* |
|---|---|---|---|---|---|
| Red oak | 588.15 K | 510 kJ/kg (Parker) | 1730 J/(kg K) | 430 kJ/kg | **0.940 MJ/kg** |
| Southern pine | 593.15 K | 522 kJ/kg (Parker) | 1739 J/(kg K) | 430 kJ/kg | **0.952 MJ/kg** |
| Corrugated board | 623.15 K | 1800 × 330 = 594 kJ/kg | 1800 J/(kg K) (Semmes) | 430 kJ/kg | **1.024 MJ/kg** |
| Straw | 593.15 K | 581 kJ/kg (Rothermel) | 581/300 = 1938 J/(kg K) | 416 kJ/kg | **0.998 MJ/kg** |

Straw takes Rothermel's heat of pre-ignition rather than Parker's
integral, 522 kJ/kg, because its spread rate in `flame_spread.md` comes from
Rothermel's model, which is built on that number; the two differ by 11 %.

## How it compares with what was measured

- Tewarson's 1.81 MJ/kg for Douglas fir, the core's default, and Mikkola's
  1.7 MJ/kg for spruce at 10 % moisture (*Fire Safety Science* 3, 1991,
  p. 550) include the wood's water. At 12 % moisture a kilogram of dry wood
  carries 0.12 kg of water, which takes 0.12 × (4.18 × 80 + 2257) =
  311 kJ to warm and boil: oak's *L* becomes 1.25 MJ/kg, pine's 1.26. The
  literature range Mikkola gives is 1.4 to 7 MJ/kg; its low end is the
  early-burning value, its high end the whole-test slope.
- The whole-test slopes Tran and White measured, 6.6 MJ/kg for red oak and
  8.2 for southern pine (table 4), are larger by the char's insulation:
  the time-averaged burning over a test is held back by the char that
  grows. The core grows that char itself, so those values are not used.

## What is left out

- The rise of *c* past 300 °C, Parker's fit's limit: oak and pine catch at
  315 and 320 °C, just past it.
- Cardboard's own heat of pyrolysis: wood's is taken for its cellulose.
- How *L* changes with the moisture a game gives a body: that is the
  bus's water, not this number.
