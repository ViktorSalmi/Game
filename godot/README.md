# Stadsbyggaren (Godot 4)

Isometrisk (2:1) stadsbyggare/civilisationsspel. Du börjar i en grotta med fem personer och utvecklar en stam till städer.
Byggd och testad med Godot 4.4.1; öppnas i senare 4.x (Godot kan fråga om uppgradering – tryck OK).

## Starta
1. Öppna Godot → **Import** → välj `godot/project.godot` → **Import & Edit**.
2. Tryck **F5**. En egen värld genereras (seed 1621).

Andra världar (Debug → *Customize Run Instances* → *Main Run Args*, eller kommandoraden efter `--`):
- `--seed=42` annan slumpvärld (obs: `--prewarm` blir långsamt när befolkningen är stor; 120 år ≈ 3–4 min) · `--size=512` större karta
- `--boras` läser Borås-kartan från `../data/boras-data.json` (se tools/bake-boras.mjs) · `--data=sökväg`
- `--speed=8` starthastighet · `--prewarm=60` förkör 60 år innan spelet visas (för tester)

## Kontroller
- **WASD/pilar**: panorera (Shift = snabbare) · **mushjul**: zoom · **mitten-dra**: panorera
- **Vänsterklick**: välj person/byggnad · **högerklick**: skicka spejaren (röd figur)
- **Mellanslag**: paus · **1–7**: hastighet 1×–64× · knappen **Spola 10 år** · **M**: hela kartan · **F**: dimma · **B**: stadsgränser · **L**: info · **Esc**: avsluta

## Spelet idag
- Procedurell värld (hav, strand, skog, fält, myr, berg, sjöar, floder) med grotta nära vatten och skog
- Människor med behov (mat, energi), jobb (fälla träd, bryta sten, samla bär, odla, bygga), födelse, åldrande, död
- Automatisk stadsbyggnad: hus, åkrar, läger; kolonisering till nya städer
- Sju tidsåldrar (Mörka → Feudala → Slottsåldern → Imperieåldern → Industriella → Moderna → Informationsåldern), knutna till tidigaste år
  (1650, 1730, 1810, 1880, 1940, 2010) samt teknik, invånare och guld. Husen byter utseende (tält/koja → långhus → timmerhus → stenhus → villor → flerbostadshus/höghus).
- Städerna planerar själva: bostäder, åkrar, skolor (teknik), marknader, kyrkor, fabriker (guld) och läger; centrum byts (lägereld → långhall → borg → stadshus)
- Vägar uppgraderas från stigar till vägar när tekniken tillåter
- Fog of war, minikarta, resursrad, logg
- Stadsområden med färgade gränser (B), stadslista, stadsnivåer (läger → metropol), vägar/stigar mellan byggnader

## Utseende (kodritat, inga färdiga bilder)
- Marken är en enda shader: organiska kanter mellan skog/fält/vatten/bebyggelse, strand, hillshade, brus och rörligt vatten
- Granar, tallar, björkar och ekar med skuggor; bärbuskar och stenar
- Hus från OpenStreetMap (om `bld` finns i datan): sadeltak, skorstenar, fönster; flerbostadshus, industri
- Vägklasser (stor väg, huvudgata, lokalgata, järnväg)
- Obs: riktiga hus/lokalgator/skog kräver en ny körning av `node tools/bake-boras.mjs` (utan `--snabb`)

## Tekniskt (tidigare etapp)
- Terräng som GPU-meshar per kartbit (32×32 rutor), byggda efter behov runt kameran
- Vägar och järnväg, ortsnamn och sevärdheter (skärmrymd, konstant textstorlek)
- Fog of war (mjuk, 4×4 rutor/pixel), diamantformad minikarta, AoE-inspirerat HUD (resurser är platshållare)
- A*-vägsökning över hela rutnätet

Allt grafiskt är platta platshållare – inget riktigt konstverk än.

## Teststyrning (valfritt)
`godot --path godot -- --shot=bild.png --frames=120 --fit --nofog` sparar en skärmbild.
`godot --headless --path godot -- --goto=500,300 --report --frames=600` kör utan grafik och skriver en rapport.

## Sprites (förrenderade 3D → PNG-atlas)
`tools/sprite_lab.gd` bygger 3D-modeller med kod (grotta, tält, kojor, långhus, timmerhus, stenhus, flerbostadshus, kyrka, skola, fabriker, åkrar, läger,
träd, buskar, stenar, människor i 8 riktningar med gångcykel), belyser dem och renderar isometriska PNG-sprites.
`tools/pack_atlas.py` packar dem till `assets/sprites/atlas.png` + `atlas.json` som spelet läser.

    for set in eras buildings trees people; do
      xvfb-run -a godot --path godot --rendering-driver opengl3 -s tools/sprite_lab.gd -- --out=ut --set=$set
    done
    python3 godot/tools/pack_atlas.py ut godot/assets/sprites

Du kan byta ut sprites mot egen grafik: behåll namn/ankarpunkt i `atlas.json`.

## Tester utan grafik
`godot --headless --path godot -s tests/sim_test.gd -- --seconds=9000` kör simuleringen och skriver ut utvecklingen.
