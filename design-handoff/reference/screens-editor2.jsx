/**
 * Editor v2 — Hevy-pattern rework (Mobbin research 2026-07-20). DISPOSABLE.
 * Principles verified on Mobbin (Hevy flows):
 *  · flat exercise cards — name + summary only, structure shown as a
 *    colored rail + pill label, never an accordion container
 *  · one ⋯ menu per card holds ALL structural verbs — each its own tiny flow
 *  · tap a card → focused sheet editing ONLY that exercise's numbers
 *  · reorder is a dedicated mode: compact rows + drag handles + Done
 *  · group settings (rounds/rest) behind a tap on the group pill
 *  · CREATION IS THE SAME SURFACE: mode="new" starts empty — add
 *    exercises with sane defaults, structure emerges later.
 *  · FORMAT-FIRST is an optional shortcut, not a gate: quiet chips on the
 *    empty state (EMOM / AMRAP / Tabata / For time / Circuit) pin a format
 *    pill; added exercises land inside it. Skipping them = straight sets.
 *    The group-pill sheet has the same type switcher, so any group can be
 *    converted after the fact too.
 * Edit-mode demo content = Hyrox Upper Body (post-clarify, AMA-2304).
 */

const E2 = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
};

// One registry: label, color, default config, which steppers it needs
const E2_TYPES = {
  superset: { label: 'Superset', color: 'var(--ready-mod)', d: { rounds: 3, rest: 60 } },
  circuit:  { label: 'Circuit',  color: '#4AD97F', d: { rounds: 4 } },
  emom:     { label: 'EMOM',     color: '#5AB8F4', d: { rounds: 10 } },
  amrap:    { label: 'AMRAP',    color: '#F4A24A', d: { capMin: 10 } },
  tabata:   { label: 'Tabata',   color: '#F4564A', d: { workSec: 20, restSec: 10, rounds: 8 } },
  fortime:  { label: 'For time', color: '#C58AF4', d: { capMin: 20 } },
  warmup:   { label: 'Warm-up',  color: '#8890A0', d: { rounds: 2 } },
};
const E2_FORMATS = ['emom', 'amrap', 'tabata', 'fortime', 'circuit'];

const e2GroupsInit = () => ({
  wu:  { type: 'warmup',   name: 'Warm-up',    rounds: 2 },
  ssA: { type: 'superset', name: 'Superset A', rounds: 4, rest: 180 },
  ssB: { type: 'superset', name: 'Superset B', rounds: 4, rest: 90 },
  fin: { type: 'circuit',  name: 'Finisher',   rounds: 5 },
});
const e2ExsInit = () => [
  { id: 1,  n: 'Ski',                      dist: 1000, grp: 'wu' },
  { id: 2,  n: 'Press ups',                sets: 2, reps: 5,  grp: 'wu' },
  { id: 3,  n: 'Pull ups',                 sets: 2, reps: 5,  grp: 'wu' },
  { id: 4,  n: 'Bench Press',              sets: 4, reps: 8, weight: 60, grp: 'ssA' },
  { id: 5,  n: 'Pull Ups',                 sets: 4, reps: 8,  grp: 'ssA' },
  { id: 6,  n: 'Single-Arm Incline Press', sets: 4, reps: 8, weight: 22, grp: 'ssB' },
  { id: 7,  n: 'Single-Arm Incline Row',   sets: 4, reps: 8, weight: 22, grp: 'ssB' },
  { id: 8,  n: 'Incline Bicep Curls',      sets: 3, reps: 12, weight: 10, rest: 60, grp: null },
  { id: 9,  n: 'Ski',                      dist: 300, grp: 'fin' },
  { id: 10, n: 'Farmers Walk',             dist: 40, weight: 32, grp: 'fin' },
];
// Rig preset: EMOM-first creation, two moves in
const e2EmomGroups = () => ({ fmt: { type: 'emom', name: 'EMOM', rounds: 10 } });
const e2EmomExs = () => [
  { id: 1, n: 'Cal Row', reps: 12, grp: 'fmt' },
  { id: 2, n: 'Burpees', reps: 10, grp: 'fmt' },
];

