/**
 * Completed-workout sync & fill-in actuals — 2026-08-07. DISPOSABLE.
 * Evolves the ORIGINAL proto loop (DDTodayScreen timeline, DDActivityScreen
 * matched/typed/blank, backfill editor) into the full flow:
 *   connect Strava/Garmin/Apple → completed sessions land on Today →
 *   map an unmatched activity to the plan it was → FILL IN ACTUALS
 *   (planned vs done, per exercise) → verified session in Progress.
 * Principles: sources are read-only (we never post); mapping attaches,
 * never duplicates; "as planned" is one tap, adjusting is steppers with
 * the plan as ghost; RPE closes the loop (proto voice).
 */

const SY = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', orange: '#FC4C02', purple: '#C58AF4', red: '#F4564A',
};

function SYChip({ icon, bg, ink, size = 34 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: 999, background: bg,
      color: ink || '#fff', display: 'flex', alignItems: 'center',
      justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={icon} size={Math.round(size * 0.47)}/>
    </div>
  );
}

// ------------------------------------------------- 1 · Connect sources
function SYConnectScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const src = (icon, bg, name, sub, state, cta) => (
    <div style={{ background: SY.card, border: '1px solid var(--border)',
      borderRadius: 16, padding: '13px 14px', marginBottom: 9 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <SYChip icon={icon} bg={bg}/>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="dd-display" style={{ fontSize: 14.5,
            fontWeight: 700 }}>{name}</div>
          <div className="af-mono" style={{ fontSize: 8, marginTop: 3,
            color: 'var(--fg-dim)', lineHeight: 1.5 }}>{sub}</div>
        </div>
        {state === 'on'
          ? <span className="af-mono" style={{ fontSize: 9, color: SY.lime,
              flexShrink: 0 }}>CONNECTED ✓</span>
          : <span className="dd-display" onClick={() => toast(cta)}
              style={{ fontSize: 12, fontWeight: 700, background: SY.lime,
                color: SY.ink, borderRadius: 999, padding: '8px 14px',
                cursor: 'pointer', flexShrink: 0 }}>Connect</span>}
      </div>
    </div>
  );
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => toast('Back to Settings')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Settings
        </div>
        <div className="dd-display" style={{ fontSize: 26, fontWeight: 800,
          marginTop: 8 }}>Pull your training in</div>
        <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 5,
          lineHeight: 1.5 }}>
          Finished sessions land on Today by themselves — then you fill in
          what you actually did. We only read; we never post.
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '16px 18px 96px' }}>
        {src('watch', SY.card2, 'Apple Health',
          'WORKOUTS FROM YOUR APPLE WATCH · HEART RATE + CALORIES', 'on')}
        {src('watch', SY.blue, 'Garmin',
          'RUNS + STRENGTH · PULLED AUTOMATICALLY AFTER SYNC', 'on')}
        {src('run', SY.orange, 'Strava',
          'EVERYTHING YOU RECORD THERE · INCL. OTHER APPS VIA STRAVA', 'off',
          'Opens Strava OAuth — read-only scope, then first pull (panel 2)')}
        <div style={{ background: SY.card, border: '1px solid var(--border)',
          borderRadius: 14, padding: '11px 13px', marginTop: 6 }}>
          <div className="af-mono" style={{ fontSize: 8.5,
            color: 'var(--fg-muted)', lineHeight: 1.7 }}>
            SAME WORKOUT FROM TWO SOURCES? WE KEEP ONE — WATCH BEATS PHONE,
            RICHER DATA WINS. NOTHING COUNTS TWICE.
          </div>
        </div>
      </div>
    </>
  );
}

