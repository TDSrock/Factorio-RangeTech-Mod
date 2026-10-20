-- Finds all turrets and sorts them into categories. Data stage only.
-- The rules (and the tables behind them) live in lib/categories.lua.
local categories = require("lib.categories")

local M = {}

-- place_result -> item name, for every item that places an entity.
local function build_item_index()
  local index = {}
  for type_name in pairs(defines.prototypes["item"]) do
    for _, item in pairs(data.raw[type_name] or {}) do
      if item.place_result and not index[item.place_result] then
        index[item.place_result] = item.name
      end
    end
  end
  return index
end

-- Prototype tables that damage effects are usually delivered through (action_delivery references
-- a projectile, stream, beam or chain by name, and the damage is defined in that prototype).
local REFERENCE_TABLES = {
  projectile = "projectile",
  stream = "stream",
  beam = "beam",
  chain = "chain-active-trigger",
}

-- Sums damage amounts per damage type found anywhere inside a (possibly deeply nested) table,
-- following references to projectiles, streams, beams and chains.
local function scan_damage(node, found, depth, seen)
  if type(node) ~= "table" or depth > 14 or seen[node] then return end
  seen[node] = true
  if type(node.type) == "string" and type(node.amount) == "number" and data.raw["damage-type"][node.type] then
    found[node.type] = (found[node.type] or 0) + node.amount
  end
  for key, child in pairs(node) do
    if type(child) == "string" and REFERENCE_TABLES[key] then
      local referenced = data.raw[REFERENCE_TABLES[key]]
      if referenced and referenced[child] then
        scan_damage(referenced[child], found, depth + 1, seen)
      end
    else
      scan_damage(child, found, depth + 1, seen)
    end
  end
end

local function main_damage_type(attack_parameters)
  local found = {}
  scan_damage(attack_parameters.ammo_type, found, 0, {})
  local best, best_amount
  for damage_type, amount in pairs(found) do
    if not best_amount or amount > best_amount or (amount == best_amount and damage_type < best) then
      best, best_amount = damage_type, amount
    end
  end
  return best
end

-- Returns category, reason, and the ammo categories / damage type that could not be mapped.
local function classify(proto)
  if proto.type == "artillery-turret" then
    return categories.IGNORED, "artillery turret"
  end

  local known_group, known_reason = categories.known_turret(proto.name)
  if known_group then return known_group, "known turret rule: " .. known_reason end

  local unmapped = {}
  local ap = proto.attack_parameters
  if ap then
    local damage_type = main_damage_type(ap)
    local damage_group, damage_how
    if damage_type then damage_group, damage_how = categories.group_for_damage_type(damage_type) end

    local ammo_categories = ap.ammo_categories or (ap.ammo_category and { ap.ammo_category }) or {}
    for _, ammo_category in ipairs(ammo_categories) do
      local group, how = categories.group_for_ammo_category(ammo_category)
      if group then
        -- Generic vanilla categories (electric, flamethrower) are reused by mods for other weapon
        -- kinds; when the damage type points somewhere more specific, that wins.
        if categories.GENERIC_AMMO_CATEGORIES[ammo_category] and damage_group
          and damage_group ~= group and damage_group ~= categories.IGNORED then
          return damage_group, "damage type '" .. damage_type .. "' (" .. damage_how ..
            ") refines generic ammo category '" .. ammo_category .. "'"
        end
        return group, "ammo category '" .. ammo_category .. "' (" .. how .. ")"
      end
      unmapped[#unmapped + 1] = "ammo category '" .. ammo_category .. "'"
    end

    if damage_type then
      if damage_group then
        return damage_group, "damage type '" .. damage_type .. "' (" .. damage_how .. ")"
      end
      unmapped[#unmapped + 1] = "damage type '" .. damage_type .. "'"
    end
  end

  return "other", "nothing recognised", unmapped
end

-- Returns:
--   entries         list of { proto, item, category } for turrets that can get research
--   classification  { [turret name] = category id } for ALL scanned turrets (incl. ignored)
--   reasons         { [turret name] = why it got that category }
function M.collect(overrides, warnings)
  local items = build_item_index()
  local entries, classification, reasons = {}, {}, {}

  local types = {}
  for _, t in ipairs(categories.TURRET_TYPES) do types[#types + 1] = t end
  for _, t in ipairs(categories.IGNORED_TYPES) do types[#types + 1] = t end

  for _, type_name in ipairs(types) do
    local names = {}
    for name in pairs(data.raw[type_name] or {}) do names[#names + 1] = name end
    table.sort(names)

    for _, name in ipairs(names) do
      local proto = data.raw[type_name][name]
      local is_artillery = (proto.type == "artillery-turret")
      local placeable = items[name] ~= nil
      local usable = is_artillery or (placeable and proto.attack_parameters and proto.attack_parameters.range)

      if usable then
        local category, reason, unmapped = classify(proto)

        if category == "other" and unmapped and #unmapped > 0 then
          warnings[#warnings + 1] = "Turret '" .. name .. "' is in 'other': unknown " ..
            table.concat(unmapped, ", ") .. ". Add it to lib/categories.lua or use the override setting."
        end

        local override = overrides[name]
        if override then
          if is_artillery and override ~= categories.IGNORED then
            warnings[#warnings + 1] = "Artillery turrets cannot be reassigned, '" .. name .. "' stays ignored."
          else
            category, reason = override, "override setting"
          end
        end

        classification[name] = category
        reasons[name] = reason

        if category ~= categories.IGNORED then
          entries[#entries + 1] = { proto = proto, item = items[name], category = category }
        end
      end
    end
  end

  for name in pairs(overrides) do
    if classification[name] == nil then
      warnings[#warnings + 1] = "Override for unknown or unsupported turret '" .. name .. "' ignored."
    end
  end

  return entries, classification, reasons
end

return M
