const ICONS = {
    HURRICANE: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 12m-2 0a2 2 0 1 0 4 0a2 2 0 1 0 -4 0"/><path d="M6 6c3-3 9-3 11 1"/><path d="M18 18c-3 3-9 3-11-1"/><path d="M4 13c-1-4 2-8 6-8"/><path d="M20 11c1 4-2 8-6 8"/></svg>',
    METEORSTORM: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="8" cy="16" r="4"/><path d="M11 13l9-9"/><path d="M14 16l6-6"/><path d="M8 10l6-6"/></svg>',
    QUAKE: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12h4l2-5 3 10 3-8 2 3h6"/></svg>',
    ZONE: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9" stroke-dasharray="3 3"/><circle cx="12" cy="12" r="2"/></svg>',
    CUSTOM: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11v2a1 1 0 0 0 1 1h3l5 4V6L7 10H4a1 1 0 0 0-1 1z"/><path d="M16 9a3 3 0 0 1 0 6"/><path d="M19 6a7 7 0 0 1 0 12"/></svg>',
    OK: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5 9-10"/></svg>',
    ALERT: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><path d="M12 7v6"/><path d="M12 17h.01"/></svg>',
};

let state = { active: [], history: [], perm: { canCreate: false }, zonesEnabled: false, zoneRadii: [] };
let radiiKey = '';
let clockOffset = 0;
let formLevel = 'danger';

const $ = (id) => document.getElementById(id);
const RES = () => globalThis.resourceName || 'rose_WarnAPP';

function post(event, data) {
    return fetch(`https://${RES()}/${event}`, {
        method: 'POST',
        body: JSON.stringify(data || {}),
    });
}

// ---------------- Debug (nur sichtbar mit Config.Debug = true) ----------------
const debugInfo = { getData: 'läuft …', nachrichten: 0, fehler: [] };

function showDebug() {
    const el = $('debug');
    if (!el || el.hidden) return;
    el.textContent =
        `DEBUG\nresource: ${globalThis.resourceName || '(nicht gesetzt)'}\n` +
        `getData: ${debugInfo.getData}\nNachrichten erhalten: ${debugInfo.nachrichten}\n` +
        `rechte: ${JSON.stringify(state.perm)} · aktiv: ${state.active.length} · Verlauf: ${state.history.length}` +
        (debugInfo.fehler.length ? `\nFEHLER:\n${debugInfo.fehler.join('\n')}` : '');
}

function reportError(text) {
    debugInfo.fehler.push(text);
    if (debugInfo.fehler.length > 5) debugInfo.fehler.shift();
    showDebug();
    post('log', { text: 'FEHLER: ' + text }).catch(() => {});
}

window.addEventListener('error', (e) => reportError(`${e.message} (${(e.filename || '').split('/').pop()}:${e.lineno})`));
window.addEventListener('unhandledrejection', (e) => reportError(String(e.reason)));

// ---------------- Hilfsfunktionen ----------------
function esc(text) {
    const d = document.createElement('div');
    d.textContent = text ?? '';
    return d.innerHTML;
}

function serverNow() {
    return Date.now() + clockOffset;
}

function duration(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    const m = Math.floor(s / 60);
    const h = Math.floor(m / 60);
    if (h > 0) return `${h} h ${m % 60} min`;
    if (m > 0) return `${m} min ${s % 60} s`;
    return `${s} s`;
}

function clock(ms) {
    return new Date(ms - clockOffset).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' });
}

function timeLine(e) {
    let text = `seit ${clock(e.started)} · ${duration(serverNow() - e.started)}`;
    if (e.expires) text += ` · endet ${clock(e.expires)}`;
    return text;
}

// FiveM schickt leere Lua-Tabellen als {} statt [] -> immer in ein Array umwandeln
function toArray(value) {
    if (Array.isArray(value)) return value;
    if (value && typeof value === 'object') return Object.values(value);
    return [];
}

// Bestätigungsdialog des Handys (falls verfügbar)
function confirmPopUp(title, description, confirmLabel, onConfirm) {
    if (typeof globalThis.SetPopUp === 'function') {
        globalThis.SetPopUp({
            title,
            description,
            buttons: [
                { title: 'Abbrechen' },
                { title: confirmLabel, color: 'red', cb: onConfirm },
            ],
        });
    } else {
        onConfirm();
    }
}

