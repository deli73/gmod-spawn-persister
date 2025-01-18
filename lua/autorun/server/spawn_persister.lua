local sfs = IncludeCS("spawn_persister/thirdparty/sfs.lua")

local function getPersistFile(append)
  if append then
    append = append .. "_"
  else
    append = ""
  end
  local PersistPage = GetConVarString("sbox_persist"):Trim()
  if PersistPage == "" then return nil end
  file.CreateDir("persist/spawnpoints")
  return "persist/spawnpoints/" .. game.GetMap() .. "_" .. append .. PersistPage .. ".dat"
end

local SPAWN_POS = "PersistentSpawnPos"
local SPAWN_ANG = "PersistentSpawnAngle"
local SPAWN_DUCK = "PersistentSpawnDucking"
--[[
  Player networked values:
  "PersistentSpawnPos" = Vector
  "PersistentSpawnAngle" = Angle

  Spawnpoint table format (also for dc points):
  <SteamID> = {
    "pos" = Vector
    "ang" = Angle
    "duck" = bool
  }
]]--

local playerSpawns = {}
local playerDCPoints = {}

local function printDebug(str, ...)
  MsgC( Color( 180, 42, 0 ), "[SpawnPersister DEBUG] ", color_white, string.format( str, ... ), "\n" )
end

local function printMsg(str, ...)
  MsgC( Color( 0, 180, 180 ), "[SpawnPersister] ", color_white, string.format( str, ... ), "\n" )
end

local cv_saveBots = CreateConVar(
  "spawnp_c_savebots", "0", FCVAR_CHEAT,
  "Allow spawn and disconnect points of bots to be set and saved."
)

local function enterCollidingVehicle(ply)
  local phys = ply:GetPhysicsObject()
  if not IsValid(phys) then return end
  if phys:IsPenetrating() then --flushed emoji??
    local mins = ply:OBBMins()
    local maxs = ply:OBBMaxs()
    local startpos = ply:GetPos()
    local tr = util.TraceHull( {
      start = startpos,
      endpos = startpos,
      maxs = maxs,
      mins = mins,
      filter = ply,
      collisiongroup = COLLISION_GROUP_VEHICLE,
      ignoreworld = true
    } )
    if tr.Hit then
      local vehicle = tr.Entity
      ply:EnterVehicle(vehicle)
    end
  end
end

local function savePlayerSpawns()
  printMsg("Saving Spawns...")
  local tabSize = #(table.GetKeys(playerSpawns))
  -- write as json
  local encoded, err = sfs.encode(playerSpawns)
  if err and tabSize > 0 then --if save failed and not empty
    ErrorNoHalt("[SpawnPersister ERROR] Encoding error in spawn saving!")
    return
  end
  --if tabSize == 0 then return end
  file.Write(getPersistFile(), encoded)
  printMsg("Spawns Saved!")
end

local function savePlayerDCs()
  printMsg("Saving reconnection points...")
  local tabSize = #(table.GetKeys(playerDCPoints))
  -- write as json
  local encoded, err = sfs.encode(playerDCPoints)
  if err and tabSize > 0 then --if save failed and not empty
    ErrorNoHalt("[SpawnPersister ERROR] Encoding error in reconnection point saving!")
    return
  end
  --if tabSize == 0 then return end
  file.Write(getPersistFile("dcpoints"), encoded)
  printMsg("Reconnection points saved!")
end

