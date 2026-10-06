# Evigheten

Ett oändligt, självspelande världsspel i en enda fil. Öppna `index.html` i webbläsaren (valfritt `?seed=123` för en bestämd värld).

- Procedurellt genererad oändlig värld (biomer, skogar, berg, hav, ruiner, helgedomar, mutagen-pölar)
- En hjälte som spelar själv: samlar resurser, jagar, vilar, grundar stad, förhandlar fred, åldras och efterträds av en arvinge
- Städer som växer, bygger, kolonisera och går i krig; riken går från stenålder till framtid
- Djur med gener som muteras och utvecklas över generationer (natur­ligt urval), slumpmässiga händelser (storm, torka, pest, meteor, jordbävning…)
- Kontroller: WASD/pilar tar över hjälten · dubbelklick ger order · dra för att panorera · hjul för zoom · F följ hjälten · mellanslag paus · 1–5 hastighet

## Borås-läge (trogen karta)

Spelet kan använda riktig OpenStreetMap-data för Borås kommun (sjöar, å, skog, bebyggelse, vägar, järnväg, ortsnamn, sevärdheter, höjd).
Utan datafil körs den oändliga procedurella världen.

```bash
node tools/bake-boras.mjs   # hämtar och bakar data/boras-data.json (Node 18+, behöver internet)
node tools/build.mjs        # bäddar in datan -> dist/boras.html (en enda fil att dela)
```

- Spelet laddar `data/boras-data.json` (eller `?data=sökväg`); `?procedural=1` tvingar oändlig värld.
- `tools/mock-data.mjs` skapar SYNTETISK testdata (inte en riktig karta) för utveckling utan nät.
- Data © OpenStreetMap-bidragsgivare (ODbL). Höjddata via Open-Meteo.
