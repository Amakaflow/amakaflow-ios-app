/**
 * AmakaFlow hi-fi screens — onboarding, pairing, history, settings.
 */


// ------------------------------------------------------------------ Onboarding
function OnboardingScreen({ state, nav, setState }) {
  const [step, setStep] = React.useState(0);
  const [answers, setAnswers] = React.useState({
    goal: [], goalDetails: { event: '', date: '', strength: null },
    hours: 8, modality: [], experience: null, injury: null,
  });
  const q = [
    {
      k: 'goal',
      title: 'What are you training for?',
      sub: 'Select all that apply. Add a date if you have one.',
      multiGoal: true,
    },
    {
      k: 'hours',
      title: 'How many hours per week?',
      sub: 'Honest average — coach will adapt',
      slider: true,
    },
    {
      k: 'modality',
      title: 'Which modalities?',
      sub: 'Pick all that apply',
      multi: true,
      options: [
        { v: 'run', label: 'Running' },
        { v: 'lift', label: 'Strength' },
        { v: 'ride', label: 'Cycling' },
        { v: 'row', label: 'Rowing / erg' },
        { v: 'swim', label: 'Swimming' },
      ],
    },
    {
      k: 'experience',
      title: 'Training experience?',
      options: [
        { v: 'new', label: 'New to structured training', hint: '0–1 years' },
        { v: 'inter', label: 'Intermediate', hint: '1–3 years consistent' },
        { v: 'adv', label: 'Advanced', hint: '3+ years, races regularly' },
      ],
    },
    {
      k: 'injury',
      title: 'Any current injuries or limits?',
      sub: 'Optional — helps coach avoid re-aggravation',
      options: [
        { v: 'none', label: 'None right now' },
        { v: 'knee', label: 'Knee' },
        { v: 'back', label: 'Lower back' },
        { v: 'ankle', label: 'Ankle / Achilles' },
        { v: 'other', label: 'Something else', hint: 'Add detail later' },
      ],
    },
  ];
  const cur = q[step];
  const total = q.length;
  const val = answers[cur.k];
  const answered = cur.slider
    ? true
    : cur.multiGoal ? (val || []).length > 0
    : cur.multi ? (val || []).length > 0 : !!val;

  const set = (v) => {
    if (cur.multi) {
      setAnswers(a => {
        const arr = a[cur.k] || [];
        return { ...a, [cur.k]: arr.includes(v) ? arr.filter(x => x !== v) : [...arr, v] };
      });
    } else {
      setAnswers(a => ({ ...a, [cur.k]: v }));
    }
  };

  const next = () => {
    if (step < total - 1) setStep(step + 1);
    else {
      setState(s => ({ ...s, onboarded: true, toast: 'Coaching profile ready' }));
      nav('pairing');
    }
  };

  return (
    <>
      <div style={{ padding: '14px 20px 0', display: 'flex', alignItems: 'center', gap: 12 }}>
        <div onClick={() => step > 0 && setStep(step - 1)}
          style={{ color: step > 0 ? 'var(--fg-muted)' : 'var(--fg-dim)',
            cursor: step > 0 ? 'pointer' : 'default' }}>
          <Icon name="chevL" size={20}/>
        </div>
        <div className="af-prog" style={{ flex: 1 }}>
          <div className="af-prog-fill" style={{ width: `${((step + 1) / total) * 100}%` }}/>
        </div>
        <div className="af-mono" style={{ fontSize: 11, color: 'var(--fg-muted)' }}>
          {step + 1}/{total}
        </div>
      </div>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '28px 24px 20px' }}>
        <div className="af-label">COACHING PROFILE</div>
        <div className="af-h1" style={{ marginTop: 6, fontSize: 24 }}>{cur.title}</div>
        {cur.sub && <div className="af-muted" style={{ fontSize: 13, marginTop: 8 }}>{cur.sub}</div>}

        <div style={{ marginTop: 28 }}>
          {cur.multiGoal ? (
            <MultiGoal answers={answers} setAnswers={setAnswers}/>
          ) : cur.slider ? (
            <div>
              <div style={{ textAlign: 'center', marginBottom: 24 }}>
                <div className="af-mono" style={{ fontSize: 56, fontWeight: 500,
                  letterSpacing: '-0.02em', lineHeight: 1 }}>
                  {answers.hours}
                </div>
                <div className="af-label" style={{ marginTop: 6 }}>HOURS PER WEEK</div>
              </div>
              <input type="range" min="2" max="18" value={answers.hours}
                onChange={e => setAnswers(a => ({ ...a, hours: +e.target.value }))}
                style={{ width: '100%', accentColor: 'var(--fg)' }}/>
              <div className="af-mono" style={{ display: 'flex',
                justifyContent: 'space-between', fontSize: 10,
                color: 'var(--fg-muted)', marginTop: 6 }}>
                <span>2</span><span>10</span><span>18+</span>
              </div>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {cur.options.map(o => {
                const sel = cur.multi ? (val || []).includes(o.v) : val === o.v;
                return (
                  <button key={o.v} onClick={() => set(o.v)}
                    style={{
                      all: 'unset', cursor: 'pointer',
                      padding: '14px 16px', borderRadius: 10,
                      border: `1px solid ${sel ? 'var(--fg)' : 'var(--border)'}`,
                      background: sel ? 'var(--accent-bg)' : 'var(--bg-elev)',
                      display: 'flex', alignItems: 'center', gap: 12,
                    }}>
                    <div style={{ width: 18, height: 18, borderRadius: cur.multi ? 4 : 999,
                      border: `1.5px solid ${sel ? 'var(--fg)' : 'var(--border-str)'}`,
                      background: sel ? 'var(--fg)' : 'transparent',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      color: 'var(--bg)', flexShrink: 0 }}>
                      {sel && <Icon name="check" size={12}/>}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: 14, fontWeight: 500 }}>{o.label}</div>
                      {o.hint && <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{o.hint}</div>}
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px' }}>
        <Btn wide size="lg" onClick={next} disabled={!answered}>
          {step === total - 1 ? 'Finish · pair watch' : 'Continue'}
          <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

// Multi-goal UI: cards that can be selected, with inline expansion for details.
function MultiGoal({ answers, setAnswers }) {
  const goals = answers.goal || [];
  const set = (v) => {
    setAnswers(a => {
      let next = [...(a.goal || [])];
      // "none" is mutually exclusive
      if (v === 'none') return { ...a, goal: next.includes('none') ? [] : ['none'] };
      // selecting anything else removes "none"
      next = next.filter(x => x !== 'none');
      if (next.includes(v)) next = next.filter(x => x !== v);
      else next.push(v);
      return { ...a, goal: next };
    });
  };
  const setDetail = (k, v) =>
    setAnswers(a => ({ ...a, goalDetails: { ...a.goalDetails, [k]: v } }));

  const cards = [
    { v: 'race',  emoji: '🏃', label: 'Race or event',
      hint: 'Marathon, HYROX, triathlon, ultra' },
    { v: 'shape', emoji: '🏋️', label: 'Strength / aesthetic',
      hint: 'Build, cut, look good' },
    { v: 'health',emoji: '🩺', label: 'Medical / general health',
      hint: 'Doctor-recommended, baseline fitness' },
    { v: 'none',  emoji: '😶', label: 'No specific goal',
      hint: "Just keep me moving" },
  ];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {cards.map(c => {
        const sel = goals.includes(c.v);
        return (
          <div key={c.v} style={{ borderRadius: 12,
            border: `1px solid ${sel ? 'var(--fg)' : 'var(--border)'}`,
            background: sel ? 'var(--accent-bg)' : 'var(--bg-elev)',
            overflow: 'hidden' }}>
            <button onClick={() => set(c.v)}
              style={{ all: 'unset', cursor: 'pointer', width: '100%',
                padding: '14px 14px',
                display: 'flex', alignItems: 'center', gap: 12, boxSizing: 'border-box' }}>
              <div style={{ fontSize: 22, lineHeight: 1, width: 28, textAlign: 'center' }}>{c.emoji}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500 }}>{c.label}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{c.hint}</div>
              </div>
              {sel
                ? <div onClick={(e) => { e.stopPropagation(); set(c.v); }}
                    style={{ color: 'var(--fg-muted)', padding: 4, cursor: 'pointer' }}>
                    <Icon name="close" size={14}/>
                  </div>
                : <div style={{ width: 18, height: 18, borderRadius: 4,
                    border: '1.5px solid var(--border-str)' }}/>
              }
            </button>
            {/* expansion */}
            {sel && c.v === 'race' && (
              <div style={{ padding: '12px 14px 14px', borderTop: '1px solid var(--border)',
                display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 8 }}>
                <input className="af-input" placeholder="Event name"
                  value={answers.goalDetails.event}
                  onChange={e => setDetail('event', e.target.value)}/>
                <input className="af-input" placeholder="Date · optional"
                  value={answers.goalDetails.date}
                  onChange={e => setDetail('date', e.target.value)}/>
              </div>
            )}
            {sel && c.v === 'shape' && (
              <div style={{ padding: '10px 14px 14px', borderTop: '1px solid var(--border)',
                display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                {['Build muscle','Lose weight','Just look good'].map(opt => {
                  const on = answers.goalDetails.strength === opt;
                  return (
                    <Chip key={opt} outline={!on}
                      style={{ cursor: 'pointer', fontSize: 11, padding: '6px 10px',
                        background: on ? 'var(--fg)' : 'transparent',
                        color: on ? 'var(--bg)' : 'var(--fg)',
                        borderColor: on ? 'var(--fg)' : 'var(--border-str)' }}
                      onClick={() => setDetail('strength', opt)}>{opt}</Chip>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ------------------------------------------------------------------ Pairing (multi-watch with roles)
function PairingScreen({ state, nav, setState }) {
  const [devices, setDevices] = React.useState([
    { id: 'g965', name: 'Garmin FR965', model: 'Forerunner 965',
      roles: ['workouts', 'recovery'], sync: '2m ago', icon: 'watch' },
    { id: 'aw9',  name: 'Apple Watch', model: 'Series 9',
      roles: ['recovery'], sync: '8m ago', icon: 'watch' },
    { id: 'whp',  name: 'Whoop 4.0', model: 'Strap',
      roles: ['recovery'], sync: '14m ago', icon: 'heart' },
  ]);
  const [addOpen, setAddOpen] = React.useState(false);
  const [pairing, setPairing] = React.useState(null);
  const [code, setCode] = React.useState(['', '', '', '', '', '']);
  const inputs = React.useRef([]);

  const ALL_ROLES = [
    { v: 'workouts', label: 'Workouts' },
    { v: 'recovery', label: 'Recovery' },
    { v: 'strength', label: 'Strength' },
  ];
  const toggleRole = (devId, role) => {
    setDevices(ds => ds.map(d => {
      if (d.id !== devId) return d;
      return { ...d, roles: d.roles.includes(role)
        ? d.roles.filter(r => r !== role)
        : [...d.roles, role] };
    }));
  };
  const onKey = (i, v) => {
    const dg = v.replace(/\D/g, '').slice(0, 1);
    setCode(c => { const n = [...c]; n[i] = dg; return n; });
    if (dg && i < 5) inputs.current[i + 1]?.focus();
  };
  const finishPair = () => {
    const newDev = { id: 'g' + Math.random().toString(36).slice(2,6),
      name: 'Garmin FR265', model: 'Forerunner 265',
      roles: ['workouts'], sync: 'just now', icon: 'watch' };
    setDevices(d => [...d, newDev]);
    setPairing(null); setAddOpen(false); setCode(['','','','','','']);
    setState(s => ({ ...s, toast: 'Watch paired' }));
  };

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')}
        title="Devices" sub={`${devices.length} connected`}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-label" style={{ marginBottom: 8 }}>CONNECTED DEVICES</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {devices.map(d => (
            <Card key={d.id} style={{ padding: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ width: 38, height: 38, borderRadius: 10,
                  background: 'var(--accent-bg)', display: 'flex',
                  alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Icon name={d.icon} size={18}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500 }}>{d.name}</div>
                  <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 2,
                    display: 'flex', alignItems: 'center', gap: 4 }}>
                    <span className="af-dot af-dot-high" style={{ width: 5, height: 5,
                      boxShadow: 'none' }}/>
                    {d.model.toUpperCase()} · SYNCED {d.sync.toUpperCase()}
                  </div>
                </div>
                <Icon name="info" size={14} style={{ color: 'var(--fg-dim)' }}/>
              </div>
              <div style={{ display: 'flex', gap: 6, marginTop: 12, flexWrap: 'wrap' }}>
                {ALL_ROLES.map(r => {
                  const on = d.roles.includes(r.v);
                  return (
                    <Chip key={r.v} outline={!on}
                      onClick={() => toggleRole(d.id, r.v)}
                      style={{ fontSize: 10, padding: '4px 9px',
                        background: on ? 'var(--fg)' : 'transparent',
                        color: on ? 'var(--bg)' : 'var(--fg-muted)',
                        borderColor: on ? 'var(--fg)' : 'var(--border-str)' }}>
                      {on && <Icon name="check" size={9}/>}
                      {r.label}
                    </Chip>
                  );
                })}
              </div>
            </Card>
          ))}
        </div>
        <div style={{ marginTop: 14 }}>
          <Btn variant="ghost" wide size="md" onClick={() => setAddOpen(true)}>
            <Icon name="plus" size={14}/> Add device
          </Btn>
        </div>

        <div style={{ marginTop: 18, padding: 12, background: 'var(--bg-subtle)',
          borderRadius: 10, display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <Icon name="info" size={14} style={{ color: 'var(--fg-muted)', flexShrink: 0,
            marginTop: 2 }}/>
          <div className="af-muted" style={{ fontSize: 11, lineHeight: 1.55 }}>
            Roles decide which device feeds which metric. If two devices fight for the same role, the most-recently-synced wins.
          </div>
        </div>
      </div>

      <Sheet open={addOpen && !pairing} onClose={() => setAddOpen(false)} title="Add device">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { v: 'garmin', name: 'Garmin', sub: '6-digit pairing code', live: true, letter: 'G', tone: 'oklch(0.55 0.16 235)' },
            { v: 'apple',  name: 'Apple Watch', sub: 'Auto-detect via HealthKit', live: true, letter: 'A', tone: 'oklch(0.30 0 0)' },
            { v: 'strava', name: 'Strava', sub: 'OAuth · coming soon', live: false, letter: 'S', tone: 'oklch(0.65 0.20 35)' },
            { v: 'whoop',  name: 'Whoop',  sub: 'OAuth · coming soon', live: false, letter: 'W', tone: 'oklch(0.30 0 0)' },
            { v: 'polar',  name: 'Polar',  sub: 'OAuth · coming soon', live: false, letter: 'P', tone: 'oklch(0.55 0.18 30)' },
          ].map(o => (
            <div key={o.v}
              onClick={() => o.live && (o.v === 'garmin' ? setPairing('garmin') : finishPair())}
              style={{ padding: '14px 14px', borderRadius: 12,
                border: '1px solid var(--border)',
                opacity: o.live ? 1 : 0.6,
                cursor: o.live ? 'pointer' : 'not-allowed',
                display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ width: 32, height: 32, borderRadius: 8,
                background: o.tone, color: '#fff', fontWeight: 700,
                fontFamily: 'var(--font-mono)', fontSize: 13,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0 }}>{o.letter}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500 }}>{o.name}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{o.sub}</div>
              </div>
              {!o.live
                ? <Chip outline style={{ fontSize: 9 }}>SOON</Chip>
                : <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>}
            </div>
          ))}
        </div>
      </Sheet>

      <Sheet open={pairing === 'garmin'} onClose={() => setPairing(null)} title="Pair Garmin">
        <div className="af-muted" style={{ fontSize: 12, marginBottom: 14, lineHeight: 1.5 }}>
          Open AmakaFlow on your Garmin. A 6-digit code will appear — enter it below.
        </div>
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          {code.map((d, i) => (
            <input key={i} ref={el => inputs.current[i] = el}
              value={d} onChange={e => onKey(i, e.target.value)}
              inputMode="numeric" maxLength={1} className="af-mono"
              style={{
                flex: 1, height: 48, textAlign: 'center', fontSize: 20,
                fontWeight: 500,
                border: `1px solid ${d ? 'var(--fg)' : 'var(--border-str)'}`,
                borderRadius: 10, background: 'var(--bg-elev)',
                color: 'var(--fg)', outline: 'none' }}/>
          ))}
        </div>
        <Btn wide size="lg" onClick={finishPair}
          disabled={code.join('').length !== 6}>Pair watch</Btn>
      </Sheet>
    </>
  );
}

// ------------------------------------------------------------------ Pairing (legacy single-watch — kept for reference)
function PairingScreenLegacy({ state, nav, setState }) {
  const [code, setCode] = React.useState(['', '', '', '', '', '']);
  const [error, setError] = React.useState('');
  const [busy, setBusy] = React.useState(false);
  const [success, setSuccess] = React.useState(false);
  const inputs = React.useRef([]);

  const onKey = (i, v) => {
    const d = v.replace(/\D/g, '').slice(0, 1);
    setCode(c => {
      const n = [...c]; n[i] = d; return n;
    });
    setError('');
    if (d && i < 5) inputs.current[i + 1]?.focus();
  };
  const onBack = (i, e) => {
    if (e.key === 'Backspace' && !code[i] && i > 0) inputs.current[i - 1]?.focus();
  };

  const submit = () => {
    const full = code.join('');
    if (full.length !== 6) { setError('Enter all 6 digits'); return; }
    setBusy(true); setError('');
    setTimeout(() => {
      if (full === '000000') {
        setError('Code invalid — check your watch');
        setBusy(false);
      } else {
        setSuccess(true);
        setTimeout(() => {
          setState(s => ({ ...s, paired: true, toast: 'Watch paired' }));
          nav('home');
        }, 900);
      }
    }, 900);
  };

  return (
    <>
      <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('home')}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '4px 24px 20px' }}>
        <div style={{ width: 56, height: 56, borderRadius: 14,
          background: 'var(--accent-bg)', display: 'flex', alignItems: 'center',
          justifyContent: 'center', marginBottom: 18 }}>
          <Icon name="watch" size={26}/>
        </div>
        <div className="af-label">PAIR WATCH</div>
        <div className="af-h1" style={{ marginTop: 6 }}>Enter the 6-digit code</div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 8, lineHeight: 1.5 }}>
          Open AmakaFlow on your Garmin watch. A pairing code will appear — enter it below.
        </div>

        <div style={{ display: 'flex', gap: 8, margin: '30px 0 10px' }}>
          {code.map((d, i) => (
            <input key={i} ref={el => inputs.current[i] = el}
              value={d} onChange={e => onKey(i, e.target.value)}
              onKeyDown={e => onBack(i, e)} inputMode="numeric" maxLength={1}
              className="af-mono"
              style={{
                flex: 1, height: 56, textAlign: 'center', fontSize: 22,
                fontWeight: 500, border: `1px solid ${success ? 'var(--ready-high)' : error ? 'var(--destructive)' : d ? 'var(--fg)' : 'var(--border-str)'}`,
                borderRadius: 10, background: 'var(--bg-elev)', color: 'var(--fg)',
                outline: 'none',
                transition: 'border-color 0.2s',
              }}/>
          ))}
        </div>
        {error && <div style={{ color: 'var(--destructive)', fontSize: 12 }}>{error}</div>}
        {success && <div style={{ color: 'var(--ready-high)', fontSize: 12,
          display: 'flex', alignItems: 'center', gap: 4 }}>
          <Icon name="check" size={12}/> Paired successfully
        </div>}

        <div style={{ marginTop: 28, padding: 14, border: '1px solid var(--border)',
          borderRadius: 10, display: 'flex', gap: 12, alignItems: 'flex-start' }}>
          <Icon name="info" size={16} style={{ color: 'var(--fg-muted)', flexShrink: 0,
            marginTop: 1 }}/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 12, fontWeight: 500 }}>Don't see the code?</div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 3, lineHeight: 1.5 }}>
              Install AmakaFlow from Connect IQ, then open the app on your watch. Bluetooth must be on.
            </div>
          </div>
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px' }}>
        <Btn wide size="lg" onClick={submit} disabled={busy || code.join('').length !== 6 || success}>
          {busy ? 'Pairing…' : success ? 'Paired' : 'Pair watch'}
        </Btn>
        <div style={{ height: 4 }}/>
        <Btn wide size="md" variant="ghost" onClick={() => nav('home')}>Skip for now</Btn>
      </div>
    </>
  );
}

