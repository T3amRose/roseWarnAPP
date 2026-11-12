Config = {}

-- Wie oft (in ms) der Server gg_weathersystem abfragt
Config.CheckInterval = 2000

-- Bildschirm-Meldung: 'ox_lib', 'esx' oder 'none' (dann nur Handy)
Config.Notify = 'none'

-- Nur für ox_lib: Position ('top', 'top-right', 'top-left', 'bottom', 'center-right' ...)
Config.NotifyPosition = 'top'

-- Wie lange die Bildschirm-Meldung sichtbar ist (ms, nur ox_lib)
Config.Duration = 12000

-- Alarmton (typischer Handy-Warnton 853/960 Hz wie bei Cell Broadcast)
-- Mit /alarmstop kann jeder Spieler einen laufenden Alarm abbrechen.
Config.Sound = {
    enabled = true,
    volume = 0.4,          -- 0.0 bis 1.0
    repeats = 2,           -- wie oft das Warnmuster abgespielt wird (ein Durchgang ca. 5,5 s)
    infoSound = 'chime',   -- Ton bei Admin-Warnungen der Stufe "Hinweis": 'chime', 'emergency' oder 'none'
    allClear = true,       -- kurzer Entwarnungston, wenn eine Warnung vorbei ist
}

-- Gibt Wetterwechsel und Admin-Aktionen in der Server-Konsole aus
Config.Debug = false

-- Spieler, die während einer Warnung joinen, bekommen sie auch
Config.NotifyOnJoin = true

-- Wie viele Einträge der Verlauf in der App zeigt
Config.HistorySize = 15

-- lb-phone App
Config.Phone = {
    enabled = true,          -- App im Handy anzeigen
    notifications = true,    -- Handy-Benachrichtigung (Push) bei Start/Ende
    identifier = 'rose_WarnAPP',
    name = 'Warnungen',
    description = 'Unwetterwarnungen sowie Warnungen und Sperrzonen von PD, MD, DoJ und FD.',
    developer = 'Wetterdienst',
    defaultApp = true,       -- true: bei jedem vorinstalliert, nicht löschbar
}

---------------------------------------------------------------------
-- Wer darf Warnungen in der App schreiben?
---------------------------------------------------------------------
Config.Admin = {
    -- ESX-Gruppen, die Warnungen schreiben und ALLE Warnungen aufheben dürfen
    groups = { 'admin', 'superadmin' },
    -- Alternativ per ACE-Recht: add_ace group.admin rose_WarnAPP.admin allow
    ace = 'rose_WarnAPP.admin',
    -- So steht es bei Warnungen von Admins ohne Behörden-Job
    label = 'Leitstelle',
    -- Längste erlaubte Dauer in Minuten (0 = Warnung bleibt, bis sie aufgehoben wird)
    maxMinutes = 240,
    -- Name der Person zusätzlich zur Behörde anzeigen
    showAuthor = false,
}

-- Behörden (ESX-Jobname = Schlüssel). Mitglieder dürfen Warnungen senden
-- und die Warnungen ihrer eigenen Behörde wieder aufheben.
-- minGrade: ab welchem Rang (0 = alle)
-- zone: Vorlage, die beim Haken "Sperrzone" automatisch eingesetzt wird
Config.Agencies = {
    police = {
        label = 'LSPD', short = 'PD', minGrade = 0,
        zone = {
            title = 'Polizeieinsatz',
            text = 'Polizeieinsatz in diesem Bereich. Der Bereich ist gesperrt, bitte weiträumig umfahren und den Anweisungen der Polizei folgen.',
        },
    },
    ambulance = {
        label = 'EMS', short = 'MD', minGrade = 0,
        zone = {
            title = 'Rettungseinsatz',
            text = 'Rettungseinsatz in diesem Bereich. Bitte Rettungswege freihalten und den Bereich meiden.',
        },
    },
    doj = { -- Job existiert noch nicht
        label = 'Department of Justice', short = 'DoJ', minGrade = 0,
        zone = {
            title = 'Gesperrter Bereich',
            text = 'Dieser Bereich wurde durch das Department of Justice gesperrt. Betreten verboten.',
        },
    },
    fire = { -- Job existiert noch nicht
        label = 'Fire Department', short = 'FD', minGrade = 0,
        zone = {
            title = 'Feuerwehreinsatz',
            text = 'Feuerwehreinsatz in diesem Bereich. Rauch- und Brandgefahr! Fenster und Türen schließen und den Bereich meiden.',
        },
    },
}

