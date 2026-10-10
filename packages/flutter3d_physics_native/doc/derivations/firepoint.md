# The least burning that holds a flame on cardboard and straw

`F3dMaterial.critical_mass_flux` is the least fuel gas a surface must give
off for a flame to stand on it; a patch that gives less goes out. For wood
the core takes Rasbash's 2.5 g/(m² s) (Rasbash, Drysdale and Deepak, *Fire
Safety Journal* 10, 1986; Drysdale, *An Introduction to Fire Dynamics*,
§6.3). No open source gives it for corrugated board or straw (gap G3 of the
research notes). This derives it.

## What is measured

- Wood's firepoint, 2.5 g/(m² s) (Rasbash), the core's
  `F3D_CRITICAL_MASS_FLUX`, which OAK and PINE keep.
- The effective heats of combustion, per kilogram lost: red oak 12.4 and
  southern pine 13.9 MJ/kg (Tran and White, *Fire and Materials* 16, 1992,
  table 4); corrugated board 14.03 and straw 10.1 MJ/kg by micro-scale
  combustion calorimetry (UL FSRI Materials and Products Database).

## The derivation

Rasbash's firepoint balance asks the flame to hand the surface enough heat
to keep making the gas it burns: a share φ of what the gas releases comes
back, and it must pay for gasifying it and for what the surface loses,

<math display="block"><mrow><mi>φ</mi><mspace width="0.2em"/><mi>Δ</mi><msub><mi>H</mi><mi>c</mi></msub><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mtext>cr</mtext><mo>″</mo></msubsup><mo>=</mo><mi>L</mi><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mtext>cr</mtext><mo>″</mo></msubsup><mo>+</mo><msubsup><mi>q</mi><mtext>loss</mtext><mo>″</mo></msubsup></mrow></math>

For cellulosic fuels that catch near the same temperature, 315 to 350 °C,
the losses at the surface are alike, and so are *L*, 0.94 to 1.02 MJ/kg
(`heat_of_gasification.md`), against φΔ*H*<sub>c</sub> of several MJ/kg.
What then sets the least burning is the heat its gas releases: a flame
stands on a cellulosic surface once it releases a fixed heat a square metre,

<math display="block"><mrow><msubsup><mover><mi>m</mi><mo>˙</mo></mover><mtext>cr</mtext><mo>″</mo></msubsup><mo>=</mo><mfrac><msubsup><mi>q</mi><mtext>cr</mtext><mo>″</mo></msubsup><mrow><mi>Δ</mi><msub><mi>H</mi><mi>c</mi></msub></mrow></mfrac><mo>,</mo><mspace width="1em"/><msubsup><mi>q</mi><mtext>cr</mtext><mo>″</mo></msubsup><mo>=</mo><mn>2.5</mn><mspace width="0.2em"/><mtext>g/(m² s)</mtext><mo>×</mo><mfrac><mrow><mn>12.4</mn><mo>+</mo><mn>13.9</mn></mrow><mn>2</mn></mfrac><mspace width="0.2em"/><mtext>MJ/kg</mtext><mo>=</mo><mn>32.9</mn><mspace width="0.2em"/><mtext>kW/m²</mtext></mrow></math>

the wood anchor taken over the two woods the presets carry.

| Material | Δ*H*<sub>c</sub> | ṁ''<sub>cr</sub> |
|---|---|---|
| Oak, pine (Rasbash, kept) | 12.4, 13.9 MJ/kg | 2.5 g/(m² s) |
| Corrugated board | 14.03 MJ/kg | **2.34 g/(m² s)** |
| Straw | 10.1 MJ/kg | **3.25 g/(m² s)** |

The core carries 32.9 kW/m² as `F3D_FIREPOINT_RELEASE` and divides it by
each preset's own heat of combustion.

## What it rests on, and what is left out

- The scaling holds while *L* is small against φΔ*H*<sub>c</sub>; for wood
  with φ ≈ 0.3 that is 0.94 against about 4 MJ/kg.
- Lin and Huang give 4 g/(m² s) for wood's flame-out under irradiation
  (*Fire Technology*, 2022, pp. 2–3): the extinction limit, which sits
  above Rasbash's ignition firepoint. The core uses one number for both,
  and keeps Rasbash's so the presets agree with WOOD.
- Straw burns as a bed whose flame stands among the stalks, not on a
  surface; the firepoint is applied to the bed's patch as to a solid's.
