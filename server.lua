local RES = 'gg_weathersystem'

local activeWeather = nil   -- z.B. 'HURRICANE', solange ein Ereignis läuft
local activeQuake   = nil   -- Quake-Tabelle, solange ein Beben läuft
local lastWeather   = nil

local history = {}          -- neueste zuerst: { id, kind, label, level, text, detail, started, ended, expires }
local weatherEntry = nil    -- laufender Verlaufseintrag (Wetter)
local quakeEntry   = nil    -- laufender Verlaufseintrag (Beben)
local nextId = 0

local ESX = nil
CreateThread(function()
    if GetResourceState('es_extended') == 'started' then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        if ok then ESX = obj end
    end
end)

-- Zeit in Millisekunden (für die App)
local function nowMs()
    return os.time() * 1000
end

local function format(text, data)
    return (text:gsub('{(%w+)}', function(key)
        local v = data and data[key]
        return v ~= nil and tostring(v) or ''
    end))
end

local function quakeText(q)
    return format(Config.Quake.start, {
        magnitude = q.magnitude and string.format('%.1f', q.magnitude) or '?',
        where = q.where or q.label or '',
    })
end

local function quakeDetail(q)
    if q.magnitude then return ('Stärke %.1f'):format(q.magnitude) end
    return nil
end

local function debugPrint(text)
    if Config.Debug then print('[rose_WarnAPP] ' .. text) end
end

---------------------------------------------------------------------
-- Rechte: Admin und/oder Behörden-Job
---------------------------------------------------------------------
local function isAdmin(src)
    if not src or src <= 0 then return false end
    if Config.Admin.ace and IsPlayerAceAllowed(src, Config.Admin.ace) then return true end
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local group = xPlayer.getGroup and xPlayer.getGroup()
            for _, g in ipairs(Config.Admin.groups or {}) do
                if group == g then return true end
            end
        end
    end
    return false
end

-- Liefert den Behörden-Schlüssel (z.B. 'police'), wenn der Spieler dazugehört
local function getAgency(src)
    if not ESX then return nil end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    local job = xPlayer.getJob and xPlayer.getJob() or xPlayer.job
    if not job or not job.name then return nil end
    local agency = Config.Agencies[job.name]
    if agency and (tonumber(job.grade) or 0) >= (agency.minGrade or 0) then
        return job.name
    end
    return nil
end

-- { canCreate, isAdmin, agency, sender }
local function getPermission(src)
    local admin = isAdmin(src)
    local agency = getAgency(src)
    local sender = nil
    if agency then
        sender = Config.Agencies[agency].label
    elseif admin then
        sender = Config.Admin.label
    end
    local preset = (agency and Config.Agencies[agency].zone) or Config.Zones.preset or {}
    return {
        canCreate = admin or agency ~= nil,
        isAdmin = admin,
        agency = agency,
        sender = sender,
        zoneTitle = preset.title,
        zoneText = preset.text,
    }
end

local function canEnd(src, e)
    if isAdmin(src) then return true end
    local agency = getAgency(src)
    return agency ~= nil and agency == e.agency
end

