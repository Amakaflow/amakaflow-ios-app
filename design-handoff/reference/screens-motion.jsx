/**
 * DD Motion — "it writes itself". 2026-08-05 (+reel import & AI draft).
 * DISPOSABLE. One build engine, three surfaces:
 *   · watch  — To your Apple Watch plan composes (COMPOSING…)
 *   · import — Instagram reel parses into a workout (PARSING…)
 *   · ai     — Create-with-AI draft writes in (DRAFTING…), WHY THIS
 *              bullets type first, then the blocks
 * Motion tokens: fast 160 · base 280 · slow 420ms;
 * ease-out-quart cubic-bezier(.25,1,.5,1); spring cubic-bezier(.34,1.4,.64,1);
 * stagger 130ms/beat. SwiftUI: .spring(response:0.35,dampingFraction:0.8);
 * wipe ≈ mask + width anim; streamed-LLM beats = one beat per SSE chunk.
 */

const SM = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', purple: '#C58AF4', gray: '#8890A0',
};

// ---------------------------------------------------------------- scripts
// Beat kinds: band · row (under last band) · bullet (WHY THIS) ·
// credit (provenance card) · pills (meta pill row)
const SM_WATCH = {
  title: 'To your Apple Watch',
  verb: 'COMPOSING', doneNote: 'PREP + RAMPS + COOLDOWN',
  cta: 'Schedule on the watch', building: 'Composing…',
  script: [
    { t: 'band', label: 'Mobility prep', tag: '2 STEPS · ~4 MIN', color: SM.gray },
    { t: 'row', name: 'Ski erg', d: '500 M · EASY', chip: 'REST · YOU END IT' },
    { t: 'row', name: 'Assault bike', d: '2:00 MIN · EASY' },
    { t: 'band', label: 'Deadlift', tag: 'RAMP + 3 WORKING', color: SM.lime },
    { t: 'row', name: 'Warm-up set', d: '8 REPS · LIGHT · ~40%', chip: 'REST · YOU END IT' },
    { t: 'row', name: 'Warm-up set', d: '5 REPS · MODERATE · ~60%', chip: 'REST · YOU END IT' },
    { t: 'row', name: 'Working sets ×3', d: '10 REPS', chip: 'REST · YOU END IT' },
    { t: 'band', label: 'Leg Press', tag: 'NO WARM-UPS — YOUR CALL', color: SM.lime },
    { t: 'row', name: 'Working sets ×3', d: '10 REPS', chip: 'REST · YOU END IT' },
    { t: 'band', label: 'Overhead Press', tag: 'RAMP + 3 WORKING', color: SM.lime },
    { t: 'row', name: 'Warm-up set', d: '8 REPS · LIGHT', chip: 'REST · YOU END IT' },
    { t: 'row', name: 'Warm-up set', d: 'OPEN · GO TILL READY · END ON TAP', open: true },
    { t: 'row', name: 'Working sets ×3', d: '10 REPS', chip: 'REST · YOU END IT' },
    { t: 'band', label: 'Cooldown', tag: '2 STEPS · AFTER THE LAST SET', color: SM.blue },
    { t: 'row', name: 'Stretch flow', d: '3:00 MIN · EASY' },
    { t: 'row', name: 'Treadmill', d: 'OPEN · WALK IT OFF · END ON TAP', open: true },
  ],
};

const SM_IMPORT = {
  title: 'DB Full-body AMRAP',
  verb: 'PARSING', doneNote: 'FROM THE REEL — NOTHING SAVED YET',
  cta: 'Check the structure', building: 'Parsing the reel…',
  script: [
    { t: 'credit', initial: 'g', bg: SM.purple, name: 'gospelofgainz',
      sub: 'REEL CAPTION + VIDEO PARSED' },
    { t: 'pills', pills: ['FROM INSTAGRAM', '5 ROUNDS · ~20 MIN', 'HIIT'] },
    { t: 'band', label: 'Round 1–3', tag: '3 ROUNDS · ~12 MIN', color: '#F4A24A' },
    { t: 'row', name: 'Wall balls', d: '20 REPS · MED BALL 6 KG' },
    { t: 'row', name: 'Barbell thrusters', d: '12 REPS · 40 KG',
      chip: 'SWAP? NO BARBELL', open: true },
    { t: 'row', name: 'Burpee broad jumps', d: '10 REPS · BODYWEIGHT' },
    { t: 'band', label: 'Finisher', tag: '1 ROUND · ~4 MIN', color: SM.purple },
    { t: 'row', name: 'Sled push', d: '2 × 20 M · 80 KG',
      chip: 'SWAP? NO SLED', open: true },
  ],
};

