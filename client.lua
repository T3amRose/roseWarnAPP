local resourceName = GetCurrentResourceName()
local appData = { active = {}, history = {} }
local permission = { canCreate = false, isAdmin = false }

-- Daten für die App inkl. Rechte (nur zur Anzeige; der Server prüft selbst)
local function payload()
    local data = {}
    for k, v in pairs(appData) do data[k] = v end
    data.permission = permission
    return data
end

---------------------------------------------------------------------
-- Sperrzonen: Blips, Hinweis beim Betreten, NPCs anhalten
---------------------------------------------------------------------
local zones = {}        -- [id] = { x, y, z, radius, label, blipRadius, blipCenter }
local insideZone = nil
local FROZEN = 'ggZoneFrozen' -- State-Bag-Markierung an eingefrorenen NPCs/Fahrzeugen

local function showHelp(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, 5000)
end

local function markFrozen(entity, zoneId)
    pcall(function()
        Entity(entity).state:set(FROZEN, zoneId, NetworkGetEntityIsNetworked(entity))
    end)
end

local function frozenZone(entity)
    local ok, value = pcall(function() return Entity(entity).state[FROZEN] end)
    return ok and value or nil
end

-- Fahrzeug (mit NPC-Fahrer) komplett stilllegen
local function freezeVehicle(veh, driver, zoneId)
    SetVehicleHandbrake(veh, true)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    SetVehicleForwardSpeed(veh, 0.0)
    FreezeEntityPosition(veh, true)
    markFrozen(veh, zoneId)

    if driver and driver ~= 0 then
        ClearPedTasks(driver)
        SetBlockingOfNonTemporaryEvents(driver, true)
        SetPedKeepTask(driver, true)
        TaskVehicleTempAction(driver, veh, 6, 1000000) -- Bremse halten
        markFrozen(driver, zoneId)
    end
end

-- Fußgänger einfrieren
local function freezePed(ped, zoneId)
    ClearPedTasksImmediately(ped)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStandStill(ped, -1)
    SetPedKeepTask(ped, true)
    FreezeEntityPosition(ped, true)
    markFrozen(ped, zoneId)
end

-- Wieder freigeben (nur wer die Entity kontrolliert, kann das)
local function releaseVehicle(veh)
    FreezeEntityPosition(veh, false)
    SetVehicleUndriveable(veh, false)
    SetVehicleHandbrake(veh, false)
    SetVehicleEngineOn(veh, true, true, false)
    markFrozen(veh, nil)

    local driver = GetPedInVehicleSeat(veh, -1)
    if driver ~= 0 and not IsPedAPlayer(driver) and NetworkHasControlOfEntity(driver) then
        ClearPedTasks(driver)
        SetBlockingOfNonTemporaryEvents(driver, false)
        SetPedKeepTask(driver, false)
        TaskVehicleDriveWander(driver, veh, 15.0, 786603)
        markFrozen(driver, nil)
    end
end

local function releasePed(ped)
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedKeepTask(ped, false)
    TaskWanderStandard(ped, 10.0, 10)
    markFrozen(ped, nil)
end

local function removeZone(id)
    local z = zones[id]
    if not z then return end
    if DoesBlipExist(z.blipRadius) then RemoveBlip(z.blipRadius) end
    if DoesBlipExist(z.blipCenter) then RemoveBlip(z.blipCenter) end
    if z.speedZone then RemoveRoadNodeSpeedZone(z.speedZone) end
    zones[id] = nil
    if insideZone == id then insideZone = nil end
    -- Freigabe passiert im NPC-Thread (auch für NPCs, die anderen Spielern gehören)
end

