// Copyright (c) 2026 Emanoel IMS. MIT.
// Pure geometry for educational mechanisms; not a manufacturing/stress solver.
const TAU = 2 * Math.PI
const ALPHA = Math.PI / 9 // Standard 20-degree, unshifted full-depth teeth.
const involute = angle => Math.tan(angle) - angle
const polar = (radius, angle) => [radius * Math.cos(angle), radius * Math.sin(angle)]
const bounded = (value, min, max) => Number.isFinite(value) && value >= min && value <= max

/**
 * A counterclockwise concave gear outline in its local XY plane, tooth at +X.
 * Dimensions share the caller's unit. backlash is the tooth-thickness reduction
 * at the pitch circle, PER gear. Flanks are sampled true involutes; roots have
 * radial extensions and circular lands, not cutter-generated trochoid fillets.
 * Only external, unshifted 20-degree gears with 20..160 teeth are supported.
 * Use mPrism for this concave outline: prismOf's convex hull erases the gaps.
 */
export function spurGear({teeth, module: size, backlash = size * .04, samples = 12}) {
  if (!Number.isInteger(teeth) || !bounded(teeth, 20, 160) || !bounded(size, .001, 1000) ||
      !bounded(backlash, 0, size * .15) || !Number.isInteger(samples) || !bounded(samples, 6, 24)) {
    throw new RangeError('Expected 20..160 teeth, positive bounded module, backlash 0..0.15 module and 6..24 samples')
  }
  const pitchRadius = teeth * size / 2, baseRadius = pitchRadius * Math.cos(ALPHA)
  const rootRadius = pitchRadius - 1.25 * size, tipRadius = pitchRadius + size
  const startRadius = Math.max(baseRadius, rootRadius)
  const half = radius => (Math.PI * size / 2 - backlash) / (2 * pitchRadius) +
    involute(ALPHA) - involute(Math.acos(Math.min(1, baseRadius / radius)))
  const rootHalf = half(startRadius), tipHalf = half(tipRadius), outline = []
  for (let tooth = 0; tooth < teeth; tooth++) {
    const center = tooth * TAU / teeth
    outline.push(polar(rootRadius, center - rootHalf))
    // Include the pitch radius explicitly so pitch thickness is exact in the
    // polygon too, rather than depending on interpolation between flank samples.
    const radii = Array.from({length: samples + 1}, (_, i) => startRadius + (tipRadius - startRadius) * i / samples)
    if (pitchRadius > startRadius) radii.push(pitchRadius)
    radii.sort((a, b) => a - b)
    for (const radius of radii) outline.push(polar(radius, center - half(radius)))
    for (let i = 1; i <= 4; i++) outline.push(polar(tipRadius, center - tipHalf + 2 * tipHalf * i / 4))
    for (const radius of [...radii].reverse().slice(1)) outline.push(polar(radius, center + half(radius)))
    if (startRadius > rootRadius) outline.push(polar(rootRadius, center + rootHalf))
    const gap = TAU / teeth - 2 * rootHalf
    for (let i = 1; i < 4; i++) outline.push(polar(rootRadius, center + rootHalf + gap * i / 4))
  }
  // Adjacent radial/root endpoints can coincide for high tooth counts.
  const points = outline.filter((p, i) => !i || Math.hypot(p[0] - outline[i - 1][0], p[1] - outline[i - 1][1]) > size * 1e-10)
  return {teeth, module: size, backlash, pressureAngle: ALPHA, pitchRadius, baseRadius, rootRadius, tipRadius, outline: points}
}

/**
 * Compatible external gears, first center [0,0], second [distance,0].
 * phaseAt(driverAngle) returns [driverAngle, drivenAngle] in radians, CCW in
 * that SAME local plane. One driver tooth faces a driven gap at angle zero.
 * Keep this phase convention when mapping both gears into a shared 3D frame.
 * This is ideal prescribed kinematics, not a contact/dynamics/backlash solver.
 */
export function externalGearPair({teethA, teethB, module: size, backlash = size * .04, samples = 12}) {
  const first = spurGear({teeth: teethA, module: size, backlash, samples})
  const second = spurGear({teeth: teethB, module: size, backlash, samples})
  const distance = first.pitchRadius + second.pitchRadius, ratio = teethA / teethB
  const contactRatio = (Math.sqrt(first.tipRadius ** 2 - first.baseRadius ** 2) +
    Math.sqrt(second.tipRadius ** 2 - second.baseRadius ** 2) - distance * Math.sin(ALPHA)) /
    (Math.PI * size * Math.cos(ALPHA))
  return {
    first, second, distance, ratio, contactRatio,
    phaseAt(driverAngle) {
      if (!bounded(driverAngle, -1e6, 1e6)) throw new RangeError('Expected a finite bounded angle in radians')
      return [driverAngle, Math.PI + Math.PI / teethB - driverAngle * ratio]
    },
  }
}

/**
 * Inline slider-crank, pivot [0,0], horizontal guide Y=0, all angles radians.
 * side=+1 puts the slider to the right; side=-1 to the left. Both pin centers,
 * rod orientation, slider displacement and stroke use this single closure.
 * A caller may rigidly map these local coordinates into its world plane.
 * No offset guide, force, steam pressure or dynamic engine model is implied.
 */
export function sliderCrank({radius, rodLength, side = 1}, angle) {
  if (!bounded(radius, .001, 1e4) || !bounded(rodLength, radius * 1.01, 1e5) ||
      ![1, -1].includes(side) || !bounded(angle, -1e6, 1e6)) {
    throw new RangeError('Expected positive radius, rodLength >= 1.01 radius, side +/-1 and a bounded radian angle')
  }
  const pin = [radius * Math.cos(angle), radius * Math.sin(angle)]
  const slider = [pin[0] + side * Math.sqrt(rodLength ** 2 - pin[1] ** 2), 0]
  return {
    pivot: [0, 0], pin, slider, stroke: 2 * radius,
    rodAngle: Math.atan2(slider[1] - pin[1], slider[0] - pin[0]),
    displacement: slider[0] - (side * rodLength - radius),
  }
}
