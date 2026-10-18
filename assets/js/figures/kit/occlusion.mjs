// Copyright (c) 2026 Emanoel IMS. MIT.
// Pure, bounded BSP partitioning for opaque orthographic SVG surfaces.
const EPSILON = 1e-6
const dot = (a, b) => a.reduce((sum, value, i) => sum + value * b[i], 0)
const point = p => Array.isArray(p) && p.length === 3 && p.every(Number.isFinite)

/** Unit plane {normal, offset} through three non-collinear world points. */
export function planeThrough(a, b, c) {
  if (![a, b, c].every(point)) throw new TypeError('Expected finite 3D points')
  const u = b.map((v, i) => v - a[i]), v = c.map((x, i) => x - a[i])
  const n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
  const length = Math.hypot(...n)
  if (!Number.isFinite(length) || length < EPSILON) throw new RangeError('Cannot construct a plane from collinear or unbounded points')
  const normal = n.map(x => x / length)
  return {normal, offset: dot(normal, a)}
}

function split(item, plane) {
  const points = item.points, distances = points.map(p => dot(plane.normal, p) - plane.offset)
  const positive = distances.some(d => d > EPSILON), negative = distances.some(d => d < -EPSILON)
  if (!positive && !negative) return {on: item}
  if (!negative) return {front: item}
  if (!positive) return {back: item}
  const front = [], back = [], segment = item.segment === true
  for (let i = 0; i < (segment ? 1 : points.length); i++) {
    const j = (i + 1) % points.length, a = points[i], b = points[j], da = distances[i], db = distances[j]
    if (da >= -EPSILON) front.push(a)
    if (da <= EPSILON) back.push(a)
    if ((da > EPSILON && db < -EPSILON) || (da < -EPSILON && db > EPSILON)) {
      const t = da / (da - db), intersection = a.map((value, axis) => value + t * (b[axis] - value))
      front.push(intersection)
      back.push(intersection)
    }
    if (segment) {
      if (db >= -EPSILON) front.push(b)
      if (db <= EPSILON) back.push(b)
    }
  }
  const minimum = segment ? 2 : 3
  return {
    front: front.length >= minimum ? {...item, points: front} : null,
    back: back.length >= minimum ? {...item, points: back} : null,
  }
}

/**
 * Return far-to-near fragments, retaining caller metadata without mutating inputs.
 * Faces must be convex and planar; triangulate concave polygons first. Segments
 * use {segment:true, points:[a,b]}. Supply world-space partition planes and a
 * direction pointing toward the orthographic camera. Include all relevant face
 * planes for exact ordering; unpartitioned cells fall back to centroid depth.
 * This orders opaque surfaces; it is not a boolean-solid/collision/transparency
 * engine. Exceeding the bounded work budget throws, never silently drops faces.
 */
export function orderSurfaces(items, {planes, view, maxFragments = 100_000}) {
  if (!Array.isArray(items) || items.length > 20_000 || !Array.isArray(planes) || planes.length > 32 ||
      !point(view) || Math.hypot(...view) < EPSILON || !Number.isInteger(maxFragments) || maxFragments < 1 || maxFragments > 100_000) {
    throw new RangeError('Invalid occlusion bounds or camera')
  }
  for (const plane of planes) {
    if (!point(plane.normal) || Math.abs(Math.hypot(...plane.normal) - 1) > EPSILON || !Number.isFinite(plane.offset)) {
      throw new TypeError('Expected normalized finite planes')
    }
  }
  for (const item of items) {
    if (!Array.isArray(item.points) || item.points.length < (item.segment === true ? 2 : 3) || item.points.length > 256 ||
        (item.segment === true && item.points.length !== 2) || !item.points.every(point)) throw new TypeError('Invalid surface')
  }
  let work = 0
  const depth = item => item.points.reduce((sum, p) => sum + dot(p, view), 0) / item.points.length
  function visit(group, index) {
    work += group.length
    if (work > maxFragments) throw new RangeError('Occlusion fragment budget exceeded')
    if (!group.length) return []
    if (index === planes.length) return [...group].sort((a, b) => {
      const delta = depth(a) - depth(b)
      return Math.abs(delta) > EPSILON ? delta : Number(a.segment === true) - Number(b.segment === true)
    })
    const plane = planes[index], front = [], back = [], on = []
    for (const item of group) {
      const parts = split(item, plane)
      if (parts.front) front.push(parts.front)
      if (parts.back) back.push(parts.back)
      if (parts.on) on.push(parts.on)
    }
    const toward = dot(plane.normal, view) > 0
    return [...visit(toward ? back : front, index + 1), ...visit(on, index + 1), ...visit(toward ? front : back, index + 1)]
  }
  return visit(items, 0)
}
