-- Prototype stage: runs after every other mod's data stage, so every turret (modded or not)
-- exists by now.
--
-- For every turret that is not ignored this creates hidden copies with a longer range (one per
-- research level) and the range research itself. control.lua swaps turrets for the right copy.
-- Quality is a runtime property of the entity, so it works on top of the copies automatically.
local categories = require("lib.categories")
local config = require("lib.config").load()
local classify = require("lib.classify")
local science = require("lib.science")
local icon_lib = require("lib.icons")

local PREFIX = categories.PREFIX
local warnings = config.warnings

local function fmt(number)
  return string.format("%g", number)
end

local entries, classification, reasons = classify.collect(config.overrides, warnings)

local by_category = {}
for _, entry in ipairs(entries) do
  by_category[entry.category] = by_category[entry.category] or {}
  table.insert(by_category[entry.category], entry)
end

local function new_range(base_range, settings_for_category, level)
  if settings_for_category.mode == "flat" then
    return base_range + settings_for_category.amount * level
  end
  return base_range * (1 + settings_for_category.amount / 100 * level)
end

-- Localised list of turret names for the technology description.
local function turret_list(list)
  local names = { "" }
  local shown = math.min(#list, 8)
  for i = 1, shown do
    local proto = list[i].proto
    if i > 1 then names[#names + 1] = ", " end
    names[#names + 1] = proto.localised_name or { "entity-name." .. proto.name }
  end
  if #list > shown then names[#names + 1] = ", ..." end
  return names
end

local mod_data = {
  turrets = {},       -- base turret name -> { category }
  variants = {},      -- variant name -> { base, level }
  categories = {},    -- category -> { levels, tech_prefix, mode, amount }
  techs = {},         -- technology name -> category
  plans = {},         -- category -> list of { level, count, time, packs } for the report
  classification = classification,
  reasons = reasons,
  warnings = warnings,
  variant_prefix = PREFIX .. "var-",
}

for _, category in ipairs(categories.IDS) do
  local list = by_category[category]
  local cfg = config.categories[category]

  if list and #list > 0 and cfg.levels and cfg.levels > 0 then
    local plan = science.plan(list, cfg.levels, config.cost, config.icon_official_only)

    if not plan.icons then
      warnings[#warnings + 1] = "No technology icon found for category '" .. category .. "', no research created."
    else
      local new_prototypes = {}

      -- Hidden turret variants.
      for _, entry in ipairs(list) do
        local base = entry.proto
        local group = base.fast_replaceable_group or (PREFIX .. base.name)
        base.fast_replaceable_group = group
        mod_data.turrets[base.name] = {
          category = category,
          base_range = base.attack_parameters.range,
          ranges = {},    -- range per level, for the report
        }

        for level = 1, cfg.levels do
          local variant = table.deepcopy(base)
          variant.name = mod_data.variant_prefix .. base.name .. "-" .. level
          variant.localised_name = base.localised_name or { "entity-name." .. base.name }
          variant.hidden = true
          variant.hidden_in_factoriopedia = true
          variant.factoriopedia_alternative = base.name
          variant.placeable_by = { item = entry.item, count = 1 }
          variant.fast_replaceable_group = group

          local base_range = base.attack_parameters.range
          local range = new_range(base_range, cfg, level)
          variant.attack_parameters.range = range
          if variant.prepare_range then
            variant.prepare_range = variant.prepare_range * (range / base_range)
          end

          mod_data.variants[variant.name] = { base = base.name, level = level }
          mod_data.turrets[base.name].ranges[level] = range
          new_prototypes[#new_prototypes + 1] = variant
        end
      end

      -- Technologies.
      mod_data.categories[category] = {
        levels = cfg.levels,
        tech_prefix = PREFIX .. category .. "-",
        mode = cfg.mode,
        amount = cfg.amount,
      }

      local affects = turret_list(list)
      for level = 1, cfg.levels do
        local level_plan = plan.levels[level]
        local tech_name = PREFIX .. category .. "-" .. level

        local prerequisites = {}
        for _, name in ipairs(level_plan.prerequisites) do prerequisites[#prerequisites + 1] = name end
        if level > 1 then prerequisites[#prerequisites + 1] = PREFIX .. category .. "-" .. (level - 1) end

        local category_name = { "rangetech.category-" .. category }
        local description_key = (cfg.mode == "flat") and "rangetech.effect-flat" or "rangetech.effect-percent"
        local effect = { description_key, fmt(cfg.amount), category_name, fmt(cfg.amount * level) }

        new_prototypes[#new_prototypes + 1] = {
          type = "technology",
          name = tech_name,
          localised_name = { "rangetech.tech-name", category_name, tostring(level) },
          localised_description = { "", effect, "\n", { "rangetech.affects", affects } },
          icons = icon_lib.compose(plan.icons),
          effects = { { type = "nothing", effect_description = effect } },
          prerequisites = prerequisites,
          unit = {
            count = level_plan.count,
            ingredients = level_plan.ingredients,
            time = level_plan.time,
          },
          upgrade = true,
          order = "e-z[rangetech]-" .. category .. "-" .. string.format("%03d", level),
        }
        mod_data.techs[tech_name] = category

        local packs = {}
        for _, ingredient in ipairs(level_plan.ingredients) do packs[#packs + 1] = ingredient[1] end
        mod_data.plans[category] = mod_data.plans[category] or {}
        table.insert(mod_data.plans[category], {
          level = level,
          count = level_plan.count,
          time = level_plan.time,
          packs = packs,
        })
      end

      data:extend(new_prototypes)
    end
  end
end

data:extend({
  { type = "mod-data", name = "rangetech-config", data = mod_data },
})

-- Classification is also written to factorio-current.log so it can be checked without a save.
local names = {}
for name in pairs(classification) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
  log("[range-tech] " .. name .. " -> " .. classification[name] .. " (" .. tostring(reasons[name]) .. ")")
end
for _, warning in ipairs(warnings) do
  log("[range-tech] WARNING: " .. warning)
end
