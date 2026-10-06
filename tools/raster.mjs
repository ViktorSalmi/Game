// Gemensam logik: gör om OpenStreetMap-element till spelets rutnät (50 m per ruta).
// Används av bake-boras.mjs (riktig data) och mock-data.mjs (syntetisk testdata).
export const CELL = 50;

export function makeProj(b, cell = CELL) {
  const lat0 = (b.S + b.N) / 2, mLat = 110574, mLon = 111320 * Math.cos(lat0 * Math.PI / 180);
  return {
    w: Math.ceil((b.E - b.W) * mLon / cell), h: Math.ceil((b.N - b.S) * mLat / cell), cell,
    px: lon => (lon - b.W) * mLon / cell, py: lat => (b.N - lat) * mLat / cell,
  };
}
export function makeGrid(proj, fill = 3) {
  const n = proj.w * proj.h;
  return { proj, bio: new Uint8Array(n).fill(fill), prio: new Uint8Array(n), riv: new Uint8Array(n), road: new Uint8Array(n), inside: null, bld: [], bldIds: new Set() };
}

// biomer i spelet: 0 sjö, 1 vad/å, 3 gräs/åker, 4 skog, 6 berg, 8 myr, 9 bebyggelse, 10 utanför kommunen
export function classify(t) {
  if (t.natural === 'water' || t.waterway === 'riverbank' || t.landuse === 'reservoir') return { biome: 0, prio: 9 };
  if (t.landuse && /^(residential|industrial|commercial|retail|construction)$/.test(t.landuse)) return { biome: 9, prio: 7 };
  if (t.natural === 'bare_rock' || t.natural === 'scree') return { biome: 6, prio: 6 };
  if (t.natural === 'wetland') return { biome: 8, prio: 5 };
  if (t.landuse && /^(farmland|meadow|orchard|farmyard|grass|cemetery|allotments|recreation_ground)$/.test(t.landuse)) return { biome: 3, prio: 4 };
  if (t.leisure && /^(park|pitch|golf_course|garden)$/.test(t.leisure)) return { biome: 3, prio: 4 };
  if (t.natural === 'wood' || t.landuse === 'forest') return { biome: 4, prio: 3 };
  return null;
}

const eq = (a, b) => a[0] === b[0] && a[1] === b[1];
export function assembleRings(segs) {
  const rings = [], pool = segs.map(s => s.slice());
  while (pool.length) {
    let cur = pool.pop();
    for (;;) {
      const first = cur[0], last = cur[cur.length - 1];
      if (cur.length > 3 && eq(first, last)) break;
      let found = -1, rev = false;
      for (let i = 0; i < pool.length; i++) {
        const s = pool[i];
        if (eq(s[0], last)) { found = i; rev = false; break; }
        if (eq(s[s.length - 1], last)) { found = i; rev = true; break; }
      }
      if (found < 0) break;
      const s = pool.splice(found, 1)[0]; if (rev) s.reverse();
      cur = cur.concat(s.slice(1));
    }
    rings.push(cur);
  }
  return rings;
}
const pts = g => g.map(p => [p.lon, p.lat]);
function ringsOf(el, proj) {
  let rings = [];
  if (el.type === 'way' && el.geometry) rings = [pts(el.geometry)];
  else if (el.type === 'relation' && el.members) {
    const outer = [], inner = [];
    for (const m of el.members) if (m.type === 'way' && m.geometry) (m.role === 'inner' ? inner : outer).push(pts(m.geometry));
    rings = assembleRings(outer).concat(assembleRings(inner));
  }
  return rings.filter(r => r.length >= 3).map(r => r.map(p => [proj.px(p[0]), proj.py(p[1])]));
}