local function setPlayerSpawn(ply)
  if not IsValid(ply) then return end
  if not cv_saveBots:GetBool() and ply:IsBot() then return end
  if ply:InVehicle() then
    ply:PrintMessage(HUD_PRINTCENTER, "Can't set spawn in vehicles!")
    --note: you can LOG OUT in vehicles tho
    return
  end
  ply:SetNW2Vector(SPAWN_POS, ply:GetPos())
  ply:SetNW2Angle(SPAWN_ANG, ply:LocalEyeAngles())
  ply:SetNW2Bool(SPAWN_DUCK, ply:Crouching())
  --override brick spawn
  ply.SuperCoolBrickSpawn = nil
  ply:SetNWVector("SpawnPos", nil)
  --save spawnpoint to table
  local spawnTab = {}
  spawnTab["pos"] = ply:GetNW2Vector(SPAWN_POS)
  spawnTab["ang"] = ply:GetNW2Angle(SPAWN_ANG)
  spawnTab["duck"] = ply:GetNW2Bool(SPAWN_ANG)
  playerSpawns[ply:SteamID()] = spawnTab
  ply:PrintMessage(HUD_PRINTCENTER, "Set your spawn!")
  printMsg("Set player spawn for " .. ply:Name())
end

local function setPlayerDC(ply)
  if not cv_saveBots:GetBool() and ply:IsBot() then return end
  local tab = {}
  -- convert values
  tab["pos"] = ply:GetPos()
  tab["ang"] = ply:LocalEyeAngles()
  tab["duck"] = ply:Crouching()
  -- save with steam ID
  playerDCPoints[ply:SteamID()] = tab
end

local function resetPlayerSpawn(ply, args)
  if not IsValid(ply) then return end
  local remove_main_spawns = true
  local remove_brick_spawns = false
  for _,v in ipairs(args) do
    if v == "bricks" then
      remove_brick_spawns = true
    end
    if v == "bricksonly" then
      remove_main_spawns = false
      remove_brick_spawns = true
    end
  end
  if remove_brick_spawns then
    if IsValid(ply.SuperCoolBrickSpawn) or ply:GetNWVector("SpawnPos", false) then
      ply.SuperCoolBrickSpawn = nil
      ply:SetNWVector("SpawnPos", nil)
      ply:PrintMessage(HUD_PRINTCENTER, "Removed your brick spawnpoint!")
      printMsg("Removed brick spawn for " .. ply:Name())
    end
  end
  -- remove info
  if remove_main_spawns then
    ply:SetNW2Vector(SPAWN_POS, nil)
    ply:SetNW2Angle(SPAWN_ANG, nil)
    ply:SetNW2Bool(SPAWN_DUCK, false)
    ply:PrintMessage(HUD_PRINTCENTER, "Removed your main spawnpoint!")
    printMsg("Remove main spawn for " .. ply:Name())
  end
end

