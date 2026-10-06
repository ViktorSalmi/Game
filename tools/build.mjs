#!/usr/bin/env node
// Bäddar in data/boras-data.json i index.html -> dist/boras.html (en enda fil som går att dela/publicera)
import fs from 'node:fs';
const src = process.argv[2] || 'data/boras-data.json', outp = process.argv[3] || 'dist/boras.html';
const html = fs.readFileSync('index.html', 'utf8'), json = fs.readFileSync(src, 'utf8').replace(/</g, '\\u003c');
const tag = '<script id="boras-data" type="application/json"></script>';
if (!html.includes(tag)) throw new Error('hittar inte data-taggen i index.html');
fs.mkdirSync('dist', { recursive: true });
fs.writeFileSync(outp, html.replace(tag, `<script id="boras-data" type="application/json">${json}</script>`));
console.log('Skrev', outp, (fs.statSync(outp).size / 1e6).toFixed(2), 'MB');
