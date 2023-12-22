# Ghost Crypt

Explorers vs ghosts game. Ghosts are invisible unless
you shine magic light on them. They do most damage if they get behind you.

Usage:
- Start a new game using golden trophy.

Note: This is a multiplayer game, you need at least two players to
start a match. Game will automatically end if there is not enough players
present on both teams.

Premise:
- There is a group of explorers and group of ghosts.
- Both are controlled by players.
- When an explorer is captured by a ghost, they become a ghost
- Ghosts are invisible to players by default, but players
  have flashlights that, when directed at a ghost, make the ghost
  lose health.
- Explorers can collect treasures. But be careful, once you pick
  a treasure, it's yours to keep (until your capture).
- Treasures come in weird shapes. Use `rotate` button in your inventory
  to rotate the shape.
- Only explorers can collect treasures. As an explorer, your goal
  is to fill your inventory with treasure of maximal value while
  capturing or avoiding as many ghosts as you can.
- As a ghost, your goal is to capture explorers. If you were an explorer
  previously, you have an incentive to first capture players who have
  the highest treasure count, so that they don't get more score then you
  when you used to be an explorer.

Game mechanics:
- There is a large cost for activating light beam tool, and smaller cost for sustaining the light.
- You can't destroy walls, but you can collect sand from sand piles.
- Flowing sand can be crafted into sand source by placing 9 sands in the crafting grid.
- Statues can be used to determine location of ghosts and explorers.
  There are two types of statues. One of them looks at the closest
  ghost, another looks at the closest explorer.
- If you place a sand source at least two blocks above a player,
  the player would not be able to escape unless they have a "ghost miasma"
  node with them to stop the sand from flowing down.

Hints:
- If you get lost, try drawing a map on a pice of paper

## Building from source
Dependencies:
- `GNU Make >= 4.4`
- `Tiled >= 1.10`
- `Python >= 3.11` with `Pillow >= 10.1`

After installing the dependencies, run `make`
to build all the required files.

## Development

Tiled usage:
- On exporting, make sure that "Infinite" map property is set to false.
- `build_scripts/make_animations.py` uses Tiled animations
  to generate multi-node textures.
- You can set `min_players` (int) custom map property to set a limit
  on the minimum number of connected players required for this map to be
  chosen. Same for `max_players`.

Converting sounds to mono:
- `ffmpeg -i stereo.flac -ac 1 mono.flac`

Prepend a name to all files in current directory:
- `for f in *.png; do mv "$f" "ghost_crypt_main_$f"; done`

## License

Code: LGPLv2 or later. See COPYING.LESSER

- File: ghost_crypt_main.png
- Source: https://opengameart.org/content/dungeon-crawl-32x32-tiles-supplemental
- License: CC0

- Files: ghost_crypt_main_step\*.ogg
- Source: https://opengameart.org/content/9-wet-snow-steps
- License: CC0

- Everything else: own work, or modification of the above
- License: CC0