// ---------------- Anzeige ----------------
function render() {
    const active = state.active;
    const status = $('status');

    if (active.length > 0) {
        status.className = 'status alert';
        $('statusIcon').innerHTML = ICONS.ALERT;
        $('statusTitle').textContent = active.length === 1 ? '1 aktive Warnung' : `${active.length} aktive Warnungen`;
        $('statusSub').textContent = 'Folge den Hinweisen und bring dich in Sicherheit.';
    } else {
        status.className = 'status calm';
        $('statusIcon').innerHTML = ICONS.OK;
        $('statusTitle').textContent = 'Keine Warnungen';
        $('statusSub').textContent = 'Alles ruhig.';
    }

    $('activeList').innerHTML = active.map((e) => `
        <div class="event ${e.level === 'info' ? 'info' : ''}">
            <div class="event-head">
                <span class="event-icon">${ICONS[e.kind] || ICONS.ALERT}</span>
                <span class="event-name">${esc(e.label)}</span>
                <span class="badge">${e.level === 'info' ? 'Hinweis' : 'Warnung'}</span>
            </div>
            ${e.detail ? `<div class="event-sender">${esc(e.detail)}</div>` : ''}
            <div class="event-text">${esc(e.text)}</div>
            ${e.zone ? `
                <div class="zone-info">
                    <span class="zone-icon">${ICONS.ZONE}</span>
                    <span>Sperrzone ${Math.round(e.zone.radius)} m${e.zone.street ? ' um ' + esc(e.zone.street) : ''}</span>
                    <button class="map-btn" data-map="${e.id}">Auf Karte</button>
                </div>` : ''}
            <div class="event-time" data-id="${e.id}">${timeLine(e)}</div>
            ${canEnd(e) ? `<button class="end-btn" data-end="${e.id}">Warnung aufheben</button>` : ''}
        </div>
    `).join('');

    // Formular für Admins / Behörden
    const perm = state.perm;
    $('adminToggle').hidden = !perm.canCreate;
    if (!perm.canCreate) $('adminForm').hidden = true;
    $('fSender').textContent = perm.sender ? `Senden als: ${perm.sender}` : '';
    $('fSender').hidden = !perm.sender;

    $('fZoneBox').hidden = !state.zonesEnabled || state.zoneRadii.length === 0;
    const key = state.zoneRadii.join(',');
    if (key !== radiiKey) {
        radiiKey = key;
        $('fRadius').innerHTML = state.zoneRadii.map((r, i) =>
            `<option value="${r}" ${i === Math.min(1, state.zoneRadii.length - 1) ? 'selected' : ''}>${r} m</option>`
        ).join('');
    }

    const history = state.history;
    $('historyEmpty').hidden = history.length > 0;
    $('historyList').innerHTML = history.map((e) => {
        const live = !e.ended;
        const sub = live
            ? `seit ${clock(e.started)}`
            : `${clock(e.started)} – ${clock(e.ended)} · ${duration(e.ended - e.started)}`;
        return `
            <li>
                <span class="h-icon">${ICONS[e.kind] || ICONS.ALERT}</span>
                <div class="h-main">
                    <div class="h-name">${esc(e.label)}${e.detail ? ' · ' + esc(e.detail) : ''}</div>
                    <div class="h-sub">${sub}</div>
                </div>
                <span class="h-state ${live ? 'live' : ''}">${live ? 'Aktiv' : 'Vorbei'}</span>
            </li>`;
    }).join('');
}

// Darf ich diese Warnung aufheben? (Server prüft zusätzlich)
function canEnd(e) {
    if (!e.custom) return false;
    const perm = state.perm;
    return perm.isAdmin === true || (!!perm.agency && perm.agency === e.agency);
}

function setState(data) {
    if (!data || typeof data !== 'object') return;
    const perm = data.permission && typeof data.permission === 'object' ? data.permission : {};
    state = {
        active: toArray(data.active),
        history: toArray(data.history),
        perm: {
            canCreate: perm.canCreate === true,
            isAdmin: perm.isAdmin === true,
            agency: typeof perm.agency === 'string' ? perm.agency : null,
            sender: typeof perm.sender === 'string' ? perm.sender : null,
            zoneTitle: typeof perm.zoneTitle === 'string' ? perm.zoneTitle : '',
            zoneText: typeof perm.zoneText === 'string' ? perm.zoneText : '',
        },
        zonesEnabled: data.zonesEnabled === true,
        zoneRadii: toArray(data.zoneRadii).map(Number).filter((n) => n > 0),
    };
    if (data.now) clockOffset = data.now - Date.now();
    $('debug').hidden = data.debug !== true;
    try {
        render();
    } catch (err) {
        reportError('render: ' + err.message);
    }
    showDebug();
}

// Laufende Zeit jede Sekunde aktualisieren
setInterval(() => {
    document.querySelectorAll('.event-time[data-id]').forEach((el) => {
        const e = state.active.find((x) => String(x.id) === el.dataset.id);
        if (e) el.textContent = timeLine(e);
    });
}, 1000);

