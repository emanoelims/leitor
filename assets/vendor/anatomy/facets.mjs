// A small facet engine for parts that turn about any axis or are cut open: prisms of any (concave, holed) section
// extruded along any frame axis, posed by a rotation and a translation, split by half-spaces (to draw what sits inside
// the cut housing through its openings), shaded with the kit's own four-tone light and drawn back to front with
// outlines only on silhouettes and creases. Same classes as the kit's solidSvg, so ISO_CSS styles it in both themes.
// The page inlines this file after the kit (import line and `export ` stripped); names are prefixed `m`.
import { iso, pathOf } from "./iso-kit.mjs";

const M_BANDS = [0, 0.2, 0.42, 0.62];
export const mDot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
export const mSub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export const mAdd = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const mMul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
export const mUnit = (a) => { const l = Math.hypot(a[0], a[1], a[2]) || 1; return [a[0] / l, a[1] / l, a[2] / l]; };
export function mView(P) {
  const a = (P.azimuth * Math.PI) / 180, e = ((P.elevation ?? 30) * Math.PI) / 180;
  return [Math.cos(a) * Math.cos(e), Math.sin(a) * Math.cos(e), Math.sin(e)];
}
export function mLight(P) {
  const a = (P.azimuth * Math.PI) / 180;
  return mUnit([-Math.sin(a), Math.cos(a), 1.2]);
}
export function mBand(score) { let t = 0; while (t < 4 && score >= M_BANDS[t]) t++; return t; }
const mArea = (ring) => { let s = 0; for (let i = 0; i < ring.length; i++) { const p = ring[i], q = ring[(i + 1) % ring.length]; s += p[0] * q[1] - q[0] * p[1]; } return s / 2; };
export const mArc = (cx, cy, r, a0, a1, n) => Array.from({ length: n + 1 }, (_, i) => { const a = a0 + ((a1 - a0) * i) / n; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; });

