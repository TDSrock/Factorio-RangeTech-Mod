local categories = require("lib.categories")
local presets = require("lib.presets")

local extend = {}

-- Preset dropdown: "percent" and "flat" ready-made, "custom" uses the per-category settings below.
extend[#extend + 1] = {
  type = "string-setting",
  name = "rangetech-preset",
  setting_type = "startup",
  default_value = "percent",
  allowed_values = { "percent", "flat", "custom" },
  order = "a-preset",
}

-- Move turrets between categories: "gun-turret=laser; some-modded-turret=ignored".
extend[#extend + 1] = {
  type = "string-setting",
  name = "rangetech-overrides",
  setting_type = "startup",
  default_value = "",
  allow_blank = true,
  auto_trim = true,
  order = "b-overrides",
}

-- Research cost (only used with the "custom" preset).
extend[#extend + 1] = {
  type = "int-setting",
  name = "rangetech-cost-base",
  setting_type = "startup",
  default_value = presets.cost.base_count,
  minimum_value = 1,
  maximum_value = 100000,
  order = "c-1-cost-base",
}
extend[#extend + 1] = {
  type = "double-setting",
  name = "rangetech-cost-growth",
  setting_type = "startup",
  default_value = presets.cost.growth,
  minimum_value = 1,
  maximum_value = 10,
  order = "c-2-cost-growth",
}
extend[#extend + 1] = {
  type = "int-setting",
  name = "rangetech-research-time",
  setting_type = "startup",
  default_value = presets.cost.time,
  minimum_value = 1,
  maximum_value = 600,
  order = "c-3-research-time",
}

-- Per category (only used with the "custom" preset).
for index, id in ipairs(categories.IDS) do
  local prefix = "rangetech-" .. id .. "-"
  extend[#extend + 1] = {
    type = "int-setting",
    name = prefix .. "levels",
    setting_type = "startup",
    default_value = presets.percent.levels,
    minimum_value = 0,
    maximum_value = 20,
    order = "d-" .. index .. "-1",
  }
  extend[#extend + 1] = {
    type = "string-setting",
    name = prefix .. "mode",
    setting_type = "startup",
    default_value = presets.percent.mode,
    allowed_values = { "percent", "flat" },
    order = "d-" .. index .. "-2",
  }
  extend[#extend + 1] = {
    type = "double-setting",
    name = prefix .. "amount",
    setting_type = "startup",
    default_value = presets.percent.amount,
    minimum_value = 0.1,
    maximum_value = 1000,
    order = "d-" .. index .. "-3",
  }
end

data:extend(extend)
