/**
 * Part A — 8 essential screens (10 sub-screens) for v1 coverage.
 * Built on existing ui.jsx primitives + tokens only.
 */

// =================================================================== A1 — Coach chat
function CoachChatScreen({ state, nav, setState }) {
  const { tab } = state;
  const [empty, setEmpty] = React.useState(false);
  const [draft, setDraft] = React.useState('');
  const scrollRef = React.useRef(null);
  const [msgs, setMsgs] = React.useState([
    { who: 'coach', kind: 'text', text: "Morning. HRV +8, sleep 7h 42m — green light for the 4×8 threshold today." },
    { who: 'user',  kind: 'text', text: "Felt a little off in the warmup yesterday. Should I move it?" },
    { who: 'coach', kind: 'text', text: "You looked fine on the recovery spin. Let's try the first rep at 4:38 — call it after rep 2." },
    { who: 'coach', kind: 'workout', title: '4×8 min @ threshold', meta: '64m · Z3–4 · TSS 78' },
    { who: 'coach', kind: 'swap',    text: "If you'd rather move it, here are two alternatives:" },
  ]);

  const send = () => {
    if (!draft.trim()) return;
    setMsgs(m => [...m, { who: 'user', kind: 'text', text: draft.trim() }]);
    setDraft('');
    setTimeout(() => {
      setMsgs(m => [...m, { who: 'coach', kind: 'text',
        text: "Got it — adjusting." }]);
    }, 600);
  };
  React.useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [msgs]);

  const quickReplies = ['Move to Saturday', 'Why threshold?', 'Felt off today'];

  return (
    <>
      <TopBar title="Coach" sub="Online · replies in <1m"
        right={<Icon name="sliders" size={18}/>}/>
      {empty ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center',
          padding: '0 40px 80px', textAlign: 'center' }}>
          <div style={{ width: 64, height: 64, borderRadius: 999,
            background: 'color-mix(in oklch, var(--ready-high), transparent 75%)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            marginBottom: 18, fontSize: 28 }}>💬</div>
          <div className="af-h2" style={{ fontSize: 18 }}>Ask your coach anything</div>
          <div className="af-muted" style={{ fontSize: 12, marginTop: 10, lineHeight: 1.55 }}>
            Swap a workout, ask why, log how you feel. Replies in under a minute.
          </div>
          <div style={{ marginTop: 22, display: 'flex', gap: 6, flexWrap: 'wrap',
            justifyContent: 'center' }}>
            {['How am I doing?', 'Plan my week', 'I tweaked my knee'].map(s => (
              <Chip key={s} outline onClick={() => { setEmpty(false); setDraft(s); }}
                style={{ fontSize: 11, cursor: 'pointer' }}>{s}</Chip>
            ))}
          </div>
        </div>
      ) : (
        <div ref={scrollRef} className="af-scroll" style={{ flex: 1, overflowY: 'auto',
          padding: '0 16px 12px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {msgs.map((m, i) => <ChatBubble key={i} m={m}/>)}
        </div>
      )}

      {/* Quick replies above input */}
      <div style={{ padding: '0 14px 8px', display: 'flex', gap: 6,
        overflowX: 'auto', flexShrink: 0 }} className="af-scroll">
        {quickReplies.map(q => (
          <Chip key={q} outline onClick={() => setDraft(q)}
            style={{ fontSize: 11, padding: '5px 10px', flexShrink: 0, cursor: 'pointer' }}>{q}</Chip>
        ))}
      </div>
      <div style={{ padding: '0 14px 10px', display: 'flex', gap: 8, alignItems: 'center',
        borderTop: '1px solid var(--border)', paddingTop: 10, flexShrink: 0 }}>
        <input className="af-input" placeholder="Message your coach…"
          value={draft} onChange={e => setDraft(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && send()}
          style={{ flex: 1 }}/>
        <button style={{ all: 'unset', cursor: 'pointer', width: 36, height: 36,
          borderRadius: 999, background: 'var(--bg-elev)',
          border: '1px solid var(--border)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="mic" size={14}/>
        </button>
        <button onClick={send}
          style={{ all: 'unset', cursor: 'pointer', width: 36, height: 36,
          borderRadius: 999, background: 'var(--fg)', color: 'var(--bg)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="plane" size={14}/>
        </button>
      </div>
      <TabBar active={2} onChange={i => setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

function ChatBubble({ m }) {
  const isUser = m.who === 'user';
  if (m.kind === 'text') {
    return (
      <div style={{ display: 'flex', justifyContent: isUser ? 'flex-end' : 'flex-start' }}>
        <div style={{ maxWidth: '78%', padding: '9px 12px', borderRadius: 14,
          [isUser ? 'borderBottomRightRadius' : 'borderBottomLeftRadius']: 4,
          background: isUser ? 'var(--fg)' : 'var(--bg-elev)',
          color: isUser ? 'var(--bg)' : 'var(--fg)',
          border: isUser ? 'none' : '1px solid var(--border)',
          fontSize: 12.5, lineHeight: 1.5 }}>
          {m.text}
        </div>
      </div>
    );
  }
  if (m.kind === 'workout') {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
        <div style={{ maxWidth: '85%', padding: '12px 14px', borderRadius: 14,
          borderBottomLeftRadius: 4, background: 'var(--bg-elev)',
          border: '1px solid var(--border)' }}>
          <div className="af-label" style={{ fontSize: 8 }}>SUGGESTED · TODAY</div>
          <div style={{ fontSize: 12.5, fontWeight: 500, marginTop: 4 }}>{m.title}</div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>{m.meta}</div>
          <div style={{ display: 'flex', gap: 6, marginTop: 10 }}>
            <Chip style={{ fontSize: 10, background: 'var(--fg)', color: 'var(--bg)',
              borderColor: 'var(--fg)', cursor: 'pointer' }}>Accept</Chip>
            <Chip outline style={{ fontSize: 10, cursor: 'pointer' }}>Keep current</Chip>
          </div>
        </div>
      </div>
    );
  }
  if (m.kind === 'swap') {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-start' }}>
        <div style={{ maxWidth: '85%', padding: '12px 14px', borderRadius: 14,
          borderBottomLeftRadius: 4, background: 'var(--bg-elev)',
          border: '1px solid var(--border)' }}>
          <div style={{ fontSize: 12, marginBottom: 8 }}>{m.text}</div>
          {[
            { t: 'Move to Saturday', s: 'Long run swap' },
            { t: 'Replace with Z2 run', s: '45m easy' },
          ].map(o => (
            <div key={o.t} style={{ padding: '8px 10px', marginTop: 6,
              background: 'var(--bg-subtle)', borderRadius: 8,
              display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 11, fontWeight: 500 }}>{o.t}</div>
                <div className="af-muted" style={{ fontSize: 10, marginTop: 1 }}>{o.s}</div>
              </div>
              <Icon name="chevR" size={12} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          ))}
        </div>
      </div>
    );
  }
  return null;
}

// =================================================================== A2 — Edit profile
function EditProfileScreen({ state, nav, setState }) {
  const [form, setForm] = React.useState({
    name: 'Adaeze Okafor', handle: '@adaeze',
    bio: 'Hybrid athlete, HYROX 2026 in May. Coffee first.',
    goals: ['HYROX prep', 'Endurance'],
    hours: 8, level: 'Intermediate',
    bday: '1992-04-14', sex: 'F',
    height: 168, weight: 62, unit: 'metric',
  });
  const [dirty, setDirty] = React.useState(false);
  const set = (k, v) => { setForm(f => ({ ...f, [k]: v })); setDirty(true); };

  const goalOptions = ['HYROX prep', 'Marathon', 'Endurance', 'Strength', 'Build muscle', 'Lose weight', 'General fitness'];
  const toggleGoal = (g) => set('goals',
    form.goals.includes(g) ? form.goals.filter(x => x !== g) : [...form.goals, g]);

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')}
        title="Edit profile" sub="Public to teammates"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        {/* Avatar */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center',
          padding: '4px 0 20px' }}>
          <div style={{ position: 'relative', cursor: 'pointer' }}>
            <div style={{ width: 88, height: 88, borderRadius: 999,
              background: 'linear-gradient(135deg, var(--ready-high) 0%, oklch(0.55 0.16 200) 100%)',
              color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 32, fontWeight: 600, fontFamily: 'var(--font-mono)' }}>AO</div>
            <div style={{ position: 'absolute', bottom: 0, right: 0,
              width: 30, height: 30, borderRadius: 999,
              background: 'var(--fg)', color: 'var(--bg)',
              border: '3px solid var(--bg)',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="camera" size={13}/>
            </div>
          </div>
        </div>

        <FieldGroup label="NAME">
          <input className="af-input" value={form.name} onChange={e => set('name', e.target.value)}/>
        </FieldGroup>
        <FieldGroup label="HANDLE">
          <input className="af-input af-mono" value={form.handle} onChange={e => set('handle', e.target.value)}/>
        </FieldGroup>
        <FieldGroup label={`BIO · ${form.bio.length}/140`}>
          <textarea className="af-input" rows={3} value={form.bio}
            maxLength={140} onChange={e => set('bio', e.target.value)}
            style={{ resize: 'none', fontFamily: 'inherit' }}/>
        </FieldGroup>

        <FieldGroup label="GOALS">
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {goalOptions.map(g => {
              const on = form.goals.includes(g);
              return (
                <Chip key={g} outline={!on} onClick={() => toggleGoal(g)}
                  style={{ fontSize: 11, cursor: 'pointer',
                    background: on ? 'var(--fg)' : 'transparent',
                    color: on ? 'var(--bg)' : 'var(--fg)',
                    borderColor: on ? 'var(--fg)' : 'var(--border-str)' }}>{g}</Chip>
              );
            })}
          </div>
        </FieldGroup>

        <FieldGroup label={`WEEKLY HOURS · ${form.hours}h`}>
          <input type="range" min="2" max="20" step="1" value={form.hours}
            onChange={e => set('hours', +e.target.value)}
            style={{ width: '100%', accentColor: 'var(--fg)' }}/>
          <div className="af-mono" style={{ display: 'flex', justifyContent: 'space-between',
            fontSize: 9, color: 'var(--fg-muted)', marginTop: 4 }}>
            <span>2h</span><span>20h</span>
          </div>
        </FieldGroup>

        <FieldGroup label="LEVEL">
          <div className="af-seg">
            {['Beginner', 'Intermediate', 'Advanced'].map(l => (
              <div key={l} className="af-seg-item" data-on={form.level === l}
                onClick={() => set('level', l)}>{l}</div>
            ))}
          </div>
        </FieldGroup>

        <div style={{ display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 10 }}>
          <FieldGroup label="BIRTHDAY">
            <input className="af-input af-mono" type="date" value={form.bday}
              onChange={e => set('bday', e.target.value)}/>
          </FieldGroup>
          <FieldGroup label="SEX">
            <div className="af-seg" style={{ height: 40 }}>
              {['F','M','—'].map(s => (
                <div key={s} className="af-seg-item" data-on={form.sex === s}
                  onClick={() => set('sex', s)}>{s}</div>
              ))}
            </div>
          </FieldGroup>
        </div>

        <FieldGroup label="MEASUREMENTS">
          <div style={{ display: 'flex', gap: 10 }}>
            <div style={{ flex: 1, position: 'relative' }}>
              <input className="af-input af-mono" value={form.height}
                onChange={e => set('height', e.target.value)}
                style={{ paddingRight: 36 }}/>
              <span className="af-mono" style={{ position: 'absolute', right: 12, top: '50%',
                transform: 'translateY(-50%)', fontSize: 10, color: 'var(--fg-muted)' }}>
                {form.unit === 'metric' ? 'cm' : 'in'}
              </span>
            </div>
            <div style={{ flex: 1, position: 'relative' }}>
              <input className="af-input af-mono" value={form.weight}
                onChange={e => set('weight', e.target.value)}
                style={{ paddingRight: 36 }}/>
              <span className="af-mono" style={{ position: 'absolute', right: 12, top: '50%',
                transform: 'translateY(-50%)', fontSize: 10, color: 'var(--fg-muted)' }}>
                {form.unit === 'metric' ? 'kg' : 'lb'}
              </span>
            </div>
            <div className="af-seg" style={{ width: 110, height: 40 }}>
              {['metric','imp'].map(u => (
                <div key={u} className="af-seg-item" data-on={form.unit === u || (u === 'imp' && form.unit !== 'metric')}
                  onClick={() => set('unit', u)}>{u === 'metric' ? 'kg/cm' : 'lb/in'}</div>
              ))}
            </div>
          </div>
        </FieldGroup>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => { setDirty(false); nav('settings'); }} disabled={!dirty}>
          {dirty ? 'Save changes' : 'Saved'}
        </Btn>
      </div>
    </>
  );
}

function FieldGroup({ label, children }) {
  return (
    <div style={{ marginBottom: 16 }}>
      <div className="af-label" style={{ marginBottom: 6 }}>{label}</div>
      {children}
    </div>
  );
}

// =================================================================== A3 — Workout editor
function WorkoutEditorScreen({ state, nav }) {
  const [form, setForm] = React.useState({
    name: 'Threshold intervals', type: 'Run',
    date: '2026-04-24', time: '06:30', duration: '64',
  });
  const [blocks, setBlocks] = React.useState([
    { id: 'b1', label: 'Warmup', items: [
      { id: 'i1', name: 'Easy jog', detail: '15 min · Z1' },
    ]},
    { id: 'b2', label: 'Main set', items: [
      { id: 'i2', name: '4×8 min threshold', detail: '4 × 8 min @ 4:38/km · 3 min rest' },
    ]},
    { id: 'b3', label: 'Cooldown', items: [
      { id: 'i3', name: 'Easy jog', detail: '5 min · Z1' },
    ]},
  ]);
  const [pickerOpen, setPickerOpen] = React.useState(null); // block id or null
  const [notes, setNotes] = React.useState('Stay relaxed in shoulders. Call rep 3 if HR climbs past 178.');

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }));

  const exerciseLibrary = [
    { kind: 'Run', name: 'Tempo run', detail: '20 min @ Z3' },
    { kind: 'Run', name: 'Hill repeats', detail: '6×60s · 2 min rest' },
    { kind: 'Strength', name: 'Back squat', detail: '4×5 @ 80% 1RM' },
    { kind: 'Strength', name: 'RDL', detail: '3×8 @ 70%' },
    { kind: 'Hybrid', name: 'Wall balls', detail: '3×20 reps' },
    { kind: 'Mobility', name: '90/90 hip', detail: '2×8 each side' },
  ];

  const addExercise = (blockId, ex) => {
    setBlocks(bs => bs.map(b => b.id === blockId
      ? { ...b, items: [...b.items, { id: 'i' + Math.random().toString(36).slice(2,6), ...ex }] }
      : b));
    setPickerOpen(null);
  };
  const addBlock = () => setBlocks(bs => [...bs,
    { id: 'b' + Math.random().toString(36).slice(2,6), label: 'New block', items: [] }]);

  return (
    <>
      <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('workouts')}
        title="New workout"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <FieldGroup label="NAME">
          <input className="af-input" value={form.name} onChange={e => set('name', e.target.value)}/>
        </FieldGroup>
        <FieldGroup label="TYPE">
          <div style={{ display: 'flex', gap: 6 }}>
            {['Run','Strength','Hybrid','Mobility'].map(t => (
              <Chip key={t} outline={form.type !== t} onClick={() => set('type', t)}
                style={{ fontSize: 11, cursor: 'pointer', flex: 1,
                  textAlign: 'center', justifyContent: 'center',
                  background: form.type === t ? 'var(--fg)' : 'transparent',
                  color: form.type === t ? 'var(--bg)' : 'var(--fg)',
                  borderColor: form.type === t ? 'var(--fg)' : 'var(--border-str)' }}>{t}</Chip>
            ))}
          </div>
        </FieldGroup>
        <div style={{ display: 'grid', gridTemplateColumns: '1.3fr 1fr 1fr', gap: 8 }}>
          <FieldGroup label="DATE">
            <input className="af-input af-mono" type="date" value={form.date}
              onChange={e => set('date', e.target.value)}/>
          </FieldGroup>
          <FieldGroup label="TIME">
            <input className="af-input af-mono" type="time" value={form.time}
              onChange={e => set('time', e.target.value)}/>
          </FieldGroup>
          <FieldGroup label="DURATION">
            <div style={{ position: 'relative' }}>
              <input className="af-input af-mono" value={form.duration}
                onChange={e => set('duration', e.target.value)}
                style={{ paddingRight: 30 }}/>
              <span className="af-mono" style={{ position: 'absolute', right: 12, top: '50%',
                transform: 'translateY(-50%)', fontSize: 10, color: 'var(--fg-muted)' }}>min</span>
            </div>
          </FieldGroup>
        </div>

        <div className="af-label" style={{ marginBottom: 8 }}>BLOCKS</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {blocks.map(b => (
            <div key={b.id} style={{ background: 'var(--bg-elev)',
              border: '1px solid var(--border)', borderRadius: 12, padding: 12 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
                <Icon name="grip" size={14} style={{ color: 'var(--fg-dim)', cursor: 'grab' }}/>
                <input className="af-input" value={b.label}
                  onChange={e => setBlocks(bs => bs.map(x => x.id === b.id
                    ? { ...x, label: e.target.value } : x))}
                  style={{ flex: 1, height: 32, fontSize: 12, fontWeight: 500,
                    background: 'transparent', border: 'none', padding: 0 }}/>
              </div>
              {b.items.map(it => (
                <div key={it.id} style={{ padding: '8px 0', display: 'flex',
                  alignItems: 'center', gap: 10, borderTop: '1px solid var(--border)' }}>
                  <Icon name="grip" size={12} style={{ color: 'var(--fg-dim)' }}/>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 12, fontWeight: 500 }}>{it.name}</div>
                    <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 1 }}>{it.detail}</div>
                  </div>
                  <Icon name="close" size={12} style={{ color: 'var(--fg-dim)', cursor: 'pointer' }}/>
                </div>
              ))}
              <button onClick={() => setPickerOpen(b.id)}
                style={{ all: 'unset', cursor: 'pointer', width: '100%',
                  padding: '8px 0', marginTop: 4, fontSize: 11,
                  color: 'var(--fg-muted)', textAlign: 'left',
                  borderTop: '1px dashed var(--border-str)' }}>
                + Add exercise
              </button>
            </div>
          ))}
        </div>
        <Btn variant="ghost" wide size="sm" onClick={addBlock} style={{ marginTop: 10 }}>
          + Add block
        </Btn>

        <FieldGroup label="NOTES">
          <textarea className="af-input" rows={3} value={notes}
            onChange={e => setNotes(e.target.value)}
            style={{ resize: 'none', fontFamily: 'inherit', marginTop: 6 }}/>
        </FieldGroup>
      </div>

      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('workouts')}>Save workout</Btn>
      </div>

      <Sheet open={!!pickerOpen} onClose={() => setPickerOpen(null)} title="Add exercise">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {exerciseLibrary.map(ex => (
            <div key={ex.name} onClick={() => addExercise(pickerOpen, ex)}
              style={{ padding: '12px 12px', borderRadius: 8, cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 10 }}>
              <Chip outline style={{ fontSize: 9 }}>{ex.kind}</Chip>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{ex.name}</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 1 }}>{ex.detail}</div>
              </div>
              <Icon name="plus" size={14} style={{ color: 'var(--fg-muted)' }}/>
            </div>
          ))}
        </div>
      </Sheet>
    </>
  );
}

