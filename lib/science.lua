-- Works out which science packs each range research needs. Data stage only.
--
-- For a category:
--   * level 1 needs the packs of the "easiest" turret's unlock technology,
--   * the last level needs the union of the packs of ALL turrets in the category,
--   * levels in between add the missing packs gradually (cheapest pack first).
local M = {}

local FALLBACK_PACK = "automation-science-pack"

---------------------------------------------------------------------------
-- Indexes
---------------------------------------------------------------------------

local unlock_index -- recipe name -> list of technologies unlocking it
local result_index -- item name -> list of recipe names producing it

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

-- Set of science pack names a technology needs. Technologies without a unit
-- (research triggers) inherit from their prerequisites.
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
        for pack in pairs(tech_packs(pre, (depth or 0) + 1)) do packs[pack] = true end
      end
    end
  end
  return packs
end

local function count_keys(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- Rough "how hard is it to unlock this" measure: fewer packs, then lower unit count.
local function tech_cost(tech)
  local count = tech.unit and tech.unit.count or 0
  return count_keys(tech_packs(tech)) * 1e9 + count
end

local function cheapest(techs)
  local best, best_cost
  for _, tech in ipairs(techs) do
    if tech.enabled ~= false then
      local cost = tech_cost(tech)
      if not best_cost or cost < best_cost or (cost == best_cost and tech.name < best.name) then
        best, best_cost = tech, cost
      end
    end
  end
  return best
end

-- The technology that unlocks an item (via a recipe), or nil if it is available from the start.
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

local function sorted_packs(set)
  local list = {}
  for pack in pairs(set) do list[#list + 1] = pack end
  table.sort(list, function(a, b)
    local oa = (data.raw.tool[a] and data.raw.tool[a].order) or "zzz"
    local ob = (data.raw.tool[b] and data.raw.tool[b].order) or "zzz"
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  return list
end

local function icons_of(tech)
  if tech.icons then return table.deepcopy(tech.icons) end
  if tech.icon then
    return { { icon = tech.icon, icon_size = tech.icon_size or 256 } }
  end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- entries: list of { proto, item, category } of ONE category.
-- Returns { icons = ..., unlock_prerequisite = tech name or nil, levels = { [n] = { packs, prerequisites, count, time } } }
function M.plan(entries, level_count, cost)
  -- Per turret: unlock tech and pack set.
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
      cost = (tech and tech_cost(tech) or 0),
    }
  end

  -- Easiest turret = fewest packs / cheapest unlock.
  table.sort(infos, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)
  local easiest = infos[1]

  local union = {}
  for _, info in ipairs(infos) do
    for pack in pairs(info.packs) do union[pack] = true end
  end

  -- Packs that are in the union but not needed for the easiest turret.
  local extra_set = {}
  for pack in pairs(union) do
    if not easiest.packs[pack] then extra_set[pack] = true end
  end
  local extra = sorted_packs(extra_set)

  local plan = { levels = {} }
  plan.unlock_prerequisite = easiest.tech and easiest.tech.name or nil

  -- Icon: unlock tech of the easiest turret, else of any turret in the category.
  if easiest.tech then plan.icons = icons_of(easiest.tech) end
  if not plan.icons then
    for _, info in ipairs(infos) do
      if info.tech then
        plan.icons = icons_of(info.tech)
        if plan.icons then break end
      end
    end
  end
  if not plan.icons and data.raw.technology["military"] then
    plan.icons = icons_of(data.raw.technology["military"])
  end

  for level = 1, level_count do
    local added
    if level_count == 1 then
      added = #extra
    else
      added = math.floor((level - 1) * #extra / (level_count - 1) + 0.5)
    end

    local set = {}
    for pack in pairs(easiest.packs) do set[pack] = true end
    for i = 1, added do set[extra[i]] = true end
    local packs = sorted_packs(set)

    local prerequisites, seen = {}, {}
    local function add_prerequisite(name)
      if name and not seen[name] then
        seen[name] = true
        prerequisites[#prerequisites + 1] = name
      end
    end
    if level == 1 then add_prerequisite(plan.unlock_prerequisite) end
    for _, pack in ipairs(packs) do
      local pack_tech = unlock_tech_for_pack(pack)
      if pack_tech then add_prerequisite(pack_tech.name) end
    end

    local ingredients = {}
    for _, pack in ipairs(packs) do
      ingredients[#ingredients + 1] = { pack, 1 }
    end

    plan.levels[level] = {
      ingredients = ingredients,
      prerequisites = prerequisites, -- previous level is added by the caller
      count = math.max(1, math.floor(cost.base_count * (cost.growth ^ (level - 1)) + 0.5)),
      time = cost.time,
    }
  end

  return plan
end

return M
