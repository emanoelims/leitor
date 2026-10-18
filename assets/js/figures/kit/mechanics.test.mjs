import {test} from 'node:test'
import assert from 'node:assert/strict'
import {spurGear, externalGearPair, sliderCrank} from './mechanics.mjs'

const near = (a, b, tolerance = 1e-8) => assert.ok(Math.abs(a - b) < tolerance, `${a} != ${b}`)
const placed = (points, angle, x = 0) => points.map(([u, v]) => [x + u * Math.cos(angle) - v * Math.sin(angle), u * Math.sin(angle) + v * Math.cos(angle)])
const cross = (a, b, c) => (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
// Independent polygon collision probe, restricted only by overlapping bounding
// boxes. Proper crossings imply positive overlap; tangent contact is allowed.
function intersect(a, b) {
  const edges = points => points.map((p, i) => [p, points[(i + 1) % points.length]])
  const ae = edges(a), be = edges(b)
  const amin = Math.min(...a.map(p => p[0])), amax = Math.max(...a.map(p => p[0]))
  const bmin = Math.min(...b.map(p => p[0])), bmax = Math.max(...b.map(p => p[0]))
  const relevant = ([p, q], min, max) => Math.max(p[0], q[0]) >= min && Math.min(p[0], q[0]) <= max
  const left = ae.filter(e => relevant(e, bmin, bmax)), right = be.filter(e => relevant(e, amin, amax))
  for (const [p, q] of left) {
    for (const [r, s] of right) {
      if (Math.max(p[1], q[1]) < Math.min(r[1], s[1]) || Math.max(r[1], s[1]) < Math.min(p[1], q[1])) continue
      if (cross(p, q, r) * cross(p, q, s) < -1e-15 && cross(r, s, p) * cross(r, s, q) < -1e-15) return true
    }
  }
  return false
}

test('involute dimensions, pitch thickness, concavity and scaling agree with standard gearing', () => {
  const gear = spurGear({teeth: 24, module: 2, backlash: .08})
  near(gear.pitchRadius, 24); near(gear.rootRadius, 21.5); near(gear.tipRadius, 26)
  near(gear.baseRadius, 24 * Math.cos(Math.PI / 9))
  const pitch = gear.outline.filter(p => Math.abs(Math.hypot(...p) - 24) < 1e-9 && Math.abs(Math.atan2(p[1], p[0])) < .1)
  assert.equal(pitch.length, 2)
  near((Math.atan2(pitch[1][1], pitch[1][0]) - Math.atan2(pitch[0][1], pitch[0][0])) * 24, Math.PI - .08)
  const scaled = spurGear({teeth: 24, module: 6, backlash: .24})
  gear.outline.forEach((p, i) => p.forEach((v, j) => near(scaled.outline[i][j], 3 * v)))
  assert.ok(gear.outline.some((p, i, all) => cross(all[(i + all.length - 1) % all.length], p, all[(i + 1) % all.length]) < -1e-8))
  const area = gear.outline.reduce((sum, p, i, all) => sum + cross([0, 0], p, all[(i + 1) % all.length]), 0) / 2
  assert.ok(area > Math.PI * gear.rootRadius ** 2 && area < Math.PI * gear.tipRadius ** 2)
})

test('gear pairs preserve pitch tangency, speed ratio and clearance across a full driver revolution', () => {
  for (const [teethA, teethB, backlash = .04, samples = 12] of [[20, 20], [20, 40], [24, 60], [40, 20], [20, 160], [20, 40, 0, 6], [160, 160, .15, 24]]) {
    const pair = externalGearPair({teethA, teethB, module: 1, backlash, samples})
    near(pair.distance, (teethA + teethB) / 2)
    assert.ok(pair.contactRatio > 1)
    for (let i = 0; i <= 360; i++) {
      const [a, b] = pair.phaseAt(i * Math.PI / 180)
      near((b - Math.PI - Math.PI / teethB) * teethB + a * teethA, 0)
      assert.equal(intersect(placed(pair.first.outline, a), placed(pair.second.outline, b, pair.distance)), false, `${teethA}:${teethB} overlap at ${i} degrees`)
    }
    const [a, b] = pair.phaseAt(0)
    assert.equal(intersect(placed(pair.first.outline, a), placed(pair.second.outline, b + Math.PI / teethB, pair.distance)), true, 'probe must detect an incorrectly phased pair')
  }
})

test('both slider branches maintain rigid pin closure and exactly twice-radius stroke over 721 poses', () => {
  for (const side of [-1, 1]) {
    let min = Infinity, max = -Infinity
    for (let i = 0; i <= 720; i++) {
      const pose = sliderCrank({radius: 24, rodLength: 80, side}, i * Math.PI / 360)
      near(Math.hypot(...pose.pin), 24)
      near(Math.hypot(pose.pin[0] - pose.slider[0], pose.pin[1] - pose.slider[1]), 80)
      near(pose.slider[1], 0)
      near(pose.pin[0] + 80 * Math.cos(pose.rodAngle), pose.slider[0])
      near(pose.pin[1] + 80 * Math.sin(pose.rodAngle), pose.slider[1])
      min = Math.min(min, pose.displacement); max = Math.max(max, pose.displacement)
    }
    near(min, 0); near(max, 48)
  }
})

test('unsupported, non-finite and unbounded mechanisms fail explicitly', () => {
  for (const options of [
    {teeth: 10, module: 1}, {teeth: 161, module: 1}, {teeth: 20.5, module: 1},
    {teeth: 20, module: 0}, {teeth: 20, module: Infinity}, {teeth: 20, module: 1, backlash: -.1},
    {teeth: 20, module: 1, backlash: .2}, {teeth: 20, module: 1, samples: 1000},
  ]) assert.throws(() => spurGear(options), RangeError)
  assert.throws(() => externalGearPair({teethA: 20, teethB: 40, module: 1}).phaseAt(NaN), RangeError)
  for (const options of [{radius: 4, rodLength: 3}, {radius: 4, rodLength: 4}, {radius: NaN, rodLength: 8}, {radius: 4, rodLength: 8, side: 0}]) {
    assert.throws(() => sliderCrank(options, 0), RangeError)
  }
  assert.throws(() => sliderCrank({radius: 4, rodLength: 8}, Infinity), RangeError)
})
