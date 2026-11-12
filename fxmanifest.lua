fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'rose_WarnAPP'
description 'Warnmeldungen bei Hurrikan, Erdbeben, Meteoriten usw. aus gg_weathersystem, inkl. lb-phone App'
version '1.1.0'

dependency 'gg_weathersystem'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'

-- Eigene NUI-Seite (wie in der lb-phone App-Vorlage), damit Callbacks funktionieren.
-- Außerhalb des Handys blendet sich die Seite selbst aus.
ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/alarm.js',
    'ui/icon.svg',
}