// ---------------- Admin: Formular ----------------
function showFormError(text) {
    const el = $('fError');
    el.textContent = text || '';
    el.hidden = !text;
}

$('adminToggle').addEventListener('click', () => {
    const form = $('adminForm');
    form.hidden = !form.hidden;
    $('adminToggle').classList.toggle('open', !form.hidden);
    showFormError('');
});

$('fLevel').addEventListener('click', (ev) => {
    const btn = ev.target.closest('button[data-level]');
    if (!btn) return;
    formLevel = btn.dataset.level;
    $('fLevel').querySelectorAll('button').forEach((b) => b.classList.toggle('active', b === btn));
});

// Vorlage bei "Sperrzone" automatisch einsetzen (bleibt bearbeitbar)
let insertedPreset = { title: null, text: null };

$('fZone').addEventListener('change', () => {
    const on = $('fZone').checked;
    $('fRadiusRow').hidden = !on;

    const title = $('fTitle');
    const text = $('fText');
    const perm = state.perm;

    if (on) {
        if (!title.value.trim() && perm.zoneTitle) {
            title.value = perm.zoneTitle;
            insertedPreset.title = perm.zoneTitle;
        }
        if (!text.value.trim() && perm.zoneText) {
            text.value = perm.zoneText;
            insertedPreset.text = perm.zoneText;
        }
    } else {
        // Nur entfernen, wenn noch unverändert
        if (insertedPreset.title !== null && title.value === insertedPreset.title) title.value = '';
        if (insertedPreset.text !== null && text.value === insertedPreset.text) text.value = '';
        insertedPreset = { title: null, text: null };
    }
});

$('fSend').addEventListener('click', () => {
    const title = $('fTitle').value.trim();
    const text = $('fText').value.trim();
    const minutes = Number($('fMinutes').value) || 0;
    const zone = !$('fZoneBox').hidden && $('fZone').checked;
    const radius = Number($('fRadius').value) || 0;

    // Bei Sperrzone darf leer bleiben -> Server nimmt die Vorlage
    if (!title && !zone) return showFormError('Bitte einen Titel eingeben.');
    if (!text && !zone) return showFormError('Bitte eine Nachricht eingeben.');
    if (zone && !radius) return showFormError('Bitte einen Radius wählen.');
    showFormError('');

    const extra = zone ? ` Dazu eine Sperrzone von ${radius} m um deine Position.` : '';
    confirmPopUp(
        'Warnung senden?',
        `„${title || state.perm.zoneTitle || 'Sperrzone'}“ geht mit Alarmton an alle Spieler.${extra}`,
        'Senden',
        () => {
            post('createWarning', { title, text, level: formLevel, minutes, zone, radius }).catch(() => {});
            $('fTitle').value = '';
            $('fText').value = '';
            $('fMinutes').value = '0';
            $('fZone').checked = false;
            $('fRadiusRow').hidden = true;
            insertedPreset = { title: null, text: null };
            $('adminForm').hidden = true;
            $('adminToggle').classList.remove('open');
        }
    );
});

// Warnung aufheben / Sperrzone auf der Karte
$('activeList').addEventListener('click', (ev) => {
    const mapBtn = ev.target.closest('button[data-map]');
    if (mapBtn) {
        post('setWaypoint', { id: Number(mapBtn.dataset.map) }).catch(() => {});
        return;
    }

    const btn = ev.target.closest('button[data-end]');
    if (!btn) return;
    const id = Number(btn.dataset.end);
    const e = state.active.find((x) => x.id === id);
    const extra = e && e.zone ? ' Die Sperrzone wird ebenfalls aufgehoben.' : '';
    confirmPopUp('Warnung aufheben?', `Alle bekommen eine Entwarnung.${extra}`, 'Aufheben', () => {
        btn.disabled = true;
        post('endWarning', { id }).catch(() => {});
    });
});

// ---------------- Daten ----------------
// Live-Updates vom Client-Script (exports['lb-phone']:SendCustomAppMessage)
window.addEventListener('message', (event) => {
    const msg = event.data;
    if (msg && msg.type === 'rose_WarnAPP:update') {
        debugInfo.nachrichten++;
        setState(msg.data);
    }
});

async function load() {
    try {
        const res = await post('getData');
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        debugInfo.getData = 'ok';
        setState(await res.json());
    } catch (err) {
        // Der Client schickt die Daten beim Öffnen zusätzlich per Nachricht
        debugInfo.getData = 'fehlgeschlagen: ' + err.message;
        showDebug();
    }
}

try {
    render();
} catch (err) {
    reportError('render: ' + err.message);
}
load();