if engine.ActiveGamemode() == "sandbox" then
  --when persistence saving, save spawns and disconnect points to files
  hook.Add("PersistenceSave", "spawn persister on save", function(name)
    local allPlayers = player.GetHumans() --[sic]
    for _, ply in ipairs(allPlayers) do
      if ply:GetInfoNum("spawnp_save_pos_dc", 0) == 1 then
        setPlayerDC(ply)
      end
    end
    savePlayerSpawns()
    savePlayerDCs()
  end)
  -- on load, pull all player spawn data
  hook.Add("PersistenceLoad", "spawn persister on load", function(name)
    -- spawn points
    local data = file.Read(getPersistFile())
    if data then
      local pSpawns, err = sfs.decode(data)
      if err then
        ErrorNoHalt("[SpawnPersister ERROR] Decoding error in spawnpoint loading!")
      else
        playerSpawns = pSpawns --merge in the player spawnpoints
        printMsg("Loaded player spawnpoints.")
      end
    end
    -- disconnect points
    local data = file.Read(getPersistFile("dcpoints"))
    if data then
      local pdc, err = sfs.decode(data)
      if err then
        ErrorNoHalt("[SpawnPersister ERROR] Decoding error in reconnection point loading!")
      else
        playerDCPoints = pdc --merge in the player dc points
        printMsg("Loaded player reconnection points.")
      end
    end
  end)
  -- when player joins, load their persistent spawnpoint if any, and move them to dc point
  gameevent.Listen("player_activate")
  hook.Add("player_activate", "spawn persister on join", function(data)
    local ply = Player(data.userid) --get player entity
    if not cv_saveBots:GetBool() and ply:IsBot() then return end --skip bots if not allowed
    if not IsValid(ply) then return end
    --load spawn data into player networked values
    for id, spawn in pairs(playerSpawns) do
      if ply:SteamID() == id then
        ply:SetNW2Vector(SPAWN_POS, spawn["pos"])
        ply:SetNW2Angle (SPAWN_ANG, spawn["ang"])
        ply:SetNW2Bool (SPAWN_DUCK, spawn["duck"])
        --set location to spawn point at first
        ply:SetPos(spawn["pos"])
        ply:SetEyeAngles(spawn["ang"])
        if spawn["duck"] then
          ply:AddFlags(FL_DUCKING)
        else
          ply:RemoveFlags(FL_DUCKING)
          ply:AddFlags(FL_ANIMDUCKING)
        end
        break
      end
    end
    for id, dc in pairs(playerDCPoints) do
      if ply:SteamID() == id then
        --move the player to the dc point if present to override spawnpoint right now
        ply:SetPos(dc["pos"])
        --angle setting doesn't work on the first tick for THE FIRST SPAWN EACH RESTART??
        --for SOME reason ???
        --need to delay it by around a second, but lag masks this difference anyway lmao so w/e
        timer.Simple(1, function()
          ply:SetEyeAngles(dc["ang"])
        end)
        --quack
        if dc["duck"] then
          ply:AddFlags(FL_DUCKING)
        else
          ply:RemoveFlags(FL_DUCKING)
          ply:AddFlags(FL_ANIMDUCKING)
        end
        --if the player is colliding with a vehicle on load, just get in.
        --they probably logged out in it or something but even if not it's better to not be stuck.
        timer.Simple(1, function()
          enterCollidingVehicle(ply)
        end)
        break
      end
    end
    printMsg("Loaded player spawn data for " .. ply:Name())
    --test for vehicle collisions

  end)

  -- when player spawns, move them to their spawn position if any
  hook.Add("PlayerSpawn", "spawn persister on spawn", function(ply, transition)
    if IsValid(ply.SuperCoolBrickSpawn) then return end --let spawn brick override player spawnpoint
    if not ply:GetNW2Vector(SPAWN_POS, false) then return end --if no spawnpoint then leave
    -- get the networked values and move the player to the right position
    local pos = ply:GetNW2Vector(SPAWN_POS)
    local ang = ply:GetNW2Angle(SPAWN_ANG)
    local duck = ply:GetNW2Bool(SPAWN_DUCK)
    ply:SetPos(pos)
    ply:SetEyeAngles(ang)
    if duck then ply:AddFlags(FL_DUCKING) end

  end)
  --when player disconnects, auto-save their position if the relevant client convar is set
  hook.Add("PlayerDisconnected", "spawn persister on disconnect", function(ply)
    if ply:GetInfoNum("spawnp_save_pos_dc", 0) == 1 then
      setPlayerDC(ply)
    end
    --savePlayerSpawns()
  end)
  --when server closes, auto-save player positions also

  -- force-save spawnpoints manually
  concommand.Add("spawnp_save", function(ply, cmd, args)
    savePlayerSpawns()
  end)

  -- manually set your spawn to the current location
  concommand.Add("sv__spawnp_set_here", function(ply, cmd, args)
    setPlayerSpawn(ply)
  end)

  -- reset your spawn (brick("bricksonly"), main, or both("bricks"))
  concommand.Add("sv__spawnp_reset", function(ply, cmd, args)
    resetPlayerSpawn(ply, args)
  end)

  -- numpad.Register("np_spawnp_set_here", function(ply, data)
  --   ply:ConCommand("spawnp_set_here")
  -- end)

  -- concommand.Add("np__spawnp_set_here", function(ply, cmd, args)
  --   if #args == 1 then
  --     local key = args[1]
  --     numpad.OnDown(ply, key, "np_spawnp_set_here")
  --   end
  -- end)
end