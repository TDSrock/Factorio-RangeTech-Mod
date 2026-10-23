-- Works out which science packs each range research needs. Data stage only.
--
-- For a category:
--   * level 1 needs the packs of the "easiest" turret's unlock technology,
--   * the last level needs the union of the packs of ALL turrets in the category,
--   * levels in between add the missing packs gradually (cheapest pack first).
local M = {}

local icons = require("lib.icons")

local FALLBACK_PACK = "automation-science-pack"

---------------------------------------------------------------------------
-- Indexes
---------------------------------------------------------------------------

local unlock_index
local result_index

local function ensure_indexes()
  if unlock_index then return end
  unlock_index, result_index = {}, {}

  for _, tech in pairs(data.raw.technology or {}) do
    for _, effect in pairs(tech.effects or {}) do
      if effect.type == "unlock-recipe" and effect.recipe then
        unlock_index[effect.recipe] = unlock_index[effect.recipe] or {}
        table.insert(unlock_index[effect.recipe], tech)
      end
    end
  end

  for _, recipe in pairs(data.raw.recipe or {}) do
    local results = recipe.results
    if not results and recipe.result then
      results = { { type = "item", name = recipe.result } }
    end

    for _, result in pairs(results or {}) do
      local name = result.name or result[1]
      if name then
        result_index[name] = result_index[name] or {}
        table.insert(result_index[name], recipe.name)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Technology helpers
---------------------------------------------------------------------------

local function ingredient_name(ingredient)
  return ingredient.name or ingredient[1]
end

local function tech_packs(tech, depth)
  local packs = {}

  if tech.unit and tech.unit.ingredients then
    for _, ingredient in pairs(tech.unit.ingredients) do
      packs[ingredient_name(ingredient)] = true
    end
  elseif (depth or 0) < 6 then
    for _, prerequisite in pairs(tech.prerequisites or {}) do
      local pre = data.raw.technology[prerequisite]
      if pre then
        for pack in pairs(tech_packs(pre, (depth or 0) + 1)) do
          packs[pack] = true
        end
      end
    end
  end

  return packs
end

local function count_keys(set)
  local n = 0
  for _ in pairs(set) do
    n = n + 1
  end
  return n
end

local function tech_cost(tech)
  local count = tech.unit and tech.unit.count or 0
  return count_keys(tech_packs(tech)) * 1e9 + count
end

local function cheapest(techs)
  local best, best_cost

  for _, tech in ipairs(techs) do
    if tech.enabled ~= false then
      local cost = tech_cost(tech)

      if not best_cost
        or cost < best_cost
        or (cost == best_cost and tech.name < best.name) then
        best, best_cost = tech, cost
      end
    end
  end

  return best
end

