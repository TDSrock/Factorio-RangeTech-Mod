-- Resolves the startup settings (preset or custom) into one config table. Data stage only.
local categories = require("lib.categories")
local presets = require("lib.presets")

local M = {}

local function value(name)
  local setting = settings.startup[name]
  return setting and setting.value
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "gun-turret=laser; some-turret = ignored" -> { ["gun-turret"] = "laser", ... }
local function parse_overrides(text, warnings)
  local overrides = {}
  for entry in string.gmatch(text or "", "[^;,\n\r]+") do
    entry = trim(entry)
    if entry ~= "" then
      local name, cat = string.match(entry, "^([^=:]+)[=:](.+)$")
      if name then
        name, cat = trim(name), string.lower(trim(cat))
      end
      if name and name ~= "" and categories.is_valid(cat) then
        overrides[name] = cat
      else
        warnings[#warnings + 1] = "Invalid category override ignored: '" .. entry .. "'"
      end
    end
  end
  return overrides
end

function M.load()
  local warnings = {}
  local preset = value("rangetech-preset") or "percent"
  local config = { preset = preset, categories = {}, warnings = warnings }

  config.overrides = parse_overrides(value("rangetech-overrides"), warnings)

  if preset == "custom" then
    for _, id in ipairs(categories.IDS) do
      config.categories[id] = {
        levels = value("rangetech-" .. id .. "-levels"),
        mode = value("rangetech-" .. id .. "-mode"),
        amount = value("rangetech-" .. id .. "-amount"),
      }
    end
    config.cost = {
      base_count = value("rangetech-cost-base"),
      growth = value("rangetech-cost-growth"),
      time = value("rangetech-research-time"),
    }
  else
    local p = presets[preset] or presets.percent
    for _, id in ipairs(categories.IDS) do
      config.categories[id] = { levels = p.levels, mode = p.mode, amount = p.amount }
    end
    config.cost = {
      base_count = presets.cost.base_count,
      growth = presets.cost.growth,
      time = presets.cost.time,
    }
  end

  return config
end

return M
