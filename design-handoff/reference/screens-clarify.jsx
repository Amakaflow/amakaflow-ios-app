/**
 * AMA-2304 — "Check the structure" intervene step. DISPOSABLE prototype.
 * Social imports with implied grouping land HERE between the processing
 * animation and the library. Parser guesses arrive pre-grouped but tagged
 * SUGGESTED — nothing commits silently. One-tap Confirm/Undo per group,
 * select-rows→chips for missed pairs, free-text "Describe it" for the
 * long tail. Demo content = the anchor reel @trainwithsmee DMqEsenN6Dl
 * (Hyrox upper body): two implied supersets, straight-set curls, a
 * 5-round ski+farmers finisher, prose warm-up.
 */

const DC = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  blue: '#5AB8F4',
  purple: '#C58AF4',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
};
const DC_TYPES = {
  superset: { label: 'Superset', color: 'var(--ready-mod)' },
  circuit:  { label: 'Circuit',  color: '#4AD97F' },
  warmup:   { label: 'Warm-up',  color: '#8890A0' },
  sets:     { label: 'Sets',     color: 'rgba(255,255,255,0.35)' },
};

let dcNextId = 100;
const dcGroup = (structure, label, meta, ex, over) => ({
  id: dcNextId++, kind: 'group', structure, label, meta, ex,
  status: 'suggested', rounds: null, ...over });
const dcRow = (n, d) => ({ id: dcNextId++, kind: 'row', n, d });

// Parsed result for the anchor reel — what the ingestor would hand us,
// pre-grouped by weak inference (formatting patterns), NOT committed.
const dcInitialUnits = () => [
  dcGroup('warmup', 'Warm-up', 'SKI + 2 ROUNDS', [
    ['Ski', '1000 M · EASY PACE'],
    ['Press ups', '2 × 5'],
    ['Pull ups', '2 × 5'],
  ]),
  dcGroup('superset', 'Bench + Pull Ups', '3 MIN REST', [
    ['Bench Press', '8 REPS'],
    ['Pull Ups', '8 REPS'],
  ], { rounds: 4 }),
  dcGroup('superset', 'Incline Press + Row', '90S REST', [
    ['Single-Arm Incline Press', '8 REPS / ARM'],
    ['Single-Arm Incline Row', '8 REPS / ARM'],
  ], { rounds: 4 }),
  dcRow('Incline Bicep Curls', '3 × 12 · 60S REST'),
  dcGroup('circuit', 'Finisher', 'FOR TIME', [
    ['Ski', '300 M'],
    ['Farmers Walk', '40 M'],
  ], { rounds: 5 }),
];

// Canned NL round-trip: "curls go after the incline pair, finisher is a
// circuit x5" → structured patch. Real impl = small LLM call → blocks[].
function dcApplyNote(units) {
  return units
    .filter(u => !(u.kind === 'row' && u.n === 'Incline Bicep Curls'))
    .map(u => {
      if (u.kind === 'group' && u.label === 'Incline Press + Row')
        return { ...u, label: 'Incline Press + Row + Curls', status: 'noted',
          ex: [...u.ex, ['Incline Bicep Curls', '3 × 12 · AFTER THE PAIR']] };
      if (u.kind === 'group' && u.structure === 'circuit')
        return { ...u, status: 'noted', rounds: 5 };
      return u;
    });
}