local function addZone(id, e)
    local zd = e.zone
    local z = {
        x = zd.x + 0.0, y = zd.y + 0.0, z = (zd.z or 0) + 0.0,
        radius = zd.radius + 0.0,
        label = e.label,
    }
    z.blipRadius = AddBlipForRadius(z.x, z.y, z.z, z.radius)
    SetBlipColour(z.blipRadius, Config.Zones.blipColor or 1)
    SetBlipAlpha(z.blipRadius, Config.Zones.blipAlpha or 100)

    z.blipCenter = AddBlipForCoord(z.x, z.y, z.z)
    SetBlipSprite(z.blipCenter, 526)
    SetBlipColour(z.blipCenter, Config.Zones.blipColor or 1)
    SetBlipScale(z.blipCenter, 0.9)
    SetBlipAsShortRange(z.blipCenter, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Sperrzone: ' .. (e.label or ''))
    EndTextCommandSetBlipName(z.blipCenter)

    -- GTA-Verkehrssteuerung: Tempo 0 auf allen Straßen im Radius.
    -- Wirkt auf den KI-Verkehr, auch wenn niemand hinschaut.
    if Config.Zones.stopVehicles then
        z.speedZone = AddRoadNodeSpeedZone(z.x, z.y, z.z, z.radius, 0.0, false)
    end

    zones[id] = z
end

-- Zonen an die aktiven Warnungen anpassen
local function syncZones()
    local wanted = {}
    local active = appData.active
    if type(active) == 'table' then
        for _, e in pairs(active) do
            if type(e) == 'table' and type(e.zone) == 'table' and e.id then
                wanted[e.id] = e
            end
        end
    end
    for id in pairs(zones) do
        if not wanted[id] then removeZone(id) end
    end
    if Config.Zones.enabled then
        for id, e in pairs(wanted) do
            if not zones[id] then addZone(id, e) end
        end
    end
end

-- Hinweis beim Betreten / Verlassen
CreateThread(function()
    while true do
        Wait(1000)
        if next(zones) and Config.Zones.enterMessage then
            local pos = GetEntityCoords(PlayerPedId())
            local found = nil
            for id, z in pairs(zones) do
                if #(pos.xy - vector2(z.x, z.y)) <= z.radius then found = id break end
            end
            if found ~= insideZone then
                if found then
                    showHelp(('~r~Sperrzone~s~: %s~n~Bitte verlasse den Bereich.'):format(zones[found].label or ''))
                elseif insideZone then
                    showHelp('Du hast die Sperrzone verlassen.')
                end
                insideZone = found
            end
        elseif insideZone then
            insideZone = nil
        end
    end
end)

-- In welcher Zone liegt dieser Punkt? (nil = keine)
local function zoneAt(pos)
    for id, z in pairs(zones) do
        if #(pos.xy - vector2(z.x, z.y)) <= z.radius then return id end
    end
    return nil
end

-- Fahrzeuge mit NPC-Fahrer in Zonen: abbremsen, dann komplett einfrieren
local brakingSince = {} -- [veh] = GetGameTimer() beim Bremsbeginn

local function handleVehicles()
    if not Config.Zones.stopVehicles then return end
    local now = GetGameTimer()
    for veh, t in pairs(brakingSince) do
        if not DoesEntityExist(veh) or now - t > 10000 then brakingSince[veh] = nil end
    end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local zoneId = zoneAt(GetEntityCoords(veh))
        if zoneId and NetworkHasControlOfEntity(veh) and not IsEntityPositionFrozen(veh) then
            local driver = GetPedInVehicleSeat(veh, -1)
            -- KI-Fahrzeug: NPC-Fahrer ODER "Geisterfahrer" (GTA entfernt den Fahrer-Ped,
            -- wenn man nicht hinschaut, das Auto fährt aber weiter)
            local aiDriven = (driver ~= 0 and not IsPedAPlayer(driver))
                or (driver == 0 and GetEntitySpeed(veh) > 0.5 and not IsVehicleSeatFree(veh, -1))
                or (driver == 0 and GetEntitySpeed(veh) > 1.0)
            if aiDriven then
                local braking = brakingSince[veh]
                if driver ~= 0 and GetEntitySpeed(veh) > 2.0 and (not braking or now - braking < 1500) then
                    -- erst kurz abbremsen, damit es nicht ruckartig stehen bleibt
                    brakingSince[veh] = braking or now
                    if NetworkHasControlOfEntity(driver) then
                        SetBlockingOfNonTemporaryEvents(driver, true)
                        TaskVehicleTempAction(driver, veh, 6, 1500)
                    end
                else
                    -- langsam genug, Bremszeit vorbei oder Geisterfahrer -> fixieren
                    brakingSince[veh] = nil
                    local ctrlDriver = (driver ~= 0 and NetworkHasControlOfEntity(driver)) and driver or nil
                    freezeVehicle(veh, ctrlDriver, zoneId)
                end
            end
        end
    end
end

-- Fußgänger in Zonen einfrieren
local function handlePeds()
    if not Config.Zones.stopPeds then return end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, true)
            and not IsPedDeadOrDying(ped, true)
            and not IsEntityPositionFrozen(ped)
            and NetworkHasControlOfEntity(ped) then
            local zoneId = zoneAt(GetEntityCoords(ped))
            if zoneId then freezePed(ped, zoneId) end
        end
    end