const SM_AI = {
  title: 'Chest Pump — 45',
  verb: 'DRAFTING', doneNote: 'DRAFT · NOT SAVED — REFINE OR COMMIT',
  cta: 'Save to Library', building: 'Drafting…',
  script: [
    { t: 'pills', pills: ['~43 MIN', 'STRENGTH', '5 EXERCISES + WU', 'FITS HOME GYM ✓'] },
    { t: 'bullet', d: 'Your ask: chest pump · ~45 min · nothing on cables' },
    { t: 'bullet', d: 'Readiness 78% — normal load; bench +2.5 kg vs last time' },
    { t: 'bullet', d: 'No cables at Home gym — band fly stands in' },
    { t: 'band', label: 'Warm-up', tag: '~5 MIN', color: SM.gray },
    { t: 'row', name: 'Band pull-aparts', d: '2 × 15 · LIGHT' },
    { t: 'row', name: 'Incline push-up', d: '2 × 10 · BODYWEIGHT' },
    { t: 'band', label: 'Chest pump', tag: '5 EXERCISES · ~38 MIN', color: SM.lime },
    { t: 'row', name: 'Bench press', d: '3 × 8 · 77 KG', chip: 'REST 90S' },
    { t: 'row', name: 'Incline DB press', d: '3 × 8 · 2×24 KG', chip: 'REST 90S' },
    { t: 'row', name: 'Dumbbell fly', d: '3 × 10 · 2×14 KG', chip: 'REST 60S' },
    { t: 'row', name: 'Band fly', d: '3 × 12 · SWAPPED — NO CABLES',
      chip: 'REST 60S', open: true },
    { t: 'row', name: 'Chest dip', d: '3 × 8 · BODYWEIGHT', chip: 'REST 60S' },
  ],
};