// =================================================================== A4 — Suggest workout
function SuggestWorkoutScreen({ state, nav, setState }) {
  const [swapOpen, setSwapOpen] = React.useState(false);
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('home')}
        title="Today's session" sub="Based on your readiness"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <Card style={{ padding: 14, marginBottom: 14, display: 'flex',
          alignItems: 'center', gap: 14 }}>
          <Ring value={84} size={64} stroke={5}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="af-h3" style={{ fontSize: 15 }}>Ready · 84%</div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 4, lineHeight: 1.5 }}>
              HRV +8 · Sleep 7h 42m · RHR 48
            </div>
          </div>
        </Card>

        <div className="af-label" style={{ marginBottom: 6 }}>WHY THIS</div>
        <div style={{ fontSize: 12.5, lineHeight: 1.6, color: 'var(--fg-muted)',
          marginBottom: 18 }}>
          You're well-recovered after Tuesday's easy run, and you said you wanted a Hyrox-style finisher this week. A controlled threshold block hits the aerobic system without overspending — you'll still be fresh for Saturday's long ride.
        </div>

        <Card style={{ padding: 14, marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <Icon name="run" size={14}/>
            <span className="af-label" style={{ fontSize: 9 }}>THRESHOLD RUN</span>
          </div>
          <div className="af-h2" style={{ fontSize: 17 }}>4×8 min @ threshold</div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 4 }}>
            64m · Z3–4 · TSS 78 · 10.2 km
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 6,
            marginTop: 12, padding: '10px 0',
            borderTop: '1px solid var(--border)' }}>
            <Metric k="DURATION" v="64m"/>
            <Metric k="TSS" v="78"/>
            <Metric k="INTENSITY" v="0.87"/>
          </div>
        </Card>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <Btn wide size="lg" onClick={() => nav('player')}>
            Start workout <Icon name="chevR" size={14}/>
          </Btn>
          <Btn wide variant="ghost" size="md" onClick={() => setSwapOpen(true)}>
            <Icon name="swap" size={14}/> Swap
          </Btn>
          <Btn wide variant="ghost" size="md" onClick={() => nav('home')}>
            Take a rest day
          </Btn>
        </div>
      </div>

      <Sheet open={swapOpen} onClose={() => setSwapOpen(false)} title="Swap workout">
        <div className="af-muted" style={{ fontSize: 12, marginBottom: 12, lineHeight: 1.5 }}>
          Two alternatives that fit today's readiness.
        </div>
        {[
          { t: '5 km tempo', m: '30m · Z3 · TSS 52', why: 'Shorter, more focused' },
          { t: 'Aerobic Z2 run', m: '55m · Z2 · TSS 45', why: 'Easier on the legs' },
        ].map(o => (
          <Card key={o.t} onClick={() => setSwapOpen(false)}
            style={{ padding: 12, marginBottom: 8, cursor: 'pointer' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Icon name="run" size={14} style={{ color: 'var(--fg-muted)' }}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{o.t}</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 2 }}>{o.m}</div>
                <div className="af-muted" style={{ fontSize: 10.5, marginTop: 4 }}>{o.why}</div>
              </div>
              <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          </Card>
        ))}
      </Sheet>
    </>
  );
}