end

-- Alles freigeben, was zu einer aufgehobenen Zone gehört
-- (läuft bei jedem Spieler, damit auch NPCs freikommen, deren Besitzer gewechselt hat)
local function releaseEnded()
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local zoneId = frozenZone(veh)
        if zoneId and not zones[zoneId] and NetworkHasControlOfEntity(veh) then
            releaseVehicle(veh)
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        local zoneId = frozenZone(ped)
        if zoneId and not zones[zoneId] and not IsPedAPlayer(ped) and NetworkHasControlOfEntity(ped) then
            if IsPedInAnyVehicle(ped, false) then
                FreezeEntityPosition(ped, false)
                markFrozen(ped, nil)
            else
                releasePed(ped)
            end
        end
    end
end

CreateThread(function()
    while true do
        local hasZones = next(zones) ~= nil
        Wait(hasZones and 500 or 2000)

        local ok, err = pcall(function()
            if hasZones then
                handleVehicles()
                handlePeds()
            end
            releaseEnded()
        end)
        if not ok and Config.Debug then
            print('[rose_WarnAPP] NPC-Fehler: ' .. tostring(err))
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= resourceName then return end
    for id in pairs(zones) do removeZone(id) end
    pcall(releaseEnded)
end)

---------------------------------------------------------------------
-- Bildschirm-Meldung
---------------------------------------------------------------------
local function playAlarm(data)
    local s = Config.Sound
    if not s or not s.enabled then return end

    local sound
    if data.phase == 'stop' then
        sound = s.allClear and 'allclear' or nil
    elseif data.level == 'info' then
        sound = s.infoSound
    else
        sound = 'emergency'
    end
    if not sound or sound == 'none' then return end

    SendNUIMessage({
        action = 'rose_WarnAPP:sound',
        sound = sound,
        volume = s.volume,
        repeats = s.repeats,
    })
end

local function notify(data)
    if Config.Notify == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        exports.ox_lib:notify({
            title = data.title,
            description = data.description,
            type = data.type or 'inform',
            icon = data.icon,
            duration = Config.Duration,
            position = Config.NotifyPosition or 'top',
        })
    elseif Config.Notify == 'esx' then
        TriggerEvent('esx:showNotification', ('~r~%s~s~\n%s'):format(data.title, data.description))
    end
    playAlarm(data)
end

-- Laufenden Alarm abbrechen: /alarmstop
RegisterCommand('alarmstop', function()
    SendNUIMessage({ action = 'rose_WarnAPP:sound', sound = 'stop' })
end, false)

RegisterNetEvent('rose_WarnAPP:notify', notify)

---------------------------------------------------------------------
-- lb-phone App
---------------------------------------------------------------------

-- Daten an die geöffnete App schicken
local function sendToApp()
    if not Config.Phone.enabled or GetResourceState('lb-phone') ~= 'started' then return end
    pcall(function()
        exports['lb-phone']:SendCustomAppMessage(Config.Phone.identifier, {
            type = 'rose_WarnAPP:update',
            data = payload(),
        })
    end)
end

