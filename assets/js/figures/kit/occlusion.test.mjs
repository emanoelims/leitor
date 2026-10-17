import {test} from 'node:test'
import assert from 'node:assert/strict'
import {planeThrough, orderSurfaces} from './occlusion.mjs'

const zPlane = z => planeThrough([0, 0, z], [1, 0, z], [0, 1, z])
const square = (id, z) => ({id, points: [[-1, -1, z], [1, -1, z], [1, 1, z], [-1, 1, z]]})
const area = points => Math.abs(points.reduce((sum, a, i) => {
  const b = points[(i + 1) % points.length]
  return sum + a[0] * b[1] - b[0] * a[1]
}, 0)) / 2

test('camera reversal reverses opaque painting order without changing caller data', () => {
  const items = [square('near', 2), square('far', -2)], snapshot = structuredClone(items)
  assert.deepEqual(orderSurfaces(items, {planes: [zPlane(0)], view: [0, 0, 1]}).map(x => x.id), ['far', 'near'])
  assert.deepEqual(orderSurfaces(items, {planes: [zPlane(0)], view: [0, 0, -1]}).map(x => x.id), ['near', 'far'])
  assert.deepEqual(items, snapshot)
})

test('crossing opaque surfaces split and paint the nearer material at both sides', () => {
  const flat = square('flat', 0)
  const sloped = {...square('sloped', 0), points: [[-1, -1, -1], [1, -1, 1], [1, 1, 1], [-1, 1, -1]]}
  const result = orderSurfaces([flat, sloped], {
    planes: [zPlane(0), planeThrough(...sloped.points.slice(0, 3))], view: [0, 0, 1],
  })
  // Evaluate the actual painting order on either side of the crossing, not just
  // the centroid ordering (both unsplit centroids lie at z=0).
  const inside = (points, x, y) => {
    let sign = 0
    for (let i = 0; i < points.length; i++) {
      const a = points[i], b = points[(i + 1) % points.length]
      const cross = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
      if (Math.abs(cross) < 1e-8) continue
      if (sign && Math.sign(cross) !== sign) return false
      sign = Math.sign(cross)
    }
    return true
  }
  for (const x of [-0.8, -0.4, 0.4, 0.8]) {
    const covering = result.filter(face => inside(face.points, x, 0.2))
    assert.equal(covering.at(-1).id, x < 0 ? 'flat' : 'sloped')
  }
  for (const id of ['flat', 'sloped']) {
    assert.ok(Math.abs(result.filter(x => x.id === id).reduce((s, x) => s + area(x.points), 0) - 4) < 1e-8)
  }
})

test('segments crossing a plane preserve both halves and draw after coplanar fills', () => {
  const edge = {id: 'edge', segment: true, points: [[-1, 0, -1], [1, 0, 1]]}
  const result = orderSurfaces([edge, square('fill', 0)], {planes: [zPlane(0)], view: [0, 0, 1]})
  assert.deepEqual(result.map(x => x.id), ['edge', 'fill', 'edge'])
  assert.deepEqual(result[0].points, [[-1, 0, -1], [0, 0, 0]])
  assert.deepEqual(result[2].points, [[0, 0, 0], [1, 0, 1]])
  const coplanar = {...edge, points: [[-1, 0, 0], [1, 0, 0]]}
  assert.deepEqual(orderSurfaces([coplanar, square('fill', 0)], {planes: [], view: [0, 0, 1]}).map(x => x.id), ['fill', 'edge'])
})

test('three crossing sheets preserve local visibility where whole-face centroid order cannot', () => {
  const heights = [(x, y) => 1.2 * x, (x, y) => 1.2 * y, (x, y) => -x - y]
  const sheets = heights.map((height, id) => ({id, points: square('', 0).points.map(([x, y]) => [x, y, height(x, y)])}))
  const result = orderSurfaces(sheets, {planes: sheets.map(s => planeThrough(...s.points.slice(0, 3))), view: [0, 0, 1]})
  const visible = new Set()
  for (const [x, y] of [[.8, .3], [.3, .8], [-.8, -.3], [-.3, -.8], [.7, -.6], [-.6, .7]]) {
    const covers = face => face.points.every((a, i) => {
      const b = face.points[(i + 1) % face.points.length]
      return (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]) >= -1e-8
    })
    const expected = heights.map(h => h(x, y)).reduce((best, z, i, values) => z > values[best] ? i : best, 0)
    assert.equal(result.filter(covers).at(-1).id, expected)
    visible.add(expected)
  }
  assert.equal(visible.size, 3)
})

test('plane construction is orientation invariant for physical ordering', () => {
  const items = [square('a', -1), square('b', 1)]
  const forward = zPlane(0), reverse = {normal: forward.normal.map(n => -n), offset: 0}
  assert.deepEqual(orderSurfaces(items, {planes: [forward], view: [0, 0, 1]}), orderSurfaces(items, {planes: [reverse], view: [0, 0, 1]}))
})

test('malformed inputs and work exhaustion fail explicitly', () => {
  assert.throws(() => planeThrough([0, 0, 0], [1, 1, 1], [2, 2, 2]), /collinear/)
  assert.throws(() => planeThrough([NaN, 0, 0], [1, 0, 0], [0, 1, 0]), /finite/)
  assert.throws(() => planeThrough([0, 0, 0], [1e308, 0, 0], [0, 1e308, 0]), /unbounded/)
  for (const options of [
    {planes: [], view: [0, 0, 0]},
    {planes: Array(33).fill(zPlane(0)), view: [0, 0, 1]},
    {planes: [{normal: [0, 0, 2], offset: 0}], view: [0, 0, 1]},
    {planes: [], view: [0, 0, 1], maxFragments: 0},
  ]) assert.throws(() => orderSurfaces([square('a', 0)], options))
  assert.throws(() => orderSurfaces([{points: [[0, 0, Infinity], [1, 0, 0], [0, 1, 0]]}], {planes: [], view: [0, 0, 1]}), /surface/)
  assert.throws(() => orderSurfaces([square('a', 0)], {planes: [zPlane(0)], view: [0, 0, 1], maxFragments: 1}), /budget/)
})
