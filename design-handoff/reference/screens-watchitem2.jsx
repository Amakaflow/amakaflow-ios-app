/**
 * Watch item sheet v2 — 2026-08-07 fidelity + wiring redesign. DISPOSABLE.
 * Fixes the shipped AMA-2386 sheet (PR #539) against David's dogfood report:
 *  · snapshot pills + "See steps" crammed into one non-wrapping row → now a
 *    dedicated ON THE WATCH card: wrapped pill rows + full-width See-steps row
 *  · See steps did nothing → read-only step overlay (Strava peek-sheet
 *    pattern, AMA-2371 band anatomy), DELIVERED COPY watermark
 *  · edits vanished (demo store) + Replace CTA hidden behind AMA2375_DEMO →
 *    CTA is ALWAYS visible (dim idle / lit with count), rows carry an amber
 *    EDITED chip while draft ≠ delivered, apply-note under CTA (Speak
 *    "applies starting next lesson" pattern): changes live in the shared
 *    enrichment store and only reach the watch on Replace
 *  · Open workout dead-ended on "Workout unavailable" → footer becomes a
 *    linked-workout row with the workout NAME when linked; honest disabled
 *    state when the watch copy has no library link
 * Mobbin: Fi base-device edit sheet 30ad6584, Speak apply-note 6cf45db2,
 * Strava read-only peek 39a71ad8, Runna step bands 543ecf4e.
 * WJ prefix (WI taken by v1). Panels: idle / steps / edited / replacing /
 * replaced. Panel 1 is LIVE: toggle cooldown, open See steps.
 */

const WJ = {
  lime: 'var(--ready-high)', amber: 'var(--ready-mod)', red: '#F4564A',
  ink: '#0d1200', card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)', blue: '#5AB8F4',
};

const WJ_PILLS = ['9 STEPS', 'MOBILITY ×2', 'RAMPS ×1', 'OPEN REST'];

const WJ_STEPS = [
  { band: 'MOBILITY', color: WJ.blue, rows: ['Ski erg — 500 m', 'Jump rope — 2:00'] },
  { band: 'WARM-UP · BENCH PRESS', color: WJ.amber, rows: ['8 × ~40% — easy', '5 × ~60%', '3 × ~80%'] },
  { band: 'WORK', color: WJ.lime, rows: ['Bench Press — 3 × 5 · 85 kg', 'Back Squat — 3 × 5 · 120 kg', 'Romanian Deadlift — 3 × 8 · 70 kg'] },
  { band: 'REST', color: 'var(--fg-dim)', rows: ['Open — end on tap between sets'] },
];

function WJTag({ children, color }) {
  return (
    <span className="af-mono" style={{ fontSize: 7.5, fontWeight: 700,
      color: color || 'var(--fg-dim)', border: `1px solid ${color || 'var(--border-str)'}`,
      borderRadius: 999, padding: '2px 7px', whiteSpace: 'nowrap' }}>{children}</span>
  );
}

function WJToggle({ on, onClick }) {
  return (
    <div onClick={onClick} style={{ width: 44, height: 26, borderRadius: 999,
      background: on ? WJ.lime : WJ.card2, position: 'relative',
      cursor: 'pointer', flexShrink: 0, transition: 'background .15s' }}>
      <div style={{ width: 22, height: 22, borderRadius: 999, background: '#fff',
        position: 'absolute', top: 2, left: on ? 20 : 2, transition: 'left .15s' }}/>
    </div>
  );
}

