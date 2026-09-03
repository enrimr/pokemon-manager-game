# Pokémon sprites (gen 1+2, national dex 1..251)

Classic 96x96 front sprites, downloaded from the PokeAPI sprites mirror:

    https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/<id>.png

Re-download (from the repo root):

    for i in $(seq 1 251); do curl -sf --retry 3 -o assets/pokemon/$i.png \
      "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/$i.png"; done

Rendered via `PokeArt` (shared/ui/poke_art.gd) with NEAREST filtering.

NOTE: the artwork is Nintendo/Game Freak/Creatures IP, used here for a
personal, non-commercial fan project. Do not distribute this game
commercially with these assets.

## Battle sprites (front/ + back/)

Gen-V Black/White 96x96 pairs — the most modern pixel set with BACK sprites
for all 251 — used by the battle views (foe = front, ours = back):

    .../sprites/pokemon/versions/generation-v/black-white/<id>.png
    .../sprites/pokemon/versions/generation-v/black-white/back/<id>.png
