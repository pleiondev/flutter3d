# How large the drops a splash throws are

Where falling water lands hard enough, the core throws part of it back up
as a crown of drops (`land()` in `csrc/src/f3d_shallow.c`). The size of a
drop's splash drops was Mundo and colleagues' fit (*Int. J. Multiphase
Flow* 21, 1995, as Wright and Potapczuk, NASA/TM-2004-212916, p. 8, give
it),

<math display="block"><mrow><mfrac><msub><mi>d</mi><mi>s</mi></msub><msub><mi>d</mi><mn>0</mn></msub></mfrac><mo>=</mo><mo>min</mo><mo>(</mo><mn>8.72</mn><msup><mi>e</mi><mrow><mo>−</mo><mn>0.0281</mn><mi>K</mi></mrow></msup><mo>,</mo><mn>1</mn><mo>)</mo><mo>,</mo><mspace width="1em"/><mi>K</mi><mo>=</mo><mtext>Oh</mtext><mspace width="0.2em"/><msup><mtext>Re</mtext><mn>1.25</mn></msup></mrow></math>

measured for drops of 150 µm and less at no more than 18 m/s, which puts
*K* between 77 and 180. A game's drops are millimetres across and land at
10 m/s and more: a 3 mm drop at 10 m/s is *K* ≈ 845, where the fit gives
drops 10⁻¹⁰ of its size — Wright and Potapczuk (p. 9) call the fit
physically wrong outside its data. This replaces it with a law that holds
over the game's range (gap G10 of the research notes).

## What is measured

Xiong and colleagues computed 43 drops of 2.0 to 4.1 mm striking a deep
pool at 1 to 8 m/s, We from 41 to 1790, resolved to 10 µm, and counted
every drop their crowns threw (arXiv:2608.29762, 2026, §IV):

- the number of secondary drops, *N*<sub>s</sub> = 7.33 × 10⁻⁴
  We<sup>9/5</sup> (fig. 8), the We<sup>9/5</sup> that Okawa and
  colleagues measured in the laboratory;
- their total volume, a share *C*<sub>m</sub> of the drop's own
  *D*³ that does not change with We: 0.013 when the crown splashes all
  round, as a drop falling straight down does (fig. 12);
- their sizes over their median, distributed as a Gamma with shape
  *k* = 4.6 and scale β = 0.23 (fig. 9);
- and the median falling as We<sup>−3/5</sup> (fig. 10), what a balance of
  the rim's capillary pull against the inertia of its eddies at that size
  gives, with eddy velocities scaling as the cube root of size (§IV,
  eqs. 19 to 24).

The paper prints the exponent but not the coefficient of the last law.

## The derivation

The drops' volume is their number times the mean cube of their size:

<math display="block"><mrow><msub><mi>C</mi><mi>m</mi></msub><msup><mi>D</mi><mn>3</mn></msup><mo>=</mo><mfrac><mi>π</mi><mn>6</mn></mfrac><msub><mi>N</mi><mi>s</mi></msub><msubsup><mi>d</mi><mtext>med</mtext><mn>3</mn></msubsup><msub><mi>M</mi><mn>3</mn></msub><mo>,</mo><mspace width="1em"/><msub><mi>M</mi><mn>3</mn></msub><mo>=</mo><msup><mi>β</mi><mn>3</mn></msup><mi>k</mi><mo>(</mo><mi>k</mi><mo>+</mo><mn>1</mn><mo>)</mo><mo>(</mo><mi>k</mi><mo>+</mo><mn>2</mn><mo>)</mo><mo>=</mo><mn>2.069</mn></mrow></math>

*M*<sub>3</sub> the third moment of the Gamma of size over median. So

<math display="block"><mrow><mfrac><msub><mi>d</mi><mtext>med</mtext></msub><mi>D</mi></mfrac><mo>=</mo><msup><mrow><mo>(</mo><mfrac><mrow><mn>6</mn><msub><mi>C</mi><mi>m</mi></msub></mrow><mrow><mi>π</mi><mo>×</mo><mn>7.33</mn><mo>×</mo><msup><mn>10</mn><mrow><mo>−</mo><mn>4</mn></mrow></msup><mo>×</mo><msub><mi>M</mi><mn>3</mn></msub></mrow></mfrac><mo>)</mo></mrow><mrow><mn>1</mn><mo>/</mo><mn>3</mn></mrow></msup><msup><mtext>We</mtext><mrow><mo>−</mo><mn>3</mn><mo>/</mo><mn>5</mn></mrow></msup><mo>=</mo><mn>2.54</mn><mspace width="0.2em"/><msup><mtext>We</mtext><mrow><mo>−</mo><mn>3</mn><mo>/</mo><mn>5</mn></mrow></msup></mrow></math>

— the We<sup>9/5</sup> of the count and the We<sup>−3/5</sup> of the size
agree, since (We<sup>−3/5</sup>)<sup>3</sup> = We<sup>−9/5</sup> and the
volume does not change. The core takes it, no larger than the drop:

<math display="block"><mrow><mfrac><msub><mi>d</mi><mi>s</mi></msub><mi>D</mi></mfrac><mo>=</mo><mo>min</mo><mo>(</mo><mn>2.54</mn><mspace width="0.2em"/><msup><mtext>We</mtext><mrow><mo>−</mo><mn>3</mn><mo>/</mo><mn>5</mn></mrow></msup><mo>,</mo><mn>1</mn><mo>)</mo></mrow></math>

| We | *d*<sub>s</sub>/*D* | For *D* = 3 mm |
|---|---|---|
| 41 | 0.27 | 0.82 mm |
| 100 | 0.16 | 0.48 mm |
| 500 | 0.061 | 0.18 mm |
| 1790 | 0.028 | 85 µm |
| 4100 (3 mm at 10 m/s) | 0.017 | 52 µm |
| 16000 | 0.0076 | 23 µm |

Inside the computed range the drops are tens to hundreds of micrometres,
the ≈ 50 µm the paper reports seeing and earlier experiments measured
(§II). Past We = 1790 it is extrapolated, on a law whose exponent the
paper derives from the breakup's physics rather than fits; Mundo's fit has
no such footing.

## What is left out

- The pool's depth: the computations are at four drop diameters deep. A
  drop on a thin film or on ground takes the same law.
- The spread: every drop of a crown is thrown at the median size.
- Oblique impacts throw fewer drops, 0.004 of *D*³ when only the front
  splashes (fig. 12): the crown's share of what splashes is set elsewhere
  in `land()`, by O'Rourke and Amsden's law.
