// Alarmtöne für rose_WarnAPP – werden per Web Audio erzeugt (keine Sounddateien nötig).
// Läuft in der unsichtbaren NUI-Seite der Ressource, gesteuert über SendNUIMessage.
(function () {
    let ctx = null;
    let master = null;
    let stopAt = 0;

    function audio() {
        if (!ctx) {
            ctx = new (window.AudioContext || window.webkitAudioContext)();
            master = ctx.createGain();
            master.connect(ctx.destination);
        }
        if (ctx.state === 'suspended') ctx.resume();
        return ctx;
    }

    // Einen Ton (oder Akkord) mit weichen Kanten spielen
    function tone(freqs, start, duration, volume, type) {
        const c = audio();
        const gain = c.createGain();
        gain.connect(master);
        gain.gain.setValueAtTime(0, start);
        gain.gain.linearRampToValueAtTime(volume, start + 0.015);
        gain.gain.setValueAtTime(volume, start + duration - 0.03);
        gain.gain.linearRampToValueAtTime(0, start + duration);

        freqs.forEach((f) => {
            const osc = c.createOscillator();
            osc.type = type || 'sine';
            osc.frequency.setValueAtTime(f, start);
            osc.connect(gain);
            osc.start(start);
            osc.stop(start + duration + 0.05);
        });
    }

    // Typischer Warnton (Cell Broadcast / EU-Alert): 853 Hz + 960 Hz gleichzeitig,
    // Muster 2 s an – 0,5 s Pause – 1 s an – 0,5 s Pause – 1 s an – 0,5 s Pause
    function emergency(volume, repeats) {
        const c = audio();
        let t = c.currentTime + 0.05;
        const v = volume * 0.5; // zwei Töne addieren sich
        for (let r = 0; r < repeats; r++) {
            [[2, 0.5], [1, 0.5], [1, 0.5]].forEach(([on, off]) => {
                tone([853, 960], t, on, v, 'sine');
                t += on + off;
            });
        }
        stopAt = t;
    }

    // Sanfter Hinweis-Gong (z.B. Sternschnuppen, Nordlicht)
    function chime(volume) {
        const t = audio().currentTime + 0.05;
        tone([659.25], t, 0.35, volume, 'sine');
        tone([880], t + 0.3, 0.6, volume, 'sine');
    }

    // Entwarnung: drei kurze absteigende Töne
    function allClear(volume) {
        const t = audio().currentTime + 0.05;
        tone([880], t, 0.22, volume, 'sine');
        tone([698.46], t + 0.25, 0.22, volume, 'sine');
        tone([523.25], t + 0.5, 0.5, volume, 'sine');
    }

    function stopAll() {
        if (!ctx) return;
        // Ausgang kurz stummschalten und neu aufbauen -> alle geplanten Töne verstummen
        master.disconnect();
        master = ctx.createGain();
        master.connect(ctx.destination);
        stopAt = 0;
    }

    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || msg.action !== 'rose_WarnAPP:sound') return;

        const volume = Math.max(0, Math.min(1, Number(msg.volume ?? 0.5)));
        if (msg.sound !== 'stop') stopAll();

        switch (msg.sound) {
            case 'emergency': emergency(volume, Math.max(1, Number(msg.repeats || 2))); break;
            case 'chime': chime(volume); break;
            case 'allclear': allClear(volume); break;
            case 'stop': stopAll(); break;
        }
    });
})();
