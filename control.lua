-- Runtime: swaps turrets for the variant that matches the force's range research,
-- keeping quality, ammo, fluids, health, kills and settings.
local config

local function get_config()
  if not config then
    local mod_data = prototypes.mod_data["rangetech-config"]
    config = (mod_data and mod_data.data) or {}
    config.turrets = config.turrets or {}
    config.variants = config.variants or {}
    config.categories = config.categories or {}
    config.techs = config.techs or {}
    config.classification = config.classification or {}
    config.warnings = config.warnings or {}
  end
  return config
end

local cfg = get_config()

-- category -> list of every entity name (base + variants) that belongs to it
local category_entities = {}
for base, info in pairs(cfg.turrets) do
  local list = category_entities[info.category] or {}
  list[#list + 1] = base
  category_entities[info.category] = list
end
for variant_name, info in pairs(cfg.variants) do
  local category = cfg.turrets[info.base] and cfg.turrets[info.base].category
  if category then table.insert(category_entities[category], variant_name) end
end

---------------------------------------------------------------------------
-- Levels
---------------------------------------------------------------------------

local function get_level(force, category)
  local info = cfg.categories[category]
  if not info then return 0 end
  local level = 0
  for n = 1, info.levels do
    local tech = force.technologies[info.tech_prefix .. n]
    if tech and tech.researched then
      level = n
    else
      break
    end
  end
  return level
end

local function variant_name(base, level)
  if level <= 0 then return base end
  return cfg.variant_prefix .. base .. "-" .. level
end

-- entity name -> base name, current level (nil if not one of ours)
local function resolve(name)
  if cfg.turrets[name] then return name, 0 end
  local variant = cfg.variants[name]
  if variant then return variant.base, variant.level end
end

---------------------------------------------------------------------------
-- Replacing
---------------------------------------------------------------------------

local MAX_PRIORITY_SLOTS = 10

local function save_state(entity)
  local state = {}

  state.health = entity.health
  state.last_user = entity.last_user
  pcall(function() state.kills = entity.kills end)
  pcall(function() state.damage_dealt = entity.damage_dealt end)
  pcall(function() state.ignore_unprioritised = entity.ignore_unprioritised_targets end)

  pcall(function()
    state.priorities = {}
    for i = 1, MAX_PRIORITY_SLOTS do
      state.priorities[i] = entity.get_priority_target(i)
    end
  end)

  local ammo = entity.get_inventory(defines.inventory.turret_ammo)
  if ammo and not ammo.is_empty() then
    local copy = game.create_inventory(#ammo)
    for i = 1, #ammo do copy[i].set_stack(ammo[i]) end
    state.ammo = copy
  end

  if entity.type == "fluid-turret" then
    state.fluids = {}
    for i = 1, #entity.fluidbox do
      local fluid = entity.fluidbox[i]
      if fluid then state.fluids[i] = { name = fluid.name, amount = fluid.amount, temperature = fluid.temperature } end
    end
  end

  if entity.type == "electric-turret" then
    state.energy = entity.energy
  end

  return state
end

local function restore_state(new_entity, state)
  pcall(function() new_entity.health = state.health end)
  pcall(function() if state.last_user then new_entity.last_user = state.last_user end end)
  pcall(function() if state.kills then new_entity.kills = state.kills end end)
  pcall(function() if state.damage_dealt then new_entity.damage_dealt = state.damage_dealt end end)
  pcall(function()
    if state.ignore_unprioritised ~= nil then
      new_entity.ignore_unprioritised_targets = state.ignore_unprioritised
    end
  end)
  pcall(function()
    for i = 1, MAX_PRIORITY_SLOTS do
      if state.priorities and state.priorities[i] then
        new_entity.set_priority_target(i, state.priorities[i])
      end
    end
  end)
  pcall(function()
    if state.energy then new_entity.energy = state.energy end
  end)
  pcall(function()
    for i, fluid in pairs(state.fluids or {}) do
      new_entity.fluidbox[i] = fluid
    end
  end)

  if state.ammo then
    local inventory = new_entity.get_inventory(defines.inventory.turret_ammo)
    for i = 1, #state.ammo do
      local stack = state.ammo[i]
      if stack.valid_for_read then
        if inventory and i <= #inventory then
          inventory[i].set_stack(stack)
        else
          new_entity.surface.spill_item_stack({ position = new_entity.position, stack = stack })
        end
      end
    end
    state.ammo.destroy()
  end
end

local function replace(entity, new_name)
  local surface = entity.surface
  local position = entity.position
  local state = save_state(entity)

  local new_entity = surface.create_entity({
    name = new_name,
    position = position,
    direction = entity.direction,
    force = entity.force,
    quality = entity.quality,
    fast_replace = true,
    spill = false,
    create_build_effect_smoke = false,
    raise_built = true,
  })

  if new_entity and new_entity.valid then
    restore_state(new_entity, state)
  else
    -- Replacement failed: keep the original and drop the temporary copy.
    if state.ammo then state.ammo.destroy() end
    log("[range-tech] could not replace " .. tostring(entity.valid and entity.name) .. " with " .. new_name)
  end
end

local function normalize(entity)
  if storage.paused then return end
  if not (entity and entity.valid) then return end
  local base, current = resolve(entity.name)
  if not base then return end

  local target = get_level(entity.force, cfg.turrets[base].category)
  if target ~= current then
    replace(entity, variant_name(base, target))
  end
end

local function refresh_category(force, category)
  local names = category_entities[category]
  if not names or #names == 0 then return end
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = names, force = force })) do
      normalize(entity)
    end
  end
end

local function refresh_force(force)
  for category in pairs(cfg.categories) do
    refresh_category(force, category)
  end