// ------------------------------------------------------------------ History
function HistoryScreen({ state, setState }) {
  const items = state.history;
  return (
    <>
      <TopBar title="History" sub={`${items.length} sessions · last 30 days`}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <Card tight style={{ padding: 14, marginBottom: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between',
            alignItems: 'flex-end', marginBottom: 10 }}>
            <div>
              <div className="af-label">LOAD · LAST 4 WEEKS</div>
              <div className="af-mono" style={{ fontSize: 22, fontWeight: 500,
                marginTop: 4 }}>412 <span style={{ fontSize: 11, color: 'var(--fg-muted)' }}>TSS</span></div>
            </div>
            <Chip><span className="af-dot af-dot-high"/> Optimal</Chip>
          </div>
          <Bars values={[280, 340, 385, 412]} h={36} accent={3} w={280}/>
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6,
            color: 'var(--fg-muted)', fontSize: 10, fontFamily: 'var(--font-mono)' }}>
            <span>W-3</span><span>W-2</span><span>W-1</span><span>THIS</span>
          </div>
        </Card>

        <div className="af-seg" style={{ marginBottom: 12 }}>
          <div className="af-seg-item" data-on={true}>All</div>
          <div className="af-seg-item" data-on={false}>Run</div>
          <div className="af-seg-item" data-on={false}>Strength</div>
          <div className="af-seg-item" data-on={false}>Ride</div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {items.map((h, i) => {
            const icon = h.type === 'Run' ? 'run'
              : h.type === 'Ride' ? 'bike'
              : h.type === 'Lift' ? 'lift' : 'flag';
            return (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 12,
                padding: '12px 0',
                borderBottom: i < items.length - 1 ? '1px solid var(--border)' : 'none' }}>
                <div style={{ width: 36, height: 36, borderRadius: 8,
                  background: 'var(--accent-bg)', display: 'flex',
                  alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                  <Icon name={icon} size={16}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span style={{ fontSize: 13, fontWeight: 500, whiteSpace: 'nowrap',
                      overflow: 'hidden', textOverflow: 'ellipsis' }}>{h.title}</span>
                    {h.manual && <Chip outline style={{ fontSize: 9, padding: '2px 6px' }}>MANUAL</Chip>}
                  </div>
                  <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>
                    {h.date} · {h.dur} · RPE {h.rpe}
                  </div>
                </div>
                <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
              </div>
            );
          })}
        </div>
      </div>
      <TabBar active={4} onChange={i => setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

// ------------------------------------------------------------------ Settings
// Grouped settings row — icon · label · optional value · chevron.
function SetRow({ icon, label, value, onClick, danger, last }) {
  return (
    <div className="af-row" onClick={onClick}
      style={{ cursor: onClick ? 'pointer' : 'default',
        borderBottom: last ? 'none' : '1px solid var(--border)' }}>
      {icon && <Icon name={icon} size={16}
        style={{ color: danger ? 'var(--destructive)' : 'var(--fg-muted)', flexShrink: 0 }}/>}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13.5, color: danger ? 'var(--destructive)' : 'var(--fg)' }}>{label}</div>
        {value && <div className="af-muted" style={{ fontSize: 11, marginTop: 2,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{value}</div>}
      </div>
      <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)', flexShrink: 0 }}/>
    </div>
  );
}

