#!/usr/bin/env node
// SYNTETISK testdata i samma format som bake-boras (ingen riktig karta!). Används för att testa spelet utan nät.
import fs from 'node:fs';
import { makeProj, makeGrid, addElement, setBoundary, finalize } from './raster.mjs';
const B = { S: 57.56, W: 12.64, N: 57.92, E: 13.32 }, proj = makeProj(B), grid = makeGrid(proj);
const g = (lat, lon) => ({ lat, lon });
const circle = (lat, lon, r, n = 24) => Array.from({ length: n + 1 }, (_, i) => g(lat + Math.sin(i / n * 6.283) * r, lon + Math.cos(i / n * 6.283) * r * 1.8));
setBoundary(grid, { type: 'way', geometry: circle(57.74, 12.98, .17, 40) });
addElement(grid, { type: 'way', tags: { natural: 'wood' }, geometry: circle(57.78, 12.85, .06) });
addElement(grid, { type: 'relation', tags: { landuse: 'forest' }, members: [{ type: 'way', role: 'outer', geometry: circle(57.70, 13.1, .07).slice(0, 13) }, { type: 'way', role: 'outer', geometry: circle(57.70, 13.1, .07).slice(12) }] });
addElement(grid, { type: 'way', tags: { natural: 'water' }, geometry: circle(57.69, 12.85, .03) });
addElement(grid, { type: 'way', tags: { landuse: 'residential' }, geometry: circle(57.721, 12.94, .02) });
addElement(grid, { type: 'way', tags: { waterway: 'river' }, geometry: [g(57.85, 12.7), g(57.76, 12.9), g(57.72, 12.94), g(57.65, 13.1)] });
addElement(grid, { type: 'way', tags: { highway: 'primary' }, geometry: [g(57.60, 12.80), g(57.721, 12.94), g(57.88, 13.15)] });
addElement(grid, { type: 'way', tags: { railway: 'rail' }, geometry: [g(57.62, 13.1), g(57.721, 12.94), g(57.80, 12.7)] });
// lokalgator (rutnät) och byggnader runt centrum + i två byar
let bid = 1;
const lat0 = (B.S + B.N) / 2, mLon = 111320 * Math.cos(lat0 * Math.PI / 180);
const cellToLL = (x, y) => ({ lat: B.N - y * 50 / 110574, lon: B.W + x * 50 / mLon });
function town(cx, cy, r, n) {
  for (let i = -r; i <= r; i += 4) {                       // gator
    addElement(grid, { type: 'way', id: bid++, tags: { highway: i % 12 === 0 ? 'tertiary' : 'residential' }, geometry: [cellToLL(cx + i, cy - r), cellToLL(cx + i, cy + r)] });
    addElement(grid, { type: 'way', id: bid++, tags: { highway: i % 12 === 0 ? 'tertiary' : 'residential' }, geometry: [cellToLL(cx - r, cy + i), cellToLL(cx + r, cy + i)] });
  }
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  for (let k = 0; k < n; k++) {
    const x = cx + (rnd() * 2 - 1) * r, y = cy + (rnd() * 2 - 1) * r;
    if (Math.hypot(x - cx, y - cy) > r) continue;
    const kind = rnd() < 0.15 ? 'apartments' : rnd() < 0.08 ? 'industrial' : 'house';
    const w = (kind === 'house' ? 0.25 : 0.5) + rnd() * 0.3, h = (kind === 'house' ? 0.25 : 0.5) + rnd() * 0.3;
    const a = cellToLL(x, y), b = cellToLL(x + w, y + h);
    addElement(grid, { type: 'way', id: bid++, tags: { building: kind, 'building:levels': kind === 'apartments' ? String(3 + Math.floor(rnd() * 5)) : '2' }, bounds: { minlat: b.lat, maxlat: a.lat, minlon: a.lon, maxlon: b.lon } });
  }
}
const cc = { x: proj.px(12.94), y: proj.py(57.721) };
town(cc.x, cc.y, 40, 2600);
town(proj.px(13.10), proj.py(57.70), 16, 400);
town(proj.px(12.99), proj.py(57.83), 14, 300);

const step = 10, ew = Math.ceil(proj.w / step) + 1, eh = Math.ceil(proj.h / step) + 1, data = [];
for (let y = 0; y < eh; y++) for (let x = 0; x < ew; x++) data.push(Math.round(180 + 80 * Math.sin(x / 5) * Math.cos(y / 6) + 40 * Math.sin(x / 2.3 + y / 3)));
const places = [['Borås', 'city', 57.721, 12.94], ['Dalsjöfors', 'town', 57.70, 13.10], ['Fristad', 'town', 57.83, 12.99], ['Sandared', 'village', 57.72, 12.80], ['Viskafors', 'village', 57.62, 12.83], ['Brämhult', 'suburb', 57.76, 12.99], ['Rydal', 'village', 57.69, 12.87]].map(([n, t, lat, lon]) => ({ n, t, lat, lon }));
const pois = [['Testdjurpark', 'zoo', 57.71, 12.97], ['Testmuseum', 'museum', 57.725, 12.945], ['Testutsikten', 'viewpoint', 57.75, 12.92]].map(([n, k, lat, lon]) => ({ n, k, lat, lon }));
const { data: out, stats } = finalize(grid, { bbox: B, elev: { step, ew, eh, data }, places, pois });
const dest = process.argv[2] || 'mock-data.json';
fs.writeFileSync(dest, JSON.stringify(out)); console.log(dest, stats);