// Equipment-aware library (same demo data as the old editor's add sheet)
const E2_LIB = [
  ['Wall balls', 'CONDITIONING · MED BALL ✓'],
  ['DB thrusters', 'FULL BODY · DUMBBELLS ✓'],
  ['Burpee broad jumps', 'BODYWEIGHT ✓'],
  ['Rower', 'MACHINE · ROWER ✓'],
  ['KB swing', 'POSTERIOR · KETTLEBELL ✓'],
  ['Goblet squat', 'QUADS · KETTLEBELL ✓'],
  ['Barbell back squat', 'STRENGTH · BARBELL — NOT IN YOUR GYM'],
];

function e2Sum(e) {
  const p = [];
  if (e.sets) p.push(`${e.sets} × ${e.reps}`);
  else if (e.reps) p.push(`${e.reps} REPS`);
  if (e.dist) p.push(`${e.dist} M`);
  if (e.weight) p.push(`${e.weight} KG`);
  if (e.rest) p.push(`${e.rest}S REST`);
  return p.join(' · ');
}
function e2GroupMeta(g) {
  if (g.type === 'warmup') return `${g.rounds} ROUNDS · EASY`;
  if (g.type === 'circuit') return `${g.rounds} ROUNDS · FOR TIME`;
  if (g.type === 'emom') return `${g.rounds} MIN · EVERY MINUTE`;
  if (g.type === 'amrap') return `${g.capMin} MIN CAP · MAX ROUNDS`;
  if (g.type === 'tabata') return `${g.workSec}S ON · ${g.restSec}S OFF · ×${g.rounds}`;
  if (g.type === 'fortime') return `FOR TIME · ${g.capMin} MIN CAP`;
  return `${g.rounds} ROUNDS · ${g.rest >= 60 ? `${Math.round(g.rest / 60)} MIN` : `${g.rest}S`} REST`;
}
// Which steppers each group type needs — nothing more is shown
function e2GroupRows(g) {
  if (g.type === 'emom') return [['Minutes', 'rounds', 1, 60, 1]];
  if (g.type === 'amrap') return [['Cap min', 'capMin', 1, 60, 1]];
  if (g.type === 'tabata') return [['Work s', 'workSec', 5, 120, 5],
    ['Rest s', 'restSec', 0, 120, 5], ['Rounds', 'rounds', 1, 20, 1]];
  if (g.type === 'fortime') return [['Cap min', 'capMin', 1, 90, 1]];
  if (g.type === 'circuit' || g.type === 'warmup')
    return [['Rounds', 'rounds', 1, 20, 1]];
  return [['Rounds', 'rounds', 1, 20, 1], ['Rest s', 'rest', 0, 600, 15]];
}

function E2Stepper({ label, value, onChange, min = 0, max = 999, step = 1, unit }) {
  const bump = (d) => onChange(Math.min(max, Math.max(min, (value || 0) + d * step)));
  return (
    <div style={{ flex: 1, minWidth: 92, background: E2.card2, borderRadius: 14,
      padding: '10px 12px' }}>
      <div className="af-mono" style={{ fontSize: 8.5, color: 'var(--fg-muted)' }}>
        {label.toUpperCase()}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 6 }}>
        <span onClick={() => bump(-1)} className="dd-display"
          style={{ cursor: 'pointer', fontSize: 20, fontWeight: 700,
            color: 'var(--fg-muted)', padding: '0 6px' }}>−</span>
        <span className="dd-display" style={{ flex: 1, textAlign: 'center',
          fontSize: 17, fontWeight: 800 }}>{value || 0}{unit || ''}</span>
        <span onClick={() => bump(1)} className="dd-display"
          style={{ cursor: 'pointer', fontSize: 20, fontWeight: 700,
            color: 'var(--fg-muted)', padding: '0 6px' }}>＋</span>
      </div>
    </div>
  );
}