function SettingsScreen({ state, setState, nav }) {
  const conns = window.AF_CONNECTIONS || [];
  const connected = conns.filter(c => c.status !== 'off').length;
  const soon = () => setState && setState(s => ({ ...s, toast: 'Opening…' }));

  const Group = ({ children }) => (
    <Card tight style={{ padding: 0, marginBottom: 22 }}>
      <div style={{ padding: '0 14px' }}>{children}</div>
    </Card>
  );

  return (
    <>
      <TopBar title="Profile"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        {/* Identity */}
        <Card onClick={() => nav('edit-profile')}
          style={{ padding: 16, marginBottom: 14, display: 'flex',
          alignItems: 'center', gap: 12, cursor: 'pointer' }}>
          <div style={{ width: 46, height: 46, borderRadius: 999,
            background: 'linear-gradient(135deg, var(--ready-high) 0%, oklch(0.55 0.16 200) 100%)',
            color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 17, fontWeight: 600, fontFamily: 'var(--font-mono)', flexShrink: 0 }}>AO</div>
          <div style={{ flex: 1 }}>
            <div className="af-h3">Adaeze Okafor</div>
            <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>
              HYROX · 8H/WK · INTERMEDIATE
            </div>
          </div>
          <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
        </Card>

        {/* Upgrade — compact */}
        <Card onClick={() => nav('paywall')}
          style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 24,
            cursor: 'pointer' }}>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13, fontWeight: 500 }}>Free plan</div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>
              Upgrade for adaptive coaching
            </div>
          </div>
          <Chip>Upgrade</Chip>
        </Card>

        {/* ============ CONNECTIONS — hub card pinned at top ============ */}
        <div className="af-label" style={{ marginBottom: 8 }}>CONNECTIONS</div>
        <Card onClick={() => nav('connections')}
          style={{ marginBottom: 24, cursor: 'pointer' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ flex: 1 }}>
              <div className="af-h3">Connections</div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 4 }}>
                <span className="af-dot af-dot-high"/>
                <span className="af-muted" style={{ fontSize: 11.5 }}>
                  {connected} connected · watches, messaging, calendar
                </span>
              </div>
            </div>
            <Icon name="chevR" size={15} style={{ color: 'var(--fg-dim)', flexShrink: 0 }}/>
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            {conns.map(c => {
              const brand = c.tile && c.tile !== 'neutral';
              const off = c.status === 'off';
              return (
                <div key={c.id} style={{ position: 'relative' }}>
                  <div style={{ width: 38, height: 38, borderRadius: 999,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    background: brand ? c.tile : 'var(--accent-bg)',
                    color: brand ? '#fff' : 'var(--fg)',
                    opacity: off ? 0.4 : 1 }}>
                    <Icon name={c.icon} size={17}/>
                  </div>
                  {!off && <span className="af-dot af-dot-high" style={{ position: 'absolute',
                    bottom: -1, right: -1, border: '2px solid var(--bg-elev)',
                    boxShadow: 'none', width: 10, height: 10 }}/>}
                </div>
              );
            })}
          </div>
        </Card>

        {/* ============ PROFILE & TRAINING ============ */}
        <div className="af-label" style={{ marginBottom: 8 }}>PROFILE & TRAINING</div>
        <Group>
          <SetRow icon="user" label="Edit profile"
            value="Goals · experience · sessions / week" onClick={() => nav('edit-profile')}/>
          <SetRow icon="sliders" label="Training preferences"
            value="Disciplines · auto-swap · rest days" onClick={soon}/>
          <SetRow icon="lift" label="Equipment"
            value="Dumbbells · pull-up bar · foam roller" onClick={() => nav('equipment')} last/>
        </Group>

        {/* ============ COACHING ============ */}
        <div className="af-label" style={{ marginBottom: 8 }}>COACHING</div>
        <Group>
          <SetRow icon="heart" label="Readiness sources"
            value="HRV · sleep · resting HR" onClick={() => nav('sources')}/>
          <SetRow icon="chart" label="Fatigue threshold"
            value="Auto-swap below 45" onClick={() => nav('fatigue')}/>
          <SetRow icon="mic" label="Notifications & voice cues"
            value="Morning check-in · audio coaching" onClick={soon} last/>
        </Group>

        {/* ============ NUTRITION & ACTIVITY ============ */}
        <div className="af-label" style={{ marginBottom: 8 }}>NUTRITION & ACTIVITY</div>
        <Group>
          <SetRow icon="food" label="Nutrition"
            value="Targets · fueling reminders" onClick={() => nav('nutrition')}/>
          <SetRow icon="share" label="Activity / Social"
            value="Feed · friends · sharing" onClick={() => nav('social')} last/>
        </Group>

        {/* ============ APP ============ */}
        <div className="af-label" style={{ marginBottom: 8 }}>APP</div>
        <Group>
          <SetRow icon="gear" label="App preferences"
            value="Units · appearance · haptics" onClick={soon}/>
          <SetRow icon="info" label="Debug & diagnostics"
            value="Event log · sync state · build" onClick={() => nav('debug')}/>
          <SetRow icon="download" label="Account, privacy & data"
            value="Export · privacy · sign out" onClick={() => nav('export')} last/>
        </Group>

        <div className="af-muted af-mono" style={{ fontSize: 10, textAlign: 'center',
          marginTop: 6 }}>
          AMAKAFLOW v1.0.0 · BUILD 2026.04.24
        </div>
      </div>
      <TabBar active={5} onChange={i => setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

Object.assign(window, {
  OnboardingScreen, PairingScreen, HistoryScreen, SettingsScreen,
});
