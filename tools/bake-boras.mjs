#!/usr/bin/env node
// Hämtar OpenStreetMap-data för Borås kommun och bakar den till data/boras-data.json
// Kör:  node tools/bake-boras.mjs      (Node 18+, kräver internet till overpass + open-meteo)
// Data © OpenStreetMap-bidragsgivare (ODbL), höjd via Open-Meteo.
import fs from 'node:fs';
import { makeProj, makeGrid, addElement, setBoundary, finalize, CELL } from './raster.mjs';

const BBOX = { S: 57.56, W: 12.64, N: 57.92, E: 13.32 };
const MIRRORS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
const sleep = ms => new Promise(r => setTimeout(r, ms));

import crypto from 'node:crypto';
fs.mkdirSync('data/cache', { recursive: true });
// Varje svar cachas på disk, så ett avbrutet/begränsat körning kan återupptas utan att börja om.
let missing = 0;
async function overpass(q, tries = 8) {
  const cf = 'data/cache/' + crypto.createHash('sha1').update(q).digest('hex') + '.json';
  if (fs.existsSync(cf)) { try { return JSON.parse(fs.readFileSync(cf, 'utf8')); } catch { /* halvskriven fil */ } }
  if (CACHE_ONLY) { missing++; return []; }
  for (let a = 0; a < tries; a++) {
    for (const url of MIRRORS) {
      try {
        const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'user-agent': 'evigheten-game/1.0' }, body: 'data=' + encodeURIComponent(q) });
        if (r.ok) { const els = (await r.json()).elements || []; fs.writeFileSync(cf, JSON.stringify(els)); return els; }
        const wait = r.status === 429 || r.status === 504 ? 30000 * (a + 1) : 5000 * (a + 1);
        console.warn(`  ${r.status} från ${url} – väntar ${wait / 1000}s (försök ${a + 1}/${tries})`);
        await sleep(wait);
      } catch (e) { console.warn('  nätverksfel', e.message); await sleep(5000 * (a + 1)); }
    }
  }
  throw new Error('Overpass svarade inte – kör skriptet igen lite senare, det fortsätter där det slutade.');
}

const CACHE_ONLY = process.argv.includes('--delvis'); // bygg av det som redan finns i cachen, inga nya Overpass-anrop
const QUICK = process.argv.includes('--snabb'); // hoppar över skogslagret; omärkt mark blir skog (typiskt för Sverige)
const proj = makeProj(BBOX), grid = makeGrid(proj, QUICK ? 4 : 3);
if (QUICK) console.log('SNABBLÄGE: skogslagret hoppas över, omärkt mark räknas som skog');
console.log(`Rutnät ${proj.w}×${proj.h} (${CELL} m per ruta)`);

// kommungräns
try {
  const els = await overpass(`[out:json][timeout:120];rel["boundary"="administrative"]["admin_level"="7"]["name"="Borås kommun"];out geom;`);
  for (const e of els) setBoundary(grid, e);
  console.log('Kommungräns:', els.length ? 'ok' : 'hittades inte (hela rutan används)');
} catch (e) { console.warn('Ingen kommungräns:', e.message); }

// polygoner och linjer: små rutor och ett kartlager per fråga, så varje fråga blir lätt för servern
const NX = 5, NY = 5;
const THEMES = [
  ['vatten/myr/berg', bb => `way["natural"~"^(water|wetland|bare_rock|scree)$"]${bb};relation["natural"~"^(water|wetland)$"]${bb};way["waterway"="riverbank"]${bb};relation["waterway"="riverbank"]${bb};way["landuse"="reservoir"]${bb};`],
  ['skog', bb => `way["natural"="wood"]${bb};way["landuse"="forest"]${bb};relation["natural"="wood"]${bb};relation["landuse"="forest"]${bb};`],
  ['bebyggelse/åker', bb => `way["landuse"~"^(residential|industrial|commercial|retail|construction|farmland|meadow|orchard|farmyard|grass|cemetery|allotments|recreation_ground)$"]${bb};relation["landuse"~"^(residential|industrial|commercial|retail|farmland|meadow)$"]${bb};way["leisure"~"^(park|pitch|golf_course|garden)$"]${bb};`],
  ['vägar/å/järnväg', bb => `way["waterway"~"^(river|canal)$"]${bb};way["highway"~"^(motorway|trunk|primary|secondary|tertiary|motorway_link|trunk_link)$"]${bb};way["railway"="rail"]${bb};`],
];
const ACTIVE = THEMES.filter(t => !(QUICK && t[0] === 'skog'));
let done = 0;
for (let i = 0; i < NX; i++) for (let j = 0; j < NY; j++) {
  const s = BBOX.S + (BBOX.N - BBOX.S) * j / NY, n = BBOX.S + (BBOX.N - BBOX.S) * (j + 1) / NY;
  const w = BBOX.W + (BBOX.E - BBOX.W) * i / NX, e = BBOX.W + (BBOX.E - BBOX.W) * (i + 1) / NX;
  const bb = `(${s.toFixed(4)},${w.toFixed(4)},${n.toFixed(4)},${e.toFixed(4)})`;
  for (const [name, body] of ACTIVE) {
    done++;
    const fromCache = false;
    console.log(`[${done}/${NX * NY * ACTIVE.length}] ruta ${i * NY + j + 1}/${NX * NY} – ${name}`);
    const els = await overpass(`[out:json][timeout:180][maxsize:536870912];(${body(bb)});out geom;`);
    for (const el of els) addElement(grid, el);
    await sleep(800);
  }
}