function Metric({ k, v }) {
  return (
    <div>
      <div className="af-label" style={{ fontSize: 8 }}>{k}</div>
      <div className="af-mono" style={{ fontSize: 14, fontWeight: 500, marginTop: 3 }}>{v}</div>
    </div>
  );
}

// =================================================================== A5 — Paywall
function PaywallProScreen({ state, nav }) {
  const [plan, setPlan] = React.useState('annual');
  const price = plan === 'annual' ? '$7.99' : '$9.99';
  return (
    <>
      <div style={{ padding: '12px 18px', display: 'flex', justifyContent: 'flex-end' }}>
        <button onClick={() => nav('settings')} style={{ all: 'unset', cursor: 'pointer',
          width: 30, height: 30, borderRadius: 999, background: 'var(--bg-subtle)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="close" size={16}/>
        </button>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 16px' }}>
        {/* Hero */}
        <div style={{ position: 'relative', borderRadius: 16, padding: '24px 18px',
          background: 'linear-gradient(135deg, var(--ready-high) 0%, oklch(0.65 0.16 130) 60%, oklch(0.45 0.13 130) 100%)',
          color: '#0d1208', marginBottom: 18, overflow: 'hidden' }}>
          <div className="af-mono" style={{ fontSize: 9, letterSpacing: '0.08em',
            opacity: 0.7 }}>AMAKAFLOW</div>
          <div style={{ fontSize: 30, fontWeight: 600, letterSpacing: '-0.02em',
            marginTop: 4 }}>Pro</div>
          <div style={{ fontSize: 13, marginTop: 8, opacity: 0.85, lineHeight: 1.5 }}>
            The full coach. Adaptive replans, unlimited chat, multi-device.
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          {[
            ['adapt', 'Adaptive replans', 'Coach reshuffles your week when life happens'],
            ['msg',  'Unlimited Coach chat', 'Ask anything. Reply any time.'],
            ['heart','HRV-guided training', 'Training that respects your nervous system'],
            ['watch','Multi-watch support', 'Garmin + Apple + Whoop, with role routing'],
            ['bookmark','Unlimited saves', 'Library, plans, notes — no cap'],
            ['info', 'Priority support', 'Real humans, fast'],
          ].map(([ic, t, s]) => (
            <div key={t} style={{ padding: '12px 0', display: 'flex', gap: 12,
              alignItems: 'flex-start', borderBottom: '1px solid var(--border)' }}>
              <div style={{ width: 32, height: 32, borderRadius: 8,
                background: 'var(--accent-bg)', display: 'flex', alignItems: 'center',
                justifyContent: 'center', flexShrink: 0 }}>
                <Icon name={ic} size={14}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{t}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2, lineHeight: 1.5 }}>{s}</div>
              </div>
            </div>
          ))}
        </div>

        {/* Plan toggle */}
        <div style={{ marginTop: 18, marginBottom: 14, padding: 4,
          background: 'var(--bg-subtle)', borderRadius: 12, display: 'flex',
          border: '1px solid var(--border)' }}>
          {[
            { v: 'monthly', label: 'Monthly', sub: '$9.99' },
            { v: 'annual',  label: 'Annual',  sub: '$95.88 · save 20%' },
          ].map(o => (
            <div key={o.v} onClick={() => setPlan(o.v)}
              style={{ flex: 1, padding: '10px 12px', textAlign: 'center',
                background: plan === o.v ? 'var(--bg)' : 'transparent',
                borderRadius: 8, cursor: 'pointer',
                border: plan === o.v ? '1px solid var(--border-str)' : '1px solid transparent' }}>
              <div style={{ fontSize: 12, fontWeight: 500 }}>{o.label}</div>
              <div className="af-mono" style={{ fontSize: 10, color: 'var(--fg-muted)',
                marginTop: 2 }}>{o.sub}</div>
            </div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('settings')}>
          Start 7-day trial · {price}/mo
        </Btn>
        <div style={{ height: 6 }}/>
        <Btn wide variant="ghost" size="sm">Restore purchase</Btn>
        <div className="af-muted af-mono" style={{ fontSize: 9, textAlign: 'center',
          marginTop: 8, lineHeight: 1.5 }}>
          AUTO-RENEWS · CANCEL ANY TIME · TERMS · PRIVACY
        </div>
      </div>
    </>
  );
}

// =================================================================== A6 — RPE feedback sheet
function RPESheetScreen({ state, nav, setState }) {
  const [rpe, setRpe] = React.useState(7);
  const [notes, setNotes] = React.useState('');
  const [sleep, setSleep] = React.useState('ok');
  const [sore, setSore] = React.useState('some');
  const rungs = [
    { n: 1, e: '😎', label: 'Floating' },
    { n: 2, e: '🙂', label: 'Very easy' },
    { n: 3, e: '😌', label: 'Easy' },
    { n: 4, e: '🙂', label: 'Comfortable' },
    { n: 5, e: '😐', label: 'Moderate' },
    { n: 6, e: '😤', label: 'Somewhat hard' },
    { n: 7, e: '😬', label: 'Hard' },
    { n: 8, e: '🥵', label: 'Very hard' },
    { n: 9, e: '😵', label: 'Near max' },
    { n: 10, e: '🥴', label: 'All out' },
  ];
  const cur = rungs.find(r => r.n === rpe);
  return (
    <>
      <div style={{ flex: 1, background: 'rgba(0,0,0,0.45)',
        display: 'flex', alignItems: 'flex-end' }}>
        <div style={{ width: '100%', background: 'var(--bg)',
          borderTopLeftRadius: 22, borderTopRightRadius: 22,
          padding: '14px 22px 22px', display: 'flex', flexDirection: 'column' }}>
          <div style={{ width: 44, height: 4, background: 'var(--border-str)',
            borderRadius: 2, alignSelf: 'center', marginBottom: 14 }}/>
          <div className="af-h2" style={{ fontSize: 19, textAlign: 'center' }}>How did that feel?</div>
          <div className="af-muted" style={{ fontSize: 12, textAlign: 'center', marginTop: 6 }}>
            Rate the overall effort, 1–10
          </div>

          {/* RPE picker */}
          <div style={{ marginTop: 22, textAlign: 'center' }}>
            <div style={{ fontSize: 42, lineHeight: 1 }}>{cur.e}</div>
            <div style={{ marginTop: 6, fontSize: 13, fontWeight: 500 }}>
              {rpe} · {cur.label}
            </div>
          </div>
          <div style={{ display: 'flex', gap: 4, marginTop: 16,
            justifyContent: 'space-between' }}>
            {rungs.map(r => {
              const on = r.n === rpe;
              return (
                <button key={r.n} onClick={() => setRpe(r.n)}
                  style={{ all: 'unset', cursor: 'pointer', flex: 1, height: 36,
                    background: on ? 'var(--fg)' : 'var(--bg-elev)',
                    color: on ? 'var(--bg)' : 'var(--fg)',
                    border: `1px solid ${on ? 'var(--fg)' : 'var(--border)'}`,
                    borderRadius: 6, fontFamily: 'var(--font-mono)', fontSize: 12,
                    fontWeight: 500, textAlign: 'center' }}>{r.n}</button>
              );
            })}
          </div>

          <FieldGroup label="NOTES" >
            <textarea className="af-input" rows={2} placeholder="How did it feel? Conditions?"
              value={notes} onChange={e => setNotes(e.target.value)}
              style={{ resize: 'none', fontFamily: 'inherit', marginTop: 8 }}/>
          </FieldGroup>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8,
            marginTop: 4 }}>
            <div>
              <div className="af-label" style={{ marginBottom: 6 }}>SLEEP LAST NIGHT</div>
              <div className="af-seg" style={{ height: 32 }}>
                {['poor','ok','great'].map(s => (
                  <div key={s} className="af-seg-item" data-on={sleep === s}
                    onClick={() => setSleep(s)}>{s}</div>
                ))}
              </div>
            </div>
            <div>
              <div className="af-label" style={{ marginBottom: 6 }}>SORENESS</div>
              <div className="af-seg" style={{ height: 32 }}>
                {['none','some','lots'].map(s => (
                  <div key={s} className="af-seg-item" data-on={sore === s}
                    onClick={() => setSore(s)}>{s}</div>
                ))}
              </div>
            </div>
          </div>

          <div style={{ marginTop: 22, display: 'flex', flexDirection: 'column', gap: 6 }}>
            <Btn wide size="lg" onClick={() => nav('history')}>Log it</Btn>
            <Btn wide variant="ghost" size="sm" onClick={() => nav('history')}>Skip</Btn>
          </div>
        </div>
      </div>
    </>
  );
}