// A prism: rings [outer, ...holes] of [u, v] points in frame F = { o, a, u, v } (u x v = a), from s0 to s1 along a.
// opt.skip(ringIndex, edgeIndex) drops a side face (to replace it by hand), opt.tone is the outline tone.
export function mPrism(rings, F, s0, s1, opt = {}) {
  const fixed = rings.map((ring, k) => { const ccw = mArea(ring) > 0; return (k === 0) === ccw ? ring : [...ring].reverse(); });
  const at = (s, [u, v]) => [F.o[0] + F.a[0] * s + F.u[0] * u + F.v[0] * v, F.o[1] + F.a[1] * s + F.u[1] * u + F.v[1] * v, F.o[2] + F.a[2] * s + F.u[2] * u + F.v[2] * v];
  const sideN = fixed.map((ring) => ring.map((p, j) => { const q = ring[(j + 1) % ring.length]; return mUnit(mAdd(mMul(F.u, q[1] - p[1]), mMul(F.v, -(q[0] - p[0])))); }));
  const down = mMul(F.a, -1), up = F.a;
  const faces = [];
  for (const [s, n] of [[s0, down], [s1, up]]) {
    faces.push({ rings: fixed.map((ring) => ring.map((p) => at(s, p))), n, edges: fixed.flatMap((ring, k) => ring.map((p, j) => ({ a: at(s, p), b: at(s, ring[(j + 1) % ring.length]), nb: sideN[k][j], own: true }))) });
  }
  fixed.forEach((ring, k) => ring.forEach((p, j) => {
    const m = ring.length, q = ring[(j + 1) % m];
    if (opt.skip && opt.skip(p, q)) return;
    const n = sideN[k][j];
    const a0 = at(s0, p), b0 = at(s0, q), b1 = at(s1, q), a1 = at(s1, p);
    const sharpNext = mDot(n, sideN[k][(j + 1) % m]) < 0.94;
    faces.push({ rings: [[a0, b0, b1, a1]], n, edges: [
      { a: a0, b: b0, nb: down, own: false }, { a: b0, b: b1, nb: sideN[k][(j + 1) % m], own: sharpNext },
      { a: b1, b: a1, nb: up, own: false }, { a: a1, b: a0, nb: sideN[k][(j - 1 + m) % m], own: false } ] });
  }));
  return { faces, tone: opt.tone || "hi", convex: !!opt.convex, cut: opt.cut };
}
// A loose flat face (a band of a section face, a decal): points in 3D, normal, and for each edge the neighbour normal
// (null: an open edge that is always drawn as an outline; false: never drawn).
export const mFace = (points, n, nbs, extra = {}) => ({ rings: [points], n, edges: points.map((p, j) => ({ a: p, b: points[(j + 1) % points.length], nb: nbs[j], own: true })), ...extra });
// A concave half-cylinder groove (the back half of a bore drilled along F.a): seen from inside.
export function mGroove(F, s0, s1, r, steps = 14, from = 0, to = Math.PI) {
  const faces = [];
  const at = (s, b) => [F.o[0] + F.a[0] * s + r * (Math.cos(b) * F.u[0] + Math.sin(b) * F.v[0]), F.o[1] + F.a[1] * s + r * (Math.cos(b) * F.u[1] + Math.sin(b) * F.v[1]), F.o[2] + F.a[2] * s + r * (Math.cos(b) * F.u[2] + Math.sin(b) * F.v[2])];
  for (let i = 0; i < steps; i++) {
    const b0 = from + ((to - from) * i) / steps, b1 = from + ((to - from) * (i + 1)) / steps, bm = (b0 + b1) / 2;
    const n = mMul(mAdd(mMul(F.u, Math.cos(bm)), mMul(F.v, Math.sin(bm))), -1);
    faces.push({ rings: [[at(s0, b0), at(s1, b0), at(s1, b1), at(s0, b1)]], n, edges: [] });
  }
  return { faces, tone: "lo", convex: false };
}
// Pose: rotate about z by phi around (cx, cy), then translate.
export function mPose(mesh, phi = 0, t = [0, 0, 0], pre = [0, 0, 0]) {
  const c = Math.cos(phi), s = Math.sin(phi);
  const P3 = (q) => { const p = [q[0] + pre[0], q[1] + pre[1], q[2] + pre[2]]; return [p[0] * c - p[1] * s + t[0], p[0] * s + p[1] * c + t[1], p[2] + t[2]]; };
  const N3 = (n) => (n ? [n[0] * c - n[1] * s, n[0] * s + n[1] * c, n[2]] : n);
  return { ...mesh, faces: mesh.faces.map((f) => ({ ...f, rings: f.rings.map((r) => r.map(P3)), n: N3(f.n), edges: f.edges.map((e) => ({ ...e, a: P3(e.a), b: P3(e.b), nb: N3(e.nb) })), lines: f.lines && f.lines.map((l) => l.map(P3)) })) };
}
// Clip a polygon by the half-space dot(p, k) <= d.
export function mClip(poly, k, d) {
  const out = [];
  for (let i = 0; i < poly.length; i++) {
    const p = poly[i], q = poly[(i + 1) % poly.length];
    const fp = mDot(p, k) - d, fq = mDot(q, k) - d;
    if (fp <= 0) out.push(p);
    if ((fp < 0 && fq > 0) || (fp > 0 && fq < 0)) { const t = fp / (fp - fq); out.push(mAdd(p, mMul(mSub(q, p), t))); }
  }
  return out;
}
function mClipSeg(a, b, k, d) {
  const fa = mDot(a, k) - d, fb = mDot(b, k) - d;
  if (fa > 0 && fb > 0) return null;
  if (fa <= 0 && fb <= 0) return [a, b];
  const p = mAdd(a, mMul(mSub(b, a), fa / (fa - fb)));
  return fa <= 0 ? [a, p] : [p, b];
}
// Region: a list of half-spaces [k, d] (all must hold). Pieces of a face inside one region.
const mInRegion = (poly, region) => region.reduce((acc, [k, d]) => (acc.length > 2 ? mClip(acc, k, d) : acc), poly);
const mSegIn = (seg, region) => region.reduce((acc, [k, d]) => (acc ? mClipSeg(acc[0], acc[1], k, d) : acc), seg);

