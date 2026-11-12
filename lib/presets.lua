-- Built-in presets. "custom" in the settings uses the individual settings instead.
return {
  -- Every category: +10% of the turret's base range per level, 5 levels (+50% at the end,
  -- the same as a legendary quality turret).
  percent = { mode = "percent", amount = 10, levels = 5 },

  -- Every category: +3 tiles per level, 5 levels (+15 tiles at the end).
  flat = { mode = "flat", amount = 3, levels = 5 },

  conservative = { mode = "percent", amount = 5, levels = 5 },
  ["long-range"] = { mode = "percent", amount = 20, levels = 5 },
  gradual = { mode = "percent", amount = 5, levels = 10 },
  expensive = {
    mode = "percent", amount = 10, levels = 5,
    cost = { base_count = 500, growth = 2, time = 30 },
  },

  -- Default research cost for presets without their own cost, and for custom settings.
  -- Amount of science packs for level n = base_count * growth^(n - 1).
  cost = { base_count = 100, growth = 1.5, time = 30 },
}