// namn och sevärdheter
const bbs = `(${BBOX.S},${BBOX.W},${BBOX.N},${BBOX.E})`;
const placeEls = await overpass(`[out:json][timeout:90];node["place"~"^(city|town|village|suburb|hamlet|neighbourhood)$"]["name"]${bbs};out;`);
const places = placeEls.map(e => ({ n: e.tags.name, t: e.tags.place, lat: e.lat, lon: e.lon }));
const poiEls = await overpass(`[out:json][timeout:90];(nwr["tourism"~"^(zoo|museum|attraction|viewpoint|theme_park)$"]["name"]${bbs};nwr["historic"~"^(castle|ruins|monument|memorial|manor|archaeological_site)$"]["name"]${bbs};);out center 200;`);
const pois = poiEls.map(e => ({ n: e.tags.name, k: e.tags.tourism || e.tags.historic, lat: e.lat ?? e.center?.lat, lon: e.lon ?? e.center?.lon })).filter(p => p.lat);
console.log(`${places.length} platser, ${pois.length} sevärdheter`);

// höjd var 500:e meter (10 rutor), interpoleras i spelet
const step = 10, ew = Math.ceil(proj.w / step) + 1, eh = Math.ceil(proj.h / step) + 1, data = new Array(ew * eh).fill(0);
const coords = [];
for (let y = 0; y < eh; y++) for (let x = 0; x < ew; x++) {
  coords.push([BBOX.N - (y * step * CELL) / 110574, BBOX.W + (x * step * CELL) / (111320 * Math.cos((BBOX.S + BBOX.N) / 2 * Math.PI / 180))]);
}
// Höjd: Open-Meteo först, OpenTopoData som reserv. Cachas så att det bara behöver lyckas en gång.
const efile = 'data/cache/elev.json';
async function getJson(url, what) {
  for (let a = 0; a < 6; a++) {
    try {
      const r = await fetch(url, { headers: { 'user-agent': 'evigheten-game/1.0' } });
      const txt = await r.text();
      let j = null; try { j = JSON.parse(txt); } catch { /* inte JSON */ }
      if (r.ok && j && !j.error) return j;
      console.warn(`  ${what}: ${r.status} ${(j && j.reason) || txt.slice(0, 120)} (försök ${a + 1}/6)`);
    } catch (e) { console.warn(`  ${what}: ${e.message}`); }
    await sleep(4000 * (a + 1));
  }
  return null;
}
async function fetchElevation(part) {
  const m = await getJson(`https://api.open-meteo.com/v1/elevation?latitude=${part.map(c => c[0].toFixed(4)).join(',')}&longitude=${part.map(c => c[1].toFixed(4)).join(',')}`, 'open-meteo');
  if (m && Array.isArray(m.elevation)) return m.elevation;
  const o = await getJson(`https://api.opentopodata.org/v1/eudem25m?locations=${part.map(c => c[0].toFixed(4) + ',' + c[1].toFixed(4)).join('|')}`, 'opentopodata');
  if (o && Array.isArray(o.results)) return o.results.map(r => r.elevation ?? 200);
  return null;
}
let gotElev = false;
if (fs.existsSync(efile)) { try { const c = JSON.parse(fs.readFileSync(efile, 'utf8')); if (c.length === data.length) { c.forEach((v, i) => { data[i] = v; }); gotElev = true; console.log('Höjddata från cache'); } } catch { /* ignore */ } }
if (!gotElev && !CACHE_ONLY || !gotElev && CACHE_ONLY) {
  let ok = true;
  for (let i = 0; i < coords.length && ok; i += 50) {
    const el = await fetchElevation(coords.slice(i, i + 50));
    if (!el) { ok = false; break; }
    el.forEach((v, k) => { data[i + k] = Math.round(v); });
    await sleep(1100);
  }
  if (ok) { fs.writeFileSync(efile, JSON.stringify(data)); console.log('Höjddata klar'); }
  else { console.warn('Höjddata misslyckades – platt terräng (kartan fungerar ändå).'); data.fill(200); }
}

if (!places.some(p => p.n === 'Borås')) places.push({ n: 'Borås', t: 'city', lat: 57.721, lon: 12.940 });
if (CACHE_ONLY) console.log(`DELVIS: ${missing} bitar saknas i cachen och är tomma (utan skog/bebyggelse där).`);
const { data: out, stats } = finalize(grid, { bbox: BBOX, elev: { step, ew, eh, data }, places, pois });
fs.mkdirSync('data', { recursive: true });
fs.writeFileSync('data/boras-data.json', JSON.stringify(out));
console.log('Biomer (ruteantal):', stats);
console.log('Skrev data/boras-data.json', (fs.statSync('data/boras-data.json').size / 1e6).toFixed(2), 'MB');