// Read-only delivered-steps overlay — Strava peek pattern, AMA-2371 bands
function WJStepsOverlay({ onClose }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 20,
      background: 'rgba(0,0,0,0.55)', display: 'flex', alignItems: 'flex-end' }}
      onClick={onClose}>
      <div onClick={e => e.stopPropagation()}
        style={{ width: '100%', maxHeight: '86%', background: '#101114',
          borderRadius: '20px 20px 0 0', display: 'flex',
          flexDirection: 'column', boxShadow: '0 -14px 44px rgba(0,0,0,0.7)' }}>
        <div style={{ width: 36, height: 4, borderRadius: 2,
          background: 'rgba(255,255,255,0.22)', margin: '10px auto 0' }}/>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8,
          padding: '10px 18px 2px' }}>
          <div className="dd-display" style={{ fontSize: 16, fontWeight: 800,
            flex: 1 }}>On the watch — 9 steps</div>
          <span onClick={onClose} className="dd-display" style={{ fontSize: 12,
            fontWeight: 700, color: 'var(--fg-muted)', cursor: 'pointer' }}>Close</span>
        </div>
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          padding: '0 18px 8px' }}>DELIVERED COPY · READ-ONLY — EDITS BELOW
          DON'T CHANGE THIS UNTIL YOU REPLACE</div>
        <div className="af-scroll" style={{ overflowY: 'auto',
          padding: '2px 18px 18px' }}>
          {WJ_STEPS.map((b, bi) => (
            <div key={b.band} style={{ marginBottom: 10 }}>
              <div className="af-mono" style={{ fontSize: 8, fontWeight: 700,
                color: b.color, borderLeft: `3px solid ${b.color}`,
                padding: '3px 0 3px 9px', background: WJ.card,
                borderRadius: '0 8px 8px 0' }}>{b.band}</div>
              {b.rows.map((r, ri) => (
                <div key={ri} style={{ display: 'flex', gap: 10,
                  alignItems: 'center', padding: '8px 2px 8px 12px',
                  borderBottom: '1px solid var(--border)' }}>
                  <span className="af-mono" style={{ fontSize: 8.5,
                    color: 'var(--fg-dim)', width: 14 }}>{bi + 1}.{ri + 1}</span>
                  <span style={{ fontSize: 12.5, fontWeight: 500 }}>{r}</span>
                </div>
              ))}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

function WJSheet({ preset }) {
  const [st, set] = React.useState({
    steps: preset === 'steps',
    cooldownOn: preset === 'edited' || preset === 'replacing' || preset === 'replaced' ? true : false,
    edited: preset === 'edited' || preset === 'replacing',
    toast: null,
  });
  const replacing = preset === 'replacing';
  const replaced = preset === 'replaced';
  const changeCount = (st.edited ? 1 : 0) + (st.cooldownOn && !replaced ? 1 : 0);
  const canReplace = changeCount > 0 && !replacing && !replaced;

  const row = (title, sub, { edited, toggleKey, on, chevron = true, disabled } = {}) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12,
      background: WJ.card, border: edited
        ? '1px solid color-mix(in oklch, var(--ready-mod), transparent 45%)'
        : '1px solid var(--border)',
      borderRadius: 16, padding: '12px 14px', marginBottom: 8,
      opacity: disabled ? 0.55 : 1 }}>
      <div style={{ flex: 1, minWidth: 0, cursor: chevron ? 'pointer' : 'default' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <span className="dd-display" style={{ fontSize: 14.5,
            fontWeight: 700 }}>{title}</span>
          {chevron && <Icon name="chevR" size={12}
            style={{ color: 'var(--fg-dim)' }}/>}
          {edited && <WJTag color={WJ.amber}>EDITED</WJTag>}
        </div>
        <div className="af-mono" style={{ fontSize: 8.5, marginTop: 4,
          color: edited ? WJ.amber : 'var(--fg-muted)', lineHeight: 1.5 }}>{sub}</div>
      </div>
      <WJToggle on={on} onClick={() => toggleKey &&
        set(s => ({ ...s, [toggleKey]: !s[toggleKey] }))}/>
    </div>
  );

  return (
    <div style={{ position: 'relative', display: 'flex',
      flexDirection: 'column', height: '100%' }}>
      {/* toast */}
      {(replacing || replaced) && (
        <div style={{ position: 'absolute', top: 8, left: 16, right: 16,
          zIndex: 12, background: '#17181c',
          border: '1px solid var(--border-str)', borderRadius: 999,
          padding: '9px 15px', display: 'flex', alignItems: 'center', gap: 10,
          boxShadow: '0 10px 30px rgba(0,0,0,0.55)' }}>
          {replacing
            ? <div style={{ width: 13, height: 13, borderRadius: 999,
                border: '2px solid var(--fg-dim)', borderTopColor: WJ.lime }}/>
            : <Icon name="check" size={14} style={{ color: WJ.lime }}/>}
          <span className="dd-display" style={{ fontSize: 12, fontWeight: 700 }}>
            {replacing ? 'Updating on watch…' : 'Replaced on Apple Watch ✓'}</span>
        </div>
      )}

      <div style={{ width: 36, height: 4, borderRadius: 2,
        background: 'rgba(255,255,255,0.18)', margin: '8px auto 0' }}/>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '10px 18px 0' }}>
        {/* header — one-line truncated title, tight */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
          <div style={{ width: 34, height: 34, borderRadius: 999,
            background: WJ.card2, display: 'flex', alignItems: 'center',
            justifyContent: 'center', flexShrink: 0 }}>
            <Icon name="watch" size={16}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 17, fontWeight: 800,
              whiteSpace: 'nowrap', overflow: 'hidden',
              textOverflow: 'ellipsis' }}>Full Body Aesthetics Session</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
              color: 'var(--fg-dim)' }}>SCHEDULED · TODAY · 16:36 · WORKOUT APP</div>
          </div>
        </div>

        {/* ON THE WATCH — delivered-truth card, pills wrap, See steps = row */}
        <div style={{ background: WJ.card, border: '1px solid var(--border)',
          borderRadius: 16, marginTop: 12 }}>
          <div style={{ padding: '10px 13px 9px' }}>
            <div className="af-mono" style={{ fontSize: 7.5,
              color: 'var(--fg-dim)', marginBottom: 7 }}>
              ON THE WATCH NOW{replaced ? ' · UPDATED JUST NOW' : ''}</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {(replaced ? ['11 STEPS', 'MOBILITY ×2', 'RAMPS ×1', 'OPEN REST', 'COOLDOWN ×2'] : WJ_PILLS).map(p => (
                <span key={p} className="af-mono" style={{ fontSize: 8,
                  fontWeight: 600, color: 'var(--fg-muted)',
                  background: WJ.card2, borderRadius: 999,
                  padding: '4px 9px' }}>{p}</span>
              ))}
            </div>
          </div>
          <div onClick={() => set(s => ({ ...s, steps: true }))}
            style={{ display: 'flex', alignItems: 'center',
              justifyContent: 'space-between', padding: '10px 13px',
              borderTop: '1px solid var(--border)', cursor: 'pointer' }}>
            <span className="dd-display" style={{ fontSize: 12.5,
              fontWeight: 700, color: WJ.lime }}>See the 9 steps</span>
            <Icon name="chevR" size={13} style={{ color: WJ.lime }}/>
          </div>
        </div>

        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          margin: '13px 0 8px' }}>WATCH READINESS — RESHAPE, THEN REPLACE</div>

        {row('Mobility prep',
          st.edited ? 'SKI ERG OPEN ➜ JUMP ROPE 2:00 · 2 STEPS'
                    : 'SKI ERG 500 M ➜ JUMP ROPE 2:00 · 2 STEPS',
          { edited: st.edited, toggleKey: null, on: true })}
        {row('Warm-up sets',
          'BENCH PRESS · CUSTOM RAMP · BACK SQUAT + ROMANIAN DEADLIFT SKIPPED',
          { on: true })}
        {row('Rest between sets', 'OPEN — END REST ON TAP', { chevron: true, on: true })}
        {row('Cooldown',
          st.cooldownOn && !replaced ? 'STRETCH FLOW 3:00 · RUNS AFTER LAST SET'
            : replaced ? 'STRETCH FLOW 3:00 · ON THE WATCH' : 'OFF',
          { edited: st.cooldownOn && !replaced, toggleKey: 'cooldownOn',
            on: st.cooldownOn || replaced })}

        {/* linked workout row — honest, named, never a dead end */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 11,
          background: 'transparent', border: '1px dashed var(--border-str)',
          borderRadius: 14, padding: '10px 13px', margin: '4px 0 12px',
          cursor: 'pointer' }}>
          <Icon name="doc" size={14} style={{ color: 'var(--fg-dim)' }}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="af-mono" style={{ fontSize: 7.5,
              color: 'var(--fg-dim)' }}>FROM YOUR LIBRARY</div>
            <div className="dd-display" style={{ fontSize: 12.5,
              fontWeight: 700, marginTop: 1, whiteSpace: 'nowrap',
              overflow: 'hidden', textOverflow: 'ellipsis' }}>
              Full Body Aesthetics — open workout ›</div>
          </div>
        </div>
        <div style={{ height: 8 }}/>
      </div>

      {/* pinned action bar — ALWAYS visible, never demo-gated */}
      <div style={{ padding: '10px 18px 14px',
        borderTop: '1px solid var(--border)',
        background: 'rgba(5,5,6,0.92)' }}>
        <div className="dd-display" style={{
          background: canReplace || replacing ? WJ.lime : WJ.card2,
          color: canReplace || replacing ? WJ.ink : 'var(--fg-dim)',
          borderRadius: 999, padding: '13px 0', textAlign: 'center',
          fontSize: 14, fontWeight: 700,
          cursor: canReplace ? 'pointer' : 'default',
          boxShadow: canReplace
            ? '0 0 26px color-mix(in oklch, var(--ready-high), transparent 50%)'
            : 'none', opacity: replacing ? 0.75 : 1 }}>
          {replacing ? 'Updating on watch…'
            : replaced ? 'Up to date ✓'
            : canReplace
              ? `Replace on watch · ${changeCount} change${changeCount > 1 ? 's' : ''}`
              : 'No changes yet'}
        </div>
        <div style={{ fontSize: 9.5, color: 'var(--fg-dim)', textAlign: 'center',
          marginTop: 7, lineHeight: 1.5 }}>
          {replaced ? 'The watch has this exact copy.'
            : canReplace
              ? 'Saved here — the watch still has the old copy until you replace. Same slot, nothing extra.'
              : 'Edits save to this workout — replacing sends them to the watch.'}
        </div>
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 9 }}>
          <span className="dd-display" style={{ fontSize: 12, fontWeight: 700,
            color: WJ.red, cursor: 'pointer' }}>Remove from watch</span>
        </div>
      </div>

      {st.steps && <WJStepsOverlay onClose={() =>
        set(s => ({ ...s, steps: false }))}/>}
    </div>
  );
}

function DDWatchItem2Screen({ preset }) {
  return <WJSheet preset={preset}/>;
}

Object.assign(window, { DDWatchItem2Screen, WJSheet, WJStepsOverlay });