// =================================================================== A7a — Library detail
function LibraryDetailScreen({ state, nav }) {
  const item = (state && state.libraryDetail) || {
    kind: 'Video', title: 'Threshold pacing for hybrid athletes',
    domain: 'youtube.com', savedAt: 'Saved 3 days ago',
    tags: ['Running', 'HYROX prep'], thumb: 'video',
  };
  const [notes, setNotes] = React.useState('Listen for the 4:38/km cue at 6:14.');

  const thumbBg = {
    video:   'linear-gradient(135deg, oklch(0.65 0.18 25) 0%, oklch(0.45 0.16 25) 100%)',
    article: 'linear-gradient(135deg, oklch(0.65 0.10 230) 0%, oklch(0.40 0.08 230) 100%)',
    workout: 'linear-gradient(135deg, var(--ready-high) 0%, oklch(0.55 0.18 135) 100%)',
    plan:    'linear-gradient(135deg, oklch(0.72 0.13 85) 0%, oklch(0.45 0.13 85) 100%)',
  }[item.thumb];

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('library')}
        right={<Icon name="kebab" size={16}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 0 20px' }}>
        <div style={{ aspectRatio: '16/9', background: thumbBg,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#fff', fontSize: 56, position: 'relative' }}>
          {item.kind === 'Video' && '▶'}
          {item.kind === 'Article' && '◊'}
          {item.kind === 'Workout' && '◆'}
          {item.kind === 'Plan' && '☰'}
        </div>
        <div style={{ padding: '14px 20px' }}>
          <Chip outline style={{ fontSize: 9, marginBottom: 8 }}>{item.kind.toUpperCase()}</Chip>
          <div className="af-h2" style={{ fontSize: 19, lineHeight: 1.3 }}>{item.title}</div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 6 }}>
            {item.domain.toUpperCase()} · {item.savedAt.toUpperCase()}
          </div>
          <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap', marginTop: 10 }}>
            {item.tags.map(t => (
              <Chip key={t} outline style={{ fontSize: 9 }}>#{t}</Chip>
            ))}
          </div>

          {/* per-kind body */}
          <div style={{ marginTop: 18 }}>
            {item.kind === 'Video' && (
              <div style={{ aspectRatio: '16/9', background: 'var(--bg-subtle)',
                border: '1px solid var(--border)', borderRadius: 10,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 36, color: 'var(--fg-muted)' }}>▶ inline</div>
            )}
            {item.kind === 'Article' && (
              <>
                <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.65 }}>
                  In hybrid athletes, threshold pace isn't a single number — it's a corridor. Coaches who chase one decimal too tightly burn out their athletes by Week 6…
                </div>
                <Btn variant="ghost" size="sm" wide style={{ marginTop: 12 }}>
                  Open in browser
                </Btn>
              </>
            )}
            {item.kind === 'Workout' && (
              <Card style={{ padding: 14 }}>
                <div className="af-label" style={{ fontSize: 9 }}>FULL SESSION</div>
                <div style={{ fontSize: 14, fontWeight: 500, marginTop: 4 }}>4×500m row + 10 thrusters</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>
                  3 rounds · 40m · TSS 65
                </div>
              </Card>
            )}
            {item.kind === 'Plan' && (
              <Card style={{ padding: 14 }}>
                <div className="af-label" style={{ fontSize: 9 }}>10 WEEKS</div>
                <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {[1,2,3,4,5].map(w => (
                    <div key={w} style={{ display: 'flex', justifyContent: 'space-between',
                      padding: '6px 0', borderBottom: '1px solid var(--border)' }}>
                      <span style={{ fontSize: 12 }}>Week {w}</span>
                      <span className="af-muted af-mono" style={{ fontSize: 10 }}>5 sessions</span>
                    </div>
                  ))}
                </div>
              </Card>
            )}
          </div>

          <FieldGroup label="MY NOTES">
            <textarea className="af-input" rows={2} value={notes}
              onChange={e => setNotes(e.target.value)}
              style={{ resize: 'none', fontFamily: 'inherit', marginTop: 6 }}/>
          </FieldGroup>

          <div className="af-label" style={{ marginTop: 18, marginBottom: 8 }}>RELATED SAVES</div>
          <div style={{ display: 'flex', gap: 10, overflowX: 'auto',
            paddingBottom: 4 }} className="af-scroll">
            {['video','article','workout'].map((t, i) => (
              <div key={i} style={{ flexShrink: 0, width: 160 }}>
                <div style={{ aspectRatio: '16/9', borderRadius: 8,
                  background: {
                    video: 'linear-gradient(135deg, oklch(0.65 0.18 25), oklch(0.45 0.16 25))',
                    article: 'linear-gradient(135deg, oklch(0.65 0.10 230), oklch(0.40 0.08 230))',
                    workout: 'linear-gradient(135deg, var(--ready-high), oklch(0.55 0.18 135))',
                  }[t], display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: '#fff', fontSize: 22 }}>
                  {t === 'video' ? '▶' : t === 'article' ? '◊' : '◆'}
                </div>
                <div style={{ fontSize: 11, fontWeight: 500, marginTop: 6, lineHeight: 1.4 }}>
                  Related save title here
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
      {item.kind === 'Workout' && (
        <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
          <Btn wide size="lg" onClick={() => nav('detail')}>Use this workout</Btn>
        </div>
      )}
      {item.kind === 'Plan' && (
        <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
          <Btn wide size="lg" onClick={() => nav('programs')}>Start this plan</Btn>
        </div>
      )}
    </>
  );
}

// =================================================================== A7b — Add to library sheet
function AddToLibraryScreen({ state, nav }) {
  const [url, setUrl] = React.useState('https://youtube.com/watch?v=…');
  const [tags, setTags] = React.useState(['Running']);
  const [kind, setKind] = React.useState('Video');
  const allTags = ['Running','Strength','HYROX prep','Recovery','Nutrition'];
  const toggleTag = (t) => setTags(ts => ts.includes(t) ? ts.filter(x => x !== t) : [...ts, t]);

  return (
    <>
      <div style={{ flex: 1, background: 'rgba(0,0,0,0.45)',
        display: 'flex', alignItems: 'flex-end' }}>
        <div style={{ width: '100%', background: 'var(--bg)',
          borderTopLeftRadius: 22, borderTopRightRadius: 22, padding: '14px 20px 18px' }}>
          <div style={{ width: 44, height: 4, background: 'var(--border-str)',
            borderRadius: 2, margin: '0 auto 14px' }}/>
          <div className="af-h2" style={{ fontSize: 18 }}>Save to library</div>

          <FieldGroup label="LINK">
            <div style={{ position: 'relative' }}>
              <input className="af-input" value={url} onChange={e => setUrl(e.target.value)}
                style={{ paddingRight: 70 }}/>
              <button style={{ all: 'unset', cursor: 'pointer', position: 'absolute',
                right: 6, top: '50%', transform: 'translateY(-50%)',
                padding: '4px 10px', borderRadius: 6, fontSize: 10,
                background: 'var(--bg-subtle)', color: 'var(--fg)',
                border: '1px solid var(--border-str)' }}>Paste</button>
            </div>
          </FieldGroup>

          {/* OG preview */}
          <Card style={{ padding: 0, marginBottom: 12, overflow: 'hidden' }}>
            <div style={{ aspectRatio: '16/9',
              background: 'linear-gradient(135deg, oklch(0.65 0.18 25), oklch(0.45 0.16 25))',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#fff', fontSize: 36 }}>▶</div>
            <div style={{ padding: '10px 12px' }}>
              <div style={{ fontSize: 12, fontWeight: 500 }}>Threshold pacing for hybrid athletes</div>
              <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>YOUTUBE.COM</div>
            </div>
          </Card>

          <FieldGroup label="KIND">
            <div style={{ display: 'flex', gap: 5 }}>
              {['Auto','Video','Article','Workout','Plan'].map(k => (
                <Chip key={k} outline={kind !== k} onClick={() => setKind(k)}
                  style={{ fontSize: 10, cursor: 'pointer',
                    background: kind === k ? 'var(--fg)' : 'transparent',
                    color: kind === k ? 'var(--bg)' : 'var(--fg)',
                    borderColor: kind === k ? 'var(--fg)' : 'var(--border-str)' }}>{k}</Chip>
              ))}
            </div>
          </FieldGroup>

          <FieldGroup label="TAGS">
            <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
              {allTags.map(t => {
                const on = tags.includes(t);
                return (
                  <Chip key={t} outline={!on} onClick={() => toggleTag(t)}
                    style={{ fontSize: 10, cursor: 'pointer',
                      background: on ? 'color-mix(in oklch, var(--ready-high), transparent 70%)' : 'transparent',
                      borderColor: on ? 'var(--ready-high)' : 'var(--border-str)' }}>#{t}</Chip>
                );
              })}
            </div>
          </FieldGroup>

          <Btn wide size="lg" onClick={() => nav('library')}>Save</Btn>

          <div style={{ marginTop: 14, paddingTop: 12, borderTop: '1px solid var(--border)',
            display: 'flex', flexDirection: 'column', gap: 0 }}>
            {[
              ['📷', 'Scan QR'],
              ['📋', 'From shared'],
              ['✍️', 'Write a note'],
            ].map(([e, t]) => (
              <div key={t} className="af-row" style={{ cursor: 'pointer' }}
                onClick={() => nav('library')}>
                <div style={{ width: 26, fontSize: 16, textAlign: 'center' }}>{e}</div>
                <div style={{ flex: 1, fontSize: 12.5 }}>{t}</div>
                <Icon name="chevR" size={12} style={{ color: 'var(--fg-dim)' }}/>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}

// =================================================================== A8a — Programs list
function ProgramsListScreen({ state, nav }) {
  const [seg, setSeg] = React.useState('Active');
  const [empty, setEmpty] = React.useState(false);
  const programs = [
    { id: 'hx', name: 'HYROX Spring Block', meta: '6w · 5/wk · Intermediate',
      progress: 50, hero: 'linear-gradient(135deg, var(--ready-high), oklch(0.55 0.18 135))',
      seg: 'Active' },
    { id: 'm', name: 'Sub-1:30 Half Marathon', meta: '10w · 5/wk · Advanced',
      progress: 0, hero: 'linear-gradient(135deg, oklch(0.72 0.13 85), oklch(0.45 0.13 85))',
      seg: 'All' },
    { id: 'pp', name: 'Power & Posture', meta: '4w · 3/wk · Beginner',
      progress: 0, hero: 'linear-gradient(135deg, oklch(0.65 0.10 230), oklch(0.40 0.08 230))',
      seg: 'All' },
    { id: 'r5', name: 'Return to running', meta: '8w · 4/wk · Recovery',
      progress: 100, hero: 'linear-gradient(135deg, oklch(0.55 0.07 200), oklch(0.35 0.05 200))',
      seg: 'Archived' },
  ];
  const filtered = seg === 'All'
    ? programs
    : programs.filter(p => seg === 'Active' ? p.progress > 0 && p.progress < 100
                        : seg === 'Archived' ? p.progress === 100 : true);

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('home')}
        title="Programs" right={<Icon name="plus" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-seg" style={{ marginBottom: 16 }}>
          {['Active','All','Archived'].map(s => (
            <div key={s} className="af-seg-item" data-on={seg === s}
              onClick={() => setSeg(s)}>{s}</div>
          ))}
        </div>
        {empty || filtered.length === 0 ? (
          <div style={{ padding: '40px 20px', textAlign: 'center' }}>
            <div className="af-h3">Pick a program or have Coach build one</div>
            <div className="af-muted" style={{ fontSize: 12, marginTop: 8, lineHeight: 1.5 }}>
              Structured weeks, adaptive replans, and a clear arc to race day.
            </div>
            <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 8 }}>
              <Btn wide size="lg" onClick={() => setEmpty(false)}>Browse programs</Btn>
              <Btn wide variant="ghost" size="md">Coach builds one for me</Btn>
            </div>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {filtered.map(p => (
              <Card key={p.id} onClick={() => nav('program-detail')}
                style={{ padding: 0, overflow: 'hidden' }}>
                <div style={{ height: 80, background: p.hero,
                  display: 'flex', alignItems: 'flex-end', padding: 12 }}>
                  {p.progress > 0 && p.progress < 100 && (
                    <Chip style={{ fontSize: 9, background: 'rgba(0,0,0,0.4)',
                      color: '#fff', borderColor: 'transparent' }}>ACTIVE</Chip>
                  )}
                </div>
                <div style={{ padding: '12px 14px' }}>
                  <div style={{ fontSize: 14, fontWeight: 500 }}>{p.name}</div>
                  <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>
                    {p.meta.toUpperCase()}
                  </div>
                  {p.progress > 0 && p.progress < 100 && (
                    <>
                      <div className="af-prog" style={{ marginTop: 10 }}>
                        <div className="af-prog-fill" style={{ width: `${p.progress}%` }}/>
                      </div>
                      <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 6 }}>
                        WEEK 3 OF 6 · 50% COMPLETE
                      </div>
                    </>
                  )}
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>
    </>
  );
}

// =================================================================== A8b — Program detail
function ProgramDetailScreen({ state, nav }) {
  const [tab, setTab] = React.useState('Overview');
  const tabs = ['Overview','Calendar','Notes'];

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('programs')}
        right={<Icon name="kebab" size={16}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 0 20px' }}>
        <div style={{ height: 140, background: 'linear-gradient(135deg, var(--ready-high) 0%, oklch(0.45 0.18 135) 100%)',
          color: '#0d1208', padding: '16px 20px', display: 'flex',
          flexDirection: 'column', justifyContent: 'flex-end' }}>
          <div className="af-mono" style={{ fontSize: 9, letterSpacing: '0.08em',
            opacity: 0.7 }}>HYROX</div>
          <div style={{ fontSize: 22, fontWeight: 600, marginTop: 2,
            letterSpacing: '-0.01em' }}>Spring Block</div>
          <div className="af-mono" style={{ fontSize: 10, marginTop: 4, opacity: 0.85 }}>
            WEEK 3 OF 6 · FOUNDATION
          </div>
        </div>

        <div style={{ padding: '14px 20px 6px' }}>
          <div className="af-seg">
            {tabs.map(t => (
              <div key={t} className="af-seg-item" data-on={tab === t}
                onClick={() => setTab(t)}>{t}</div>
            ))}
          </div>
        </div>

        <div style={{ padding: '14px 20px' }}>
          {tab === 'Overview' && (
            <>
              <div className="af-muted" style={{ fontSize: 12.5, lineHeight: 1.6 }}>
                A 6-week aerobic + functional strength block. Builds threshold capacity, posterior chain durability, and HYROX-specific transitions.
              </div>
              <div className="af-label" style={{ marginTop: 18, marginBottom: 6 }}>PHILOSOPHY</div>
              <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.6 }}>
                Two hard days, two strength days, one long day, two easy days. Coach replans when readiness drops.
              </div>
              <div className="af-label" style={{ marginTop: 18, marginBottom: 8 }}>EQUIPMENT</div>
              <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {['Treadmill','Rower','Dumbbells','Wall ball','Sled'].map(e => (
                  <Chip key={e} outline style={{ fontSize: 10 }}>{e}</Chip>
                ))}
              </div>
            </>
          )}
          {tab === 'Calendar' && (
            <>
              <div className="af-label" style={{ marginBottom: 8 }}>THIS WEEK · WEEK 3</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {[
                  { d: 'Mon', t: 'Lower body — posterior', dur: '52m', done: true },
                  { d: 'Tue', t: 'Aerobic base', dur: '48m', done: true },
                  { d: 'Wed', t: 'Recovery spin', dur: '40m', done: true },
                  { d: 'Thu', t: '4×8 threshold', dur: '64m', today: true },
                  { d: 'Fri', t: 'Upper body — pull', dur: '45m' },
                  { d: 'Sat', t: 'Long ride', dur: '2h 10m' },
                  { d: 'Sun', t: 'Rest', dur: '20m' },
                ].map(d => (
                  <div key={d.d} className="af-row" onClick={() => nav('detail')}
                    style={{ background: d.today ? 'color-mix(in oklch, var(--ready-high), transparent 80%)' : 'transparent',
                      borderRadius: 8, padding: '10px 12px',
                      border: d.today ? '1px solid var(--ready-high)' : '1px solid transparent',
                      cursor: 'pointer', opacity: !d.today && !d.done ? 0.65 : 1 }}>
                    <div className="af-mono" style={{ width: 36, fontSize: 11,
                      color: 'var(--fg-muted)' }}>{d.d.toUpperCase()}</div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: 12.5, fontWeight: d.today ? 500 : 400 }}>{d.t}</div>
                      <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 1 }}>{d.dur}</div>
                    </div>
                    {d.done && <Icon name="check" size={14} style={{ color: 'var(--ready-high)' }}/>}
                  </div>
                ))}
              </div>
            </>
          )}
          {tab === 'Notes' && (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {[
                { d: 'Apr 22', t: "HRV dropped 18% overnight — moved hill repeats to Saturday and pulled today back to Z2." },
                { d: 'Apr 15', t: "Tempo pace improved 3 sec/km from Week 2. Holding the structure." },
                { d: 'Apr 8',  t: "Block start. Baseline FTP 245W, threshold pace 4:38/km." },
              ].map(n => (
                <Card key={n.d} tight style={{ padding: 12 }}>
                  <div className="af-mono" style={{ fontSize: 9,
                    color: 'var(--fg-muted)', letterSpacing: '0.05em' }}>COACH · {n.d.toUpperCase()}</div>
                  <div style={{ fontSize: 12, marginTop: 5, lineHeight: 1.55 }}>{n.t}</div>
                </Card>
              ))}
            </div>
          )}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('home')}>Continue program</Btn>
      </div>
    </>
  );
}

Object.assign(window, {
  CoachChatScreen, EditProfileScreen, WorkoutEditorScreen, SuggestWorkoutScreen,
  PaywallProScreen, RPESheetScreen, LibraryDetailScreen, AddToLibraryScreen,
  ProgramsListScreen, ProgramDetailScreen,
});