// --------------------------------------- 2 · First sync — Today fills in
function SYFirstSyncScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const card = (icon, bg, time, title, stats, src, action) => (
    <div style={{ display: 'flex', gap: 12, marginBottom: 4 }}>
      <div style={{ display: 'flex', flexDirection: 'column',
        alignItems: 'center' }}>
        <SYChip icon={icon} bg={bg} size={34}/>
        <div style={{ width: 2, flex: 1, background: 'var(--border)',
          marginTop: 4 }}/>
      </div>
      <div style={{ flex: 1, paddingBottom: 14, minWidth: 0 }}>
        <div className="af-mono" style={{ fontSize: 10.5, padding: '6px 0',
          color: 'var(--fg-muted)' }}>{time}</div>
        <div style={{ background: SY.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '12px 13px' }}>
          <div className="dd-display" style={{ fontSize: 14.5,
            fontWeight: 700 }}>{title}</div>
          <div className="af-mono" style={{ fontSize: 9.5, marginTop: 5,
            color: 'var(--fg-muted)' }}>{stats}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8,
            marginTop: 9 }}>
            <span className="af-mono" style={{ fontSize: 8, padding: '4px 9px',
              borderRadius: 999, background: SY.card2,
              color: 'var(--fg-muted)' }}>{src}</span>
            <span style={{ marginLeft: 'auto' }}>{action}</span>
          </div>
        </div>
      </div>
    </div>
  );
  return (
    <>
      <div style={{ padding: '8px 18px 4px', display: 'flex',
        alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>
          Today</div>
        <span className="af-mono" style={{ marginLeft: 'auto', fontSize: 8.5,
          color: SY.orange }}>● STRAVA CONNECTED</span>
      </div>
      {/* first-pull counter — DD Motion voice */}
      <div className="af-mono" style={{ padding: '2px 18px 10px',
        fontSize: 8.5, color: 'var(--fg-dim)' }}>
        PULLING YOUR LAST 30 DAYS… 3 OF 12 SESSIONS
        <span style={{ color: SY.lime }}> ▍</span></div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '4px 18px 96px' }}>
        {card('run', SY.orange, '12:53 – 13:52', 'Lunch Run / 8.2 km',
          '59M · 677 CAL · 143 BPM', 'FROM STRAVA',
          <span className="dd-display"
            onClick={() => toast('Opens activity — map it (panel 3)')}
            style={{ fontSize: 12, fontWeight: 700, cursor: 'pointer',
              color: 'var(--ready-mod)' }}>What was this?</span>)}
        {card('flame', SY.lime, 'YESTERDAY · 18:10', 'Hyrox Sim — Stations 1–4',
          '44M · 486 CAL · 151 BPM', 'VERIFIED · GARMIN',
          <span className="af-mono" style={{ fontSize: 10,
            color: SY.lime }}>RPE 8 ✓</span>)}
        {card('lift', SY.purple, 'MON · 17:20', 'Lower body — posterior',
          '52M · STRENGTH', 'FROM STRAVA',
          <span className="dd-display"
            onClick={() => toast('Opens fill-in actuals (panel 4)')}
            style={{ fontSize: 12, fontWeight: 700, cursor: 'pointer',
              color: 'var(--ready-mod)' }}>Fill in what you did</span>)}
      </div>
    </>
  );
}

// ------------------------------------ 3 · Unmatched activity — map it
function SYMapScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => toast('Back to Today')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Today
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12,
          marginTop: 10 }}>
          <SYChip icon="run" bg={SY.orange}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 22,
              fontWeight: 800 }}>Lunch Run</div>
            <div className="af-mono" style={{ fontSize: 9, marginTop: 3,
              color: 'var(--fg-dim)' }}>12:53 – 13:52 · FROM STRAVA</div>
          </div>
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 96px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr',
          gap: 8 }}>
          {[['8.2', 'KM'], ['59', 'MIN'], ['677', 'CAL'], ['143', 'BPM']].map(([v, k]) => (
            <div key={k} style={{ background: SY.card,
              border: '1px solid var(--border)', borderRadius: 14,
              padding: '11px 4px', textAlign: 'center' }}>
              <div className="dd-display" style={{ fontSize: 19,
                fontWeight: 800 }}>{v}</div>
              <div className="af-mono" style={{ fontSize: 8,
                color: 'var(--fg-dim)', marginTop: 3 }}>{k}</div>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 12, padding: '11px 13px', borderRadius: 14,
          background: 'color-mix(in oklch, var(--ready-mod), transparent 88%)',
          border: '1px solid color-mix(in oklch, var(--ready-mod), transparent 60%)' }}>
          <div className="dd-display" style={{ fontSize: 13, fontWeight: 700 }}>
            Which workout was this?</div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 4,
            lineHeight: 1.5 }}>
            Mapping attaches this run to the plan it was — nothing is
            duplicated, and Progress counts it once.
          </div>
        </div>

        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '14px 0 8px' }}>
          BEST MATCHES — SAME DAY, SAME SHAPE</div>
        {[['Tempo 40/20s', 'STRYD · 12:50 TODAY', 'SAME START · SAME DISTANCE', true],
          ['Zone 2 base run', 'MY WORKOUTS', 'DISTANCE FITS · HR SAYS TEMPO', false]].map(([t, src, why, best]) => (
          <div key={t} onClick={() => toast(`Mapped to “${t}” → fill in actuals (panel 4)`)}
            style={{ display: 'flex', alignItems: 'center', gap: 12,
              background: SY.card,
              border: best
                ? '1px solid color-mix(in srgb, var(--ready-high), transparent 55%)'
                : '1px solid var(--border)',
              borderRadius: 16, padding: '12px 14px', marginBottom: 8,
              cursor: 'pointer' }}>
            <SYChip icon="run" bg={SY.card2} size={32}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="dd-display" style={{ fontSize: 13.5,
                fontWeight: 700 }}>{t}</div>
              <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
                color: 'var(--fg-dim)' }}>{src}</div>
              <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
                color: best ? SY.lime : 'var(--ready-mod)' }}>{why}</div>
            </div>
            <Icon name="link" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}
        <div className="dd-display" onClick={() => toast('Search all workouts')}
          style={{ textAlign: 'center', padding: '10px 0', fontSize: 12.5,
            fontWeight: 700, color: 'var(--fg-muted)', cursor: 'pointer' }}>
          Search all workouts…</div>
        <div className="dd-display" onClick={() => toast('Keeps it as a plain run — still counts')}
          style={{ textAlign: 'center', padding: '2px 0', fontSize: 12,
            fontWeight: 700, color: 'var(--fg-dim)', cursor: 'pointer' }}>
          It was just a run — keep as is</div>
      </div>
    </>
  );
}

