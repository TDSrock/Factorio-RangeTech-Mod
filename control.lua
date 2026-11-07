-- Runtime: swaps turrets for the variant that matches the force's range research,
-- keeping quality, ammo, fluids, health, kills and settings.
local mod_commands = require("lib.mod_commands")
local config

local function get_config()
  if not config then
    local mod_data = prototypes.mod_data["rangetech-config"]
    config = (mod_data and mod_data.data) or {}
    config.turrets = config.turrets or {}
    config.variants = config.variants or {}
    config.categories = config.categories or {}
    config.techs = config.techs or {}
    config.plans = config.plans or {}
    config.classification = config.classification or {}
    config.reasons = config.reasons or {}
    config.warnings = config.warnings or {}
  end
  return config
end

local cfg = get_config()

-- category -> list of every entity name (base + variants) that belongs to it
local category_entities = {}
-- category -> list of base entity names only
local category_bases = {}
for base, info in pairs(cfg.turrets) do
  local list = category_entities[info.category] or {}
  list[#list + 1] = base
  category_entities[info.category] = list

  local bases = category_bases[info.category] or {}
  bases[#bases + 1] = base
  category_bases[info.category] = bases
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

-- Fluids of a fluid turret. Factorio 2.0 exposes them as entity.fluidbox[i]; 2.1 removed LuaFluidBox
-- and uses entity.get_fluid(i) / entity.set_fluid(i, fluid). Whichever the running game has is used.
local function read_fluids(entity)
  local fluids = {}
  local has_fluidbox, fluidbox = pcall(function() return entity.fluidbox end)
  if has_fluidbox and fluidbox then
    for i = 1, #fluidbox do
      local fluid = fluidbox[i]
      if fluid then fluids[i] = { name = fluid.name, amount = fluid.amount, temperature = fluid.temperature } end
    end
  else
    pcall(function()
      for i = 1, #entity.prototype.fluidbox_prototypes do
        local fluid = entity.get_fluid(i)
        if fluid then fluids[i] = { name = fluid.name, amount = fluid.amount, temperature = fluid.temperature } end
      end
    end)
  end
  return fluids
end

local function write_fluids(entity, fluids)
  local has_fluidbox, fluidbox = pcall(function() return entity.fluidbox end)
  for i, fluid in pairs(fluids) do
    if has_fluidbox and fluidbox then
      pcall(function() fluidbox[i] = fluid end)
    else
      pcall(function() entity.set_fluid(i, fluid) end)
    end
  end
end

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
    state.fluids = read_fluids(entity)
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
  if state.fluids then write_fluids(new_entity, state.fluids) end

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
  local old_name = entity.name
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
    return true
  end

  if state.ammo then state.ammo.destroy() end
  log(string.format("[range-tech] could not replace %s with %s on %s at (%g, %g)",
    old_name, new_name, surface.name, position.x, position.y))
  return false
end

local function normalize(entity)
  if storage.paused then return end
  if not (entity and entity.valid) then return end
  local base, current = resolve(entity.name)
  if not base then return end

  local target = get_level(entity.force, cfg.turrets[base].category)
  if target ~= current then
    return replace(entity, variant_name(base, target))
  end
end

local function refresh_category(force, category)
  local names = category_entities[category]
  if storage.paused or not names then return 0 end
  local changed = 0
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered({ name = names, force = force })) do
      if normalize(entity) then changed = changed + 1 end
    end
  end
  return changed
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
  if not category or storage.paused then return end
  local force = tech.force
  local changed = refresh_category(force, category)
  force.print({ "rangetech.research-updated", tech.localised_name, changed })
end

script.on_event(defines.events.on_research_finished, on_research_changed)
script.on_event(defines.events.on_research_reversed, on_research_changed)

script.on_event(defines.events.on_forces_merged, function(event)
  if event.destination and event.destination.valid then refresh_force(event.destination) end
end)

---------------------------------------------------------------------------
-- Sweep: a script can create a turret without raising a build event (for example
-- surface.create_entity without raise_built). Check a limited number of chunks per timer event.
---------------------------------------------------------------------------

local function sweep()
  if storage.paused then return end

  local forces = {}
  local researched = {}
  for _, force in pairs(game.forces) do
    local has_research = false
    for category in pairs(category_bases) do
      if get_level(force, category) > 0 then
        researched[category] = true
        has_research = true
      end
    end
    if has_research then forces[#forces + 1] = force end
  end
  if #forces == 0 then
    storage.sweep = nil
    return
  end

  local names = {}
  for category in pairs(researched) do
    for _, name in ipairs(category_bases[category]) do names[#names + 1] = name end
  end

  -- Store LuaObjects so the current pass can continue after saving and loading.
  if not storage.sweep then
    local surfaces = {}
    for _, surface in pairs(game.surfaces) do surfaces[#surfaces + 1] = surface end
    storage.sweep = { surfaces = surfaces, surface_index = 1 }
  end
  local pass = storage.sweep
  local remaining = settings.global["rangetech-sweep-chunks-per-event"].value
  local filter = { name = names, force = forces }
  while remaining > 0 do
    local surface = pass.surfaces[pass.surface_index]
    if not surface then
      storage.sweep = nil
      return
    end

    if surface.valid and not pass.chunks then pass.chunks = surface.get_chunks() end
    local chunk = pass.chunks and pass.chunks.valid and pass.chunks()
    if chunk then
      remaining = remaining - 1
      if surface.is_chunk_generated(chunk) then
        filter.area = chunk.area
        for _, entity in pairs(surface.find_entities_filtered(filter)) do normalize(entity) end
      end
    else
      pass.surface_index = pass.surface_index + 1
      pass.chunks = nil
    end
  end
end

local registered_interval

local function register_sweep()
  if registered_interval then
    script.on_nth_tick(registered_interval, nil)
    registered_interval = nil
  end
  local seconds = settings.global["rangetech-sweep-interval"].value
  if seconds > 0 and next(cfg.turrets) then
    registered_interval = math.floor(seconds * 60)
    script.on_nth_tick(registered_interval, sweep)
  end
end

register_sweep()

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "rangetech-sweep-interval" then
    if settings.global["rangetech-sweep-interval"].value == 0 then storage.sweep = nil end
    register_sweep()
  end
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
script.on_configuration_changed(function()
  storage.sweep = nil
  refresh_all()
end)

-- Remind players when upgrades are paused (see /range-tech-prep-uninstall).
script.on_event(defines.events.on_player_joined_game, function(event)
  if storage.paused then
    local player = game.get_player(event.player_index)
    if player then player.print({ "rangetech.cmd-paused-notice" }) end
  end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------

local CATEGORY_ORDER = {
  "bullet", "shotgun", "cannon", "railgun", "grenade",
  "missile", "flame", "laser", "electric", "cold", "acid",
  "support", "other", "ignored",
}

local REPORT_FILE = "range-tech-report.txt"

local reply = mod_commands.reply

local function is_allowed(command)
  local player = command.player_index and game.get_player(command.player_index)
  return (not player) or player.admin
end

local function format_range(range)
  return string.format("%g", range)
end

local function bonus_text(info)
  if info.mode == "flat" then
    return string.format("+%g tiles of range per level", info.amount)
  end
  return string.format("+%g%% of base range per level", info.amount)
end

-- Plain-text report for the player to review: settings, every category with its turrets, the
-- range per level of each turret, the research plan and why ignored turrets are ignored.
local function build_report(force)
  local lines = {}
  local function add(text) lines[#lines + 1] = text end

  add("Range Tech report")
  add("Mod version: " .. tostring(script.active_mods["range-tech"]))
  add("Game time: " .. math.floor(game.tick / 60) .. " s")
  add("Preset: " .. tostring(settings.startup["rangetech-preset"].value))
  local overrides = settings.startup["rangetech-overrides"].value
  add("Category overrides: " .. ((overrides and overrides ~= "") and overrides or "(none)"))
  add("Range upgrades paused: " .. tostring(storage.paused and true or false))
  add("Research progress shown for force: " .. (force and force.name or "?"))
  add("")

  local by_category = {}
  for name, category in pairs(cfg.classification) do
    by_category[category] = by_category[category] or {}
    table.insert(by_category[category], name)
  end

  for _, category in ipairs(CATEGORY_ORDER) do
    local names = by_category[category]
    if names then
      table.sort(names)
      add("== " .. category .. " (" .. #names .. " turret" .. (#names == 1 and "" or "s") .. ") ==")

      if category == "ignored" then
        add("This mod does nothing with these turrets.")
        for _, name in ipairs(names) do
          add("  " .. name .. ": " .. tostring(cfg.reasons[name] or "?"))
        end
      else
        local info = cfg.categories[category]
        if info then
          local level = force and get_level(force, category) or 0
          add("Range research: level " .. level .. " of " .. info.levels .. " researched")
          add("Bonus: " .. bonus_text(info))
          local plan = cfg.plans[category]
          if plan then
            add("Research levels:")
            for _, step in ipairs(plan) do
              add(string.format("  level %d: %d units x %d s, science: %s",
                step.level, step.count, step.time, table.concat(step.packs, ", ")))
            end
          end
        else
          add("No range research for this category (0 levels in the settings, or no icon found).")
        end

        add("Turrets:")
        for _, name in ipairs(names) do
          local turret = cfg.turrets[name]
          local text = "  " .. name
          if turret and turret.base_range then
            local ranges = {}
            for level, range in ipairs(turret.ranges or {}) do ranges[level] = format_range(range) end
            text = text .. ": base range " .. format_range(turret.base_range)
            if #ranges > 0 then text = text .. ", per level: " .. table.concat(ranges, " / ") end
          end
          text = text .. " [" .. tostring(cfg.reasons[name] or "?") .. "]"
          add(text)
        end
      end
      add("")
    end
  end

  if #cfg.warnings > 0 then
    add("== warnings ==")
    for _, warning in ipairs(cfg.warnings) do add("  " .. warning) end
    add("")
  end

  return table.concat(lines, "\n") .. "\n"
end

local function report_command(command)
  local player = command.player_index and game.get_player(command.player_index)
  local force = player and player.force or game.forces["player"]

  -- Short summary in chat.
  for _, category in ipairs(CATEGORY_ORDER) do
    local has_turrets = false
    for _, turret_category in pairs(cfg.classification) do
      if turret_category == category then has_turrets = true break end
    end
    if has_turrets then
      local line = { "", { "rangetech.cmd-category", { "rangetech.category-" .. category } } }
      local info = cfg.categories[category]
      if category == "ignored" then
        line[#line + 1] = { "rangetech.cmd-ignored" }
      elseif info and force then
        line[#line + 1] = { "rangetech.cmd-level", get_level(force, category), info.levels }
      else
        line[#line + 1] = { "rangetech.cmd-no-research" }
      end
      reply(command, line)
    end
  end

  -- Full data in script-output/.
  local ok, err = pcall(function()
    helpers.write_file(REPORT_FILE, build_report(force), false)
  end)
  if ok then
    reply(command, { "rangetech.cmd-report-written", REPORT_FILE })
  else
    reply(command, { "rangetech.cmd-report-failed" })
    log("[range-tech] could not write report: " .. tostring(err))
  end
end

-- Restore base turrets before removing the mod or changing which variants it generates.
local function disable_command(command)
  if not is_allowed(command) then
    reply(command, { "rangetech.cmd-admin-only" })
    return
  end

  -- Paused first, so the replacements below are not swapped back to variants.
  storage.paused = true
  storage.sweep = nil

  local names = {}
  for name in pairs(cfg.variants) do names[#names + 1] = name end

  local count = 0
  local failed = 0
  local remaining = 0
  if #names > 0 then
    local filter = { name = names }
    for _, surface in pairs(game.surfaces) do
      for _, entity in pairs(surface.find_entities_filtered(filter)) do
        local variant = entity.valid and cfg.variants[entity.name]
        if variant then
          if replace(entity, variant.base) then
            count = count + 1
          else
            failed = failed + 1
          end
        end
      end
    end
    for _, surface in pairs(game.surfaces) do
      remaining = remaining + surface.count_entities_filtered(filter)
    end
  end

  if failed > 0 or remaining > 0 then
    reply(command, { "rangetech.cmd-revert-incomplete", count, failed, remaining })
  else
    reply(command, { "rangetech.cmd-reverted", count })
  end
end

-- Turns range upgrades back on and upgrades every turret that is not at its research level yet.
local function enable_command(command)
  if not is_allowed(command) then
    reply(command, { "rangetech.cmd-admin-only" })
    return
  end
  storage.paused = false
  refresh_all()
  reply(command, { "rangetech.cmd-resumed" })
end

mod_commands.register({
  { name = "report", alias = "rangetech", help = { "rangetech.command-help" }, run = report_command },
  { name = "disable", alias = "range-tech-prep-uninstall", help = { "rangetech.uninstall-help" }, run = disable_command },
  { name = "enable", alias = "range-tech-resume", help = { "rangetech.resume-help" }, run = enable_command },
})
