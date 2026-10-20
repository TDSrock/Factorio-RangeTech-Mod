-- Shared constants for the category system (used by settings, data and control stages).
--
-- HOW A TURRET GETS ITS CATEGORY (see lib/classify.lua), first match wins:
--   0. the player's override setting
--   1. artillery turrets are always ignored
--   2. KNOWN_TURRETS: explicit rules for modded turrets that need special handling
--   3. its ammo category: exact name (AMMO_CATEGORY_GROUP), then name pattern
--   4. the main damage type it deals: exact name (DAMAGE_TYPE_GROUP), then name pattern
--   5. otherwise "other"
--
-- TO ADD SUPPORT FOR A MOD: add its ammo category / damage type to the tables below (or a
-- pattern, if the mod is one of several that use similar names). If it needs a brand new
-- category, add the id to IDS and add its locale lines (category name and the five
-- mod-setting lines per category in locale/en/locale.cfg).
local M = {}

M.PREFIX = "rangetech-"

-- Categories that get settings and research. Order is the display order.
M.IDS = {
  "bullet", "shotgun", "cannon", "railgun", "grenade",
  "missile", "flame", "laser", "electric", "cold", "acid",
  "support", "other",
}

-- Pseudo-category: turrets the mod does nothing with.
M.IGNORED = "ignored"

-- Prototype types that are scanned for turrets.
M.TURRET_TYPES = { "ammo-turret", "electric-turret", "fluid-turret" }

-- Turret-like types that are always ignored (their range works differently
-- and vanilla already has artillery range research).
M.IGNORED_TYPES = { "artillery-turret" }

-- Ammo category name -> category (exact match).
M.AMMO_CATEGORY_GROUP = {
  ["bullet"] = "bullet",
  ["shotgun-shell"] = "shotgun",
  ["cannon-shell"] = "cannon",
  ["railgun"] = "railgun",
  ["grenade"] = "grenade",
  ["capsule-launcher"] = "grenade",   -- Rampant Arsenal capsule turrets
  ["capsule"] = "grenade",            -- Additional Turrets laser/capsule turret
  ["turret-capsule"] = "support",     -- Rampant Arsenal medic turret
  ["rocket"] = "missile",
  ["flamethrower"] = "flame",
  ["laser"] = "laser",
  ["tesla"] = "electric",
  ["electric"] = "electric",
  ["artillery-shell"] = "ignored",
}

-- Name fragments for modded ammo categories. Checked in order, after the exact table.
-- The name is lower-cased and wrapped in dashes ("-name-"), so "-ice-" matches "ice" and
-- "ice-shard" but not "device".
M.AMMO_CATEGORY_PATTERNS = {
  { "rocket", "missile" }, { "missile", "missile" },
  { "shotgun", "shotgun" },
  { "cannon", "cannon" },
  { "railgun", "railgun" }, { "-rail-", "railgun" },
  { "grenade", "grenade" }, { "capsule", "grenade" },
  { "heal", "support" }, { "medic", "support" },
  { "flame", "flame" },
  { "laser", "laser" },
  { "tesla", "electric" },
  { "artillery", "ignored" }, { "howitzer", "ignored" },
  { "bullet", "bullet" },
  { "acid", "acid" },
  { "cold", "cold" }, { "cryo", "cold" }, { "frost", "cold" }, { "freez", "cold" }, { "-ice-", "cold" },
}

-- Damage type name -> category (exact match). Used when the ammo category is unknown.
M.DAMAGE_TYPE_GROUP = {
  ["laser"] = "laser",
  ["fire"] = "flame",
  ["electric"] = "electric",
  ["acid"] = "acid",
  ["poison"] = "acid",
  ["cold"] = "cold",
  ["healing"] = "support",   -- Rampant Arsenal medic turret
}

