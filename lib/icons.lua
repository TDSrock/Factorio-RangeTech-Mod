-- Technology icons. Data stage only.
--
-- WHAT CAN AND CANNOT BE CHECKED: Lua in the data stage cannot open image files, so the real
-- pixel size of a PNG is unknown here, and a size mismatch only shows up later when the engine
-- builds its sprite atlas (too late to back out). What this module does instead:
--   * it copies an icon only when every layer is structurally sound (a .png path, a sensible
--     icon_size, the size is carried onto each layer, sane scale), exactly as the other mod
--     defines it for its own technology, so it loads wherever that technology loads;
--   * anything that fails those checks makes the caller fall back to a vanilla icon;
--   * the startup setting "Technology icons" can force official (vanilla) art only;
--   * assets that belong to THIS mod are checked at build time instead (scripts/validate_assets.sh,
--     run in CI), where the real file can be inspected.
local M = {}

-- Path of an overlay image that belongs to this mod, for the "range" symbol on every research
-- (see README, "Range overlay icon"). Leave nil to use the one that vanilla uses.
--   M.CUSTOM_OVERLAY = "__range-tech__/graphics/range-overlay.png"
M.CUSTOM_OVERLAY = nil

local OFFICIAL_PREFIXES = { "__base__/", "__space-age__/", "__quality__/", "__elevated-rails__/", "__core__/" }

local function is_official(path)
  for _, prefix in ipairs(OFFICIAL_PREFIXES) do
    if string.sub(path, 1, #prefix) == prefix then return true end
  end
  return false
end

-- Vanilla bakes its small effect symbols (damage, range, speed, ...) into technology icons as an
-- extra layer from __core__/graphics/icons/technology/constants/.
local function is_constant_overlay(path)
  return string.find(path, "/constants/", 1, true) ~= nil
end

-- Layers of a technology's icon, each with its own icon_size (a technology may declare
-- icon_size once on itself instead of on every layer, and the copy is a different prototype).
local function layers_of(tech)
  local layers
  if tech.icons then
    layers = table.deepcopy(tech.icons)
  elseif tech.icon then
    layers = { { icon = tech.icon, icon_size = tech.icon_size, icon_mipmaps = tech.icon_mipmaps } }
  end
  if not layers then return nil end
  for _, layer in ipairs(layers) do
    layer.icon_size = layer.icon_size or tech.icon_size
    if layer.icon_mipmaps == nil then layer.icon_mipmaps = tech.icon_mipmaps end
  end
  return layers
end

local function layer_is_valid(layer)
  if type(layer.icon) ~= "string" or not string.find(layer.icon, "%.png$") then return false end
  if type(layer.icon_size) ~= "number" or layer.icon_size < 8 or layer.icon_size > 1024 then return false end
  if layer.scale ~= nil and (type(layer.scale) ~= "number" or layer.scale <= 0) then return false end
  if layer.shift ~= nil and type(layer.shift) ~= "table" then return false end
  return true
end

-- Icon layers of a technology, or nil when anything about them looks wrong.
-- Effect symbols (damage, range, ...) are removed, a range symbol is added later.
-- official_only: accept official (vanilla / DLC) art only.
function M.from_tech(tech, official_only)
  local layers = layers_of(tech)
  if not layers then return nil end

  local kept = {}
  for _, layer in ipairs(layers) do
    if not layer_is_valid(layer) then return nil end
    if official_only and not is_official(layer.icon) then return nil end
    if not is_constant_overlay(layer.icon) then kept[#kept + 1] = layer end
  end
  if #kept == 0 then return nil end
  return kept
end

local overlay_cache -- false = looked, nothing found

-- The "range" symbol layer(s) that go on top of every research icon.
-- Found by reading the artillery range research, which vanilla gives exactly this symbol, so no
-- path is hardcoded. A custom image (M.CUSTOM_OVERLAY) takes the position and size from that
-- layer, or from defaults when none is found.
function M.range_overlay()
  if overlay_cache ~= nil then return overlay_cache or nil end

  local names = {}
  for name in pairs(data.raw.technology or {}) do names[#names + 1] = name end
  table.sort(names)

  local found
  for _, name in ipairs(names) do
    local tech = data.raw.technology[name]
    local is_range_tech = false
    for _, effect in pairs(tech.effects or {}) do
      if effect.type == "artillery-range" then is_range_tech = true break end
    end

    if is_range_tech then
      local layers = layers_of(tech)
      if layers then
        local overlay = {}
        for _, layer in ipairs(layers) do
          if type(layer.icon) == "string" and is_constant_overlay(layer.icon)
            and is_official(layer.icon) and layer_is_valid(layer) then
            overlay[#overlay + 1] = layer
          end
        end
        if #overlay > 0 then
          found = overlay
          break
        end
      end
    end
  end

  if M.CUSTOM_OVERLAY then
    local custom = found and table.deepcopy(found[1]) or { icon_size = 128, shift = { 100, 100 } }
    custom.icon = M.CUSTOM_OVERLAY
    found = { custom }
  end

  overlay_cache = found or false
  return found
end

-- Base icon layers + range symbol.
function M.compose(base_layers)
  local layers = table.deepcopy(base_layers)
  local overlay = M.range_overlay()
  if overlay then
    for _, layer in ipairs(overlay) do layers[#layers + 1] = table.deepcopy(layer) end
  end
  return layers
end

return M
