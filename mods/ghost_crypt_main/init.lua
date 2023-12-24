------------------------------------------------------------
-- Global Helpers
------------------------------------------------------------

math.randomseed(os.time())
local MODNAME = "ghost_crypt_main"
local TILESET_W = 64
local TILESET_H = 95
local TEXTURE_SIDE = 32
-- wrap local node name into full node name
local M = function(name)
  return MODNAME .. ":" .. name
end

-- retrieve tile from tilesheet
local T = function(id)
  local y = math.floor(id / TILESET_W)
  local x = id % TILESET_W
  return table.concat(
    {MODNAME, ".png^[sheet:", TILESET_W, "x", TILESET_H, ":", x, ',', y}
  )
end

local TR = function(name)
  return MODNAME .. "_" .. name .. ".png"
end

local shuffle = function(list)
  local result = {}
  for i, v in ipairs(list) do
    local pos = math.random(1, #result + 1)
    table.insert(result, pos, v)
  end

  return result
end

local random_vector = function()
  return vector.new(
    math.random() - 0.5,
    0.3*(math.random() - 0.5),
    math.random() - 0.5
  )
end

function escape_color_string(str)
  return str:gsub("[:\\^]", "\\%1")
end

function build_animation(textures, frame_length)
    local result = "[combine:" .. TEXTURE_SIDE
      .. "x" .. TEXTURE_SIDE * #textures .. ":"
    for i = 1, #textures do
      result = result .. "0," .. (i - 1) * TEXTURE_SIDE
        .. "=" .. escape_color_string(textures[i])
      if (i < #textures) then
        result = result .. ":"
      end
    end

    local result = {
      name = result,
      animation = {
        type = "vertical_frames",
        aspect_w = TEXTURE_SIDE,
        aspect_h = TEXTURE_SIDE,
        length   = #textures * frame_length
      }
    }

    -- notice the nesting of tables here
    return {result, result}
end

function is_node_empty(pos)
  return "air" == minetest.get_node(pos).name
end

function load_json(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read "*a"
  --print(dump(content))
  --print(dump(path))
  file:close()
  return minetest.parse_json(content)
end

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local ITEM_MAX_WEAR = 65536 -- minetest constant
local SLOW_TICK_SPEED  = 2 -- seconds
local SLOW_TICK_RANDOM = 1 -- note: globalstep dtime is typically less than 0.04 seconds
local FAST_TICK_SPEED  = 0.2
local FAST_TICK_RANDOM = 0.2
local LIGHT_TOOL_SINGLE_USE_WEAR = 10000 -- turnight light beam on costs about 6 seconds of continuous use
local LIGHT_TOOL_CONTINUOUS_WEAR =  3000
local LIGHT_TOOL_CONTINUOUS_FIX  =  2000 -- recharge per 2 seconds
local BEAM_SIZE = 5 -- light beam radius
local LIGHT_MIN = 3 -- ambient lighting

local GHOST_SHADOW_PROB = 0.5

local SOUNDS = {
  footstep = {name = "ghost_crypt_main_step", gain = 0.5, pitch = 1.0},
  dig      = {name = "ghost_crypt_main_step", gain = 1.0, pitch = 1.0},
  dug      = {name = "ghost_crypt_main_step", gain = 1.0, pitch = 1.0},
  place    = {name = "ghost_crypt_main_step", gain = 1.0, pitch = 1.0},
  dug      = {name = "ghost_crypt_main_step", gain = 1.0, pitch = 1.0},
  fall     = {name = "ghost_crypt_main_step", gain = 1.0, pitch = 1.0},
}

------------------------------------------------------------
-- Enums
------------------------------------------------------------

-- E for enum
local E_EXPLORER = 0
local E_GHOST    = 1

-- game statuses
local E_IN_PROGRESS = 2
local E_ENDED       = 3
local E_STARTING    = 4

local UP = vector.new(0, 1, 0)

local NODEBOX_WALLMOUNTED = {
  type = "wallmounted",
  wall_top = {-0.5, 0.3, -0.5, 0.5, 0.5, 0.5},
  wall_bottom = {-0.5, -0.5, -0.5, 0.5, -0.3, 0.5},
  wall_side = {-0.5, -0.5, -0.5, -0.3, 0.5, 0.5}
}

local NODEBOX_WALLMOUNTED_SLIM = {
  type = "wallmounted",
  wall_top = {-0.5, 0.45, -0.5, 0.5, 0.5, 0.5},
  wall_bottom = {-0.5, -0.5, -0.5, 0.5, -0.45, 0.5},
  wall_side = {-0.5, -0.5, -0.5, -0.45, 0.5, 0.5}
}

------------------------------------------------------------
-- Textures
------------------------------------------------------------

local textures = {T(1521), T(1522), T(1523), T(1522)}
local ghost_afterimage_texture = T(1521)--build_animation(textures, 1)

------------------------------------------------------------
-- Node Definitions
------------------------------------------------------------

minetest.register_node(M("stone"), {
        description = "Stone",
        sounds = SOUNDS,
        tiles = {T(1162)},
        drowning = 2,
        light_source = LIGHT_MIN
})

------------------------------------------------------------
-- Mapgen
------------------------------------------------------------

minetest.register_alias("mapgen_singlenode", M("stone"))

------------------------------------------------------------
-- Game state
------------------------------------------------------------

game = {
  status = E_ENDED,
  map_id = 1
}

function start_game()
  -- 1. change game status
  -- 2. pick one player for a ghost team
  -- 3. move all other players to explorers team
  -- 4. on death, everyone turns into a ghost
  -- 5. reset map

  local connected_players = minetest.get_connected_players()
  if #connected_players < 2 then
    minetest.chat_send_all("Need at least two players to start a game")
    return
  end

  minetest.chat_send_all("Starting a new game...")
  game.status = E_STARTING

  for i, player in pairs(connected_players) do
    respawn_player(player)
    -- TODO: Save old scores for statistics?
    -- reset score counter
    local player_id = player:get_player_name()
    players[player_id].stats = setup_default_stats()
    --players[player_id] = setup_default_player_data()
  end
  game.status = E_IN_PROGRESS

  -- switch one player to the ghost team
  --if #connected_players > 1 then
  respawn_player(connected_players[math.random(#connected_players)])
  --end

  generate_map()
end

function show_score(player_id)
  local scores = {}
  for player_id, data in pairs(players) do
    table.insert(
      scores, {
        player = player_id,
        total_treasure_cost = data.stats.total_treasure_cost,
        ghosts_captured = data.stats.ghosts_captured,
        explorers_captured = data.stats.explorers_captured
    })
  end
  table.sort(
    scores, function (a, b)
      return a.total_treasure_cost > b.total_treasure_cost or
        (a.total_treasure_cost == b.total_treasure_cost
         and a.ghosts_captured > b.ghosts_captured) or
        (a.total_treasure_cost == b.total_treasure_cost
         and a.ghosts_captured == b.ghosts_captured and
         a.explorers_captured > b.explorers_captured)
  end)

  local score_string = {}
  for _, score in pairs(scores) do
    table.insert(score_string, score.player)
    table.insert(score_string, "$" .. score.total_treasure_cost)
    table.insert(score_string, score.ghosts_captured)
    table.insert(score_string, score.explorers_captured)
  end
  score_string = table.concat(score_string, ",")

  local score_formspec = {
    "formspec_version[6]",
    "size[13,10]",
    "tablecolumns[text,align=center;text,align=center;text,align=center;text,align=center]",
    "table[0.5,0.5;12,9;score; Player , Treasures collected , Ghosts captured , Explorers captured ,", score_string, "]",
  }

  minetest.show_formspec(player_id, M("score"), table.concat(score_formspec))
end

minetest.register_chatcommand(
  "score", {
    func = function(player_id)
      show_score(player_id)
    end,
})

function show_help(player_id)
  -- TODO: just get this from readme :)
  local help = [[Explorers vs ghosts game. Ghosts are invisible unless you shine magic light on them. They do most damage if they get behind you.

Usage:
- Start a new game using golden trophy.

Note: This is a multiplayer game, you need at least two players to start a match. Game will automatically end if there is not enough players present on both teams.

Premise:
- There is a group of explorers and group of ghosts.
- Both are controlled by players.
- When an explorer is captured by a ghost, they become a ghost
- Ghosts are invisible to players by default, but players have flashlights that, when directed at a ghost, make the ghost lose health.
- Explorers can collect treasures. But be careful, once you pick a treasure, it's yours to keep (until your capture).
- Treasures come in weird shapes. Use `rotate` button in your inventory to rotate the shape.
- Only explorers can collect treasures. As an explorer, your goal is to fill your inventory with treasure of maximal value while capturing or avoiding as many ghosts as you can.
- As a ghost, your goal is to capture explorers. If you were an explorer previously, you have an incentive to first capture players who have the highest treasure count, so that they don't get more score then you when you used to be an explorer.

Game mechanics:
- There is a large cost for activating light beam tool, and smaller cost for sustaining the light.
- You can't destroy walls, but you can collect sand from sand piles.
- Flowing sand can be crafted into sand source by placing 9 sands in the crafting grid.
- Statues can be used to determine location of ghosts and explorers. There are two types of statues. One of them looks at the closest ghost, another looks at the closest explorer.
- If you place a sand source at least two blocks above a player, the player would not be able to escape unless they have a "ghost miasma" node with them to stop the sand from flowing down.]]
  local formspec = {
    "formspec_version[6]",
    "size[13,10]",
    "textarea[0.5,0.5;12,9;;Help;", minetest.formspec_escape(help), "]"
  }

  minetest.show_formspec(player_id, M("help"), table.concat(formspec))
end

minetest.register_chatcommand(
  "help", {
    func = function(player_id)
      show_help(player_id)
    end,
})

minetest.register_chatcommand(
  "respawn", {
    func = function(player_id)
      minetest.get_player_by_name(player_id):set_hp(0)
    end,
})

function end_game()
  -- display final score, change game status, respawn everyone
  minetest.chat_send_all("Ending game...")
  game.status = E_ENDED

  local connected_players = minetest.get_connected_players()
  for i, player in pairs(connected_players) do
    respawn_player(player)
    show_score(player:get_player_name())
  end

  generate_map()
end

------------------------------------------------------------
-- Player state
------------------------------------------------------------

players = {}   -- main table
local ghosts = {}    -- secondary indices
local explorers = {}

function setup_default_stats()
  return {
    total_treasure_cost = 0,
    ghosts_captured = 0,
    explorers_captured = 0
  }
end
function setup_default_player_data()
  local data = {
    light_on = false,
    light_object = nil,
    light_inventory_location_list = "main",
    light_inventory_location_id = 1,
    team = nil,
    position = vector.new(),
    velocity = vector.new(),
    look_dir = vector.new(),
    --player_object = nil,
    hud = {
      score_id = nil
    },
    stats = setup_default_stats()
  }

  if game.started then
    data.team = E_GHOST
  else
    data.team = E_EXPLORER
  end

  return data
end

function light_beam_tool_turn_off(player_id)
  if not players[player_id].light_object then
    return
  end
  players[player_id].light_object:set_detach()
  players[player_id].light_object:remove()

  players[player_id].light_object = nil
  players[player_id].light_on     = false
end

local EXPLORER_TEXTURE = T(3800)
local GHOST_TEXTURE    = T(3925)
local EXPLORER_GLOW    = 8
local GHOST_GLOW       = 10
-- create front and back from the front texture
function make_player_textures(texture)
  return {
    texture,
    texture .. "^[colorize:tan:240^[opacity:235"
  }
end

function switch_to_explorer_team(player_id)
  local player = minetest.get_player_by_name(player_id)

  local properties = player:get_properties()
  properties.textures = make_player_textures(EXPLORER_TEXTURE)
  properties.use_texture_alpha = true
  properties.glow = EXPLORER_GLOW
  properties.nametag_color = "#fff0"
  player:set_properties(properties)

  players[player_id].team = E_EXPLORER
  ghosts[player_id] = nil
  explorers[player_id] = true

  minetest.chat_send_player(player_id, "You are an explorer")
end

function ghost_make_invisible(player_id)
  local player = minetest.get_player_by_name(player_id)
  local properties = player:get_properties()
  properties.textures = make_player_textures(GHOST_TEXTURE .. "^[opacity:0")
  properties.use_texture_alpha = true
  properties.nametag_color = "#fff0"
  player:set_properties(properties)

  return player
end

function switch_to_ghost_team(player_id)
  local player = ghost_make_invisible(player_id)

  players[player_id].team = E_GHOST
  ghosts[player_id] = true
  explorers[player_id] = nil

  minetest.chat_send_player(player_id, "You are a ghost")
end

function ghost_make_visible(player_id)
  local player = minetest.get_player_by_name(player_id)
  local properties = player:get_properties()
  properties.textures = make_player_textures(GHOST_TEXTURE)
  properties.use_texture_alpha = true
  properties.glow = GHOST_GLOW
  properties.nametag_color = "#fff0"
  player:set_properties(properties)
end

------------------------------------------------------------
-- Globalstep game state update
------------------------------------------------------------

-- helpers

function is_explorer_facing_ghost(distance, explorer_to_ghost, explorer_look_dir)
  return
    0 == distance
    or vector.dot(
      explorer_look_dir,
      explorer_to_ghost
    )/distance > 0.7 -- about 1/sqrt(2)
end

-- main
local globalstep_slow_dt = 0
function setup_slow_tick()
  return SLOW_TICK_SPEED + SLOW_TICK_RANDOM * math.random()
end
local slow_tick = setup_slow_tick()

local globalstep_fast_dt = 0
function setup_fast_tick()
  return FAST_TICK_SPEED + FAST_TICK_RANDOM * math.random()
end
local fast_tick = setup_fast_tick()

minetest.register_globalstep(function(dtime)
    globalstep_slow_dt = globalstep_slow_dt + dtime
    if (globalstep_slow_dt > slow_tick) then
      globalstep_slow_dt = 0
      slow_tick = setup_slow_tick()

      for player_id, player_data in pairs(players) do
        -- heal players
        local player_obj   = minetest.get_player_by_name(player_id)
        local player_props = player_obj:get_properties()
        local hp_max = player_props.hp_max
        player_obj:set_hp(math.min(player_obj:get_hp() + 1, hp_max), "auto heal")

        if E_EXPLORER == player_data.team then
          -- recharge light beam tool
          local inventory = minetest.get_inventory({type = "player", name=player_id})
          local itemstack =
            inventory:get_stack(
              player_data.light_inventory_location_list,
              player_data.light_inventory_location_id
            )

          if player_data.light_on then
            if itemstack:get_wear() + LIGHT_TOOL_CONTINUOUS_WEAR > ITEM_MAX_WEAR then
              -- torch is out of juice, turn it off!
              light_beam_tool_turn_off(player_id)
            else
              itemstack:add_wear(LIGHT_TOOL_CONTINUOUS_WEAR)
              inventory:set_stack(
                player_data.light_inventory_location_list,
                player_data.light_inventory_location_id,
                itemstack
              )
            end
          else
            -- recharge light tool
            itemstack:set_wear(
              math.max(
                itemstack:get_wear() - LIGHT_TOOL_CONTINUOUS_FIX,
                0
              )
            )
            inventory:set_stack(
              player_data.light_inventory_location_list,
              player_data.light_inventory_location_id,
              itemstack
            )
          end
        end

        if E_GHOST == player_data.team then
          -- if ghost was made visible previously, make it invisible again
          ghost_make_invisible(player_id)
        end
        -- for ghosts, there is a chance of an "after image" spawinig
        if E_GHOST == player_data.team and math.random() < GHOST_SHADOW_PROB then
          for other_player_id, other_player_data in pairs(players) do
            if other_player_id ~= player_id then
              minetest.add_particle({
                  playername = other_player_id,
                  pos = player_obj:get_pos() + UP,
                  velocity = 2*player_obj:get_velocity() + random_vector(),
                  acceleration = 0.4*random_vector(),
                  expirationtime = 2 + 4*math.random(),
                  size = 10,
                  texture = ghost_afterimage_texture,
                  --texture = T(3925),
                  glow = LIGHT_MIN + 3
              })
            end
          end
        end
      end

      -- update time of day
      minetest.set_timeofday(0.5)
    end

    globalstep_fast_dt = globalstep_fast_dt + dtime
    if (globalstep_fast_dt > fast_tick) then
      globalstep_fast_dt = 0
      fast_tick = setup_fast_tick()

      ------------------------------------------------------------
      -- Compute player interactions
      ------------------------------------------------------------

      local player_objects = minetest.get_connected_players()
      local player_id_to_player_obj = {}
      for _, obj in pairs(player_objects) do
        local player_id = obj:get_player_name()
        players[player_id].position = obj:get_pos()
        players[player_id].velocity = obj:get_velocity()
        players[player_id].look_dir = obj:get_look_dir()
        player_id_to_player_obj[player_id] = obj
        --players[player_id].player_object = obj
      end

      -- Compute distances between explorers and ghosts
      --local distances = {}
      for explorer_id, _ in pairs(explorers) do
        --distances[explorer_id] = {}
        for ghost_id, _ in pairs(ghosts) do
          local explorer_to_ghost = players[ghost_id].position - players[explorer_id].position
          local distance = vector.length(explorer_to_ghost)

          -- Process explorer to ghost interaction
          if distance > BEAM_SIZE then
            goto continue
          end

          local facing_ghost =
            is_explorer_facing_ghost(
              distance,
              explorer_to_ghost,
              players[explorer_id].look_dir)

          -- behind in a narrow cone
          local ghost_is_behind =
            is_explorer_facing_ghost(
              distance,
              -explorer_to_ghost,
              players[explorer_id].look_dir)

          local ghost_obj  = minetest.get_player_by_name(ghost_id)
          local explorer_obj = minetest.get_player_by_name(explorer_id)

          local ghost_hp = ghost_obj:get_hp()
          local explorer_hp = explorer_obj:get_hp()
          if facing_ghost and players[explorer_id].light_on then
            -- ghost takes damage and becomes visible
            ghost_make_visible(ghost_id)
            ghost_hp = ghost_hp - 2
          elseif facing_ghost and not players[explorer_id].light_on then
            -- explorer takes a bit of damage
            explorer_hp = explorer_hp - 1
          elseif ghost_is_behind then
            -- explorer takes a lot of damage
            explorer_hp = explorer_hp - 3
          end
          if ghost_hp <= 0 then
            players[explorer_id].stats.ghosts_captured =
              players[explorer_id].stats.ghosts_captured + 1
            set_formspec(player_id_to_player_obj[explorer_id])
            minetest.chat_send_all(
              table.concat(
                {
                  explorer_id, " captured ghost ", ghost_id, " -> ",
                  players[explorer_id].stats.ghosts_captured, " total"
            }))
          end
          if explorer_hp <= 0 then
            players[ghost_id].stats.explorers_captured =
              players[ghost_id].stats.explorers_captured + 1
            set_formspec(player_id_to_player_obj[ghost_id])
            minetest.chat_send_all(
              table.concat(
                {
                  ghost_id, " captured explorer ", explorer_id, " -> ",
                  players[ghost_id].stats.explorers_captured, " total"
            }))
          end
          -- actually set new hp
          ghost_obj:set_hp(ghost_hp)
          explorer_obj:set_hp(explorer_hp)

          ::continue::
        end
      end
    end
end)

------------------------------------------------------------
-- Tools
------------------------------------------------------------

-- light beam tool

local LightBeamEntity = {
  initial_properties = {
    physical = false,
    visual = "upright_sprite",
    visual_size = vector.new(BEAM_SIZE, BEAM_SIZE, BEAM_SIZE),
    textures = {"ghost_crypt_main_light_beam.png"},
    use_texture_alpha = true,
    glow = -1,
    shaded = false,
  }
}

minetest.register_entity(M("light_beam_entity"), LightBeamEntity)

function use_light_beam_tool(itemstack, user, pointed_thing)
  if not user:is_player() then
    return
  end

  local player_id = user:get_player_name()

  if players[player_id].light_on then
    light_beam_tool_turn_off(player_id)
  else
    -- if light doesn't have enough juice, it won't activate
    if itemstack:get_wear() + LIGHT_TOOL_SINGLE_USE_WEAR > ITEM_MAX_WEAR then
      return
    end

    itemstack:add_wear(LIGHT_TOOL_SINGLE_USE_WEAR)

    -- attach light beam
    local obj = minetest.add_entity(user:get_pos(), M("light_beam_entity"))
    local offset = vector.new(0,2*math.random(),8*BEAM_SIZE)
    local rotation = vector.new(90,-45,0) -- in degrees
    obj:set_attach(user, "", offset, rotation, true)

    players[player_id].light_object = obj
    players[player_id].light_on     = true
  end

  return itemstack
end

minetest.register_tool(
  M("light_beam_tool"),
  {
    description = "Staff of enlightment (captures ghosts)",
    inventory_image = T(2836),
    on_use = use_light_beam_tool,
    on_place = use_light_beam_tool
})

------------------------------------------------------------
-- Debug Tools
------------------------------------------------------------

minetest.register_craftitem(
  M("start_new_game_item"),
  {
    description = "Start new game",
    inventory_image = T(59),
    on_use = function(itemstack, user, pointed_thing)
      if not user:is_player() then
        return
      end

      start_game()
    end
  }
)

minetest.register_craftitem(
  M("explorer_team_item"),
  {
    description = "Switch to explorer team",
    inventory_image = T(3800),
    on_use = function(itemstack, user, pointed_thing)
      if not user:is_player() then
        return
      end

      local player_id = user:get_player_name()
      switch_to_explorer_team(player_id)
    end
  }
)

minetest.register_craftitem(
  M("ghost_team_item"),
  {
    description = "Switch to ghost team",
    inventory_image = T(3925),
    on_use = function(itemstack, user, pointed_thing)
      if not user:is_player() then
        return
      end

      local player_id = user:get_player_name()
      switch_to_ghost_team(player_id)
    end
  }
)

------------------------------------------------------------
-- Nodes that players can carry around
------------------------------------------------------------

minetest.register_node(M("gold_statue"), {
        description = "Gold statue",
        tiles = {T(59)},
        sounds = SOUNDS,
        drowning = 2,
        groups = {dig_immediate = 2},
        light_source = LIGHT_MIN
})

for i = 794, 820 do
  minetest.register_node(
    M("statue_" .. i), {
      description = "Statue",
      drawtype = "plantlike",
      paramtype2 = "degrotate",
      visual_scale = 2.0,
      sounds = SOUNDS,
      tiles = {T(i)},
      drowning = 2,
      groups = {dig_immediate = 2},
      light_source = LIGHT_MIN
  })
end

-- torches
local torch_textures = {T(1359), T(1360), T(1361), T(1362)}
minetest.register_node(
    M("torch"), {
      description = "Torch",
      drawtype = "signlike",
      paramtype2 = "wallmounted",
      stack_max = 43,
      visual_scale = 2.0,
      inventory_image = torch_textures[1],
      wield_image = torch_textures[1],
      sounds = SOUNDS,
      tiles = build_animation(torch_textures, 0.3),
      groups = {dig_immediate = 2},
      walkable = false,
      climable = true,
      move_resistance = 1,
      floodable = false,
      sunlight_propagates = true,
      drowning = 2,
      post_effect_color = "#80203033",
      light_source = minetest.LIGHT_MAX,
      selection_box = {
        type = "wallmounted",
        wall_top = {-0.9, 0.3, -0.5, 0.9, 0.5, 0.5},
        wall_bottom = {-0.9, -0.5, -0.5, 0.9, -0.3, 0.5},
        wall_side = {-0.5, -0.9, -0.5, -0.3, 0.9, 0.5}
      },
      on_place = function(itemstack, placer, pointed_thing)
        -- due to the shape of the torch, we can only place it if:
        -- 1. it is placed on a wall
        -- 2. there is no nodes above or below

        if "node" ~= pointed_thing.type then
          return itemstack
        end

        if is_node_empty(pointed_thing.above + UP)
          and is_node_empty(pointed_thing.above - UP)
        then
          return minetest.item_place(itemstack, placer, pointed_thing)
        end
      end
  })

-- fountains
local textures = {T(16), T(17)}
minetest.register_node(
    M("fountain"), {
      description = "Fountain",
      drawtype = "signlike",
      paramtype2 = "wallmounted",
      stack_max = 16,
      visual_scale = 1.3,
      sounds = SOUNDS,
      inventory_image = textures[1],
      wield_image = textures[1],
      tiles = build_animation(textures, 0.2),
      groups = {dig_immediate = 2},
      walkable = false,
      climable = true,
      move_resistance = 1,
      floodable = true,
      sunlight_propagates = true,
      drowning = 2,
      post_effect_color = "#30208033",
      light_source = minetest.LIGHT_MAX,
      selection_box = {
        type = "wallmounted",
        wall_top = {-0.9, 0.3, -0.5, 0.9, 0.5, 0.5},
        wall_bottom = {-0.9, -0.5, -0.5, 0.9, -0.3, 0.5},
        wall_side = {-0.5, -0.9, -0.5, -0.3, 0.9, 0.5}
      },
      on_place = function(itemstack, placer, pointed_thing)
        -- due to the shape of the torch, we can only place it if:
        -- 1. it is placed on a wall
        -- 2. there is no nodes above or below

        if "node" ~= pointed_thing.type then
          return itemstack
        end

        if true or is_node_empty(pointed_thing.above + UP)
          and is_node_empty(pointed_thing.above - UP)
        then
          return minetest.item_place(itemstack, placer, pointed_thing)
        end
      end
  })

-- build a texture spanning several nodes
function build_multinode_texture(name)
  local result = {
    name = name,
    backface_culling = true,
    align_style = "world",
    scale = 16
  }

  return result
end

minetest.register_node(
  M("corruption"), {
    description = "Ghost miasma",
    -- HACK: minetest doesn't support world-aligned textures for signlike
    --drawtype = "signlike",
    drawtype = "nodebox",
    node_box = NODEBOX_WALLMOUNTED_SLIM,
    use_texture_alpha = "clip",
    paramtype2 = "wallmounted",
    stack_max = 53,
    sounds = SOUNDS,
    --invert the texture so it's not blood
    --also actully looks kinda cool
    tiles = {build_multinode_texture(TR(3273) .. "^[invert:rgb")},
    --tiles = {build_multinode_texture(TR(3273))},
    groups = {dig_immediate = 2},
    walkable = false,
    climable = false,
    move_resistance = 1,
    floodable = false,
    sunlight_propagates = true,
    drowning = 2,
    post_effect_color = "#5abdab33", --"#f0203033",
    light_source = LIGHT_MIN + 4,
    selection_box = NODEBOX_WALLMOUNTED
})

-- todo: replace glue with dirt or some other trash
-- sand pile
local sand_texture = T(260)
minetest.register_node(
    M("sand_source"), {
      description = "Sand block",
      drawtype = "liquid",
      liquidtype = "source",
      liquid_alternative_source = M("sand_source"),
      liquid_alternative_flowing = M("sand_flowing"),
      sounds = SOUNDS,
      tiles = {sand_texture},
      groups = {dig_immediate = 2},
      walkable = true,
      liquid_viscosity = 2,
      move_resistance = 3,
      disable_jump = true,
      liquid_range = 4,
      liquid_renewable = false,
      drowning = 3,
      post_effect_color = "#a0a078f3",
      light_source = LIGHT_MIN
  })

minetest.register_node(
    M("sand_flowing"), {
      description = "Sand piece",
      drawtype = "flowingliquid",
      liquidtype = "flowing",
      liquid_alternative_source = M("sand_source"),
      liquid_alternative_flowing = M("sand_flowing"),
      paramtype2 = "flowingliquid",
      sounds = SOUNDS,
      tiles = {sand_texture},
      special_tiles = {sand_texture, sand_texture},
      groups = {dig_immediate = 2},
      walkable = true,
      liquid_viscosity = 2,
      move_resistance = 3,
      disable_jump = true,
      liquid_range = 4,
      liquid_renewable = false,
      drowning = 3,
      post_effect_color = "#a0a078f3",
      light_source = LIGHT_MIN
  })

minetest.register_craft({
    type = "shapeless",
    output = M("sand_source"),
    recipe = {
      M("sand_flowing"), M("sand_flowing"), M("sand_flowing"),
      M("sand_flowing"), M("sand_flowing"), M("sand_flowing"),
      M("sand_flowing"), M("sand_flowing"), M("sand_flowing")
    }
})

------------------------------------------------------------
-- Tilesets
------------------------------------------------------------

local dir = minetest.get_modpath(MODNAME) .. "/tiled/tilesets/"
local names = minetest.get_dir_list(dir, false)
local tilesets = {}
for _, filename in pairs(names) do
  local full_path = dir .. filename
  local _, _, name = string.find(filename, "^(.+).json$")
  if not name then
    print("Wrong filename: " .. filename)
    goto next_tileset
  end

  local data = load_json(full_path)
  tilesets[name] = {
    width  = data.tilewidth,
    height  = data.tileheight,
    properties = data.properties, -- custom properties!
    animations = {} -- animation can be either in time or space domain
  }

  for _, tile in pairs(data.tiles) do
    if tile.animation then
      tilesets[name].animations[tile.id] = {}

      -- yeah we don't care about animation duration for now
      for _, animation in pairs(tile.animation) do
        table.insert(tilesets[name].animations[tile.id], animation.tileid)
      end
    end
  end
  ::next_tileset::
end

------------------------------------------------------------
-- Map Generation
------------------------------------------------------------

local map_dir = minetest.get_modpath(MODNAME) .. "/tiled/maps/"
local map_filenames = minetest.get_dir_list(map_dir, false)
local maps = {}
local tiles = {}
for _, map_filename in pairs(map_filenames) do
  local full_path = map_dir .. map_filename
  local _, _, map_name = string.find(map_filename, "^(.+).json$")
  if not map_name then
    print("Wrong filename: " .. map_filename)
    goto next_map
  end

  local map = load_json(full_path)
  maps[map_name] = {
    width  = map.width,
    height  = map.height,
    floor = {},
    walls = {},
    ceiling = {},
    ghost_spawns = {},
    explorer_spawns = {},
    min_players = 0,
    max_players = 2^16
  }

  -- load used tiles
  for _, layer in pairs(map.layers) do
    -- check if this layer type is supported
    if not maps[map_name][layer.name] then
      goto next_layer
    end

    if "tilelayer" == layer.type then
      for idx, tile in pairs(layer.data) do
        maps[map_name][layer.name][idx] = tile % 2^16 -- highest bits are used for rotation info

        if 0 ~= tile then
          tiles[tile] = true
        end
      end
    elseif "objectgroup" == layer.type then
      for _, object in pairs(layer.objects) do
        --print(dump(object))
        -- only rectangles are supported for now
        --if "rectangle" == object.shape then
        table.insert(maps[map_name][layer.name], object)
        --end
      end
    end
    ::next_layer::
  end

  -- load custom properties
  for _, property in pairs(map.properties) do
    if "min_players" == property.name and "int" == property.type then
      maps[map_name].min_players = property.value
    elseif "max_players" == property.name and "int" == property.type then
      maps[map_name].max_players = property.value
    end
  end
  ::next_map::
end

-- register tiles used by loaded maps
for tile, _ in pairs(tiles) do
  local data = {
    light_source = LIGHT_MIN,
    drowning = 2,
    sounds = SOUNDS
  }

  -- todo: multiple tileset support
  local name = "ghost_crypt_main"
  -- todo: what's up with -1 here?
  if (tilesets[name].animations[tile-1]) then
    data.tiles = {build_multinode_texture(TR(tile-1))}

  else
    data.tiles = T(tile)
  end

  minetest.register_node(M(tile), data)
end

-- helpers
function tile_to_cid(tile)
  if 0 == tile then
    return minetest.CONTENT_AIR
  else
    return minetest.get_content_id(M(tile))
  end
end

function pick_map()
  -- pick a map
  local map_names = {}
  for map_name, map in pairs(maps) do
    if map.min_players <= #players and map.max_players >= #players then
      table.insert(map_names, map_name)
    end
  end

  game.map_name = map_names[math.random(#map_names)]

  minetest.chat_send_all("Playing on map " .. game.map_name)
end

function generate_map()
  -- clear old statues and stuff
  minetest.clear_objects()
  pick_map()

  local layer_name = "floor"
  local map = maps[game.map_name]
  local WALL_HEIGHT = 5
  local level_height = WALL_HEIGHT + 2

  local minp = vector.new(0,0,0)
  local maxp = vector.new(map.width, level_height, map.height)
  local vm = minetest.get_voxel_manip(minp, maxp)
  local pmin, pmax = vm:get_emerged_area()
  minetest.emerge_area(pmin, pmax)
  local c_stone = minetest.get_content_id(M("stone"))

  local data = {}
  local param1 = {}
  local param2 = {}
  local area = VoxelArea(pmin, pmax)
  for i = 1, area:getVolume() do
    table.insert(param1, LIGHT_MIN)
    table.insert(param2, 0)

    local pos = area:position(i)
    if pos.z >= map.width or pos.x >= map.height or pos.y >= level_height or
      pos.x < 0 or pos.z < 0 or pos.y < 0 then
      table.insert(data, c_stone)
      goto continue
    end

    local idx = pos.z + pos.x * map.width + 1
    if (pos.y == 0) then
      local tile = map.floor[idx]
      table.insert(data, tile_to_cid(tile))
    elseif (pos.y == level_height - 1) then
      local tile = map.ceiling[idx]
      table.insert(data, tile_to_cid(tile))
    else
      local tile = map.walls[idx]
      if 0 ~= tile then
        table.insert(data, tile_to_cid(tile))
        goto continue
      end
      -- empty space above floor!
      local SAND_PROB = 0.002
      local TREASURE_PROB = 0.02
      local STATUE_PROB = 0.01
      if (pos.y <= 2 and math.random() < SAND_PROB) then
        table.insert(data, minetest.get_content_id(M("sand_source")))
        goto continue
      end

      if (pos.y == 1 and math.random() < TREASURE_PROB) then
        table.insert(data, minetest.get_content_id(M("treasure_" .. math.random(#treasures))))
        param2[i] = 1
        goto continue
      end

      -- spawn entities
      if (pos.y == 2 and math.random() < STATUE_PROB) then
        local statue_ids = {M("statue_explorer_facing"), M("statue_ghost_facing")}
        local p = vector.new(pos.x, 1.5, pos.z)
        minetest.add_entity(p, statue_ids[math.random(#statue_ids)])
      end

      -- insert air
      table.insert(data, tile_to_cid(tile))
    end
    ::continue::
  end

  vm:set_data(data)
  vm:set_light_data(param1)
  vm:set_param2_data(param2)
  vm:update_liquids()
  --vm:calc_lighting()
  vm:write_to_map(false)
end

minetest.after(0.1, generate_map)

------------------------------------------------------------
-- Death handling
------------------------------------------------------------

local function register_death_chest(side, texture, name)
  minetest.register_node(
    M(side .. "_chest"), {
      description = name,
      drawtype = "plantlike",
      paramtype2 = "degrotate",
      inventory_image = texture .. "^[verticalframe:4:1",
      wield_image = texture .. "^[verticalframe:4:1",
      visual_scale = 1.6,
      stack_max = 11,
      sounds = SOUNDS,
      tiles = {{
          name = texture,
          animation = {
            type = "vertical_frames",
            aspect_w = TEXTURE_SIDE,
            aspect_h = TEXTURE_SIDE,
            length   = 4
          }
      }},
      groups = {dig_immediate = 2},
      light_source = LIGHT_MIN + 2,
      on_construct = function(pos)
      end
  })
end
register_death_chest("explorer", TR("explorer_drop"), "Trapped Explorer")
register_death_chest("ghost",    TR("ghost_drop"),    "Trapped Ghost")
--register_death_chest("ghost",    TR("explorer_drop") .. "^[invert:g", "Trapped Ghost")

-- call each time player dies
function respawn_player(player)
  local player_id = player:get_player_name()
  -- HACK: minetest.get_connected_players() can be laggy
  if not players[player_id] then
    return
  end

  light_beam_tool_turn_off(player_id)

  -- setup inventory
  local inventory = player:get_inventory()
  inventory:set_list("main", {})
  inventory:set_list("craft", {})
  inventory:set_list("craftpreview", {})

  local endgame_items = {
    M("start_new_game_item"),
    M("explorer_team_item"),
    M("ghost_team_item"),
    M("explorer_chest 11"),
    M("ghost_chest 11")
  }

  -- TODO: have different number of torches depending on the map?
  local explorer_items = {
    M("light_beam_tool"),
    M("torch 43")
  }

  local ghost_items = {
    M("corruption 53")
  }

  --players[player_id] = setup_default_player_data()

  if E_STARTING == game.status then
    switch_to_explorer_team(player_id)
    add_items(inventory, explorer_items)
  elseif E_ENDED == game.status then
    switch_to_explorer_team(player_id)
    add_items(inventory, explorer_items)
    add_items(inventory, ghost_items)
    add_items(inventory, endgame_items)
  elseif E_IN_PROGRESS == game.status then
    switch_to_ghost_team(player_id)
    add_items(inventory, ghost_items)
  end

  set_formspec(player)

  -- find spawn location
  local layer_name = ""
  if E_EXPLORER == players[player_id].team then
    layer_name = "explorer_spawns"
  elseif E_GHOST == players[player_id].team then
    layer_name = "ghost_spawns"
  end
  local spawns = maps[game.map_name][layer_name]
  local spawn = spawns[math.random(#spawns)]
  local s = TEXTURE_SIDE
  local x = spawn.x/s + math.random(spawn.width / s)
  local y = spawn.y/s + math.random(spawn.height / s)
  player:set_pos(vector.new(y, 3, x))
  local player_props = player:get_properties()
  local hp_max = player_props.hp_max
  player:set_hp(hp_max, "respawn")

  return player_id
end

function set_formspec(player)
  local player_id = player:get_player_name()

  local stats = players[player_id].stats

  local stats_text = {
    --"Statistics:\n",
    --"Game state: IN_GAME\n",
    --"Team: GHOST\n",
    "Total treasure cost: $", stats.total_treasure_cost, "\n",
    "Ghosts captured: ", stats.ghosts_captured, "\n",
    "Explorers captured: ", stats.explorers_captured, "\n",
    --"Time left: 10:10\n",
  }

  -- custom inventory formspec
  -- TODO: might need to adjust for screen size?
  local formspec = {
    "formspec_version[6]",
    "size[13,11]",
    "list[current_player;main;0.4,4.6;10,5;]",
    --"list[current_player;main;1.5,5.5;8,4;]",
    "list[current_player;craft;6.5,0.625;3,3;]",
    "listring[]",
    "list[current_player;craftpreview;10.5,1.875;2.875,2.875;]",
    -- extra stuff
    -- stats
    "label[0.5,1;", table.concat(stats_text,""), "]",
    -- craft rotate button
    "button[1.625,3.1;3,1;rotate;Rotate craft]",
    "button_exit[11,0.5;1.5,0.9;exit;Exit]"
  }
  player:set_inventory_formspec(table.concat(formspec, ""))
  local inv = player:get_inventory()
  inv:set_size("main", 50)
  inv:set_width("main", 10)
  player:hud_set_hotbar_itemcount(10)
end

-- call only when player joins
local function spawn_player(player)
  -- setup game state
  local player_id = player:get_player_name()
  local player_data = setup_default_player_data()
  players[player_id] = players[player_id] or player_data

  -- player physics
  player:set_physics_override({
      sneak_glitch = true,
      new_move = false
  })
  player:set_sky({
      base_color = "#f05030",
      type = "plain",
      clouds = false
  })

  set_formspec(player)

  minetest.chat_send_player(player_id, "Hint: type /help for help and type /score to view score")
  minetest.chat_send_player(player_id, "Hint: If you are stuck, type /respawn")

  respawn_player(player)
end

-- inventory helper to add multiple items at once
function add_items(inventory, items)
  for _, item in pairs(items) do
    -- todo: running multiple add_item might be a bit slow
    inventory:add_item("main", ItemStack(item))
  end
end

function check_for_endgame()
  -- if no explorers remain, end game
  -- similarly, if all ghosts leave, end game
  if game.status == E_IN_PROGRESS
    and (next(explorers) == nil or next(ghosts) == nil) then
    end_game()
  end
end

minetest.register_on_joinplayer(spawn_player)
minetest.register_on_dieplayer(function(player, reason)
    -- create player drop and respawn
    local player_id = player:get_player_name()
    if E_GHOST == players[player_id].team then
      minetest.place_node(player:get_pos(), {name = M("ghost_chest")})
    elseif E_EXPLORER == players[player_id].team then
      minetest.place_node(player:get_pos(), {name = M("explorer_chest")})
    end

    respawn_player(player)
    check_for_endgame()
end)

minetest.register_on_leaveplayer(function(player, timed_out)
    local player_id = player:get_player_name()
    players[player_id] = nil
    explorers[player_id] = nil
    ghosts[player_id] = nil

    check_for_endgame()
end)

------------------------------------------------------------
-- Treasures
------------------------------------------------------------

-- shapes:
local treasure_types_string = [[
###

##
##

###
#..

###
..#

###
.#.

##.
.##

.##
##.

.##
#..
#..

#..
.##
..#

..#
##.
#..
]]
local treasure_types = {}

function skip_spaces(str, i)
  while not ("." == str:sub(i+1, i+1) or "#" == str:sub(i+1, i+1)) and i <= #str do i = i + 1 end
  return i + 1
end

local tmp_treasure = {}
local y = 0
local x = 0
i = 0

i = skip_spaces(treasure_types_string, i)
while i <= #treasure_types_string do
  local c = treasure_types_string:sub(i, i)
  local cn = treasure_types_string:sub(i+1,i+1)

  if "#" == c then
    --table.insert(tmp_treasure, {x = x, y = y})
    tmp_treasure[x + y * 3 + 1] = true
    x = x + 1
    i = i + 1
  elseif "." == c then
    x = x + 1
    i = i + 1
  else
    y = y + 1
    x = 0
    if #treasure_types_string == i or ("." ~= cn and "#" ~= cn) then
      -- next treasure type
      table.insert(treasure_types, tmp_treasure)
      tmp_treasure = {}
      x = 0
      y = 0
    end
    i = skip_spaces(treasure_types_string, i)
  end
end

-- todo: do this every game restart
treasure_types = shuffle(treasure_types)

-- mapping from name to shape
local treasure_shapes = {}
local treasure_prices = {} -- how much each treasure is cost

treasures = {
  T(3080), T(2758), T(2547),
  T(2352), T(2607), T(2598),
  T(2755), T(3083), T(2287),
  T(2425), T(2238), T(2046)
}

-- actual treasure items located in some inventory
local treasure_instances = {}
local treasure_instances_free_id = 1 -- non-decreasing free treasure ids

-- treasure mechanics:
-- when you pick up treasure, a shape is added to your crafting area
-- (crafting area is checked to be empty first)
-- each part of this shape remembers what treasure instance its a part of
-- each treasure instance holds a pointer to treasure shape and current treasure
-- rotation
local function create_treasure_instance(shape)
  treasure_instances[treasure_instances_free_id] = {
    inv_id = 1, -- location of top left corner of the shape
    shape = shape,
    rotation = 0 -- 0,1,2,3 are possible rotation stances (90 degree rotations)
  }
  -- not free anymore
  treasure_instances_free_id = treasure_instances_free_id + 1

  -- return id that was used just now
  return treasure_instances_free_id - 1
end

for i = 1, #treasures do
  local name = M("treasure_" .. i)

  treasure_shapes[name] = treasure_types[i % #treasure_types + 1]
  treasure_prices[name] = math.floor(100*math.random())

  minetest.register_node(
    name, {
      description = "Treasure " .. i,
      sounds = SOUNDS,
      tiles = {treasures[i]},
      inventory_image = treasures[i],
      wield_image = treasures[i],
      on_drop = minetest.node_drop,
      drawtype = "signlike",
      stack_max = 1,
      selection_box = NODEBOX_WALLMOUNTED,
      walkable = false,
      paramtype2 = "wallmounted",
      drowning = 2,
      groups = {dig_immediate = 2},
      light_source = LIGHT_MIN + 1,
      on_place = function(itemstack, placer, pointed_thing)
        -- can't put treasure back!
        -- once it's taken, its yours to keep forever
        -- just like in tetris
        return itemstack
      end,
      on_dig = function(pos, node, digger)
        if (not digger:is_player()) then
          return false
        end
        local player = digger
        local player_id = player:get_player_name()

        if E_EXPLORER ~= players[player_id].team then
          minetest.chat_send_player(player_id, "Only explorers can collect treasures")
          return
        end

        local list_name = "craft"
        local inventory = player:get_inventory()
        local list = inventory:get_list(list_name)
        for i, itemstack in pairs(list) do
          if not itemstack:is_empty() then
            minetest.chat_send_player(player_id, "Clean your craft area first!")
            return false
          end
        end

        local new_list = {}
        local shape = treasure_shapes[name]
        local price = treasure_prices[name]
        local instance_id = create_treasure_instance(shape)

        for j = 1, 9 do
          if shape[j] then
            local stack = ItemStack(name)
            local meta = stack:get_meta()
            meta:set_int("treasure_instance_id", instance_id)
            meta:set_string("description", "Treasure " .. i .. ", price: $" .. price)
            table.insert(new_list, stack)
          else
            table.insert(new_list, ItemStack())
          end
        end
        inventory:set_list(list_name, new_list)
        minetest.remove_node(pos)
        local prev_cost = players[player_id].stats.total_treasure_cost
        players[player_id].stats.total_treasure_cost = prev_cost + price
        set_formspec(player)

        -- announce stats
        -- local msg = {
        --   player_id, " has found a treasure with $", price,
        --   " in price and now has $", players[player_id].stats.total_treasure_cost,
        --   " of treasure value in total"
        -- }
        local msg = {
          player_id, ": + $", price, " = $", players[player_id].stats.total_treasure_cost
        }
        minetest.chat_send_all(table.concat(msg))

        return true
      end
  })
end

------------------------------------------------------------
-- Player inventory
-------------------------------------------------------------

-- movement logic
local function get_inventory_action_stack(player, action, inventory_info)
    local ii = inventory_info
    if "move" == action then
      return player:get_inventory():get_list(ii.from_list)[ii.from_index]
    else
      return ii.stack
    end
end

function is_restricted_item(name)
  return name == M("light_beam_tool")
  or name == M("ghost_team_item")
  or name == M("explorer_team_item")
  or name == M("start_new_game_item")
end

function is_treasure(name)
  return string.match(name, "^" .. M("treasure_") .. "(%d+)$")
end

-- HACK: why doesn't InvRef:get_width work?
function get_dims(inv_name)
  if "main" == inv_name then
    return 10, 5
    --return 8, 4
  elseif "craft" == inv_name then
    return 3, 3
  end
end

local function rotate_xy(x, y, times)
  -- 90 degree rotation matrix:
  -- (0 -1)
  -- (1  0)
  if 0 == times then
    return x, y
  elseif 1 == times then
    return -y, x
  elseif 2 == times then
    return -x, -y
  elseif 3 == times then
    return y, -x
  end
end

local function rotate_id(id, times)
  times = times % 4

  local x = (id - 1) % 3 - 1
  local y = math.floor((id - 1) / 3) - 1

  local new_x, new_y = rotate_xy(x, y, times)
  new_x = new_x + 1
  new_y = new_y + 1

  return new_y * 3 + new_x + 1
end

minetest.register_allow_player_inventory_action(
  function(player, action, inventory, inventory_info)
    local player_id = player:get_player_name()

    local stack = get_inventory_action_stack(player, action, inventory_info)
    local name = stack:get_name()

    if is_restricted_item(name) then
      -- keep track of where light beam tool goes to
      -- and don't let the light tool leave the player inventory
      if "move" == action then
        players[player_id].light_inventory_location_list = inventory_info.to_list
        players[player_id].light_inventory_location_id = inventory_info.to_index
        return 1
      end

      return 0
    elseif is_treasure(name) then
      -- HACK: code below is buggy
      -- specifically, combination movement and rotation are a bit tricky to get right
      -- hence, I am restricting it so that treasure can only be moved from craft
      -- area to the main inventory, and not any other way, sort of like tetris!
      if "craft" ~= inventory_info.from_list or "main" ~= inventory_info.to_list then
        local msg = "You can only move treasure from craft to main inventory."
        minetest.chat_send_player(player_id, msg)
        return 0
      end

      -- check if destination has enough space, and move everything else
      local meta = stack:get_meta()
      local treasure_instance_id = meta:get_int("treasure_instance_id")
      local treasure_instance = treasure_instances[treasure_instance_id]
      if "move" == action then
        local inventory = player:get_inventory()
        local lists = inventory:get_lists()
        local source      = lists[inventory_info.from_list]
        local destination = lists[inventory_info.to_list]
        local source_w, source_h = get_dims(inventory_info.from_list)
        local destination_w, destination_h = get_dims(inventory_info.to_list)
        local source_is_destination =
          inventory_info.from_list == inventory_info.to_list

        -- top left corner of a shape
        local shape_w  = 3
        local shape_id = treasure_instance.inv_id - 1
        local shape_x  = shape_id % shape_w
        local shape_y  = math.floor(shape_id / shape_w)

        -- shape part source
        local source_id = inventory_info.from_index - 1
        local source_x = source_id % source_w
        local source_y = math.floor(source_id / source_w)

        -- shape part destination
        local destination_id = inventory_info.to_index - 1
        local destination_x = destination_id % destination_w
        local destination_y = math.floor(destination_id / destination_w)

        -- BUG: rotation + movemnet inside craft area can be a bit tricky
        -- maybe disallow putting treasures back into craft area entirely?
        -- so to rotate back you first would need to get rid of the item, and
        -- then put it back
        -- this would also clear the corresponding treasure_instance and
        -- its rotation value to circumvent the problem
        --print(dump(inventory_info))
        -- iterate over all parts of a shape
        for dx = 0, 2 do
          for dy = 0, 2 do
            -- todo: can implement rotation here
            local part_id = 1 + dy * 3 + dx
            part_id = rotate_id(part_id, -treasure_instance.rotation)
            -- is this part used by treasure?
            if not treasure_instance.shape[part_id] then
              goto continue
            end

            -- NOTE: movement works when shape_x, shape_y = (0, 0)
            local from_x = source_x + dx - source_x + shape_x
            local from_y = source_y + dy - source_y + shape_y
            local to_x   = destination_x + dx - source_x
            local to_y   = destination_y + dy - source_y
            -- if any part is outside the inventory, don't move
            if (
              to_x < 0 or to_x >= destination_w or to_y < 0 or to_y >= destination_h or
              from_x < 0 or from_x >= source_w or from_y < 0 or from_y >= source_h
            ) then
              --print(to_x, to_y, destination_w, destination_h)
              --print(from_x, from_y, source_w, source_h)
              minetest.chat_send_player(player_id, "Not enough space")
              return 0
            end

            local from_id = 1 + from_y * source_w    + from_x
            local to_id   = 1 + to_y * destination_w + to_x
            --print(to_id)
            -- if any part used by treasure is occupied by something else, don't move
            if not destination[to_id]:is_empty()
              and destination[to_id]:get_meta():get_int("treasure_instance_id") ~= treasure_instance_id then
              minetest.chat_send_player(player_id, "Other items occupy the same space")
              return 0
            end
            source[from_id] = ItemStack("")
            destination[to_id] = stack

            ::continue::
          end
        end
        -- HACK: minetest might segfault if we use `set_lists` directly
        minetest.after(
          0.01,
          function()
            inventory:set_lists(lists)
        end)

        local new_x = destination_x + 0 - (source_x - shape_x)
        local new_y = destination_y + 0 - (source_y - shape_y)
        local new_inv_id = new_y * destination_w + new_x + 1
        treasure_instance.inv_id = new_inv_id
      end
      return 0
    end

    return 99 -- max stack
end)

-- rotation logic
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if not fields.rotate then
      return false
    end

    local list_name = "craft"
    local inventory = player:get_inventory()
    local old_list = inventory:get_list(list_name)
    local new_list = {}

    -- note: there could be multiple treasure instances
    -- in the same rotation area
    local rotated_instances = {}

    for i, itemstack in pairs(old_list) do
      local new_i = rotate_id(i, 1)
      local id = itemstack:get_meta():get_int("treasure_instance_id")
      -- ^ returns 0 if not present
      if 0 ~= id then
        rotated_instances[id] = true
      end

      new_list[new_i] = itemstack
    end

    -- rotate all the instances
    for id, _ in pairs(rotated_instances) do
      local rot = treasure_instances[id].rotation
      treasure_instances[id].rotation = (rot + 1) % 4
    end

    inventory:set_list(list_name, new_list)

    return true
end)

------------------------------------------------------------
-- Statues
------------------------------------------------------------

-- find closest player to pos among players with ids
local function get_closest_vector(pos, ids)
  local closest_vector = false
  local closest_distance = false
  for id, _ in pairs(ids) do
    local v = players[id].position - pos
    local distance = vector.length(v)
    if not closest_distance or distance < closest_distance then
      closest_distance = distance
      closest_vector = v
    end
  end

  return closest_vector, closest_distance
end

-- create a statue that will face players with ids
local function register_statue(name, texture, ids)
  local on_click = function(self, clicker)
    if not clicker:is_player() then
      return
    end

    local player_id = clicker:get_player_name()

    if E_EXPLORER == players[player_id].team then
      minetest.chat_send_player(player_id, "Hello, Explorer!")
    elseif E_GHOST == players[player_id].team then
      minetest.chat_send_player(player_id, "Hello, Ghost!")
    end
  end

  minetest.register_entity(
    M(name), {
      initial_properties = {
        physical = true,
        visual = "upright_sprite",
        visual_size = vector.new(1.2, 2.3, 1.2),
        textures = texture,
        use_texture_alpha = true,
        pointable = true,
        collisionbox = { -0.2, -0.5, -0.2, 0.2, 0.0, 0.2 },
        stepheight = 2,
        makes_footstep_sound = true,
        glow = 1,
        shaded = true,
      },
      on_rightclick = on_click,
      on_punch = on_click,
      on_activate = function(self, staticdata, dtime_s)
        self.timer_count = 0
        self.slow_tick = setup_fast_tick()
      end,
      on_deactivate = function(self, removal)
      end,
      on_step = function(self, dtime, moveresult)
        self.timer_count = self.timer_count + dtime
        if (self.timer_count < self.slow_tick) then
          return
        end
        self.slow_tick = setup_fast_tick()
        self.timer_count = 0

        -- find closest player among specified ids
        local pos = self.object:get_pos()
        local cvec, cdist = get_closest_vector(pos, ids)
        if not cvec then
          return
        end

        local rot = vector.dir_to_rotation(cvec)

        self.object:set_rotation(
          vector.new(0, rot.y, 0)
        )
      end
  })
end

register_statue("statue_explorer_facing", make_player_textures(T(796)), explorers)
register_statue("statue_ghost_facing", make_player_textures(T(820)), ghosts)

------------------------------------------------------------
-- Mob ghosts
------------------------------------------------------------

local on_click = function(self, clicker)
end

minetest.register_entity(
  M("ghost_mob"), {
    initial_properties = {
      physical = true,
      visual = "upright_sprite",
      visual_size = vector.new(1.2, 2.3, 1.2),
      textures = make_player_textures(GHOST_TEXTURE),
      use_texture_alpha = true,
      pointable = true,
      collisionbox = { -0.2, -0.5, -0.2, 0.2, 0.0, 0.2 },
      stepheight = 2,
      makes_footstep_sound = true,
      glow = 1,
      shaded = true,
    },
    on_rightclick = on_click,
    on_punch = on_click,
    on_activate = function(self, staticdata, dtime_s)
      self.slow_timer_count = 0
      self.slow_tick = setup_slow_tick()
      self.fast_timer_count = 0
      self.fast_tick = setup_fast_tick()
    end,
    on_deactivate = function(self, removal)
    end,
    on_step = function(self, dtime, moveresult)
      -- slow timer: decide where to walk, check collisions
      self.slow_timer_count = self.slow_timer_count + dtime
      if (self.slow_timer_count > self.slow_tick) then
        self.slow_tick = setup_slow_tick()
        self.slow_timer_count = 0

        -- find the closest explorer
        local pos = self.object:get_pos()
        local cvec, cdist = get_closest_vector(pos, explorers)
        if not cvec then
          return
        end

        local rot = vector.dir_to_rotation(cvec)

        self.object:set_rotation(
          vector.new(0, rot.y, 0)
        )

        local v = vector.new(cvec.x, 0, cvec.z)
        v = vector.normalize(v)

        self.object:set_velocity(v)
      end

      -- fast timer: actually move
      -- self.fast_timer_count = self.fast_timer_count + dtime
      -- if (self.fast_timer_count > self.fast_tick) then
      --   self.fast_tick = setup_fast_tick()
      --   self.fast_timer_count = 0


      -- end
    end
})
