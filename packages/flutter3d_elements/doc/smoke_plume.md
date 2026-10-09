# How dark a fire's smoke is, at each height of its plume

`FireView` draws a fire's smoke as puffs carried up its plume. How much light
each puff stops is not chosen: it follows from how much soot the fire makes,
how fast its plume carries it and how wide the plume has grown. This is the
derivation; `fire_view.dart` cites it.

## What is measured

- The soot a fire makes: a yield *Y*<sub>s</sub> of soot per mass burnt,
  its fuel's — 0.015 for a generic wood in small fires (Tewarson), 0.0020
  for a pine crib burning freely, 0.0014 for cardboard boxes, 0.092 for a
  tyre; the core's presets and where each comes from are in
  `flutter3d_physics_native/doc/derivations/soot_yield.md`. A fire of heat
  release *Q* burning a fuel of heat of combustion Δ*H*<sub>c</sub> makes
  soot at

  <math display="block"><mrow><msub><mover><mi>m</mi><mo>˙</mo></mover><mi>s</mi></msub><mo>=</mo><msub><mi>Y</mi><mi>s</mi></msub><mfrac><mi>Q</mi><mrow><mi>Δ</mi><msub><mi>H</mi><mi>c</mi></msub></mrow></mfrac></mrow></math>

  and the core gives each fire its *Y*<sub>s</sub>/Δ*H*<sub>c</sub>, kg a
  joule (`NativeFire.sootYield`), so *Q* times it is the soot.
- The light a gram of soot stops: the mass-specific extinction coefficient
  *K*<sub>m</sub> = 8.7 ± 1.1 m²/g at 633 nm over many fuels' flaming soot
  (Mulholland and Croarkin, as the FDS User's Guide, NIST SP 1019, gives
  it). The one fuel measured on its own, crude oil, gave 8.6 to 10, 9.1 in
  summary (Evans and colleagues, *J. Res. NIST* 106, 2001, table 1), inside
  that spread, so every fire is drawn with 8.7. The soot yields measured by
  laser extinction were read with the same 8.7, so the darkness they give
  back is what was measured.
- The plume's velocity on its axis at a height *z* over the fire, from
  McCaffrey's plume region, *Q* in kW:

  <math display="block"><mrow><mi>u</mi><mo>(</mo><mi>z</mi><mo>)</mo><mo>=</mo><mn>1.11</mn><mspace width="0.2em"/><msup><mi>Q</mi><mrow><mn>1</mn><mo>/</mo><mn>3</mn></mrow></msup><msup><mi>z</mi><mrow><mo>−</mo><mn>1</mn><mo>/</mo><mn>3</mn></mrow></msup><mspace width="1em"/><mtext>m/s</mtext></mrow></math>

- Its half-width, Heskestad's, from the plume's virtual origin *z*<sub>0</sub>
  = 0.083 *Q*<sup>2/5</sup> − 1.02 *D*:

  <math display="block"><mrow><mi>b</mi><mo>(</mo><mi>z</mi><mo>)</mo><mo>=</mo><mn>0.12</mn><mo>(</mo><mi>z</mi><mo>−</mo><msub><mi>z</mi><mn>0</mn></msub><mo>)</mo></mrow></math>

  and no narrower than the fire's base it rises from, *D*/2.

## The derivation

Soot is conserved as it rises: the plume carries all of it, so across any
height the soot crossing it is the soot made. Taking the plume as a column of
radius *b* moving at *u* with the soot spread evenly across it (a top-hat
profile — the measured profiles are near Gaussian, with the soot's width about
the velocity's; the top-hat has the same flux and is what a puff of even
density draws), its concentration is

<math display="block"><mrow><mi>C</mi><mo>(</mo><mi>z</mi><mo>)</mo><mo>=</mo><mfrac><msub><mover><mi>m</mi><mo>˙</mo></mover><mi>s</mi></msub><mrow><mi>π</mi><msup><mi>b</mi><mn>2</mn></msup><mi>u</mi></mrow></mfrac></mrow></math>

and a ray through the plume's axis, across its whole width 2*b*, is dimmed
by the optical depth

<math display="block"><mrow><mi>τ</mi><mo>(</mo><mi>z</mi><mo>)</mo><mo>=</mo><msub><mi>K</mi><mi>m</mi></msub><mi>C</mi><mo>·</mo><mn>2</mn><mi>b</mi><mo>=</mo><mfrac><mrow><mn>2</mn><msub><mi>K</mi><mi>m</mi></msub><msub><mover><mi>m</mi><mo>˙</mo></mover><mi>s</mi></msub></mrow><mrow><mi>π</mi><mi>b</mi><mi>u</mi></mrow></mfrac></mrow></math>