export function fillRings(rings, w, h, paint) {
  let minY = Infinity, maxY = -Infinity;
  for (const r of rings) for (const p of r) { if (p[1] < minY) minY = p[1]; if (p[1] > maxY) maxY = p[1]; }
  for (let y = Math.max(0, Math.floor(minY)); y <= Math.min(h - 1, Math.ceil(maxY)); y++) {
    const yc = y + .5, xs = [];
    for (const r of rings) for (let i = 0, j = r.length - 1; i < r.length; j = i++) {
      const a = r[j], b = r[i];
      if ((a[1] <= yc && b[1] > yc) || (b[1] <= yc && a[1] > yc)) xs.push(a[0] + (yc - a[1]) / (b[1] - a[1]) * (b[0] - a[0]));
    }
    xs.sort((p, q) => p - q);
    for (let k = 0; k + 1 < xs.length; k += 2) {
      const x0 = Math.max(0, Math.ceil(xs[k] - .5)), x1 = Math.min(w - 1, Math.floor(xs[k + 1] - .5));
      for (let x = x0; x <= x1; x++) paint(x, y);
    }
  }
}
export function drawLine(line, w, h, paint) {
  for (let s = 0; s + 1 < line.length; s++) {
    let x0 = Math.round(line[s][0]), y0 = Math.round(line[s][1]);
    const x1 = Math.round(line[s + 1][0]), y1 = Math.round(line[s + 1][1]);
    const dx = Math.abs(x1 - x0), dy = -Math.abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    let err = dx + dy;
    for (let n = 0; n < 5000; n++) {
      if (x0 >= 0 && y0 >= 0 && x0 < w && y0 < h) paint(x0, y0);
      if (x0 === x1 && y0 === y1) break;
      const e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
    }
  }
}

// Vägklass i rutnätet: 3 stor väg, 1 huvudgata, 4 lokalgata, 2 järnväg. Högre rang skriver över lägre.
const HWY = { motorway: 3, motorway_link: 3, trunk: 3, trunk_link: 3, primary: 3, primary_link: 3, secondary: 1, secondary_link: 1, tertiary: 1, tertiary_link: 1, residential: 4, unclassified: 4, living_street: 4 };
const RROAD = { 0: 0, 4: 1, 1: 2, 3: 3, 2: 4 };
// Byggnadstyp: 0 bostad/småhus, 1 flerbostadshus/kommersiellt, 2 industri/lager, 3 offentligt/kyrka
function buildingKind(b) {
  if (/^(apartments|commercial|retail|office|hotel|dormitory|terrace)$/.test(b)) return 1;
  if (/^(industrial|warehouse|factory|manufacture|storage_tank|hangar)$/.test(b)) return 2;
  if (/^(church|chapel|cathedral|school|university|hospital|civic|public|government|train_station|stadium|museum|theatre|library|kindergarten)$/.test(b)) return 3;
  return 0;
}
export function addBuilding(grid, el) {
  const t = el.tags || {}, bb = el.bounds;
  if (!t.building || !bb || grid.bldIds.has(el.type + el.id)) return;
  if (/^(shed|garage|garages|carport|roof|hut|cabin|greenhouse|service|kiosk|ruins|construction|container|barn|farm_auxiliary|silo)$/.test(t.building)) return;
  grid.bldIds.add(el.type + el.id);
  const { proj } = grid, x0 = proj.px(bb.minlon), x1 = proj.px(bb.maxlon), y0 = proj.py(bb.maxlat), y1 = proj.py(bb.minlat);
  const w = x1 - x0, h = y1 - y0;                       // i rutor (1 ruta = 50 m)
  if (w * h * 2500 < 40) return;                         // < 40 m^2 hoppas över
  if (x1 < 0 || y1 < 0 || x0 > proj.w || y0 > proj.h) return;
  const levels = Math.max(1, Math.min(15, parseInt(t['building:levels']) || (buildingKind(t.building) === 1 ? 4 : buildingKind(t.building) === 2 ? 1 : 2)));
  // kvartsrutor (12,5 m) som heltal: x, y, bredd, höjd, meta = typ*16 + våningar
  grid.bld.push(Math.round(x0 * 4), Math.round(y0 * 4), Math.max(1, Math.round(w * 4)), Math.max(1, Math.round(h * 4)), buildingKind(t.building) * 16 + levels);
}

