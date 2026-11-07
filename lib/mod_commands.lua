-- Keep this helper self-contained so each mod can ship its own copy.
local M = {}
local mod_name = script.mod_name
local locale = mod_name .. "-commands."

function M.reply(command, message)
  if command.player_index then
    local player = game.get_player(command.player_index)
    if player then player.print(message) end
  else
    localised_print(message)
    rcon.print(message)
  end
end

function M.register(actions)
  actions = actions or {}
  local by_name = {}
  for _, action in ipairs(actions) do
    by_name[action.name] = action.run
    if action.alias then commands.add_command(action.alias, action.help, action.run) end
  end

  local usage = "/" .. mod_name
  local function show_intro(command)
    M.reply(command, { locale .. "version", script.active_mods[mod_name] })
    M.reply(command, { locale .. "summary" })
  end

  commands.add_command(mod_name, { locale .. "console-help", usage }, function(command)
    local argument = (command.parameter or ""):match("^%s*(.-)%s*$"):lower()
    if argument == "" then
      show_intro(command)
      M.reply(command, { locale .. "hint", usage })
    elseif argument == "help" or argument == "?" then
      show_intro(command)
      M.reply(command, { locale .. "console-help", usage })
      for _, action in ipairs(actions) do
        local syntax = usage .. " " .. action.name
        if action.alias then syntax = syntax .. " (/" .. action.alias .. ")" end
        M.reply(command, { locale .. "entry", syntax, action.help })
      end
    elseif by_name[argument] then
      by_name[argument](command)
    else
      M.reply(command, { locale .. "unknown", argument, usage })
    end
  end)
end

return M