// Render a list of meshes into draw items { depth, svg }. opts.regions: list of regions to split into (each a list of
// half-spaces); the result is one item list per region. Without regions there is one.
export function mItems(mesh, P, opts = {}) {
  const V = mView(P), L = mLight(P);
  const regions = opts.regions || [[]];
  const out = regions.map(() => []);
  const vis = (n) => n && mDot(n, V) > 1e-6;
  for (const f of mesh.faces) {
    if (!vis(f.n)) continue;
    const band = f.fill || (f.flat ? "paper" : mBand(mDot(mUnit(f.n), L)));
    const segsOut = [], segsCrease = [];
    for (const e of f.edges) {
      if (e.nb === false) continue;
      if (!vis(e.nb)) segsOut.push([e.a, e.b]);
      else if (e.own && mDot(f.n, e.nb) < 0.94) segsCrease.push([e.a, e.b]);
    }
    regions.forEach((region, ri) => {
      const rings = f.rings.map((ring) => mInRegion(ring, region)).filter((r) => r.length > 2);
      if (!rings.length) return;
      const cut = (list) => list.map((s) => mSegIn(s, region)).filter(Boolean);
      const o = cut(segsOut), c = cut(segsCrease);
      const lines = f.lines ? f.lines.map((l) => mSegIn(l, region)).filter(Boolean) : [];
      let sx = 0, sn = 0;
      for (const p of rings[0]) { sx += mDot(p, V); sn++; }
      const d = rings.map((r) => pathOf(r.map((p) => iso(p, P)), true)).join("");
      const seg = (list) => list.map(([a, b]) => pathOf([iso(a, P), iso(b, P)])).join("");
      let svg = band === "cut" ? `<path class="lk-cut lk-f" d="${d}"/>` : band === "paper" ? `<path class="iso-fill" d="${d}"/>` : band === 4 ? `<path class="iso-top lk-f" d="${d}"${rings.length > 1 ? ' fill-rule="evenodd"' : ""}/>` : `<path class="iso-shade lk-f" data-shade="${band}" d="${d}"${rings.length > 1 ? ' fill-rule="evenodd"' : ""}/>`;
      if (lines.length) svg += `<path class="iso-line" data-tone="${f.lineTone || "faint"}" d="${seg(lines)}"/>`;
      if (c.length) svg += `<path class="iso-line iso-crease" data-tone="faint" d="${seg(c)}"/>`;
      if (o.length) svg += `<path class="iso-line iso-edge" data-tone="${f.tone || mesh.tone}" d="${seg(o)}"/>`;
      out[ri].push({ depth: (opts.bias || 0) + sx / sn, svg });
    });
  }
  return out;
}
export const mSvg = (items, sort = true) => (sort ? [...items].sort((a, b) => a.depth - b.depth) : items).map((i) => i.svg).join("");
// Scanline hatch of a polygon set (even-odd) in 2D: lines at angle `ang`, spacing `gap`; returns 2D segments.
export function mHatch(rings, ang, gap, phase = 0) {
  const c = Math.cos(ang), s = Math.sin(ang);
  const rot = ([x, y]) => [x * c + y * s, -x * s + y * c];
  const back = ([x, y]) => [x * c - y * s, x * s + y * c];
  const rr = rings.map((r) => r.map(rot));
  const ys = rr.flat().map((p) => p[1]);
  const lo = Math.min(...ys), hi = Math.max(...ys);
  const segs = [];
  for (let y = Math.ceil((lo - phase) / gap) * gap + phase; y < hi; y += gap) {
    const xs = [];
    for (const r of rr) for (let i = 0; i < r.length; i++) {
      const p = r[i], q = r[(i + 1) % r.length];
      if ((p[1] <= y) !== (q[1] <= y)) xs.push(p[0] + ((y - p[1]) / (q[1] - p[1])) * (q[0] - p[0]));
    }
    xs.sort((a, b) => a - b);
    for (let i = 0; i + 1 < xs.length; i += 2) if (xs[i + 1] - xs[i] > 0.05) segs.push([back([xs[i], y]), back([xs[i + 1], y])]);
  }
  return segs;
}
