# Age of Borås – Godot 4 (etapp 1)

Isometrisk (2:1) Borås-karta i Godot 4. Byggd och testad med Godot 4.4.1; öppnas i senare 4.x (Godot kan fråga om uppgradering – tryck OK).

## Starta
1. Öppna Godot → **Import** → välj `godot/project.godot` → **Import & Edit**.
2. Tryck **F5**.

Kartan läses från `../data/boras-data.json` (skapas av `node tools/bake-boras.mjs` i repots rot). Finns ingen fil visas en liten DEMO-karta.
Egen sökväg: kör med användararg `--data=C:\sökväg\boras-data.json`.

## Kontroller
- **WASD/pilar**: panorera (Shift = snabbare) · **mushjul**: zoom · **mitten-dra**: panorera
- **Högerklick**: skicka spejaren (platt platshållarfigur) – den avslöjar fog of war
- **M**: hela kartan · **F**: dimma av/på · **L**: förklaring · **Home**: till spejaren · **Esc**: avsluta
- Klicka/dra i minikartan för att hoppa

## Innehåll etapp 1
- Terräng som GPU-meshar per kartbit (32×32 rutor), byggda efter behov runt kameran
- Vägar och järnväg, ortsnamn och sevärdheter (skärmrymd, konstant textstorlek)
- Fog of war (mjuk, 4×4 rutor/pixel), diamantformad minikarta, AoE-inspirerat HUD (resurser är platshållare)
- A*-vägsökning över hela rutnätet

Allt grafiskt är platta platshållare – inget riktigt konstverk än.

## Teststyrning (valfritt)
`godot --path godot -- --shot=bild.png --frames=120 --fit --nofog` sparar en skärmbild.
`godot --headless --path godot -- --goto=500,300 --report --frames=600` kör utan grafik och skriver en rapport.
