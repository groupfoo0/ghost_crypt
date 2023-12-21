MAPS_SRC = $(wildcard maps/*.tmx)
MAPS_DEST = $(patsubst %.tmx, mods/ghost_crypt_main/tiled/%.json, $(MAPS_SRC))

TILESETS_SRC = $(wildcard tilesets/*.tsx)
TILESETS_DEST = $(patsubst %.tsx, mods/ghost_crypt_main/tiled/%.json, $(TILESETS_SRC))

.PHONY: all
all: $(MAPS_DEST) $(TILESETS_DEST) mods/ghost_crypt_main/textures/generated

mods/ghost_crypt_main/tiled/maps/%.json: maps/%.tmx
	mkdir -p mods/ghost_crypt_main/tiled/maps
	tiled --export-map $< $@

mods/ghost_crypt_main/tiled/tilesets/%.json: tilesets/%.tsx
	mkdir -p mods/ghost_crypt_main/tiled/tilesets
	tiled --export-tileset $< $@

# TODO: add support for multiple tilesets
mods/ghost_crypt_main/textures/generated: mods/ghost_crypt_main/tiled/tilesets/ghost_crypt_main.json
	mkdir -p mods/ghost_crypt_main/textures/generated
	./build_scripts/make_animations.py $< $@

clean:
	$(RM) $(MAPS_DEST) $(TILESETS_DEST) mods/ghost_crypt_main/textures/generated/*