letting through *e*<sup>−τ</sup> of what is behind. In the plume region *b*
grows as *z* and *u* falls as *z*<sup>−1/3</sup>, so

<math display="block"><mrow><mi>τ</mi><mo>∝</mo><msup><mi>z</mi><mrow><mo>−</mo><mn>2</mn><mo>/</mo><mn>3</mn></mrow></msup></mrow></math>

— the smoke is darkest just over the flame and thins as it climbs, as a
plume is seen to.

### The puffs

A puff stands for a stretch of the plume as long as it is wide, 2*b*. To
draw the plume without gaps, one leaves the flame's tip each time the gas
there has risen that far:

<math display="block"><mrow><mfrac><mrow><mi>d</mi><mi>N</mi></mrow><mrow><mi>d</mi><mi>t</mi></mrow></mfrac><mo>=</mo><mfrac><mrow><mi>u</mi><mo>(</mo><msub><mi>z</mi><mtext>tip</mtext></msub><mo>)</mo></mrow><mrow><mn>2</mn><mi>b</mi><mo>(</mo><msub><mi>z</mi><mtext>tip</mtext></msub><mo>)</mo></mrow></mfrac></mrow></math>

and each puff is drawn, wherever it has risen to, with the plume's optical
depth there: its opacity through its middle 1 − *e*<sup>−τ(*z*)</sup>. A
fire whose fuel makes no soot — glowing charcoal's — sends up none.

A puff is let go once the plume it stands in lets through all but a
hundredth of the light, τ = 0.01. Writing τ = *k* *z*<sup>−2/3</sup> with *k*
from the formula above, that is at

<math display="block"><mrow><msub><mi>z</mi><mtext>end</mtext></msub><mo>=</mo><msup><mrow><mo>(</mo><mfrac><mi>k</mi><mn>0.01</mn></mfrac><mo>)</mo></mrow><mrow><mn>3</mn><mo>/</mo><mn>2</mn></mrow></msup></mrow></math>

which it reaches, rising at *u*(*z*), after

<math display="block"><mrow><msub><mi>t</mi><mtext>end</mtext></msub><mo>=</mo><msubsup><mo>∫</mo><msub><mi>z</mi><mtext>tip</mtext></msub><msub><mi>z</mi><mtext>end</mtext></msub></msubsup><mfrac><mrow><mi>d</mi><mi>z</mi></mrow><mrow><mi>u</mi><mo>(</mo><mi>z</mi><mo>)</mo></mrow></mfrac><mo>=</mo><mfrac><mn>3</mn><mrow><mn>4</mn><mo>·</mo><mn>1.11</mn><mspace width="0.2em"/><msup><mi>Q</mi><mrow><mn>1</mn><mo>/</mo><mn>3</mn></mrow></msup></mrow></mfrac><mrow><mo>(</mo><msubsup><mi>z</mi><mtext>end</mtext><mrow><mn>4</mn><mo>/</mo><mn>3</mn></mrow></msubsup><mo>−</mo><msubsup><mi>z</mi><mtext>tip</mtext><mrow><mn>4</mn><mo>/</mo><mn>3</mn></mrow></msubsup><mo>)</mo></mrow></mrow></math>

its life.

### When the view cannot hold them all

A large fire's plume stays visible a long way up — τ falls only as
*z*<sup>−2/3</sup> — and tiling all of it can take more puffs than a view
holds. Sending fewer, farther apart, thins the plume where it is darkest and
most looked at, just over the flame. Instead every puff is still sent, and
each lives the share *s* of its life that lets the view hold them,

<math display="block"><mrow><mi>s</mi><mo>=</mo><mo>min</mo><mrow><mo>(</mo><mn>1</mn><mo>,</mo><mfrac><msub><mi>N</mi><mtext>held</mtext></msub><mrow><munder><mo>∑</mo><mi>i</mi></munder><msub><mrow><mo>(</mo><mfrac><mrow><mi>d</mi><mi>N</mi></mrow><mrow><mi>d</mi><mi>t</mi></mrow></mfrac><mo>)</mo></mrow><mi>i</mi></msub><msub><mi>t</mi><mrow><mtext>end</mtext><mo>,</mo><mi>i</mi></mrow></msub></mrow></mfrac><mo>)</mo></mrow></mrow></math>

so each plume is drawn whole as far up as its puffs reach, fading out over
the last tenth of their life, and not drawn above.

## What is left out

- The plume bent over by wind: its width and speed are the still-air ones;
  the puffs drift with the wind as the gas does.
- Smoke from a smouldering fire, whose soot is much paler (albedo near
  0.97 against flaming pine's 0.66).