// --------------------------------- 4 · Fill in actuals — planned vs done
function SYActualsScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const [states, setStates] = React.useState({ squat: 'adjust', rdl: 'plan',
    split: null, nordic: null });
  const [rpe, setRpe] = React.useState(8);
  const mark = (k, v) => setStates(s => ({ ...s, [k]: v }));
  const doneCount = Object.values(states).filter(Boolean).length;

  const row = (k, name, planned, adjustBody) => {
    const st = states[k];
    return (
      <div style={{ background: SY.card,
        border: st ? '1px solid color-mix(in srgb, var(--ready-high), transparent 65%)'
          : '1px solid var(--border)',
        borderRadius: 16, padding: '12px 14px', marginBottom: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 14,
              fontWeight: 700 }}>{name}</div>
            <div className="af-mono" style={{ fontSize: 8.5, marginTop: 3,
              color: 'var(--fg-dim)' }}>PLANNED · {planned}</div>
          </div>
          <div className="af-seg" style={{ width: 150 }}>
            {[['plan', '✓ As planned'], ['adjust', 'Adjust']].map(([v, l]) => (
              <div key={v} className="af-seg-item" data-on={st === v}
                onClick={() => mark(k, v)}
                style={{ fontSize: 10, padding: '6px 2px' }}>{l}</div>
            ))}
          </div>
        </div>
        {st === 'adjust' && adjustBody}
      </div>
    );
  };

  const stepper = (label, val, ghost) => (
    <div style={{ flex: 1, background: SY.card2, borderRadius: 12,
      padding: '8px 10px' }}>
      <div className="af-mono" style={{ fontSize: 8,
        color: 'var(--fg-muted)' }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8,
        marginTop: 4 }}>
        <span style={{ cursor: 'pointer', color: 'var(--fg-muted)',
          fontWeight: 700 }}>−</span>
        <span className="dd-display" style={{ flex: 1, textAlign: 'center',
          fontSize: 15, fontWeight: 800 }}>{val}</span>
        <span style={{ cursor: 'pointer', color: 'var(--fg-muted)',
          fontWeight: 700 }}>＋</span>
      </div>
      {ghost && <div className="af-mono" style={{ fontSize: 7.5, marginTop: 3,
        color: 'var(--fg-dim)', textAlign: 'center' }}>{ghost}</div>}
    </div>
  );

  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => toast('Back — draft kept')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Activity
        </div>
        <div className="dd-display" style={{ fontSize: 22, fontWeight: 800,
          marginTop: 8 }}>What you actually did</div>
        <div className="af-mono" style={{ fontSize: 8.5, marginTop: 4,
          color: 'var(--fg-muted)' }}>
          LOWER BODY — POSTERIOR · MON 17:20 · {doneCount} OF 4 CONFIRMED</div>
        <div className="dd-display"
          onClick={() => { setStates({ squat: 'plan', rdl: 'plan',
            split: 'plan', nordic: 'plan' });
            toast('All confirmed as planned — adjust any if needed'); }}
          style={{ display: 'inline-block', marginTop: 9,
            background: SY.card2, borderRadius: 999, padding: '7px 13px',
            fontSize: 11.5, fontWeight: 700, cursor: 'pointer' }}>
          ✓ All as planned</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 150px' }}>
        {row('squat', 'Back squat', '3 × 5 · 85 KG',
          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            {stepper('SETS', 3, null)}
            {stepper('REPS', 5, null)}
            {stepper('KG', 90, 'PLANNED 85')}
          </div>)}
        {row('rdl', 'Romanian deadlift', '3 × 8 · 70 KG')}
        {row('split', 'Split squat', '2 × 10 · 2×20 KG')}
        {row('nordic', 'Nordic curl', '2 × 6 · SLOW')}

        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-muted)', margin: '14px 0 8px' }}>
          HOW HARD WAS IT? · RPE</div>
        <div className="af-rpe-grid">
          {Array.from({ length: 10 }, (_, i) => i + 1).map(n => (
            <button key={n} className="af-rpe" data-sel={rpe === n}
              onClick={() => setRpe(n)}>{n}</button>
          ))}
        </div>
        <div style={{ fontSize: 10, color: 'var(--fg-dim)', marginTop: 12,
          lineHeight: 1.5, textAlign: 'center' }}>
          Actuals update your history — next time this plan shows what you
          really lifted, not what was written.
        </div>
      </div>
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
        zIndex: 30 }}>
        <div className="dd-display dd-glow"
          onClick={() => doneCount === 4
            ? toast('Saved — session verified ✓ (panel 5)')
            : toast(`${4 - doneCount} exercises unconfirmed — confirm or adjust them`)}
          style={{ background: doneCount === 4 ? SY.lime : SY.card2,
            color: doneCount === 4 ? SY.ink : 'var(--fg-dim)',
            borderRadius: 999, padding: '15px 0', textAlign: 'center',
            fontSize: 14.5, fontWeight: 700, cursor: 'pointer',
            transition: 'background .3s, color .3s',
            boxShadow: doneCount === 4 ? undefined : 'none' }}>
          {doneCount === 4 ? `Save session · RPE ${rpe}`
            : `Confirm ${4 - doneCount} more to save`}
        </div>
      </div>
    </>
  );
}

