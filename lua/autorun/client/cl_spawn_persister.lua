local minigame_helper_exists = false
hook.Add("InitPostEntity", "spawnp check for minigame helper", function()
  minigame_helper_exists = (scripted_ents.GetType("brickpoint") ~= nil)
end)


if engine.ActiveGamemode() == "sandbox" then

  concommand.Add("spawnp_set_here", function(ply, cmd, args)
    ply:ConCommand("sv__spawnp_set_here")
  end)

  --alias for convenience
  concommand.Add("spawn", function (ply, cmd, args)
    ply:ConCommand("sv__spawnp_set_here")
  end)

  concommand.Add("spawnp_reset", function(ply, cmd, args)
    ply:ConCommand("sv__spawnp_reset")
  end)

  local auto_spawn = CreateClientConVar(
    "spawnp_save_pos_dc", 0, true, true,
    "Automatically save position when disconnecting", 0, 1
  )

  -- local spawn_set_key = CreateClientConVar(
  --   "spawnp_respawn_key", "", true, true)
  -- )

  hook.Add("AddToolMenuCategories", "spawn persister menu categories", function()
    spawnmenu.AddToolCategory("Utilities", "spawnp", "#Persistent Spawnpoints")
  end)

  hook.Add("PopulateToolMenu", "spawn persister menu populate", function()
    spawnmenu.AddToolMenuOption(
    "Utilities", "spawnp", "spawnp_settings", "#Settings", "", "", function(panel)
      panel:ClearControls()
      panel:CheckBox("Load where you last disconnected on connect", "spawnp_save_pos_dc")
      panel:Button("Set Spawn Here", "spawnp_set_here")
      panel:Button("Remove persistent spawnpoints", "sv__spawnp_reset")
      if minigame_helper_exists then
        panel:Button("Remove brick spawnpoints", "sv__spawnp_reset", "bricksonly")
        panel:Button("Remove ALL spawnpoints", "sv__spawnp_reset", "bricks")
      end
      panel:Help("We recommend running 'bind home spawn'\nto allow for easy spawn setting.")
      -- local binder = vgui.Create("DBinder", panel)
      -- function binder:OnChange(num)
      --   LocalPlayer():ConCommand("np__spawnp_set_here " .. input.GetKeyName(num))
      -- end
      -- panel:AddItem(binder)
    end)
  end)

end