// ------------------------------------------------------------ build engine
function SMBuildScreen({ set, cfg, speed = 1 }) {
  const [visible, setVisible] = React.useState(0);
  const [done, setDone] = React.useState(false);
  const [runId, setRunId] = React.useState(0);
  const scrollRef = React.useRef(null);
  const total = cfg.script.filter(x => x.t === 'row' || x.t === 'bullet').length;

  React.useEffect(() => {
    setVisible(0); setDone(false);
    let i = 0; let timer = null;
    const kick = setTimeout(() => {
      timer = setInterval(() => {
        i += 1;
        setVisible(i);
        if (i >= cfg.script.length) {
          clearInterval(timer); timer = null;
          setTimeout(() => setDone(true), 260 / speed);
        }
      }, 130 / speed);
    }, 420 / speed);
    return () => { clearTimeout(kick); if (timer) clearInterval(timer); };
  }, [runId, speed]);

  React.useEffect(() => {
    if (scrollRef.current)
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [visible]);

  const shown = cfg.script.slice(0, visible);
  const countShown = shown.filter(x => x.t === 'row' || x.t === 'bullet').length;

  // assemble render list in script order; rows nest under last band
  const out = [];
  shown.forEach(b => {
    if (b.t === 'band') out.push({ kind: 'band', band: b, rows: [] });
    else if (b.t === 'row' && out.length && out[out.length - 1].kind === 'band')
      out[out.length - 1].rows.push(b);
    else out.push({ kind: b.t, beat: b });
  });
  let rowNum = 0;

  return (
    <>
      <div style={{ padding: '10px 18px', opacity: 0.3 }}>
        <div className="dd-display" style={{ fontSize: 22, fontWeight: 800,
          marginTop: 2 }}>{cfg.title}</div>
      </div>
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0,
        top: 58, background: 'var(--bg-elev)', borderRadius: '20px 20px 0 0',
        padding: '14px 20px 0', zIndex: 40, display: 'flex',
        flexDirection: 'column',
        animation: 'sm-sheet-in .42s cubic-bezier(.25,1,.5,1)' }}>
        <div className="af-sheet-handle"/>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div className="af-h2">{cfg.title}</div>
          <span className="dd-display" onClick={() => setRunId(r => r + 1)}
            style={{ marginLeft: 'auto', fontSize: 11.5, fontWeight: 700,
              color: 'var(--fg-muted)', background: SM.card2,
              borderRadius: 999, padding: '6px 12px', cursor: 'pointer' }}>
            ↺ Replay</span>
        </div>
        <div className="af-mono" style={{ fontSize: 8.5, margin: '6px 0 12px',
          color: done ? SM.lime : 'var(--fg-dim)', transition: 'color .3s' }}>
          {done ? `READY · ${cfg.doneNote}`
            : `${cfg.verb}… ${countShown} OF ${total}`}
          {!done && <span className="sm-caret">▍</span>}
        </div>

        <div ref={scrollRef} className="af-scroll" style={{ flex: 1,
          overflowY: 'auto', paddingBottom: 110, scrollBehavior: 'smooth' }}>
          {out.map((el, i) => {
            if (el.kind === 'credit') return (
              <div key={i} className="sm-row" style={{ display: 'flex',
                alignItems: 'center', gap: 10, background: SM.card,
                border: '1px solid var(--border)', borderRadius: 12,
                padding: '9px 12px', marginBottom: 10 }}>
                <div className="dd-display sm-num" style={{ width: 30,
                  height: 30, borderRadius: 999, background: el.beat.bg,
                  color: '#fff', display: 'flex', alignItems: 'center',
                  justifyContent: 'center', fontSize: 13, fontWeight: 800 }}>
                  {el.beat.initial}</div>
                <div style={{ flex: 1 }}>
                  <div className="dd-display" style={{ fontSize: 12.5,
                    fontWeight: 700 }}>{el.beat.name}</div>
                  <div className="af-mono sm-wipe" style={{ fontSize: 8,
                    marginTop: 2, color: 'var(--fg-dim)' }}>{el.beat.sub}</div>
                </div>
              </div>
            );
            if (el.kind === 'pills') return (
              <div key={i} className="sm-row" style={{ display: 'flex', gap: 6,
                flexWrap: 'wrap', marginBottom: 10 }}>
                {el.beat.pills.map((p, pi) => (
                  <span key={p} className="af-mono sm-chip" style={{ fontSize: 8.5,
                    padding: '4px 9px', borderRadius: 999, background: SM.card2,
                    color: 'var(--fg-muted)',
                    animationDelay: `${pi * 70}ms` }}>{p}</span>
                ))}
              </div>
            );
            if (el.kind === 'bullet') return (
              <div key={i} className="sm-row" style={{ display: 'flex', gap: 8,
                alignItems: 'flex-start', marginBottom: 6, padding: '0 2px' }}>
                <span className="sm-num" style={{ width: 5, height: 5,
                  borderRadius: 99, background: SM.lime, marginTop: 6,
                  flexShrink: 0 }}/>
                <span className="sm-wipe" style={{ fontSize: 11.5,
                  lineHeight: 1.5, color: 'var(--fg)' }}>{el.beat.d}</span>
              </div>
            );
            // band + rows
            return (
              <div key={i} style={{ margin: '4px 0 10px',
                animation: 'sm-band-in .28s cubic-bezier(.25,1,.5,1) both' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8,
                  background: `color-mix(in srgb, ${el.band.color}, transparent 84%)`,
                  border: `1px solid color-mix(in srgb, ${el.band.color}, transparent 60%)`,
                  borderRadius: el.rows.length ? '12px 12px 0 0' : 12,
                  padding: '7px 12px' }}>
                  <span className="dd-display" style={{ fontSize: 12,
                    fontWeight: 700, color: el.band.color }}>{el.band.label}</span>
                  <span className="af-mono" style={{ marginLeft: 'auto',
                    fontSize: 8.5, color: 'var(--fg-muted)' }}>{el.band.tag}</span>
                </div>
                {el.rows.length > 0 && (
                  <div style={{ background: SM.card,
                    border: '1px solid var(--border)', borderTop: 'none',
                    borderRadius: '0 0 12px 12px', padding: '2px 12px' }}>
                    {el.rows.map((r, ri) => {
                      rowNum += 1; const n = rowNum;
                      return (
                        <div key={ri} className="sm-row" style={{ display: 'flex',
                          alignItems: 'center', gap: 10, padding: '10px 0',
                          borderTop: ri === 0 ? 'none' : '1px solid var(--border)' }}>
                          <span className="af-mono sm-num" style={{ fontSize: 10,
                            fontWeight: 700, color: 'var(--fg-dim)',
                            width: 16 }}>{n}</span>
                          <div style={{ flex: 1, minWidth: 0 }}>
                            <div className="dd-display" style={{ fontSize: 13,
                              fontWeight: 600 }}>{r.name}</div>
                            <div className="af-mono sm-wipe" style={{ fontSize: 9,
                              marginTop: 2,
                              color: r.open ? 'var(--ready-mod)'
                                : 'var(--fg-muted)' }}>{r.d}</div>
                          </div>
                          {r.chip && <span className="af-mono sm-chip"
                            style={{ fontSize: 8, padding: '4px 8px',
                              borderRadius: 999,
                              background: r.open
                                ? 'color-mix(in srgb, var(--ready-mod), transparent 84%)'
                                : SM.card2,
                              color: r.open ? 'var(--ready-mod)'
                                : 'var(--fg-muted)',
                              flexShrink: 0 }}>{r.chip}</span>}
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12 }}>
          <div className="dd-display"
            onClick={() => done && set && set(s => ({ ...s, toast: `${cfg.cta} ✓` }))}
            style={{ background: done ? SM.lime : SM.card2,
              color: done ? SM.ink : 'var(--fg-dim)', borderRadius: 999,
              padding: '15px 0', textAlign: 'center', fontSize: 14.5,
              fontWeight: 700, cursor: done ? 'pointer' : 'default',
              transition: 'background .35s, color .35s',
              animation: done ? 'sm-cta-land .5s cubic-bezier(.34,1.4,.64,1)' : 'none' }}>
            {done ? cfg.cta : cfg.building}
          </div>
        </div>
      </div>
    </>
  );
}

function DDMotionScreen({ dd, set, nav, preset }) {
  if (preset === 'import') return <SMBuildScreen set={set} cfg={SM_IMPORT}/>;
  if (preset === 'ai') return <SMBuildScreen set={set} cfg={SM_AI}/>;
  if (preset === 'ai-half') return <SMBuildScreen set={set} cfg={SM_AI} speed={0.5}/>;
  if (preset === 'half') return <SMBuildScreen set={set} cfg={SM_WATCH} speed={0.5}/>;
  return <SMBuildScreen set={set} cfg={SM_WATCH}/>;
}

Object.assign(window, { DDMotionScreen, SMBuildScreen });