// --------------------------------------------- 5 · Verified — the payoff
function SYVerifiedScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => toast('Back to Today')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Today
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12,
          marginTop: 10 }}>
          <SYChip icon="lift" bg={SY.purple}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 22,
              fontWeight: 800 }}>Lower body — posterior</div>
            <div className="af-mono" style={{ fontSize: 9, marginTop: 3,
              color: 'var(--fg-dim)' }}>MON 17:20 · 52 MIN · FROM STRAVA</div>
          </div>
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 96px' }}>
        <div style={{ padding: '11px 13px', borderRadius: 14,
          background: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
          border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Icon name="check" size={14} style={{ color: SY.lime }}/>
            <span className="dd-display" style={{ fontSize: 13,
              fontWeight: 700, color: SY.lime }}>Verified session</span>
          </div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 5,
            lineHeight: 1.5 }}>
            Strava metrics + your actuals + RPE 8 — counted once in Progress.
          </div>
        </div>

        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '14px 0 8px' }}>
          WHAT YOU DID · VS PLAN</div>
        <div style={{ background: SY.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '4px 14px' }}>
          {[['Back squat', '3 × 5 · 90 KG', '+5 KG VS PLAN', SY.lime],
            ['Romanian deadlift', '3 × 8 · 70 KG', 'AS PLANNED', 'var(--fg-dim)'],
            ['Split squat', '2 × 10 · 2×20 KG', 'AS PLANNED', 'var(--fg-dim)'],
            ['Nordic curl', '2 × 6', 'AS PLANNED', 'var(--fg-dim)']].map(([n, d, delta, c], i) => (
            <div key={n} style={{ display: 'flex', alignItems: 'center',
              gap: 10, padding: '11px 0',
              borderTop: i === 0 ? 'none' : '1px solid var(--border)' }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="dd-display" style={{ fontSize: 13.5,
                  fontWeight: 600 }}>{n}</div>
                <div className="af-mono" style={{ fontSize: 9, marginTop: 2,
                  color: 'var(--fg-muted)' }}>{d}</div>
              </div>
              <span className="af-mono" style={{ fontSize: 8, color: c }}>
                {delta}</span>
            </div>
          ))}
        </div>
        <div style={{ fontSize: 10, color: 'var(--fg-dim)', marginTop: 12,
          lineHeight: 1.5, textAlign: 'center' }}>
          Next time you run this plan, the editor ghosts show 90 kg — your
          real last time.
        </div>
      </div>
    </>
  );
}

function DDActualsScreen({ dd, set, nav, preset }) {
  if (preset === 'sync') return <SYFirstSyncScreen set={set}/>;
  if (preset === 'map') return <SYMapScreen set={set}/>;
  if (preset === 'actuals') return <SYActualsScreen set={set}/>;
  if (preset === 'verified') return <SYVerifiedScreen set={set}/>;
  return <SYConnectScreen set={set}/>;
}

Object.assign(window, { DDActualsScreen, SYConnectScreen, SYFirstSyncScreen,
  SYMapScreen, SYActualsScreen, SYVerifiedScreen });
