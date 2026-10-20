-- Built-in presets. "custom" in the settings uses the individual settings instead.
return {
  -- Every category: +10% of the turret's base range per level, 5 levels (+50% at the end,
  -- the same as a legendary quality turret).
  percent = { mode = "percent", amount = 10, levels = 5 },

  -- Every category: +3 tiles per level, 5 levels (+15 tiles at the end).
  flat = { mode = "flat", amount = 3, levels = 5 },

  -- Research cost, shared by both presets (and the default for custom).
  -- Amount of science packs for level n = base_count * growth^(n - 1).
  cost = { base_count = 100, growth = 1.5, time = 30 },
}