-- Texte für eigene Warnungen
Config.Custom = {
    danger = { title = 'WARNUNG',  type = 'error'  },
    info   = { title = 'HINWEIS',  type = 'inform' },
    stop   = 'Entwarnung: „{label}“ wurde aufgehoben.',
}

---------------------------------------------------------------------
-- Sperrzonen (Radius um die Person, die die Warnung sendet)
---------------------------------------------------------------------
Config.Zones = {
    enabled = true,
    radii = { 50, 100, 150, 250, 500 },  -- Auswahl in der App (Meter)
    stopPeds = true,         -- Fußgänger in der Zone bleiben stehen
    stopVehicles = true,     -- NPC-Fahrzeuge in der Zone halten an
    blipColor = 1,           -- 1 = rot (Blip-Farben: docs.fivem.net/docs/game-references/blips)
    blipAlpha = 100,         -- Durchsichtigkeit des Kreises (0-255)
    enterMessage = true,     -- Hinweis oben links beim Betreten / Verlassen
    -- Vorlage für Admins ohne Behörden-Job (Behörden haben ihre eigene, siehe Config.Agencies)
    preset = {
        title = 'Sperrzone',
        text = 'Dieser Bereich ist gesperrt. Bitte meide die Gegend und folge den Anweisungen der Einsatzkräfte.',
    },
}

---------------------------------------------------------------------
-- Automatische Warnungen aus gg_weathersystem
---------------------------------------------------------------------
-- Name wie in gg_weathersystem. Eintrag löschen = keine Warnung.
-- level: 'danger' (rot) oder 'info' (blau)
Config.WeatherEvents = {
    HURRICANE = {
        label = 'Hurrikan',
        title = 'UNWETTERWARNUNG',
        start = 'Ein Hurrikan zieht auf! Runter vom Wasser und such dir Schutz.',
        stop  = 'Entwarnung: Der Hurrikan ist abgezogen.',
        type  = 'error',
        level = 'danger',
        icon  = 'hurricane',
    },
    METEORSTORM = {
        label = 'Meteoritenhagel',
        title = 'METEORITENWARNUNG',
        start = 'Meteoritenhagel! Achte auf Einschläge und bleib in Deckung.',
        stop  = 'Entwarnung: Der Meteoritenhagel ist vorbei.',
        type  = 'error',
        level = 'danger',
        icon  = 'meteor',
    },
    -- Sternschnuppen / Nordlicht sind keine Warnungen. Bei Bedarf wieder einkommentieren:
    -- STARFALL = { label = 'Sternschnuppen', title = 'HIMMELSEREIGNIS', start = 'Sternschnuppen am Himmel.', stop = 'Die Sternschnuppen sind vorbei.', type = 'inform', level = 'info', icon = 'star' },
    -- AURORA   = { label = 'Nordlicht', title = 'HIMMELSEREIGNIS', start = 'Nordlichter sind zu sehen.', stop = 'Die Nordlichter sind verschwunden.', type = 'inform', level = 'info', icon = 'star' },
}

-- Erdbeben ({magnitude} und {where} werden ersetzt)
Config.Quake = {
    label = 'Erdbeben',
    title = 'ERDBEBENWARNUNG',
    start = 'Erdbeben der Stärke {magnitude} {where}! Bring dich in Sicherheit.',
    stop  = 'Entwarnung: Das Erdbeben hat aufgehört.',
    type  = 'error',
    level = 'danger',
    icon  = 'house-crack',
}