---------------------------------------------------------------------
-- Daten für die Handy-App
---------------------------------------------------------------------
local function buildData()
    local active = {}
    for _, e in ipairs(history) do
        if not e.ended then active[#active + 1] = e end
    end
    return {
        active = active,
        history = history,
        now = nowMs(),
        debug = Config.Debug == true,
        maxMinutes = Config.Admin.maxMinutes,
        zonesEnabled = Config.Zones.enabled == true,
        zoneRadii = Config.Zones.radii,
    }
end

local function pushData(target)
    TriggerClientEvent('rose_WarnAPP:data', target or -1, buildData())
end

local function addHistory(kind, entry, text, detail)
    nextId = nextId + 1
    local e = {
        id = nextId,
        kind = kind,
        label = entry.label,
        level = entry.level,
        text = text,
        detail = detail,
        started = nowMs(),
    }
    table.insert(history, 1, e)

    -- Verlauf kürzen, aber nie aktive Warnungen entfernen
    while #history > Config.HistorySize do
        local removed = false
        for i = #history, 1, -1 do
            if history[i].ended then
                table.remove(history, i)
                removed = true
                break
            end
        end
        if not removed then break end
    end
    return e
end

local function endHistory(e)
    if e then e.ended = nowMs() end
end

---------------------------------------------------------------------
-- Meldungen
---------------------------------------------------------------------
-- phase: 'start' oder 'stop' (steuert Alarmton bzw. Entwarnungston)
local function send(target, entry, text, phase)
    TriggerClientEvent('rose_WarnAPP:notify', target, {
        title = entry.title,
        description = text,
        type = entry.type,
        icon = entry.icon,
        level = entry.level,
        phase = phase or 'start',
    })

    if Config.Phone.enabled and Config.Phone.notifications and GetResourceState('lb-phone') == 'started' then
        local data = {
            app = Config.Phone.identifier,
            title = entry.title,
            content = text,
        }
        if target == -1 then
            pcall(function() exports['lb-phone']:NotifyEveryone('online', data) end)
        else
            pcall(function() exports['lb-phone']:SendNotification(target, data) end)
        end
    end
end

---------------------------------------------------------------------
-- Admin-Warnungen
---------------------------------------------------------------------
local function customEntry(e)
    local style = Config.Custom[e.level] or Config.Custom.danger
    local title = style.title .. ': ' .. e.label
    if e.sender then title = ('[%s] %s'):format(e.senderShort or e.sender, title) end
    return {
        label = e.label,
        title = title,
        type = style.type,
        level = e.level,
        icon = 'triangle-exclamation',
    }
end

local function endCustom(e, by)
    if not e or e.ended then return end
    endHistory(e)
    send(-1, customEntry(e), format(Config.Custom.stop, { label = e.label }), 'stop')
    debugPrint(('Admin-Warnung #%d aufgehoben (%s)'):format(e.id, by or 'abgelaufen'))
    pushData()
end

local function clean(text, maxLen)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #text == 0 then return nil end
    return text:sub(1, maxLen)
end

-- Erlaubte Radien als Set
local allowedRadius = {}
for _, r in ipairs(Config.Zones.radii or {}) do allowedRadius[r] = true end

-- Position der sendenden Person (serverseitig, sonst vom Client gemeldet)
local function getCoords(src, fallback)
    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local c = GetEntityCoords(ped)
        if c and (c.x ~= 0.0 or c.y ~= 0.0) then return c.x, c.y, c.z end
    end
    if type(fallback) == 'table' and tonumber(fallback.x) and tonumber(fallback.y) then
        return tonumber(fallback.x), tonumber(fallback.y), tonumber(fallback.z) or 0.0
    end
    return nil
end

RegisterNetEvent('rose_WarnAPP:createWarning', function(data)
    local src = source
    local perm = getPermission(src)
    if not perm.canCreate then return end
    if type(data) ~= 'table' then return end

    local label = clean(data.title, 40)
    local text = clean(data.text, 300)

    -- Sperrzone ohne eigenen Text -> Vorlage verwenden
    if Config.Zones.enabled and data.zone == true then
        label = label or clean(perm.zoneTitle, 40)
        text = text or clean(perm.zoneText, 300)
    end
    if not label or not text then return end

    local level = data.level == 'info' and 'info' or 'danger'
    local minutes = math.floor(tonumber(data.minutes) or 0)
    minutes = math.max(0, math.min(minutes, Config.Admin.maxMinutes or 240))

    -- Absender
    local detailParts = {}
    if perm.sender then detailParts[#detailParts + 1] = perm.sender end
    if Config.Admin.showAuthor then detailParts[#detailParts + 1] = GetPlayerName(src) end
    local detail = #detailParts > 0 and table.concat(detailParts, ' · ') or nil

    -- Sperrzone
    local zone = nil
    local radius = tonumber(data.radius)
    if Config.Zones.enabled and data.zone == true and radius and allowedRadius[radius] then
        local x, y, z = getCoords(src, data.coords)
        if x then
            zone = {
                x = x, y = y, z = z,
                radius = radius,
                street = clean(data.street, 60),
            }
        end
    end

    local e = addHistory('CUSTOM', { label = label, level = level }, text, detail)
    e.custom = true
    e.agency = perm.agency
    e.sender = perm.sender
    e.senderShort = perm.agency and Config.Agencies[perm.agency].short or nil
    e.zone = zone
    if minutes > 0 then
        e.expires = nowMs() + minutes * 60000
        SetTimeout(minutes * 60000, function() endCustom(e) end)
    end

    local message = text
    if zone then
        message = ('%s Sperrzone: %d m%s.'):format(text, zone.radius, zone.street and (' um ' .. zone.street) or '')
    end

    debugPrint(('Warnung #%d von %s (%s): %s'):format(e.id, GetPlayerName(src), perm.sender or '-', label))
    send(-1, customEntry(e), message, 'start')
    pushData()
end)

RegisterNetEvent('rose_WarnAPP:endWarning', function(id)
    local src = source
    for _, e in ipairs(history) do
        if e.id == id and e.custom and not e.ended then
            if canEnd(src, e) then endCustom(e, GetPlayerName(src)) end
            return
        end
    end
end)

RegisterNetEvent('rose_WarnAPP:checkAdmin', function()
    local src = source
    TriggerClientEvent('rose_WarnAPP:permission', src, getPermission(src))
end)

---------------------------------------------------------------------
-- gg_weathersystem abfragen
---------------------------------------------------------------------
local function getState()
    if GetResourceState(RES) ~= 'started' then return nil end
    local ok, state = pcall(function() return exports[RES]:getState() end)
    if ok and type(state) == 'table' then return state end
    return nil
end

local function getQuake(state)
    local ok, q = pcall(function() return exports[RES]:getQuake() end)
    if ok and type(q) == 'table' then return q end
    if state and type(state.quake) == 'table' then return state.quake end
    return nil
end

CreateThread(function()
    while true do
        Wait(Config.CheckInterval)

        local state = getState()
        if state then
            local changed = false
            local weather = state.weather and tostring(state.weather):upper() or nil

            if weather ~= lastWeather then
                debugPrint(('Wetter: %s -> %s'):format(tostring(lastWeather), tostring(weather)))
                lastWeather = weather
            end

            -- Wetter-Ereignisse
            local newEvent = (weather and Config.WeatherEvents[weather]) and weather or nil
            if newEvent ~= activeWeather then
                if activeWeather then
                    local old = Config.WeatherEvents[activeWeather]
                    endHistory(weatherEntry)
                    weatherEntry = nil
                    if old then send(-1, old, old.stop, 'stop') end
                end
                if newEvent then
                    local cur = Config.WeatherEvents[newEvent]
                    weatherEntry = addHistory(newEvent, cur, cur.start)
                    send(-1, cur, cur.start)
                end
                activeWeather = newEvent
                changed = true
            end

            -- Erdbeben
            local q = getQuake(state)
            if q and not activeQuake then
                activeQuake = q
                debugPrint('Erdbeben gestartet')
                local text = quakeText(q)
                quakeEntry = addHistory('QUAKE', Config.Quake, text, quakeDetail(q))
                send(-1, Config.Quake, text)
                changed = true
            elseif not q and activeQuake then
                activeQuake = nil
                debugPrint('Erdbeben beendet')
                endHistory(quakeEntry)
                quakeEntry = nil
                send(-1, Config.Quake, Config.Quake.stop, 'stop')
                changed = true
            end

            if changed then pushData() end
        end
    end
end)

---------------------------------------------------------------------
-- Client fragt Daten an (beim Laden / Spawn)
---------------------------------------------------------------------
RegisterNetEvent('rose_WarnAPP:requestData', function()
    pushData(source)
end)

-- Debug-Ausgaben vom Client / aus der App
local logCount = {}
RegisterNetEvent('rose_WarnAPP:clientLog', function(text)
    if not Config.Debug then return end
    local src = source
    logCount[src] = (logCount[src] or 0) + 1
    if logCount[src] > 50 then return end -- Spam-Schutz
    print(('[rose_WarnAPP] [Spieler %s] %s'):format(src, tostring(text):sub(1, 300)))
end)

-- Spieler, die während einer laufenden Warnung joinen
RegisterNetEvent('rose_WarnAPP:requestActive', function()
    local src = source
    pushData(src)
    if not Config.NotifyOnJoin then return end
    if activeWeather and Config.WeatherEvents[activeWeather] then
        local cur = Config.WeatherEvents[activeWeather]
        send(src, cur, cur.start)
    end
    if activeQuake then
        send(src, Config.Quake, quakeText(activeQuake))
    end
    for _, e in ipairs(history) do
        if e.custom and not e.ended then
            send(src, customEntry(e), e.text)
        end
    end
end)