end

local function refresh_all()
  for _, force in pairs(game.forces) do
    refresh_force(force)
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local filters = {}
for name in pairs(cfg.turrets) do filters[#filters + 1] = { filter = "name", name = name } end
for name in pairs(cfg.variants) do filters[#filters + 1] = { filter = "name", name = name } end

if #filters > 0 then
  local function on_built(event)
    normalize(event.entity or event.destination)
  end

  for _, event in pairs({
    defines.events.on_built_entity,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
    defines.events.on_entity_cloned,
  }) do
    script.on_event(event, on_built, filters)
  end

  -- Space platform building: registered without an event filter (the name is checked in normalize).
  script.on_event(defines.events.on_space_platform_built_entity, on_built)
end

local function on_research_changed(event)
  local tech = event.research
  local category = cfg.techs[tech.name]
  if category then refresh_category(tech.force, category) end
end

script.on_event(defines.events.on_research_finished, on_research_changed)
script.on_event(defines.events.on_research_reversed, on_research_changed)

script.on_event(defines.events.on_forces_merged, function(event)
  if event.destination and event.destination.valid then refresh_force(event.destination) end
end)

---------------------------------------------------------------------------
-- Blueprints: variants never leave the mod. Every blueprint (copy, cut, new blueprint,
-- re-selecting contents, library records) is rewritten to the normal turret names, so it
-- works with and without this mod, and ghosts built from it are always the normal turret.
---------------------------------------------------------------------------

local function downgrade_blueprint(item)
  local entities = item.get_blueprint_entities()
  if not entities then return end
  local changed = false
  for _, blueprint_entity in pairs(entities) do
    local variant = cfg.variants[blueprint_entity.name]
    if variant then
      blueprint_entity.name = variant.base
      changed = true
    end
  end
  -- Only write when something changed: set_blueprint_entities rebuilds the blueprint
  -- and clears the event's entity mapping.
  if changed then item.set_blueprint_entities(entities) end
end

if next(cfg.variants) then
  script.on_event(defines.events.on_player_setup_blueprint, function(event)
    local item = event.record or event.stack
    if not item then return end
    local ok, err = pcall(downgrade_blueprint, item)
    if not ok then log("[range-tech] could not rewrite blueprint: " .. tostring(err)) end
  end)
end

script.on_init(refresh_all)
script.on_configuration_changed(refresh_all)

---------------------------------------------------------------------------
-- /rangetech: shows the category of every turret and the current research level
---------------------------------------------------------------------------

local CATEGORY_ORDER = {
  "bullet", "shotgun", "cannon", "railgun", "grenade",
  "missile", "flame", "laser", "electric", "cold", "acid",
  "support", "other", "ignored",
}

local function turret_name(name)
  local proto = prototypes.entity[name]
  return proto and proto.localised_name or name
end

commands.add_command("rangetech", { "rangetech.command-help" }, function(command)
  local player = command.player_index and game.get_player(command.player_index)
  local function say(message)
    if player then player.print(message) else game.print(message) end
  end

  local by_category = {}
  for name, category in pairs(cfg.classification) do
    by_category[category] = by_category[category] or {}
    table.insert(by_category[category], name)
  end

  local force = player and player.force or game.forces["player"]

  for _, category in ipairs(CATEGORY_ORDER) do
    local names = by_category[category]
    if names then
      table.sort(names)
      local line = { "", { "rangetech.cmd-category", { "rangetech.category-" .. category } } }
      local info = cfg.categories[category]
      if category == "ignored" then
        line[#line + 1] = { "rangetech.cmd-ignored" }
      elseif info and force then
        line[#line + 1] = { "rangetech.cmd-level", get_level(force, category), info.levels }
      else
        line[#line + 1] = { "rangetech.cmd-no-research" }
      end
      say(line)

      local list = { "" }
      for i, name in ipairs(names) do
        if i > 1 then list[#list + 1] = ", " end
        list[#list + 1] = turret_name(name)
        list[#list + 1] = " (" .. name .. ")"
        if #list >= 18 then
          say(list)
          list = { "" }
        end
      end
      if #list > 1 then say(list) end
    end
  end

  for _, warning in ipairs(cfg.warnings) do
    say("[range-tech] " .. warning)
  end
end)

---------------------------------------------------------------------------
-- Removing the mod: variants disappear from a save when the mod is removed, so turn them
-- back into normal turrets first with /rangetech-revert (admins only).
---------------------------------------------------------------------------

local function reply(command, message)
  local player = command.player_index and game.get_player(command.player_index)
  if player then player.print(message) else game.print(message) end
end

local function is_allowed(command)
  local player = command.player_index and game.get_player(command.player_index)
  return (not player) or player.admin
end

commands.add_command("rangetech-revert", { "rangetech.revert-help" }, function(command)
  if not is_allowed(command) then
    reply(command, { "rangetech.cmd-admin-only" })
    return
  end

  -- Paused first, so the replacements below are not swapped back to variants.
  storage.paused = true

  local names = {}
  for name in pairs(cfg.variants) do names[#names + 1] = name end

  local count = 0
  if #names > 0 then
    for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities_filtered({ name = names })) do
        local variant = cfg.variants[entity.name]
        if variant and entity.valid then
          replace(entity, variant.base)
          count = count + 1
        end
      end
    end
  end

  reply(command, { "rangetech.cmd-reverted", count })
end)

commands.add_command("rangetech-resume", { "rangetech.resume-help" }, function(command)
  if not is_allowed(command) then
    reply(command, { "rangetech.cmd-admin-only" })
    return
  end
  storage.paused = false
  refresh_all()
  reply(command, { "rangetech.cmd-resumed" })
end)