// One exercise card — name + summary + ⋯. Nothing else.
function E2Card({ e, inGroup, first, onOpen, onMenu }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 11,
      padding: '12px 13px',
      borderTop: inGroup && !first ? '1px solid var(--border)' : 'none',
      background: inGroup ? 'transparent' : E2.card,
      border: inGroup ? 'none' : '1px solid var(--border)',
      borderRadius: inGroup ? 0 : 16,
      marginBottom: inGroup ? 0 : 8 }}>
      <div onClick={onOpen} style={{ flex: 1, minWidth: 0, cursor: 'pointer' }}>
        <div className="dd-display" style={{ fontSize: 14, fontWeight: 600 }}>{e.n}</div>
        <div className="af-mono" style={{ fontSize: 9.5, marginTop: 3,
          color: 'var(--fg-muted)' }}>{e2Sum(e)}</div>
      </div>
      <div onClick={onMenu} style={{ cursor: 'pointer', padding: '6px 4px',
        color: 'var(--fg-dim)' }}>
        <Icon name="kebab" size={16}/>
      </div>
    </div>
  );
}

// ------------------------------------------------------------------ screen
// mode: 'edit' (default — Hyrox Upper Body) | 'new' (create from scratch)
// preset (rig only): 'menu' | 'sheet' | 'reorder' | 'add' | 'emom'
function DDEditor2Screen({ dd, set, nav, mode = 'edit', preset }) {
  const isNew = mode === 'new' || preset === 'emom';
  const [groups, setGroups] = React.useState(
    preset === 'emom' ? e2EmomGroups : isNew ? {} : e2GroupsInit);
  const [exs, setExs] = React.useState(
    preset === 'emom' ? e2EmomExs : isNew ? [] : e2ExsInit);
  const [title, setTitle] = React.useState(
    preset === 'emom' ? 'Engine EMOM' : isNew ? '' : 'Hyrox Upper Body');
  const [menuFor, setMenuFor] = React.useState(preset === 'menu' ? 4 : null);
  const [editFor, setEditFor] = React.useState(preset === 'sheet' ? 4 : null);
  const [confFor, setConfFor] = React.useState(null);   // group key
  const [pairFor, setPairFor] = React.useState(null);   // exercise id
  const [reorder, setReorder] = React.useState(preset === 'reorder');
  const [dragId, setDragId] = React.useState(null);
  const [addOpen, setAddOpen] = React.useState(preset === 'add');
  const [q, setQ] = React.useState('');
  const nextId = React.useRef(100);

  // Active workout-level format (created via the empty-state chips):
  // new exercises land inside it.
  const fmtKey = groups.fmt ? 'fmt' : null;

  const byId = (id) => exs.find(e => e.id === id);
  const upEx = (id, patch) => setExs(es => es.map(e =>
    e.id === id ? { ...e, ...patch } : e));
  const removeEx = (id) => { setExs(es => es.filter(e => e.id !== id));
    setMenuFor(null); set(s => ({ ...s, toast: 'Removed — undo in toast IRL' })); };
  const addSet = (id) => { const e = byId(id);
    if (e && e.sets) upEx(id, { sets: e.sets + 1 });
    setMenuFor(null); set(s => ({ ...s, toast: 'Set added ✓' })); };
  const upGroup = (key, patch) => setGroups(gs =>
    ({ ...gs, [key]: { ...gs[key], ...patch } }));
  const ungroup = (key) => { setExs(es => es.map(e =>
      e.grp === key ? { ...e, grp: null } : e));
    setGroups(gs => { const c = { ...gs }; delete c[key]; return c; });
    setConfFor(null); set(s => ({ ...s, toast: 'Ungrouped — now straight sets' })); };
  const switchType = (key, t) => {
    setGroups(gs => ({ ...gs, [key]: { ...E2_TYPES[t].d, ...{},
      name: gs[key].name && !E2_TYPES[gs[key].type] ? gs[key].name
        : E2_TYPES[t].label,
      type: t } }));
    set(s => ({ ...s, toast: `Now runs as ${E2_TYPES[t].label} ✓` }));
  };

  // Format-first: chip on the empty state pins a format group
  const startFormat = (t) => {
    setGroups({ fmt: { ...E2_TYPES[t].d, type: t, name: E2_TYPES[t].label } });
    set(s => ({ ...s, toast: `${E2_TYPES[t].label} — add the moves, timing is set` }));
  };

  // Creation: add with sane defaults — into the format if one is pinned.
  // Timed formats don't want 3×10: inside EMOM/AMRAP/Tabata/circuit an
  // exercise lands as plain reps.
  const addEx = (name) => {
    const fmtType = fmtKey ? groups.fmt.type : null;
    const timed = fmtType && fmtType !== 'superset';
    setExs(es => [...es, timed
      ? { id: nextId.current++, n: name, reps: 10, grp: fmtKey }
      : { id: nextId.current++, n: name, sets: 3, reps: 10, rest: 60, grp: null }]);
    setQ('');
    set(s => ({ ...s, toast: timed
      ? `${name} added to the ${E2_TYPES[fmtType].label}`
      : `${name} added · 3×10 · 60s — tap to tweak` }));
  };

  // Superset pairing — the Hevy "Superset X with:" picker
  const pair = (srcId, tgtId) => {
    const tgt = byId(tgtId);
    let key = tgt.grp && groups[tgt.grp] && groups[tgt.grp].type === 'superset'
      ? tgt.grp : null;
    if (!key) {
      key = `ss${Date.now() % 10000}`;
      setGroups(gs => ({ ...gs, [key]: { type: 'superset', name: 'Superset',
        rounds: 3, rest: 60 } }));
      setExs(es => es.map(e => e.id === tgtId ? { ...e, grp: key } : e));
    }
    setExs(es => {
      const src = es.find(e => e.id === srcId);
      const rest = es.filter(e => e.id !== srcId);
      const ti = rest.findIndex(e => e.id === tgtId);
      return [...rest.slice(0, ti + 1), { ...src, grp: key },
        ...rest.slice(ti + 1)];
    });
    setPairFor(null);
    set(s => ({ ...s, toast: `Superset: ${byId(srcId).n} + ${tgt.n} ✓` }));
  };

  // HTML5 drag — reorder mode only
  const dragOver = (overId) => {
    if (dragId == null || dragId === overId) return;
    setExs(es => {
      const from = es.findIndex(e => e.id === dragId);
      const to = es.findIndex(e => e.id === overId);
      if (from < 0 || to < 0) return es;
      const c = [...es]; const [m] = c.splice(from, 1); c.splice(to, 0, m);
      return c;
    });
  };

  // Build render runs: consecutive same-group exercises share one rail
  const runs = [];
  exs.forEach(e => {
    const last = runs[runs.length - 1];
    if (e.grp && last && last.grp === e.grp) last.items.push(e);
    else runs.push({ grp: e.grp, items: [e] });
  });

  const menuEx = menuFor != null ? byId(menuFor) : null;
  const editEx = editFor != null ? byId(editFor) : null;
  const confG = confFor ? groups[confFor] : null;
  const lib = E2_LIB.filter(([n]) =>
    !q || n.toLowerCase().includes(q.toLowerCase()));
  const GroupPill = ({ gkey, g }) => {
    const T = E2_TYPES[g.type] || E2_TYPES.superset;
    return (
      <div onClick={() => setConfFor(gkey)}
        style={{ display: 'flex', alignItems: 'center', gap: 8,
          padding: '0 2px 6px', cursor: 'pointer' }}>
        <span className="af-mono" style={{ fontSize: 8.5, fontWeight: 700,
          padding: '4px 9px', borderRadius: 999,
          background: `color-mix(in srgb, ${T.color}, transparent 82%)`,
          color: T.color }}>{(g.name || T.label).toUpperCase()}</span>
        <span className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)' }}>{e2GroupMeta(g)}</span>
        <Icon name="sliders" size={12}
          style={{ marginLeft: 'auto', color: 'var(--fg-dim)' }}/>
      </div>
    );
  };

  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div onClick={() => nav('dd-build')}
            style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
              color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
              cursor: 'pointer' }}>
            <Icon name="chevL" size={16}/> Back
          </div>
          {exs.length > 1 && (
            <span className="dd-display"
              onClick={() => setReorder(r => !r)}
              style={{ marginLeft: 'auto', fontSize: 12.5, fontWeight: 700,
                color: reorder ? E2.lime : 'var(--fg-muted)', cursor: 'pointer' }}>
              {reorder ? '✓ Done' : '⇅ Reorder'}</span>
          )}
        </div>
        <input value={title} onChange={(e) => setTitle(e.target.value)}
          placeholder={isNew ? 'Name your workout' : 'Workout title'}
          className="dd-display"
          style={{ all: 'unset', display: 'block', width: '100%', fontSize: 24,
            fontWeight: 800, marginTop: 10,
            fontFamily: 'Poppins, Geist, sans-serif',
            letterSpacing: '-0.02em', color: 'var(--fg)' }}/>
        <div className="af-mono" style={{ fontSize: 9, marginTop: 5,
          color: 'var(--fg-dim)' }}>
          {reorder ? 'DRAG ROWS TO REORDER · TAP DONE WHEN FINISHED'
            : exs.length === 0 ? 'JUST ADD EXERCISES — STRUCTURE COMES LATER'
            : 'TAP AN EXERCISE TO EDIT IT · ⋯ FOR EVERYTHING ELSE'}</div>
      </div>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 120px' }}>

        {/* ------------------------------------------------ empty state */}
        {!reorder && exs.length === 0 && !fmtKey && (
          <div style={{ textAlign: 'center', padding: '22px 10px 14px' }}>
            <div className="dd-display" style={{ fontSize: 15, fontWeight: 700 }}>
              Start with any exercise</div>
            <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 6,
              lineHeight: 1.55 }}>
              Every exercise lands as 3 × 10 · 60s rest — tap it to tweak.
              Pair any two into a superset with ⋯ whenever you're ready.
            </div>
            {/* Format-first shortcut — optional, skippable */}
            <div className="af-mono" style={{ fontSize: 9,
              color: 'var(--fg-dim)', margin: '18px 0 8px' }}>
              KNOW THE FORMAT ALREADY?</div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap',
              justifyContent: 'center' }}>
              {E2_FORMATS.map(t => (
                <span key={t} className="dd-display" onClick={() => startFormat(t)}
                  style={{ padding: '8px 13px', borderRadius: 999, fontSize: 12,
                    fontWeight: 700, cursor: 'pointer', background: E2.card2,
                    border: `1px solid color-mix(in srgb, ${E2_TYPES[t].color}, transparent 55%)` }}>
                  {E2_TYPES[t].label}</span>
              ))}
            </div>
          </div>
        )}

        {/* Format pinned but no moves yet */}
        {!reorder && exs.length === 0 && fmtKey && (
          <div style={{ marginBottom: 10 }}>
            <GroupPill gkey="fmt" g={groups.fmt}/>
            <div style={{ border: `1.5px dashed var(--border-str)`,
              borderRadius: 16, padding: '22px 14px', textAlign: 'center' }}>
              <div className="dd-display" style={{ fontSize: 13.5,
                fontWeight: 700 }}>Timing's set — add the moves</div>
              <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 5,
                lineHeight: 1.5 }}>
                Everything you add runs inside this {E2_TYPES[groups.fmt.type].label}.
                Tap the pill to change {groups.fmt.type === 'tabata'
                  ? 'work / rest / rounds' : 'the numbers'} — or the format.
              </div>
            </div>
          </div>
        )}

        {/* ------------------------------------------------ reorder mode */}
        {reorder && exs.map(e => {
          const g = e.grp ? groups[e.grp] : null;
          const T = g ? (E2_TYPES[g.type] || E2_TYPES.superset) : null;
          return (
            <div key={e.id} draggable
              onDragStart={() => setDragId(e.id)}
              onDragEnd={() => setDragId(null)}
              onDragOver={(ev) => { ev.preventDefault(); dragOver(e.id); }}
              style={{ display: 'flex', alignItems: 'center', gap: 10,
                background: dragId === e.id
                  ? 'color-mix(in srgb, var(--ready-high), transparent 85%)'
                  : E2.card,
                border: '1px solid var(--border)',
                borderLeft: T ? `3px solid ${T.color}` : '1px solid var(--border)',
                borderRadius: 12, padding: '10px 12px', marginBottom: 6,
                cursor: 'grab' }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="dd-display" style={{ fontSize: 13,
                  fontWeight: 600 }}>{e.n}</div>
                {g && <div className="af-mono" style={{ fontSize: 8,
                  color: T.color, marginTop: 2 }}>
                  {(g.name || T.label).toUpperCase()}</div>}
              </div>
              <Icon name="grip" size={16} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          );
        })}
        {reorder && (
          <div className="dd-display dd-glow" onClick={() => setReorder(false)}
            style={{ background: E2.lime, color: E2.ink, borderRadius: 999,
              padding: '13px 0', textAlign: 'center', fontSize: 14,
              fontWeight: 700, cursor: 'pointer', marginTop: 10 }}>
            Done</div>
        )}

        {/* ------------------------------------------------ normal mode */}
        {!reorder && runs.map((run, ri) => {
          const g = run.grp ? groups[run.grp] : null;
          if (!g) return run.items.map(e => (
            <E2Card key={e.id} e={e}
              onOpen={() => setEditFor(e.id)} onMenu={() => setMenuFor(e.id)}/>
          ));
          const T = E2_TYPES[g.type] || E2_TYPES.superset;
          return (
            <div key={ri} style={{ marginBottom: 10 }}>
              <GroupPill gkey={run.grp} g={g}/>
              <div style={{ background: E2.card, border: '1px solid var(--border)',
                borderLeft: `3px solid ${T.color}`, borderRadius: 16,
                overflow: 'hidden' }}>
                {run.items.map((e, i) => (
                  <E2Card key={e.id} e={e} inGroup first={i === 0}
                    onOpen={() => setEditFor(e.id)}
                    onMenu={() => setMenuFor(e.id)}/>
                ))}
              </div>
            </div>
          );
        })}

        {!reorder && (
          <div className="dd-display"
            onClick={() => setAddOpen(true)}
            style={{ textAlign: 'center',
              border: exs.length === 0 && !fmtKey ? 'none'
                : '1.5px dashed var(--border-str)',
              background: exs.length === 0 ? E2.lime : 'transparent',
              color: exs.length === 0 ? E2.ink : 'var(--fg-muted)',
              borderRadius: 16, padding: '14px 0', fontSize: 13.5,
              fontWeight: 700, cursor: 'pointer' }}>
            ＋ Add exercise</div>
        )}
      </div>

      {/* Footer */}
      {!reorder && exs.length > 0 && (
        <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
          zIndex: 30 }}>
          <div className="dd-display dd-glow"
            onClick={() => { set(s => ({ ...s,
              toast: `Saved “${title || 'New workout'}” ✓` })); nav('dd-build'); }}
            style={{ background: E2.lime, color: E2.ink, borderRadius: 999,
              padding: '16px 0', textAlign: 'center', fontSize: 15,
              fontWeight: 700, cursor: 'pointer' }}>
            Save workout</div>
        </div>
      )}

      {/* Add exercise — the creation front door. Search-first, equipment-
          aware, adds with defaults. No structure questions. */}
      <Sheet open={addOpen} onClose={() => setAddOpen(false)} title="Add exercise">
        <input className="af-input" placeholder="Search exercises..."
          value={q} onChange={(ev) => setQ(ev.target.value)}
          style={{ marginBottom: 10 }}/>
        {lib.map(([n, meta]) => (
          <div key={n} onClick={() => addEx(n)}
            style={{ display: 'flex', alignItems: 'center', gap: 11,
              padding: '11px 2px', borderBottom: '1px solid var(--border)',
              cursor: 'pointer' }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, fontWeight: 600 }}>{n}</div>
              <div className="af-mono" style={{ fontSize: 8.5, marginTop: 2,
                color: meta.includes('NOT IN') ? 'var(--ready-mod)'
                  : 'var(--fg-dim)' }}>{meta}</div>
            </div>
            <Icon name="plus" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}
        {q && <div className="dd-display" onClick={() => addEx(q)}
          style={{ textAlign: 'center', padding: '12px 0', fontSize: 12.5,
            fontWeight: 700, color: E2.lime, cursor: 'pointer' }}>
          ＋ Create “{q}”</div>}
        <div style={{ fontSize: 10, color: 'var(--fg-dim)', marginTop: 8,
          textAlign: 'center' }}>
          {fmtKey ? `Added straight into the ${E2_TYPES[groups.fmt.type].label}.`
            : 'Added as 3 × 10 · 60s rest — tap the card after to change anything.'}
        </div>
        {exs.length > 0 && (
          <Btn wide onClick={() => setAddOpen(false)}
            style={{ marginTop: 10 }}>Done adding</Btn>
        )}
      </Sheet>

      {/* ⋯ menu — ALL structural verbs, one per row (Hevy anatomy) */}
      <Sheet open={menuFor != null} onClose={() => setMenuFor(null)}
        title={menuEx ? menuEx.n : ''}>
        {menuEx && [
          ['grip', 'Reorder exercises', () => { setMenuFor(null); setReorder(true); }],
          ['swap', 'Replace exercise', () => { setMenuFor(null);
            set(s => ({ ...s, toast: 'Would open equipment-aware library' })); }],
          ['link', menuEx.grp && groups[menuEx.grp]
            && groups[menuEx.grp].type === 'superset'
            ? 'Remove from superset' : 'Add to superset',
            () => { if (menuEx.grp && groups[menuEx.grp]
                && groups[menuEx.grp].type === 'superset') {
                upEx(menuEx.id, { grp: null }); setMenuFor(null);
                set(s => ({ ...s, toast: 'Removed from superset' }));
              } else { setMenuFor(null); setPairFor(menuEx.id); } }],
          ['plus', 'Add a set', () => addSet(menuEx.id)],
          ['close', 'Remove exercise', () => removeEx(menuEx.id), true],
        ].map(([ic, label, fn, danger]) => (
          <div key={label} onClick={fn}
            style={{ display: 'flex', alignItems: 'center', gap: 13,
              padding: '13px 4px', borderBottom: '1px solid var(--border)',
              cursor: 'pointer',
              color: danger ? 'var(--destructive)' : 'var(--fg)' }}>
            <Icon name={ic} size={16}
              style={{ color: danger ? 'var(--destructive)' : 'var(--fg-muted)' }}/>
            <span className="dd-display" style={{ fontSize: 14,
              fontWeight: 600 }}>{label}</span>
          </div>
        ))}
      </Sheet>

      {/* Focused edit — one exercise, only its fields */}
      <Sheet open={editFor != null} onClose={() => setEditFor(null)}
        title={editEx ? editEx.n : ''}>
        {editEx && (
          <>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap',
              marginBottom: 14 }}>
              {editEx.sets != null && <E2Stepper label="Sets" value={editEx.sets}
                min={1} max={12} onChange={(v) => upEx(editEx.id, { sets: v })}/>}
              {editEx.reps != null && <E2Stepper label="Reps" value={editEx.reps}
                min={1} max={50} onChange={(v) => upEx(editEx.id, { reps: v })}/>}
              {editEx.dist != null && <E2Stepper label="Distance" value={editEx.dist}
                min={10} max={5000} step={10} unit=" m"
                onChange={(v) => upEx(editEx.id, { dist: v })}/>}
              {editEx.weight != null && <E2Stepper label="Weight" value={editEx.weight}
                min={0} max={300} step={2} unit=" kg"
                onChange={(v) => upEx(editEx.id, { weight: v })}/>}
              {editEx.rest != null && <E2Stepper label="Rest" value={editEx.rest}
                min={0} max={300} step={15} unit="s"
                onChange={(v) => upEx(editEx.id, { rest: v })}/>}
            </div>
            <Btn wide onClick={() => setEditFor(null)}>Done</Btn>
          </>
        )}
      </Sheet>

      {/* Group config — type switcher + only the steppers that type needs */}
      <Sheet open={!!confG} onClose={() => setConfFor(null)}
        title={confG ? (confG.name || E2_TYPES[confG.type].label) : ''}>
        {confG && (
          <>
            {confG.type !== 'warmup' && (
              <>
                <div className="af-mono" style={{ fontSize: 9,
                  color: 'var(--fg-muted)', marginBottom: 8 }}>RUNS AS</div>
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap',
                  marginBottom: 14 }}>
                  {['superset', ...E2_FORMATS].map(t => (
                    <span key={t} className="dd-display"
                      onClick={() => t !== confG.type && switchType(confFor, t)}
                      style={{ padding: '7px 12px', borderRadius: 999,
                        fontSize: 11.5, fontWeight: 700, cursor: 'pointer',
                        background: t === confG.type
                          ? `color-mix(in srgb, ${E2_TYPES[t].color}, transparent 70%)`
                          : E2.card2,
                        border: `1px solid ${t === confG.type
                          ? E2_TYPES[t].color
                          : 'transparent'}` }}>
                      {E2_TYPES[t].label}</span>
                  ))}
                </div>
              </>
            )}
            <div style={{ display: 'flex', gap: 8, marginBottom: 14,
              flexWrap: 'wrap' }}>
              {e2GroupRows(confG).map(([lab, key, mn, mx, st]) => (
                <E2Stepper key={key} label={lab} value={confG[key]} min={mn}
                  max={mx} step={st}
                  onChange={(v) => upGroup(confFor, { [key]: v })}/>
              ))}
            </div>
            <Btn wide onClick={() => setConfFor(null)}>Done</Btn>
            <div className="dd-display" onClick={() => ungroup(confFor)}
              style={{ textAlign: 'center', padding: '13px 0 2px', fontSize: 12.5,
                fontWeight: 700, color: 'var(--fg-muted)', cursor: 'pointer' }}>
              Ungroup — back to straight sets</div>
          </>
        )}
      </Sheet>

      {/* Superset picker — "Superset X with:" (Hevy verbatim pattern) */}
      <Sheet open={pairFor != null} onClose={() => setPairFor(null)}
        title={pairFor != null && byId(pairFor)
          ? `Superset ${byId(pairFor).n} with:` : ''}>
        {pairFor != null && exs.filter(e => e.id !== pairFor).map(e => (
          <div key={e.id} onClick={() => pair(pairFor, e.id)}
            style={{ display: 'flex', alignItems: 'center', gap: 12,
              padding: '12px 4px', borderBottom: '1px solid var(--border)',
              cursor: 'pointer' }}>
            <div style={{ flex: 1 }}>
              <div className="dd-display" style={{ fontSize: 13.5,
                fontWeight: 600 }}>{e.n}</div>
              <div className="af-mono" style={{ fontSize: 9, marginTop: 2,
                color: 'var(--fg-muted)' }}>{e2Sum(e)}</div>
            </div>
            {e.grp && groups[e.grp] && (
              <span className="af-mono" style={{ fontSize: 8,
                color: (E2_TYPES[groups[e.grp].type] || E2_TYPES.superset).color }}>
                {(groups[e.grp].name
                  || E2_TYPES[groups[e.grp].type].label).toUpperCase()}</span>
            )}
            <Icon name="link" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}
      </Sheet>
    </>
  );
}

Object.assign(window, { DDEditor2Screen });
