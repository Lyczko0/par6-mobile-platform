#!/usr/bin/env bash
# BASE_FINAL_APPEARANCE_CONCEPT_V1 - komplet widokow do oceny wygladu.
set -eu
OPENSCAD="${OPENSCAD:-openscad}"
# show_column=false wylacza POMARANCZOWA bryle keep-out napedu kolumny - to
# objetosc diagnostyczna, nie czesc. Pozniejsze -D w wywolaniu ja przywraca,
# z czego korzysta 13_keepouts.png.
SZ="--imgsize=1500,1400 -D show_column=false"
mkdir -p renders
r() { out="$1"; cam="$2"; shift 2
    "$OPENSCAD" -o "renders/$out" --preview $SZ --camera="$cam" "$@" main_base.scad \
        2>&1 | grep -E '^ERROR|WARNING: Assert' || true; echo "  $out"; }

# Kadrowanie pod REALNA wysokosc: kolumna siega 1090 mm, ramie w gornym
# polozeniu okolo 1500. Poprzednie odleglosci (2900/3300) obcinaly kolumne.
# Kadrowanie dobrane testem, nie na oko. Scena siega z = 0..1400 (kolumna
# 1090 + ramie w gornym polozeniu), wiec cel kamery musi byc okolo 620-650,
# a nie 430. Przy 2900 kolumna wychodzila poza kadr.
HERO="0,0,620,68,0,215,4300"
TOP="0,0,150,0,0,0,1800"
BOT="0,0,150,180,0,0,1800"
LEFT="0,0,620,90,0,270,4200"
RIGHT="0,0,620,90,0,90,4200"
REAR="0,0,560,78,0,0,3900"
ISO="0,0,650,62,0,215,4700"
DETAL="150,0,520,74,0,205,2300"

r  01_hero.png              "$HERO"
r  02_top_bez_oslon.png     "$TOP"  -D show_covers=false -D show_column_proxy=false
r  03_top_z_oslonami.png    "$TOP"
r  04_bok_lewy.png          "$LEFT"
r  05_bok_prawy.png         "$RIGHT"
r  06_tyl_serwis.png        "$REAR"
r  07_spod.png              "$BOT"  -D show_covers=false
r  08_exploded.png          "$ISO"  -D explode=90
r  09_jedno_ramie.png       "$HERO" -D show_arm=1
r  10_dwa_ramiona.png       "$HERO" -D show_arm=2
# Pozycje wozka BIORA SIE Z MODELU, nie z literalu. Wpisane na sztywno
# rozjechaly sie przy obnizeniu pokladu 250 -> 240.
r  11_kolumna_LOW.png       "$ISO"  -D carriage_z=col_carriage_low
r  12_kolumna_HIGH.png      "$ISO"  -D carriage_z=col_carriage_high
r  13_keepouts.png          "$ISO"  -D show_keepouts=true -D show_covers=false -D show_column=true

# --- z oslonami i bez, ta sama kamera, do porownania ---------------------
r  20_hero_oslony.png       "$HERO" -D show_arm=1
r  21_hero_bez_oslon.png    "$HERO" -D show_arm=1 -D show_covers=false
r  22_iso_oslony_HIGH.png   "$ISO"  -D show_arm=1 -D carriage_z=col_carriage_high
r  23_iso_bez_oslon_HIGH.png "$ISO" -D show_arm=1 -D carriage_z=col_carriage_high                                     -D show_covers=false
r  24_przod.png             "0,0,620,90,0,180,4200" -D show_arm=1
r  25_kolumna_detal.png     "$DETAL" -D show_arm=1 -D show_covers=false
# Tyl bez oslon i bez kolumny: balast na licach belek, wanna z pakietem przed
# zamiataniem tylnego castera, uchwyt kola na osi. Dodane 2026-09-24 - na tym
# widoku wyszlo, ze stary zastepnik uchwytu kola wisial nad osia i przechodzil
# przez belke, czego zaden test nie lapal.
r  26_tyl_detal.png         "-120,-40,140,72,0,300,1900" -D show_covers=false -D show_column_proxy=false
echo done