-- Some mods reuse a generic vanilla ammo category for a different kind of weapon (for example
-- Rampant Arsenal and Additional Turrets give their laser turrets ammo category "electric",
-- and acid throwers use "flamethrower"). For these, the damage type decides when it points
-- somewhere more specific.
M.GENERIC_AMMO_CATEGORIES = {
  ["electric"] = true,
  ["flamethrower"] = true,
}

-- Name fragments for modded damage types.
M.DAMAGE_TYPE_PATTERNS = {
  { "cold", "cold" }, { "cryo", "cold" }, { "frost", "cold" }, { "freez", "cold" }, { "-ice-", "cold" },
  { "acid", "acid" }, { "poison", "acid" }, { "toxic", "acid" },
  { "fire", "flame" }, { "flame", "flame" }, { "burn", "flame" }, { "thermal", "flame" },
  { "laser", "laser" },
  { "electr", "electric" }, { "lightning", "electric" }, { "tesla", "electric" }, { "shock", "electric" },
  { "heal", "support" },
}

-- Explicit rules for modded turrets, matched against the turret's entity name (a plain
-- substring). Checked before ammo category and damage type.
M.KNOWN_TURRETS = {
  -- Repair turrets heal and build instead of shooting, and their reach is not a normal turret
  -- range. Ignored by default; use the override setting to change that, e.g. "repair-turret=other".
  { pattern = "repair", group = "ignored", reason = "not compatible: repair turret, its reach is not a normal turret range" },

  -- Additional Turrets (original and revived): these are NOT real, self-contained turrets. A
  -- placed base turret (at_A1_b, at_A2_b, at_CR_b, at_LC_b) is expanded by the mod's script into
  -- several helper entities (at_*_i1, at_*_s1, ...), and the weapon is fired by script (artillery
  -- shells, cannon/rocket volleys, capsules). They also swap entities when the player picks a
  -- mode. Neither a longer prototype range nor this mod's entity swapping works with that.
  { pattern = "at_a1_", group = "ignored", reason = "not compatible: scripted multi-entity turret (Additional Turrets)" },
  { pattern = "at_a2_", group = "ignored", reason = "not compatible: scripted multi-entity turret (Additional Turrets)" },
  { pattern = "at_cr_", group = "ignored", reason = "not compatible: scripted multi-entity turret (Additional Turrets)" },
  { pattern = "at_lc_", group = "ignored", reason = "not compatible: scripted multi-entity turret (Additional Turrets)" },

  -- Universal Turret changes a turret's weapon type at runtime by swapping entities. The name
  -- is a guess from the mod's name; check the log if it is not picked up.
  { pattern = "uniturret", group = "ignored", reason = "not compatible: turret that another mod swaps at runtime (Universal Turret)" },
}

local valid = { [M.IGNORED] = true }
for _, id in ipairs(M.IDS) do valid[id] = true end

function M.is_valid(id)
  return valid[id] == true
end

local function normalise(name)
  local lowered = string.lower(name):gsub("_", "-")
  return "-" .. lowered .. "-"
end

local function match(name, exact, patterns)
  if exact[name] then return exact[name], "exact" end
  local haystack = normalise(name)
  for _, entry in ipairs(patterns) do
    if string.find(haystack, entry[1], 1, true) then
      return entry[2], "pattern '" .. entry[1] .. "'"
    end
  end
end

-- Returns group, how (or nil).
function M.group_for_ammo_category(name)
  return match(name, M.AMMO_CATEGORY_GROUP, M.AMMO_CATEGORY_PATTERNS)
end

function M.group_for_damage_type(name)
  return match(name, M.DAMAGE_TYPE_GROUP, M.DAMAGE_TYPE_PATTERNS)
end

-- Returns group, reason (or nil).
function M.known_turret(name)
  local lowered = string.lower(name)
  for _, rule in ipairs(M.KNOWN_TURRETS) do
    if string.find(lowered, rule.pattern, 1, true) then
      return rule.group, rule.reason
    end
  end
end

return M
