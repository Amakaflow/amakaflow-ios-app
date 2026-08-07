/**
 * Watch item sheet — edit readiness & replace on watch. 2026-08-07.
 * DISPOSABLE. Tapping a row in On-your-watches (AMA-2375, shipped) opens
 * THIS — not the workout editor. You see what the watch is holding,
 * re-shape its WATCH-READINESS (enhance-v2 rows: mobility / warm-ups /
 * rest / cooldown — same anatomy, same configurators), then REPLACE the
 * copy on the watch. The workout itself is never edited here.
 * States: Apple scheduled · Garmin waiting (queued, not downloaded) ·
 * edited (pending changes → lit CTA) · replacing (DD Toast morph).
 * Honesty rules: CTA idles until something changes; Apple replace =
 * remove+reschedule same slot; Garmin replace = swap the queued FIT
 * (if already downloaded, the watch copy updates on next widget sync).
 */

const WI = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', gray: '#8890A0',
};

function WIRow({ title, sub, on, onToggle, onOpen, toast, first }) {
  return (
    <div style={{ background: WI.card, border: '1px solid var(--border)',
      borderRadius: 16, padding: '11px 14px', marginBottom: 8 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div onClick={onOpen} style={{ flex: 1, minWidth: 0, cursor: 'pointer' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span className="dd-display" style={{ fontSize: 14,
              fontWeight: 700 }}>{title}</span>
            <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>
          </div>
          <div className="af-mono" style={{ fontSize: 8.5, marginTop: 4,
            color: 'var(--fg-muted)', lineHeight: 1.5 }}>{sub}</div>
        </div>
        <div className="af-switch" data-on={on} onClick={onToggle}/>
      </div>
    </div>
  );
}

function WIItemSheet({ set, device = 'apple', preset }) {
  const edited = preset === 'edited' || preset === 'replacing';
  const replacing = preset === 'replacing';
  const [cooldown, setCooldown] = React.useState(edited);
  const [changes, setChanges] = React.useState(edited ? 2 : 0);
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const bump = () => setChanges(c => c + 1);

  const isApple = device === 'apple';
  const stateLine = isApple
    ? 'SCHEDULED · TODAY · 21:21 · WORKOUT APP'
    : 'SENT · WAITING — OPEN THE WIDGET TO DOWNLOAD';
  const replaceCta = changes > 0
    ? `Replace on watch · ${changes} change${changes === 1 ? '' : 's'}`
    : 'No changes yet';
  const replaceNote = isApple
    ? 'Replaces the scheduled copy — same slot, same time. The Workout app never sees the old version again.'
    : 'Swaps the queued file. Already downloaded? The watch copy updates on its next widget sync.';

  return (
    <>
      {/* dimmed watch-list behind */}
      <div style={{ padding: '12px 18px', opacity: 0.3 }}>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
          marginTop: 20 }}>{isApple ? 'Apple Watch' : 'Garmin'}</div>
        <div className="af-mono" style={{ fontSize: 9, marginTop: 5,
          color: 'var(--fg-muted)' }}>
          {isApple ? '1 SCHEDULED · 49 SLOTS FREE'
            : '0 ON WATCH · 1 WAITING'}</div>
      </div>

      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0,
        background: 'var(--bg-elev)', borderRadius: '20px 20px 0 0',
        padding: '14px 20px 18px', zIndex: 40 }}>
        <div className="af-sheet-handle"/>

        {/* Header — what & where */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
          <div style={{ width: 34, height: 34, borderRadius: 999,
            background: isApple ? WI.card2 : WI.blue, color: '#fff',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0 }}>
            <Icon name="watch" size={16}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 17,
              fontWeight: 800 }}>
              {isApple ? 'Erg Workout For Time' : 'Engine EMOM'}</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
              color: isApple ? 'var(--fg-dim)' : 'var(--ready-mod)' }}>
              {stateLine}</div>
          </div>
        </div>

        {/* On the watch now — read-only snapshot */}
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap',
          margin: '12px 0 4px' }}>
          {(isApple
            ? ['9 STEPS', 'MOBILITY ×2', 'RAMPS ×1', 'OPEN REST']
            : ['4 STEPS', 'EMOM 10 MIN', 'NO PREP', 'LAP REST'])
            .map(p => (
            <span key={p} className="af-mono" style={{ fontSize: 8.5,
              padding: '4px 9px', borderRadius: 999, background: WI.card2,
              color: 'var(--fg-muted)' }}>{p}</span>
          ))}
          <span className="dd-display"
            onClick={() => toast('Opens the read-only step preview — not the editor')}
            style={{ fontSize: 11, fontWeight: 700, color: WI.lime,
              cursor: 'pointer', padding: '3px 4px' }}>See steps ›</span>
        </div>

        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '10px 0 8px',
          letterSpacing: '.06em' }}>WATCH READINESS — RESHAPE, THEN REPLACE</div>

        <WIRow first title="Mobility prep"
          sub={isApple ? 'SKI ERG 500 M → JUMP ROPE 2:00 · 2 STEPS'
            : 'NONE — STRAIGHT INTO MINUTE 1'}
          on={isApple}
          onToggle={() => { bump(); toast('Toggled — counts as a change'); }}
          onOpen={() => toast('Opens the sequence builder (enhance v2, AMA-2378)')}/>
        <WIRow title="Warm-up sets"
          sub={isApple ? 'ERG · CUSTOM RAMP · 1 EXERCISE' : 'NOT USED FOR EMOM'}
          on={isApple}
          onToggle={() => { bump(); toast('Toggled — counts as a change'); }}
          onOpen={() => toast('Opens per-exercise warm-ups (enhance v2)')}/>
        <WIRow title="Rest between sets"
          sub={isApple ? 'OPEN REST — YOU END IT ON THE WATCH'
            : 'LAP TO ADVANCE'}
          on={true}
          onToggle={() => { bump(); toast('Toggled — counts as a change'); }}
          onOpen={() => toast('Open / Timed — unchanged anatomy')}/>
        <WIRow title="Cooldown"
          sub={cooldown ? 'STRETCH FLOW 3:00 · 1 STEP · AFTER THE LAST SET'
            : 'OFF — ADD ONE BEFORE RESENDING'}
          on={cooldown}
          onToggle={() => { setCooldown(c => !c); bump();
            toast('Cooldown toggled — counts as a change'); }}
          onOpen={() => toast('Opens the cooldown builder (same as mobility)')}/>

        {/* Replace CTA — idle until something changed */}
        <div className="dd-display"
          onClick={() => changes > 0 && !replacing &&
            toast(isApple
              ? '“Updating on watch…” → toast morphs → “Replaced ✓”'
              : '“Updating queue…” → toast morphs → “Queue updated ✓”')}
          style={{ background: changes > 0 ? WI.lime : WI.card2,
            color: changes > 0 ? WI.ink : 'var(--fg-dim)',
            borderRadius: 999, padding: '14px 0', textAlign: 'center',
            fontSize: 14, fontWeight: 700,
            cursor: changes > 0 ? 'pointer' : 'default', marginTop: 8,
            transition: 'background .3s, color .3s',
            boxShadow: changes > 0
              ? '0 0 24px color-mix(in oklch, var(--ready-high), transparent 50%)'
              : 'none' }}>
          {replacing ? 'Updating on watch…' : replaceCta}
        </div>
        <div style={{ fontSize: 10, color: 'var(--fg-dim)', lineHeight: 1.5,
          textAlign: 'center', margin: '8px 4px 0' }}>{replaceNote}</div>

        <div style={{ display: 'flex', gap: 18, justifyContent: 'center',
          marginTop: 12 }}>
          <span className="dd-display"
            onClick={() => toast('Removed from the watch — Library untouched · Undo')}
            style={{ fontSize: 12, fontWeight: 700, color: '#F4564A',
              cursor: 'pointer' }}>Remove from watch</span>
          <span className="dd-display"
            onClick={() => toast('Opens the full workout detail — editing lives there')}
            style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-muted)',
              cursor: 'pointer' }}>Open workout ›</span>
        </div>

        {/* replacing state: pending toast pinned above the sheet */}
        {replacing && (
          <div style={{ position: 'absolute', top: -46, left: 0, right: 0,
            display: 'flex', justifyContent: 'center' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 9,
              background: 'rgba(24,24,27,0.97)',
              border: '1px solid var(--border-str)', borderRadius: 999,
              padding: '8px 15px 8px 9px',
              boxShadow: '0 12px 34px rgba(0,0,0,.5)' }}>
              <div style={{ width: 24, height: 24, borderRadius: 999,
                background: WI.card2, display: 'flex', alignItems: 'center',
                justifyContent: 'center' }}>
                <div style={{ width: 12, height: 12, borderRadius: 999,
                  border: '2px solid rgba(255,255,255,0.2)',
                  borderTopColor: WI.lime,
                  animation: 'dd-spin .8s linear infinite' }}/>
              </div>
              <span className="dd-display" style={{ fontSize: 12.5,
                fontWeight: 700 }}>Updating on watch…</span>
            </div>
          </div>
        )}
      </div>
    </>
  );
}

function DDWatchItemScreen({ dd, set, nav, preset }) {
  if (preset === 'garmin') return <WIItemSheet set={set} device="garmin"/>;
  if (preset === 'edited')
    return <WIItemSheet set={set} device="apple" preset="edited"/>;
  if (preset === 'replacing')
    return <WIItemSheet set={set} device="apple" preset="replacing"/>;
  return <WIItemSheet set={set} device="apple"/>;
}

Object.assign(window, { DDWatchItemScreen, WIItemSheet });