export function addElement(grid, el) {
  const { proj } = grid, { w, h } = proj, t = el.tags || {};
  if (t.building) { addBuilding(grid, el); return; }
  if (el.type === 'way' && el.geometry) {
    const line = () => el.geometry.map(p => [proj.px(p.lon), proj.py(p.lat)]);
    if (t.waterway === 'river' || t.waterway === 'canal') { drawLine(line(), w, h, (x, y) => { grid.riv[y * w + x] = 1; }); return; }
    if (t.highway) { const c = HWY[t.highway]; if (!c) return; drawLine(line(), w, h, (x, y) => { const i = y * w + x; if (RROAD[c] >= RROAD[grid.road[i]]) grid.road[i] = c; }); return; }
    if (t.railway === 'rail') { drawLine(line(), w, h, (x, y) => { grid.road[y * w + x] = 2; }); return; }
  }
  const c = classify(t); if (!c) return;
  fillRings(ringsOf(el, proj), w, h, (x, y) => { const i = y * w + x; if (c.prio >= grid.prio[i]) { grid.prio[i] = c.prio; grid.bio[i] = c.biome; } });
}
export function setBoundary(grid, el) {
  const { proj } = grid, { w, h } = proj;
  if (!grid.inside) grid.inside = new Uint8Array(w * h);
  fillRings(ringsOf(el, proj), w, h, (x, y) => { grid.inside[y * w + x] = 1; });
}

export function rle(a) {
  const out = []; let v = a[0], c = 0;
  for (let i = 0; i < a.length; i++) { if (a[i] === v && c < 1e9) c++; else { out.push(v, c); v = a[i]; c = 1; } }
  out.push(v, c); return out;
}

const RANK = { city: 0, town: 1, suburb: 2, village: 3, neighbourhood: 4, hamlet: 5 };
export function finalize(grid, { bbox, elev, places, pois }) {
  const { proj } = grid, { w, h } = proj, n = w * h, bio = new Uint8Array(n), road = new Uint8Array(n);
  let ok = 0;
  for (let i = 0; i < n; i++) {
    if (grid.inside && !grid.inside[i]) { bio[i] = 10; continue; }
    let b = grid.bio[i];
    if (grid.riv[i] && b !== 0) b = 1;
    if (grid.road[i]) { road[i] = grid.road[i]; if (b === 0) b = 1; }
    bio[i] = b; ok++;
  }
  const pl = places.map(p => ({ n: p.n, t: p.t, x: Math.round(proj.px(p.lon)), y: Math.round(proj.py(p.lat)) }))
    .filter(p => p.x >= 0 && p.y >= 0 && p.x < w && p.y < h && (!grid.inside || grid.inside[p.y * w + p.x]))
    .sort((a, b) => (RANK[a.t] ?? 9) - (RANK[b.t] ?? 9)).slice(0, 260);
  const po = pois.map(p => ({ n: p.n, k: p.k, x: Math.round(proj.px(p.lon)), y: Math.round(proj.py(p.lat)) }))
    .filter(p => p.x >= 0 && p.y >= 0 && p.x < w && p.y < h && bio[p.y * w + p.x] < 10).slice(0, 150);
  let lo = Infinity, hi = -Infinity; for (const v of elev.data) { if (v < lo) lo = v; if (v > hi) hi = v; }
  const stats = {}; for (let i = 0; i < n; i++) stats[bio[i]] = (stats[bio[i]] || 0) + 1;
  return {
    data: { v: 1, name: 'Borås kommun', bbox: [bbox.S, bbox.W, bbox.N, bbox.E], cell: proj.cell, w, h, biome: rle(bio), road: rle(road),
      estep: elev.step, ew: elev.ew, eh: elev.eh, elev: elev.data, lo, hi, places: pl, pois: po, bld: grid.bld },
    stats,
  };
}