local function unlock_tech_for_item(item_name)
  ensure_indexes()

  local candidates = {}
  for _, recipe_name in ipairs(result_index[item_name] or {}) do
    for _, tech in ipairs(unlock_index[recipe_name] or {}) do
      candidates[#candidates + 1] = tech
    end
  end

  return cheapest(candidates)
end

local function unlock_tech_for_pack(pack_name)
  ensure_indexes()
  return cheapest(unlock_index[pack_name] or {})
end

---------------------------------------------------------------------------
-- Pack ordering
---------------------------------------------------------------------------

local pack_order_cache = {}

local function pack_order(name)
  local cached = pack_order_cache[name]
  if cached ~= nil then return cached end

  local order = "zzz"

  for type_name in pairs(defines.prototypes["item"]) do
    local proto = data.raw[type_name] and data.raw[type_name][name]
    if proto then
      order = proto.order or "zzz"
      break
    end
  end

  pack_order_cache[name] = order
  return order
end

local function sorted_packs(set)
  local list = {}

  for pack in pairs(set) do
    list[#list + 1] = pack
  end

  table.sort(list, function(a, b)
    local oa, ob = pack_order(a), pack_order(b)
    if oa ~= ob then return oa < ob end
    return a < b
  end)

  return list
end

---------------------------------------------------------------------------
-- Icon selection
---------------------------------------------------------------------------

local FALLBACK_TECHS = {
  bullet = { "gun-turret" },
  shotgun = { "military" },
  cannon = { "tank", "military-2" },
  railgun = { "railgun" },
  grenade = { "military-2" },
  missile = { "rocketry" },
  flame = { "flamethrower" },
  laser = { "laser-turret", "laser" },
  electric = { "tesla-weapons", "laser-turret" },
  cold = { "military-2" },
  acid = { "military-3" },
  support = { "military" },
  other = { "military" },
}

local GENERIC_FALLBACKS = {
  "military",
  "military-2",
  "gun-turret",
}

-- Prefer familiar vanilla research icons where they exist.
-- The missile category uses explosive damage research as its closest
-- vanilla equivalent.
local PREFERRED_DAMAGE_TECHS = {
  electric = {
    "electric-weapons-damage-1",
    "tesla-weapons",
  },
  laser = {
    "laser-weapons-damage-1",
    "laser",
  },
  missile = {
    "stronger-explosives-3",
    "stronger-explosives-2",
    "stronger-explosives-1",
    "rocketry",
  },
  grenade = {
    "stronger-explosives-1",
    "military",
  },
  cannon = {
    "physical-projectile-damage-1",
    "physical-projectile-damage-2",
    "tank",
  },
  bullet = {
    "physical-projectile-damage-1",
    "gun-turret",
  },
  shotgun = {
    "physical-projectile-damage-1",
    "military",
  },
  flame = {
    "refined-flammables-1",
    "flamethrower",
  },
}

-- Reject recycler-themed icons without changing the separate range overlay.
local function is_recycler_icon(path)
  if type(path) ~= "string" then return false end
  return string.find(string.lower(path), "recycl", 1, true) ~= nil
end

local function acceptable_tech_icon(tech, official_only)
  if not tech then return nil end

  local layers = icons.from_tech(tech, official_only)
  if not layers then return nil end

  for _, layer in ipairs(layers) do
    if is_recycler_icon(layer.icon) then
      return nil
    end
  end

  return layers
end

local function category_of(entries)
  return entries[1] and entries[1].category or "other"
end

local function try_technology_names(names, official_only)
  for _, name in ipairs(names or {}) do
    local tech = data.raw.technology and data.raw.technology[name]
    local layers = acceptable_tech_icon(tech, official_only)

    if layers then
      return layers
    end
  end

  return nil
end

-- Scan technologies for relevant damage effects. This allows modded
-- technologies to provide an icon when no preferred vanilla technology
-- is available.
local function damage_effect_matches(effect, category)
  if type(effect) ~= "table" then return false end

  local effect_type = string.lower(tostring(effect.type or ""))
  local category_name = string.lower(tostring(effect.ammo_category or ""))
  local modifier = string.lower(tostring(effect.modifier or ""))

  local damage_effect =
    string.find(effect_type, "damage", 1, true) ~= nil
    or string.find(effect_type, "ammo-damage", 1, true) ~= nil

  if not damage_effect then return false end

  if category == "electric" then
    return category_name == "electric"
      or category_name == "tesla"
      or string.find(category_name, "electric", 1, true) ~= nil
      or string.find(modifier, "electric", 1, true) ~= nil
      or string.find(modifier, "tesla", 1, true) ~= nil
  elseif category == "laser" then
    return category_name == "laser"
      or string.find(category_name, "laser", 1, true) ~= nil
      or string.find(modifier, "laser", 1, true) ~= nil
  elseif category == "missile" then
    return category_name == "rocket"
      or category_name == "missile"
      or category_name == "explosive"
      or string.find(category_name, "rocket", 1, true) ~= nil
      or string.find(category_name, "missile", 1, true) ~= nil
      or string.find(modifier, "explosive", 1, true) ~= nil
      or string.find(modifier, "rocket", 1, true) ~= nil
  elseif category == "cannon" or category == "bullet"
    or category == "shotgun" then
    return category_name == "bullet"
      or category_name == "shotgun-shell"
      or category_name == "cannon-shell"
      or category_name == "artillery-shell"
      or string.find(category_name, "bullet", 1, true) ~= nil
      or string.find(category_name, "projectile", 1, true) ~= nil
  elseif category == "grenade" then
    return category_name == "grenade"
      or category_name == "landmine"
      or string.find(modifier, "explosive", 1, true) ~= nil
  elseif category == "flame" then
    return category_name == "flamethrower"
      or category_name == "flame"
      or string.find(modifier, "flame", 1, true) ~= nil
  end

  return false
end

local function scanned_damage_technologies(category, official_only)
  local candidates = {}

  for _, tech in pairs(data.raw.technology or {}) do
    if tech.enabled ~= false then
      local matches = false

      for _, effect in pairs(tech.effects or {}) do
        if damage_effect_matches(effect, category) then
          matches = true
          break
        end
      end

      if matches and acceptable_tech_icon(tech, official_only) then
        candidates[#candidates + 1] = tech
      end
    end
  end

  table.sort(candidates, function(a, b)
    local ca, cb = tech_cost(a), tech_cost(b)
    if ca ~= cb then return ca < cb end
    return a.name < b.name
  end)

  for _, tech in ipairs(candidates) do
    local layers = acceptable_tech_icon(tech, official_only)
    if layers then
      return layers
    end
  end

  return nil
end

local function choose_icons(entries, infos, easiest, official_only)
  local category = category_of(entries)

  -- 1. Explicitly preferred vanilla technologies.
  local layers = try_technology_names(
    PREFERRED_DAMAGE_TECHS[category],
    official_only
  )
  if layers then return layers end

  -- 2. Search technologies for a matching damage bonus, including mods.
  layers = scanned_damage_technologies(category, official_only)
  if layers then return layers end

  -- 3. Prefer the easiest turret's unlock technology.
  if easiest and easiest.tech then
    layers = acceptable_tech_icon(easiest.tech, official_only)
    if layers then return layers end
  end

  -- 4. Try every other turret's unlock technology in cost/name order.
  for _, info in ipairs(infos) do
    if info.tech then
      layers = acceptable_tech_icon(info.tech, official_only)
      if layers then return layers end
    end
  end

  -- 5. Category-specific fallback, then generic military technologies.
  local candidates, seen = {}, {}

  for _, name in ipairs(FALLBACK_TECHS[category] or {}) do
    if not seen[name] then
      candidates[#candidates + 1] = name
      seen[name] = true
    end
  end

  for _, name in ipairs(GENERIC_FALLBACKS) do
    if not seen[name] then
      candidates[#candidates + 1] = name
      seen[name] = true
    end
  end

  return try_technology_names(candidates, official_only)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function M.plan(entries, level_count, cost, official_only)
  local infos = {}

  for _, entry in ipairs(entries) do
    local tech = unlock_tech_for_item(entry.item)
    local packs = tech and tech_packs(tech) or {}

    if count_keys(packs) == 0 then
      packs = { [FALLBACK_PACK] = true }
    end

    infos[#infos + 1] = {
      name = entry.proto.name,
      tech = tech,
      packs = packs,
      cost = tech and tech_cost(tech) or 0,
    }
  end

  table.sort(infos, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)

  local easiest = infos[1]
  local union = {}

  for _, info in ipairs(infos) do
    for pack in pairs(info.packs) do
      union[pack] = true
    end
  end

  local extra_set = {}
  for pack in pairs(union) do
    if not easiest.packs[pack] then
      extra_set[pack] = true
    end
  end

  local extra = sorted_packs(extra_set)
  local plan = { levels = {} }

  plan.unlock_prerequisite = easiest.tech and easiest.tech.name or nil
  plan.icons = choose_icons(entries, infos, easiest, official_only)

  for level = 1, level_count do
    local added

    if level_count == 1 then
      added = #extra
    else
      added = math.floor(
        (level - 1) * #extra / (level_count - 1) + 0.5
      )
    end

    local set = {}
    for pack in pairs(easiest.packs) do
      set[pack] = true
    end

    for i = 1, added do
      set[extra[i]] = true
    end

    local packs = sorted_packs(set)
    local prerequisites, seen = {}, {}

    local function add_prerequisite(name)
      if name and not seen[name] then
        seen[name] = true
        prerequisites[#prerequisites + 1] = name
      end
    end

    if level == 1 then
      add_prerequisite(plan.unlock_prerequisite)
    end

    for _, pack in ipairs(packs) do
      local pack_tech = unlock_tech_for_pack(pack)
      if pack_tech then
        add_prerequisite(pack_tech.name)
      end
    end

    local ingredients = {}
    for _, pack in ipairs(packs) do
      ingredients[#ingredients + 1] = { pack, 1 }
    end

    plan.levels[level] = {
      ingredients = ingredients,
      prerequisites = prerequisites,
      count = math.max(
        1,
        math.floor(cost.base_count * (cost.growth ^ (level - 1)) + 0.5)
      ),
      time = cost.time,
    }
  end

  return plan
end

return M