local function addPhoneApp()
    if not Config.Phone.enabled or GetResourceState('lb-phone') ~= 'started' then return end

    local ok, added, err = pcall(function()
        return exports['lb-phone']:AddCustomApp({
            identifier = Config.Phone.identifier,
            name = Config.Phone.name,
            description = Config.Phone.description,
            developer = Config.Phone.developer,
            defaultApp = Config.Phone.defaultApp,
            size = 2048,
            icon = ('https://cfx-nui-%s/ui/icon.svg'):format(resourceName),
            ui = ('%s/ui/index.html'):format(resourceName),
            fixBlur = true,
            onOpen = function()
                if Config.Debug then
                    TriggerServerEvent('rose_WarnAPP:clientLog', 'App geöffnet')
                end
                -- Daten nach dem Laden der App-Seite zusätzlich hineinschicken
                TriggerServerEvent('rose_WarnAPP:checkAdmin')
                TriggerServerEvent('rose_WarnAPP:requestData')
                SetTimeout(400, sendToApp)
                SetTimeout(1200, sendToApp)
            end,
        })
    end)

    local result
    if not ok then
        result = 'Fehler: ' .. tostring(added)
    elseif added then
        result = 'App hinzugefügt'
    else
        result = 'nicht hinzugefügt: ' .. tostring(err)
    end
    print('[rose_WarnAPP] ' .. result)
    if Config.Debug then
        TriggerServerEvent('rose_WarnAPP:clientLog', 'AddCustomApp -> ' .. result)
    end
end

RegisterNetEvent('rose_WarnAPP:data', function(data)
    appData = data
    syncZones()
    sendToApp()
end)

RegisterNetEvent('rose_WarnAPP:permission', function(value)
    if type(value) == 'table' then permission = value end
    sendToApp()
end)

-- Job gewechselt -> Rechte neu abfragen
RegisterNetEvent('esx:setJob', function()
    TriggerServerEvent('rose_WarnAPP:checkAdmin')
end)

-- App-UI fragt beim Öffnen die Daten ab
RegisterNUICallback('getData', function(_, cb)
    cb(payload())
end)

-- Admin: neue Warnung aus der App
RegisterNUICallback('createWarning', function(data, cb)
    cb('ok')
    if type(data) ~= 'table' then return end

    local coords = GetEntityCoords(PlayerPedId())
    local streetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = streetHash and GetStreetNameFromHashKey(streetHash) or nil

    TriggerServerEvent('rose_WarnAPP:createWarning', {
        title = data.title,
        text = data.text,
        level = data.level,
        minutes = data.minutes,
        zone = data.zone == true,
        radius = tonumber(data.radius),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        street = street,
    })
end)

-- Sperrzone auf der Karte markieren
RegisterNUICallback('setWaypoint', function(data, cb)
    cb('ok')
    local id = type(data) == 'table' and tonumber(data.id)
    local z = id and zones[id]
    if z then
        SetNewWaypoint(z.x, z.y)
        if GetResourceState('lb-phone') == 'started' then
            pcall(function()
                exports['lb-phone']:SendNotification({
                    app = Config.Phone.identifier,
                    title = 'Sperrzone markiert',
                    content = 'Die Sperrzone ist jetzt auf deiner Karte markiert.',
                })
            end)
        end
    end
end)

-- Admin: Warnung aufheben
RegisterNUICallback('endWarning', function(data, cb)
    cb('ok')
    if type(data) == 'table' and tonumber(data.id) then
        TriggerServerEvent('rose_WarnAPP:endWarning', tonumber(data.id))
    end
end)

-- Debug-Meldungen der App-Seite -> Server-Konsole
RegisterNUICallback('log', function(data, cb)
    cb('ok')
    if Config.Debug and type(data) == 'table' and data.text then
        TriggerServerEvent('rose_WarnAPP:clientLog', 'App: ' .. tostring(data.text):sub(1, 300))
    end
end)

CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do Wait(1000) end
    Wait(1000)
    addPhoneApp()
    TriggerServerEvent('rose_WarnAPP:checkAdmin')
    TriggerServerEvent('rose_WarnAPP:requestData')
end)

-- lb-phone wurde neu gestartet -> App erneut eintragen
AddEventHandler('onClientResourceStart', function(res)
    if res == 'lb-phone' then
        SetTimeout(2000, addPhoneApp)
    end
end)

---------------------------------------------------------------------
-- Nach dem Spawn einmal nach laufenden Ereignissen fragen
---------------------------------------------------------------------
AddEventHandler('esx:playerLoaded', function()
    SetTimeout(5000, function()
        TriggerServerEvent('rose_WarnAPP:requestActive')
    end)
end)
