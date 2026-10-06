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
const step = 10, ew = Math.ceil(proj.w / step) + 1, eh = Math.ceil(proj.h / step) + 1, data = [];
for (let y = 0; y < eh; y++) for (let x = 0; x < ew; x++) data.push(Math.round(180 + 80 * Math.sin(x / 5) * Math.cos(y / 6) + 40 * Math.sin(x / 2.3 + y / 3)));
const places = [['Borås', 'city', 57.721, 12.94], ['Dalsjöfors', 'town', 57.70, 13.10], ['Fristad', 'town', 57.83, 12.99], ['Sandared', 'village', 57.72, 12.80], ['Viskafors', 'village', 57.62, 12.83], ['Brämhult', 'suburb', 57.76, 12.99], ['Rydal', 'village', 57.69, 12.87]].map(([n, t, lat, lon]) => ({ n, t, lat, lon }));
const pois = [['Testdjurpark', 'zoo', 57.71, 12.97], ['Testmuseum', 'museum', 57.725, 12.945], ['Testutsikten', 'viewpoint', 57.75, 12.92]].map(([n, k, lat, lon]) => ({ n, k, lat, lon }));
const { data: out, stats } = finalize(grid, { bbox: B, elev: { step, ew, eh, data }, places, pois });
const dest = process.argv[2] || 'mock-data.json';
fs.writeFileSync(dest, JSON.stringify(out)); console.log(dest, stats);
