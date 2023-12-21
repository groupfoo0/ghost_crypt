#!/usr/bin/env python3
# Combine tiles into animation in time and space domains
# Usage: ./make_animations.py TILED_FILE

import sys

if (len(sys.argv) != 3):
    print(f"Usage: {sys.argv[0]} [TILED_FILE.json] [TEXTURES_DIR]")
    sys.exit(1)

import json
import os
from PIL import Image
import random

tile_json_path = sys.argv[1]
textures_path  = sys.argv[2]

with open(tile_json_path) as f:
    tiles_meta = json.load(f)
    tile_dir  = os.path.dirname(tile_json_path)
    image = os.path.join(tile_dir, tiles_meta["image"])
    im = Image.open(image)

    tiles_name = tiles_meta['name']
    columns = tiles_meta['columns']
    tw = tiles_meta['tilewidth']
    th = tiles_meta['tileheight']

    for tile in tiles_meta['tiles']:
        if not 'animation' in tile:
            continue

        # Load source tiles
        source = []
        for anim in tile['animation']:
            tid = anim['tileid']
            x = tid % columns
            y = tid // columns

            source.append(im.crop((x * tw, y * th, (x+1) * tw, (y+1)*th)))

        random.shuffle(source)

        # Create result image
        canvas_size = 16
        w = tw * canvas_size
        h = th * canvas_size

        result = Image.new("RGBA", (w, h))

        for x in range(0, canvas_size):
            for y in range(0, canvas_size):
                result.paste(random.choice(source), (tw * x, th * y))

        outfile = os.path.join(
            textures_path,
            f"{tiles_name}_{tile['id']}.png")

        print(outfile)
        result.save(outfile)