// ------------------------------------------------------------------ pieces
function DCGroupCard({ u, onConfirm, onUndo, onRounds }) {
  const T = DC_TYPES[u.structure] || DC_TYPES.sets;
  const st = u.status;
  const tagC = st === 'confirmed' ? DC.lime : st === 'noted' ? DC.blue : DC.amber;
  const tagTxt = st === 'confirmed' ? `${T.label.toUpperCase()} ✓`
    : st === 'noted' ? `FROM YOUR NOTE · ${T.label.toUpperCase()}`
    : `SUGGESTED · ${T.label.toUpperCase()}`;
  const mark = (i) => u.structure === 'superset' ? `A${i + 1}` : `${i + 1}`;
  return (
    <div style={{ background: DC.card,
      border: st === 'confirmed'
        ? '1px solid color-mix(in srgb, var(--ready-high), transparent 55%)'
        : '1px solid var(--border)',
      borderLeft: `3px solid ${T.color}`, borderRadius: 16, marginBottom: 10,
      overflow: 'hidden' }}>
      <div style={{ padding: '11px 13px 9px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span className="af-mono" style={{ fontSize: 8.5, fontWeight: 700,
            padding: '4px 9px', borderRadius: 999,
            background: `color-mix(in srgb, ${tagC}, transparent 84%)`,
            color: tagC }}>{tagTxt}</span>
          <span className="af-mono" style={{ marginLeft: 'auto', fontSize: 9,
            color: 'var(--fg-dim)' }}>
            {u.rounds ? `${u.rounds} ROUNDS · ` : ''}{u.meta}</span>
        </div>
        <div className="dd-display" style={{ fontSize: 14.5, fontWeight: 700,
          marginTop: 7 }}>{u.label}</div>
      </div>
      <div style={{ borderTop: '1px solid var(--border)',
        background: 'rgba(0,0,0,0.3)', padding: '2px 13px' }}>
        {u.ex.map(([n, d], i) => (
          <div key={n + i} style={{ display: 'flex', alignItems: 'center',
            gap: 10, padding: '9px 0',
            borderTop: i === 0 ? 'none' : '1px solid var(--border)' }}>
            <span className="af-mono" style={{ fontSize: 9, fontWeight: 700,
              color: T.color, width: 20, flexShrink: 0 }}>{mark(i)}</span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="dd-display" style={{ fontSize: 13,
                fontWeight: 600 }}>{n}</div>
              <div className="af-mono" style={{ fontSize: 9, marginTop: 2,
                color: 'var(--fg-muted)' }}>{d}</div>
            </div>
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8,
        padding: '9px 13px', borderTop: '1px solid var(--border)' }}>
        {st !== 'confirmed' ? (
          <div className="dd-display" onClick={onConfirm}
            style={{ flex: 1, background: DC.lime, color: DC.ink,
              borderRadius: 999, padding: '8px 0', textAlign: 'center',
              fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
            ✓ Confirm</div>
        ) : (
          <span className="af-mono" style={{ flex: 1, fontSize: 9,
            color: DC.lime }}>SAVES AS A {T.label.toUpperCase()} BLOCK</span>
        )}
        {u.structure === 'circuit' && (
          <span className="af-mono" style={{ display: 'inline-flex',
            alignItems: 'center', gap: 7, fontSize: 11, fontWeight: 600,
            background: DC.card2, borderRadius: 999, padding: '6px 11px' }}>
            <span onClick={() => onRounds(-1)} style={{ cursor: 'pointer',
              color: 'var(--fg-muted)' }}>−</span>
            ×{u.rounds}
            <span onClick={() => onRounds(1)} style={{ cursor: 'pointer',
              color: 'var(--fg-muted)' }}>＋</span>
          </span>
        )}
        <span className="dd-display" onClick={onUndo}
          style={{ fontSize: 11.5, fontWeight: 700, color: 'var(--fg-muted)',
            background: DC.card2, borderRadius: 999, padding: '8px 13px',
            cursor: 'pointer' }}>
          {st === 'confirmed' ? 'Ungroup' : 'Undo'}</span>
      </div>
    </div>
  );
}

function DCFlatRow({ u, selected, onToggle }) {
  return (
    <div onClick={onToggle} style={{ display: 'flex', alignItems: 'center',
      gap: 11, marginBottom: 8, borderRadius: 14, padding: '11px 13px',
      cursor: 'pointer',
      background: selected
        ? 'color-mix(in srgb, var(--ready-high), transparent 88%)' : DC.card,
      border: selected
        ? '1px solid color-mix(in srgb, var(--ready-high), transparent 45%)'
        : '1px solid var(--border)' }}>
      <div style={{ width: 18, height: 18, borderRadius: 999, flexShrink: 0,
        border: selected ? 'none' : '1.5px solid var(--border-str)',
        background: selected ? DC.lime : 'transparent', color: DC.ink,
        display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {selected && <Icon name="check" size={11}/>}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="dd-display" style={{ fontSize: 13.5,
          fontWeight: 600 }}>{u.n}</div>
        <div className="af-mono" style={{ fontSize: 9, marginTop: 2,
          color: 'var(--fg-muted)' }}>{u.d}</div>
      </div>
      <span className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)' }}>
        NOT GROUPED</span>
    </div>
  );
}

// ------------------------------------------------------------------ screen
// preset: null (import landing) | 'describe' (sheet open) | 'noted'
// (after the NL note applied) — presets exist for the screenshot rig.
function DDClarifyScreen({ dd, set, nav, preset }) {
  const [units, setUnits] = React.useState(() =>
    preset === 'noted' ? dcApplyNote(dcInitialUnits()) : dcInitialUnits());
  const [sel, setSel] = React.useState([]);
  const [descOpen, setDescOpen] = React.useState(preset === 'describe');
  const [note, setNote] = React.useState(preset === 'describe'
    ? 'curls go after the incline pair, finisher is a circuit x5' : '');
  const [reading, setReading] = React.useState(false);

  const groups = units.filter(u => u.kind === 'group');
  const confirmed = groups.filter(u => u.status === 'confirmed').length;
  const pending = groups.length - confirmed;

  const confirm = (id) => setUnits(us => us.map(u =>
    u.id === id ? { ...u, status: 'confirmed' } : u));
  const confirmAll = () => setUnits(us => us.map(u =>
    u.kind === 'group' ? { ...u, status: 'confirmed' } : u));
  const undo = (id) => setUnits(us => us.flatMap(u =>
    u.id === id ? u.ex.map(([n, d]) => dcRow(n, d)) : [u]));
  const bumpRounds = (id, d) => setUnits(us => us.map(u =>
    u.id === id ? { ...u, rounds: Math.min(20, Math.max(1, u.rounds + d)) } : u));
  const toggleSel = (id) => setSel(s =>
    s.includes(id) ? s.filter(x => x !== id) : [...s, id]);

  const makeGroup = (structure) => {
    setUnits(us => {
      const rows = us.filter(u => sel.includes(u.id));
      const g = { id: dcNextId++, kind: 'group', structure,
        label: rows.map(r => r.n).join(' + '),
        meta: structure === 'superset' ? '60S REST' : 'FOR TIME',
        rounds: structure === 'superset' ? 3 : 4,
        status: 'confirmed',
        ex: rows.map(r => [r.n, r.d]) };
      const out = []; let placed = false;
      for (const u of us) {
        if (sel.includes(u.id)) {
          if (!placed) { out.push(g); placed = true; }
          continue;
        }
        out.push(u);
      }
      return out;
    });
    setSel([]);
    set(s => ({ ...s, toast: `Grouped as ${structure} ✓` }));
  };

  const applyNote = () => {
    setReading(true);
    setTimeout(() => {
      setUnits(dcApplyNote);
      setReading(false); setDescOpen(false);
      set(s => ({ ...s, toast: 'Restructured from your note — confirm below' }));
    }, 1300);
  };
  const save = (flat) => {
    set(s => ({ ...s, toast: flat
      ? 'Saved flat — group it anytime in the editor'
      : `Saved “Hyrox Upper Body” · ${confirmed} structured blocks ✓` }));
    nav('dd-build');
  };

  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => nav('dd-today')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Back
        </div>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
          marginTop: 10 }}>Check the structure</div>
        <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 5,
          lineHeight: 1.5 }}>
          10 exercises found. The grouping was implied, not stated — confirm
          it so the player runs it right.
        </div>
        {/* Provenance — where this came from, honestly */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 9,
          marginTop: 10, background: DC.card, border: '1px solid var(--border)',
          borderRadius: 12, padding: '8px 11px' }}>
          <div style={{ width: 28, height: 28, borderRadius: 999,
            background: DC.purple, color: '#fff', display: 'flex',
            alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <Icon name="camera" size={14}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 12,
              fontWeight: 700 }}>Hyrox Upper Body</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 1,
              color: 'var(--fg-dim)' }}>@TRAINWITHSMEE · REEL CAPTION PARSED</div>
          </div>
          {pending > 0 && (
            <span className="dd-display" onClick={confirmAll}
              style={{ fontSize: 11, fontWeight: 700, color: DC.lime,
                cursor: 'pointer', flexShrink: 0 }}>
              ✓ Confirm all ({pending})</span>
          )}
        </div>
      </div>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 150px' }}>
        {units.map(u => u.kind === 'group' ? (
          <DCGroupCard key={u.id} u={u}
            onConfirm={() => confirm(u.id)}
            onUndo={() => undo(u.id)}
            onRounds={(d) => bumpRounds(u.id, d)}/>
        ) : (
          <DCFlatRow key={u.id} u={u} selected={sel.includes(u.id)}
            onToggle={() => toggleSel(u.id)}/>
        ))}

        {/* Select-rows → chips: the missed-pair fixer */}
        {sel.length > 0 && (
          <div style={{ background: DC.card, borderRadius: 16, padding: 12,
            marginBottom: 10,
            border: '1px solid color-mix(in srgb, var(--ready-high), transparent 60%)' }}>
            <div className="af-mono" style={{ fontSize: 9,
              color: 'var(--fg-muted)', marginBottom: 8 }}>
              {sel.length} SELECTED — {sel.length < 2
                ? 'PICK ANOTHER TO GROUP THEM'
                : 'GROUP AS:'}</div>
            <div style={{ display: 'flex', gap: 7, flexWrap: 'wrap' }}>
              {[['superset', 'Superset'], ['circuit', 'Circuit ×4']].map(([k, l]) => (
                <span key={k} className="dd-display"
                  onClick={() => sel.length >= 2 && makeGroup(k)}
                  style={{ padding: '8px 14px', borderRadius: 999, fontSize: 12,
                    fontWeight: 700,
                    cursor: sel.length >= 2 ? 'pointer' : 'default',
                    opacity: sel.length >= 2 ? 1 : 0.4,
                    background: DC.card2,
                    border: `1px solid color-mix(in srgb, ${DC_TYPES[k].color}, transparent 55%)` }}>
                  {l}</span>
              ))}
              <span className="dd-display" onClick={() => setSel([])}
                style={{ padding: '8px 14px', borderRadius: 999, fontSize: 12,
                  fontWeight: 700, color: 'var(--fg-muted)', cursor: 'pointer' }}>
                Cancel</span>
            </div>
          </div>
        )}

        {/* NL door — the long-tail catcher */}
        <div onClick={() => setDescOpen(true)}
          style={{ display: 'flex', alignItems: 'center', gap: 10,
            border: '1.5px dashed var(--border-str)', borderRadius: 16,
            padding: '12px 14px', cursor: 'pointer', marginBottom: 12 }}>
          <Icon name="edit" size={15} style={{ color: 'var(--fg-muted)' }}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 13,
              fontWeight: 700 }}>Not right? Describe it</div>
            <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
              marginTop: 1 }}>
              “bench + pull ups are a superset, finisher is a circuit ×5”</div>
          </div>
          <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
        </div>

        <div style={{ fontSize: 10.5, color: 'var(--fg-dim)', textAlign: 'center',
          lineHeight: 1.5, padding: '0 10px' }}>
          Unconfirmed groups save as a flat list — we never guess silently.
        </div>
      </div>

      {/* Footer — dual CTA, detail-screen anatomy */}
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
        display: 'flex', gap: 8, zIndex: 30 }}>
        <div className="dd-display" onClick={() => save(true)}
          style={{ flex: 1, background: 'rgba(16,16,18,0.96)',
            color: 'var(--fg-muted)', border: '1px solid var(--border-str)',
            borderRadius: 999, padding: '15px 0', textAlign: 'center',
            fontSize: 13.5, fontWeight: 700, cursor: 'pointer' }}>
          Leave flat
        </div>
        <div className="dd-display dd-glow" onClick={() => save(false)}
          style={{ flex: 1.5, background: DC.lime, color: DC.ink,
            borderRadius: 999, padding: '15px 0', textAlign: 'center',
            fontSize: 14.5, fontWeight: 700, cursor: 'pointer' }}>
          {confirmed > 0
            ? `Save · ${confirmed} block${confirmed === 1 ? '' : 's'} ✓`
            : 'Looks right — Save'}
        </div>
      </div>

      {/* Describe sheet — human words → structured blocks → confirm */}
      <Sheet open={descOpen} onClose={() => !reading && setDescOpen(false)}
        title="Describe the structure">
        {reading ? (
          <div style={{ textAlign: 'center', padding: '18px 6px 12px' }}>
            <div style={{ position: 'relative', width: 64, height: 64,
              margin: '0 auto 14px' }}>
              <div style={{ position: 'absolute', inset: 0, borderRadius: 999,
                border: '2.5px solid rgba(255,255,255,0.08)' }}/>
              <div style={{ position: 'absolute', inset: 0, borderRadius: 999,
                border: '2.5px solid transparent',
                borderTopColor: DC.lime,
                animation: 'dd-spin .9s linear infinite' }}/>
              <div style={{ position: 'absolute', inset: 12, borderRadius: 999,
                background: DC.lime, color: DC.ink, display: 'flex',
                alignItems: 'center', justifyContent: 'center' }}>
                <Icon name="edit" size={18}/>
              </div>
            </div>
            <div className="dd-display" style={{ fontSize: 15, fontWeight: 700,
              animation: 'dd-step-in .35s cubic-bezier(.2,.8,.2,1)' }}>
              Reading your note…</div>
            <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 6,
              fontStyle: 'italic', lineHeight: 1.5 }}>“{note}”</div>
          </div>
        ) : (
          <>
            <div style={{ fontSize: 11.5, color: 'var(--fg-muted)',
              marginBottom: 10, lineHeight: 1.5 }}>
              Say it like you'd tell a training partner — we turn it into
              blocks you can confirm. Nothing applies until you check it.
            </div>
            <textarea className="af-input" rows={3} value={note}
              placeholder='e.g. "A1/A2 are a superset, last two are a circuit x5"'
              onChange={(ev) => setNote(ev.target.value)}
              style={{ width: '100%', resize: 'none', borderRadius: 14,
                fontSize: 13, lineHeight: 1.5, fontFamily: 'inherit',
                boxSizing: 'border-box', marginBottom: 10 }}/>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap',
              marginBottom: 14 }}>
              {['curls go after the incline pair, finisher is a circuit x5',
                'everything is straight sets — leave it flat'].map(h => (
                <span key={h} className="af-mono" onClick={() => setNote(h)}
                  style={{ fontSize: 9, padding: '6px 10px', borderRadius: 999,
                    background: DC.card2, color: 'var(--fg-muted)',
                    cursor: 'pointer' }}>“{h}”</span>
              ))}
            </div>
            <Btn wide disabled={!note.trim()} onClick={applyNote}>
              Apply to workout</Btn>
          </>
        )}
      </Sheet>
    </>
  );
}

Object.assign(window, { DDClarifyScreen });
