/**
 * AmakaFlow hi-fi screens (Card Stack direction).
 * Each screen is a self-contained component that receives (state, nav, setState).
 * Interactions wired: Start, Readiness detail sheet, SWAP from player,
 * Log manually, Pair submit, RPE + injury free-text.
 */


// ------------------------------------------------------------------ Home
function HomeScreen({ state, nav, setState }) {
  const { readiness, tab } = state;
  const [readyOpen, setReadyOpen] = React.useState(false);
  const [logOpen, setLogOpen] = React.useState(false);
  const [logType, setLogType] = React.useState('Run');
  const [logDist, setLogDist] = React.useState('');
  const [logDur, setLogDur] = React.useState('');
  const [logRPE, setLogRPE] = React.useState(null);
  const empty = state.emptyHome === true;
  const readyLabel = readiness >= 70 ? 'Ready' : readiness >= 45 ? 'Moderate' : 'Recover';
  const readyDot = readiness >= 70 ? 'high' : readiness >= 45 ? 'mod' : 'low';

  const submitManual = () => {
    if (!logType || !logDur) return;
    setLogOpen(false);
    setState(s => ({
      ...s,
      history: [{
        date: 'Today', type: logType, title: `Manual ${logType.toLowerCase()}`,
        dur: `${logDur} min`, rpe: logRPE || 6, manual: true,
      }, ...s.history],
      toast: 'Logged manually',
    }));
    setLogDist(''); setLogDur(''); setLogRPE(null);
  };

  // Week strip data (Sun-Sat), today highlighted
  const weekStrip = [
    { d: 'Sun', dt: 20, icon: 'heart', val: 'rest', done: true },
    { d: 'Mon', dt: 21, icon: 'lift',  val: '52m', done: true },
    { d: 'Tue', dt: 22, icon: 'run',   val: '8.2km', done: true },
    { d: 'Wed', dt: 23, icon: 'bike',  val: '40m', done: true },
    { d: 'Thu', dt: 24, icon: 'run',   val: '10.2km', today: true },
    { d: 'Fri', dt: 25, icon: 'lift',  val: '45m' },
    { d: 'Sat', dt: 26, icon: 'bike',  val: '2h10' },
  ];

  return (
    <>
      <div style={{ padding: '10px 18px 12px', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between' }}>
        <div onClick={() => {}} style={{ color: 'var(--fg-muted)', cursor: 'pointer',
          width: 28, height: 28, display: 'flex', alignItems: 'center' }}>
          <Icon name="chevL" size={20}/>
        </div>
        <div style={{ textAlign: 'center' }}>
          <div className="af-h3" style={{ fontSize: 15 }}>Today</div>
          <div className="af-label" style={{ fontSize: 9, marginTop: 1 }}>THU · APR 24</div>
        </div>
        <div onClick={() => nav('settings')} style={{ color: 'var(--fg-muted)',
          cursor: 'pointer', width: 28, height: 28, display: 'flex',
          alignItems: 'center', justifyContent: 'flex-end' }}>
          <Icon name="gear" size={18}/>
        </div>
      </div>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 18px 16px' }}>

        {/* 2-col metric cards */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8,
          marginBottom: 10 }}>
          <Card onClick={() => setReadyOpen(true)} style={{ padding: 14 }}>
            <div className="af-label" style={{ fontSize: 9 }}>READINESS</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 6 }}>
              <span className="af-mono" style={{ fontSize: 30, fontWeight: 500,
                letterSpacing: '-0.02em', lineHeight: 1 }}>{readiness}</span>
              <span className="af-muted af-mono" style={{ fontSize: 12 }}>%</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 8 }}>
              <span className={`af-dot af-dot-${readyDot}`} style={{ width: 6, height: 6 }}/>
              <span className="af-muted" style={{ fontSize: 11 }}>{readyLabel}</span>
            </div>
          </Card>
          <Card style={{ padding: 14 }}>
            <div className="af-label" style={{ fontSize: 9 }}>TODAY'S LOAD</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 6 }}>
              <span className="af-mono" style={{ fontSize: 30, fontWeight: 500,
                letterSpacing: '-0.02em', lineHeight: 1 }}>78</span>
              <span className="af-muted af-mono" style={{ fontSize: 12 }}>tss</span>
            </div>
            <div style={{ position: 'relative', marginTop: 12, height: 6,
              borderRadius: 999, overflow: 'hidden',
              background: 'linear-gradient(90deg, var(--ready-high) 0%, var(--ready-mod) 60%, var(--ready-low) 100%)' }}>
              {/* RPE marker */}
              <div style={{ position: 'absolute', left: '62%', top: -3, bottom: -3,
                width: 2, background: 'var(--fg)', borderRadius: 1 }}/>
            </div>
            <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 5,
              display: 'flex', justifyContent: 'space-between' }}>
              <span>EASY</span><span>HARD</span>
            </div>
          </Card>
        </div>

        {/* Program / Empty State */}
        {!empty ? (
          <div onClick={() => nav('workouts')}
            style={{ position: 'relative', padding: '16px 16px',
              borderRadius: 14, cursor: 'pointer', overflow: 'hidden',
              background: 'linear-gradient(135deg, color-mix(in oklch, var(--ready-high), transparent 65%) 0%, color-mix(in oklch, var(--ready-high), transparent 88%) 100%)',
              border: '1px solid color-mix(in oklch, var(--ready-high), transparent 55%)' }}>
            <div className="af-label" style={{ fontSize: 9, color: 'var(--fg)',
              opacity: 0.7 }}>CURRENT PROGRAM</div>
            <div className="af-h2" style={{ marginTop: 6, fontSize: 17 }}>
              HYROX Spring Block
            </div>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center',
              marginTop: 6, fontSize: 12, color: 'var(--fg)', opacity: 0.85 }}>
              <span>Foundation · Wk 3 of 6</span>
              <span style={{ opacity: 0.5 }}>·</span>
              <span className="af-mono">42d to race</span>
            </div>
            <div style={{ position: 'absolute', right: 14, top: '50%',
              transform: 'translateY(-50%)', color: 'var(--fg)', opacity: 0.6 }}>
              <Icon name="chevR" size={16}/>
            </div>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <Btn wide size="lg" onClick={() => nav('onboarding')}>
              Build me a plan <Icon name="chevR" size={14}/>
            </Btn>
            <Btn wide variant="ghost" size="md" onClick={() => nav('detail')}>
              Just today's workout
            </Btn>
            <Btn wide variant="ghost" size="md" onClick={() => nav('coach')}>
              Coach picks for me
            </Btn>
          </div>
        )}

        {/* Week strip */}
        <div style={{ display: 'flex', justifyContent: 'space-between',
          alignItems: 'center', margin: '20px 0 8px' }}>
          <div className="af-label">THIS WEEK</div>
          <div onClick={() => nav('workouts')} style={{ fontSize: 11,
            color: 'var(--fg-muted)', cursor: 'pointer' }}>See all</div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 4 }}>
          {weekStrip.map((w, i) => (
            <div key={i} onClick={() => w.today && nav('detail')}
              style={{ padding: '8px 2px 10px', borderRadius: 10,
                background: w.today
                  ? 'color-mix(in oklch, var(--ready-high), transparent 60%)'
                  : 'var(--bg-elev)',
                border: w.today ? '1px solid var(--ready-high)' : '1px solid var(--border)',
                display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
                cursor: w.today ? 'pointer' : 'default',
                opacity: !w.today && !w.done ? 0.65 : 1 }}>
              <div className="af-label" style={{ fontSize: 8 }}>{w.d.toUpperCase()}</div>
              <div className="af-mono" style={{ fontSize: 12, fontWeight: 500 }}>{w.dt}</div>
              <div style={{ width: 22, height: 22, borderRadius: 6,
                background: w.today ? 'transparent' : 'var(--accent-bg)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: w.done && !w.today ? 'var(--fg-muted)' : 'var(--fg)' }}>
                <Icon name={w.icon} size={12}/>
              </div>
              <div className="af-mono" style={{ fontSize: 8.5,
                color: w.today ? 'var(--fg)' : 'var(--fg-muted)',
                whiteSpace: 'nowrap' }}>{w.val}</div>
            </div>
          ))}
        </div>

        {/* 4-col summary metrics */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6,
          marginTop: 18, padding: '14px 8px',
          background: 'var(--bg-subtle)', borderRadius: 12, border: '1px solid var(--border)' }}>
          {[
            ['STRESS', '412'],
            ['DIST', '38.4'],
            ['DUR', '6h12'],
            ['ELEV', '420'],
          ].map(([k, v]) => (
            <div key={k} style={{ textAlign: 'center' }}>
              <div className="af-label" style={{ fontSize: 8 }}>{k}</div>
              <div className="af-mono" style={{ fontSize: 15, fontWeight: 500,
                marginTop: 4, letterSpacing: '-0.01em' }}>{v}</div>
            </div>
          ))}
        </div>

        {/* Recovery indicator */}
        <Card onClick={() => setReadyOpen(true)} tight
          style={{ marginTop: 12, padding: '12px 14px', display: 'flex',
            alignItems: 'center', gap: 12 }}>
          <Ring value={readiness} size={42} stroke={4}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span className="af-label" style={{ fontSize: 9 }}>RECOVERY</span>
              <span style={{ fontSize: 12, fontWeight: 500 }}>·</span>
              <span style={{ fontSize: 12, fontWeight: 500 }}>{readyLabel}</span>
            </div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 3, lineHeight: 1.4 }}>
              HRV +8 vs 7d · Sleep 7h 42m · RHR 48
            </div>
          </div>
          <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
        </Card>
      </div>
      <TabBar active={tab} onChange={i => setState(s => ({ ...s, tab: i }))}/>

      {/* Readiness sheet */}
      <Sheet open={readyOpen} onClose={() => setReadyOpen(false)} title="Readiness">
        <div style={{ display: 'flex', gap: 16, alignItems: 'center', marginBottom: 18 }}>
          <Ring value={readiness} size={100} stroke={7} label="READY"/>
          <div style={{ flex: 1 }}>
            <div className="af-h2">{readyLabel}</div>
            <div className="af-muted" style={{ fontSize: 12, marginTop: 4 }}>
              Adaptive coach recommendation: proceed as planned.
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          {[
            { k: 'HRV', v: '72 ms', delta: '+8 vs 7d', src: 'Whoop 4.0', val: [58,62,65,64,70,68,72] },
            { k: 'Resting HR', v: '48 bpm', delta: '−2 vs 7d', src: 'Garmin FR965', val: [52,50,51,49,50,49,48] },
            { k: 'Sleep', v: '7h 42m', delta: '92% score', src: 'Apple Watch', val: [6,6.5,7,7.2,7,7.5,7.7] },
            { k: 'Training load', v: '412 TSS', delta: 'Optimal range', src: 'Calculated', val: [380,395,410,420,415,405,412] },
          ].map(m => (
            <div key={m.k} className="af-row" style={{ alignItems: 'flex-start' }}>
              <div style={{ flex: 1 }}>
                <div className="af-h3" style={{ fontWeight: 500 }}>{m.k}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{m.delta}</div>
                <div style={{ marginTop: 4, display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span className="af-mono" style={{ fontSize: 9,
                    color: 'var(--fg-dim)', letterSpacing: '0.04em',
                    textTransform: 'uppercase' }}>SOURCE · {m.src}</span>
                  <span style={{ fontSize: 10, color: 'var(--fg-muted)',
                    textDecoration: 'underline', cursor: 'pointer' }}>change</span>
                </div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column',
                alignItems: 'flex-end', gap: 4, paddingTop: 2 }}>
                <Spark points={m.val} w={60} h={20} color="var(--ready-high)"/>
                <div className="af-mono" style={{ fontSize: 13 }}>{m.v}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{ height: 14 }}/>
        <Btn wide onClick={() => setReadyOpen(false)}>Got it</Btn>
      </Sheet>

      {/* Log manually sheet */}
      <Sheet open={logOpen} onClose={() => setLogOpen(false)} title="Log manually">
        <div className="af-label" style={{ marginBottom: 6 }}>TYPE</div>
        <div className="af-seg" style={{ marginBottom: 14 }}>
          {['Run','Ride','Lift','Other'].map(t => (
            <div key={t} className="af-seg-item" data-on={logType === t}
              onClick={() => setLogType(t)}>{t}</div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 10, marginBottom: 14 }}>
          <div style={{ flex: 1 }}>
            <div className="af-label" style={{ marginBottom: 6 }}>DURATION</div>
            <input className="af-input" placeholder="min" value={logDur}
              onChange={e => setLogDur(e.target.value.replace(/\D/g, ''))}/>
          </div>
          <div style={{ flex: 1 }}>
            <div className="af-label" style={{ marginBottom: 6 }}>DISTANCE</div>
            <input className="af-input" placeholder="km · optional" value={logDist}
              onChange={e => setLogDist(e.target.value)}/>
          </div>
        </div>
        <div className="af-label" style={{ marginBottom: 8 }}>RPE (0–10)</div>
        <div className="af-rpe-grid" style={{ marginBottom: 18 }}>
          {Array.from({length: 10}, (_, i) => i + 1).map(n => (
            <button key={n} className="af-rpe" data-sel={logRPE === n}
              onClick={() => setLogRPE(n)}>{n}</button>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <Btn variant="ghost" wide onClick={() => setLogOpen(false)}>Cancel</Btn>
          <Btn wide onClick={submitManual} disabled={!logDur}>Log session</Btn>
        </div>
      </Sheet>
    </>
  );
}

// ------------------------------------------------------------------ Workouts list
function WorkoutsScreen({ state, nav, setState }) {
  const { tab } = state;
  const week = [
    { day: 'Mon · Apr 21', type: 'Strength', icon: 'lift', title: 'Lower body — posterior', dur: '52m', z: 'Z2', done: true },
    { day: 'Tue · Apr 22', type: 'Easy run', icon: 'run', title: 'Aerobic base, 75% MAF', dur: '48m', z: 'Z2', done: true, src: 'stryd' },
    { day: 'Wed · Apr 23', type: 'Ride',  icon: 'bike', title: 'Recovery spin', dur: '40m', z: 'Z1', done: true },
    { day: 'Thu · Apr 24', type: 'Run', icon: 'run', title: '4×8 min @ threshold', dur: '64m', z: 'Z3–4', today: true },
    { day: 'Fri · Apr 25', type: 'Strength', icon: 'lift', title: 'Upper body — pull focus', dur: '45m', z: 'Z2' },
    { day: 'Sat · Apr 26', type: 'Ride', icon: 'bike', title: 'Long endurance ride', dur: '2h 10m', z: 'Z2', src: 'runna' },
    { day: 'Sun · Apr 27', type: 'Rest', icon: 'heart', title: 'Rest / mobility', dur: '20m', z: '—', rest: true },
  ];
  // Source badge — third-party plan provider. Generic colored circle, not the actual logo.
  const sourceBadge = (src) => {
    if (!src) return null;
    const palette = {
      stryd: { bg: 'oklch(0.72 0.16 55)',  letter: 'S' },
      runna: { bg: 'oklch(0.68 0.16 150)', letter: 'R' },
    };
    const p = palette[src];
    if (!p) return null;
    return (
      <div title={src} style={{ width: 16, height: 16, borderRadius: 999,
        background: p.bg, color: '#fff', fontSize: 9, fontWeight: 700,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: 'var(--font-mono)', flexShrink: 0 }}>{p.letter}</div>
    );
  };
  return (
    <>
      <TopBar title="This week" sub="Apr 21 – Apr 27 · Block 2 of 4"
        right={<Icon name="cal" size={18}/>} onRight={() => {}}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-seg" style={{ marginBottom: 14 }}>
          <div className="af-seg-item" data-on={true}>Week</div>
          <div className="af-seg-item" data-on={false}>Block</div>
          <div className="af-seg-item" data-on={false}>Month</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {week.map((w, i) => (
            <Card key={i} onClick={w.today ? () => nav('detail') : undefined}
              style={{
                padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 12,
                borderColor: w.today ? 'var(--fg)' : 'var(--border)',
                opacity: w.done ? 0.6 : 1,
              }}>
              <div style={{ width: 38, textAlign: 'center' }}>
                <div className="af-label" style={{ fontSize: 9 }}>{w.day.split(' · ')[0].toUpperCase()}</div>
                <div className="af-mono" style={{ fontSize: 15, fontWeight: 500, marginTop: 2 }}>
                  {w.day.split(' ')[2]}
                </div>
              </div>
              <div style={{ width: 32, height: 32, borderRadius: 8,
                background: 'var(--accent-bg)', display: 'flex',
                alignItems: 'center', justifyContent: 'center', flexShrink: 0,
                color: w.rest ? 'var(--fg-muted)' : 'var(--fg)' }}>
                <Icon name={w.icon} size={16}/>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span className="af-label" style={{ fontSize: 9 }}>{w.type.toUpperCase()}</span>
                  {w.today && <Chip style={{ fontSize: 9, padding: '2px 6px' }}>TODAY</Chip>}
                  {w.done && <Icon name="check" size={12} style={{ color: 'var(--ready-high)' }}/>}
                </div>
                <div style={{ fontSize: 13, fontWeight: 500, marginTop: 2,
                  whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                  {w.title}
                </div>
                <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>
                  {w.dur} · {w.z}
                </div>
              </div>
              {sourceBadge(w.src)}
              <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
            </Card>
          ))}
        </div>
      </div>
      <TabBar active={1} onChange={i => setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

// ------------------------------------------------------------------ Detail
function DetailScreen({ state, nav }) {
  const intervals = [
    { label: 'Warm-up', dur: '12 min', z: 'Z1–Z2', pace: '6:00/km' },
    { label: '8 min @ threshold', dur: '8 min', z: 'Z3–4', pace: '4:38/km', rep: true },
    { label: 'Recovery', dur: '3 min', z: 'Z1', pace: 'easy' },
    { label: '8 min @ threshold', dur: '8 min', z: 'Z3–4', pace: '4:38/km', rep: true },
    { label: 'Recovery', dur: '3 min', z: 'Z1', pace: 'easy' },
    { label: '8 min @ threshold', dur: '8 min', z: 'Z3–4', pace: '4:38/km', rep: true },
    { label: 'Recovery', dur: '3 min', z: 'Z1', pace: 'easy' },
    { label: '8 min @ threshold', dur: '8 min', z: 'Z3–4', pace: '4:38/km', rep: true },
    { label: 'Cool-down', dur: '8 min', z: 'Z1', pace: '6:30/km' },
  ];
  return (
    <>
      <TopBar
        left={'<Back'} onLeft={() => nav('home')}
        right={<Icon name="swap" size={18}/>} onRight={() => nav('swap-from-home')}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-label">THRESHOLD RUN · THU</div>
        <div className="af-h1" style={{ marginTop: 6 }}>4×8 min @ threshold</div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 8, lineHeight: 1.5 }}>
          Sustain lactate threshold pace. Four 8-minute efforts with 3-minute jogs between. Target HR 165–172 bpm.
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
          gap: 10, margin: '18px 0', padding: '14px 0',
          borderTop: '1px solid var(--border)', borderBottom: '1px solid var(--border)' }}>
          {[
            ['TIME', '64m'], ['DIST', '10.2km'], ['TSS', '78'], ['IF', '0.87'],
          ].map(([k, v]) => (
            <div key={k}>
              <div className="af-label">{k}</div>
              <div className="af-mono" style={{ fontSize: 15, fontWeight: 500, marginTop: 3 }}>{v}</div>
            </div>
          ))}
        </div>

        <div className="af-label" style={{ marginBottom: 10 }}>INTERVALS</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {intervals.map((iv, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10,
              padding: '10px 12px',
              background: iv.rep ? 'var(--accent-bg)' : 'var(--bg-subtle)',
              border: '1px solid var(--border)', borderRadius: 8 }}>
              <div className="af-mono" style={{ fontSize: 11, color: 'var(--fg-muted)',
                width: 20 }}>{String(i + 1).padStart(2, '0')}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: iv.rep ? 500 : 400 }}>{iv.label}</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 1 }}>
                  {iv.z} · {iv.pace}
                </div>
              </div>
              <div className="af-mono" style={{ fontSize: 12 }}>{iv.dur}</div>
            </div>
          ))}
        </div>

        <div className="af-label" style={{ margin: '22px 0 10px' }}>COACH NOTE</div>
        <Card style={{ background: 'var(--bg-subtle)' }}>
          <div style={{ fontSize: 12, lineHeight: 1.55 }}>
            Your threshold climbed 2% this block. Hold 4:38/km — don't chase faster. Last rep should feel hard but sustainable.
          </div>
        </Card>
        <div style={{ height: 12 }}/>
      </div>
      <div style={{ padding: '12px 20px 16px', borderTop: '1px solid var(--border)',
        background: 'var(--bg-elev)' }}>
        <Btn wide size="lg" onClick={() => nav('player')}>
          Start workout <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

// ------------------------------------------------------------------ Player
function PlayerScreen({ state, nav, setState }) {
  const [paused, setPaused] = React.useState(false);
  const [elapsed, setElapsed] = React.useState(18 * 60 + 42); // 18:42 into workout
  const [swapOpen, setSwapOpen] = React.useState(false);
  React.useEffect(() => {
    if (paused) return;
    const t = setInterval(() => setElapsed(e => e + 1), 1000);
    return () => clearInterval(t);
  }, [paused]);
  const mm = String(Math.floor(elapsed / 60)).padStart(2, '0');
  const ss = String(elapsed % 60).padStart(2, '0');

  const pickSwap = (swap) => {
    setSwapOpen(false);
    setState(s => ({ ...s, toast: `Swapped: ${swap}` }));
  };

  return (
    <>
      <div style={{ padding: '14px 20px 10px', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between' }}>
        <div onClick={() => nav('home')} style={{ color: 'var(--fg-muted)',
          cursor: 'pointer' }}>
          <Icon name="chevD" size={20}/>
        </div>
        <span className="af-label">INTERVAL 3 OF 9 · LIVE</span>
        <div onClick={() => setSwapOpen(true)} style={{ color: 'var(--fg-muted)',
          cursor: 'pointer' }}>
          <Icon name="swap" size={18}/>
        </div>
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
        padding: '0 20px', overflow: 'hidden' }}>
        <div style={{ marginTop: 10 }}>
          <div className="af-label">CURRENT</div>
          <div className="af-h1" style={{ marginTop: 4, fontSize: 20 }}>8 min @ threshold</div>
          <div className="af-muted af-mono" style={{ fontSize: 12, marginTop: 4 }}>
            Target 4:38/km · HR 165–172 bpm
          </div>
        </div>

        {/* Big time display */}
        <div style={{ margin: '28px 0 12px', textAlign: 'center' }}>
          <div className="af-label" style={{ marginBottom: 8 }}>INTERVAL TIME</div>
          <div className="af-mono" style={{ fontSize: 72, fontWeight: 500,
            letterSpacing: '-0.04em', lineHeight: 1 }}>
            {mm}:{ss}
          </div>
          <div className="af-muted af-mono" style={{ fontSize: 12, marginTop: 10 }}>
            3:18 / 8:00
          </div>
          <div className="af-prog" style={{ marginTop: 10, width: 200,
            marginLeft: 'auto', marginRight: 'auto' }}>
            <div className="af-prog-fill" style={{
              width: `${(((elapsed % 480)) / 480) * 100}%`,
              background: 'var(--ready-high)' }}/>
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
          gap: 8, padding: '12px 0', borderTop: '1px solid var(--border)',
          borderBottom: '1px solid var(--border)' }}>
          {[
            ['PACE', '4:36', '/km'],
            ['HR', '168', 'bpm'],
            ['ZONE', 'Z3', ''],
          ].map(([k, v, u]) => (
            <div key={k} style={{ textAlign: 'center' }}>
              <div className="af-label">{k}</div>
              <div className="af-mono" style={{ fontSize: 20, fontWeight: 500, marginTop: 3 }}>{v}</div>
              {u && <div className="af-muted af-mono" style={{ fontSize: 10 }}>{u}</div>}
            </div>
          ))}
        </div>

        {/* Next up */}
        <div style={{ marginTop: 14 }}>
          <div className="af-label" style={{ marginBottom: 6 }}>UP NEXT</div>
          <div style={{ display: 'flex', justifyContent: 'space-between',
            alignItems: 'center', padding: '10px 12px', background: 'var(--bg-subtle)',
            borderRadius: 8 }}>
            <div>
              <div style={{ fontSize: 13 }}>Recovery jog</div>
              <div className="af-muted af-mono" style={{ fontSize: 11 }}>Z1 · 3 min</div>
            </div>
            <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        </div>
      </div>

      <div style={{ padding: '14px 20px 20px', display: 'flex', gap: 10,
        borderTop: '1px solid var(--border)', background: 'var(--bg-elev)' }}>
        <Btn variant="ghost" size="lg" style={{ flex: 1 }}
          onClick={() => setPaused(p => !p)}>
          <Icon name={paused ? 'play' : 'pause'} size={14}/>
          {paused ? 'Resume' : 'Pause'}
        </Btn>
        <Btn size="lg" style={{ flex: 1 }} onClick={() => nav('completion')}>
          <Icon name="stop" size={12}/> Finish
        </Btn>
      </div>

      <Sheet open={swapOpen} onClose={() => setSwapOpen(false)} title="Swap workout">
        <div className="af-muted" style={{ fontSize: 12, marginBottom: 14 }}>
          Coach suggestions based on your readiness ({state.readiness}) and weekly load.
        </div>
        {[
          { t: 'Easy aerobic run', d: '40 min · Z2 · MAF', note: 'Save freshness for Saturday' },
          { t: 'Tempo — 3×10 min', d: '55 min · Z3', note: 'Close match to today' },
          { t: 'Bike recovery spin', d: '45 min · Z1', note: 'If legs feel heavy' },
          { t: 'Rest day', d: '—', note: 'Move to Fri' },
        ].map((o, i) => (
          <div key={i} onClick={() => pickSwap(o.t)}
            style={{ padding: '12px 0', display: 'flex', alignItems: 'center',
              gap: 12, borderTop: i === 0 ? 'none' : '1px solid var(--border)',
              cursor: 'pointer' }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 500 }}>{o.t}</div>
              <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>{o.d}</div>
              <div className="af-muted" style={{ fontSize: 11, marginTop: 3 }}>{o.note}</div>
            </div>
            <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}
      </Sheet>
    </>
  );
}

// ------------------------------------------------------------------ Completion
function CompletionScreen({ state, nav, setState }) {
  const [rpe, setRpe] = React.useState(null);
  const [inj, setInj] = React.useState(false);
  const [notes, setNotes] = React.useState('');

  const submit = () => {
    setState(s => ({
      ...s,
      history: [{
        date: 'Today', type: 'Run', title: '4×8 min @ threshold',
        dur: '64 min', rpe: rpe || 7,
      }, ...s.history],
      toast: 'Workout saved',
    }));
    nav('home');
  };

  return (
    <>
      <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('home')}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ textAlign: 'center', padding: '8px 0 20px' }}>
          <div style={{ width: 48, height: 48, borderRadius: 999,
            background: 'color-mix(in oklch, var(--ready-high), transparent 82%)',
            color: 'var(--ready-high)', display: 'inline-flex',
            alignItems: 'center', justifyContent: 'center', marginBottom: 12 }}>
            <Icon name="check" size={22}/>
          </div>
          <div className="af-h1">Workout complete</div>
          <div className="af-muted" style={{ fontSize: 13, marginTop: 4 }}>
            4×8 min @ threshold · 64 min
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
          gap: 10, padding: '14px 0', borderTop: '1px solid var(--border)',
          borderBottom: '1px solid var(--border)', marginBottom: 24 }}>
          {[['TIME','63:12'], ['DIST','10.1km'], ['AVG HR','164'], ['TSS','81']].map(([k,v]) => (
            <div key={k}>
              <div className="af-label">{k}</div>
              <div className="af-mono" style={{ fontSize: 14, fontWeight: 500, marginTop: 3 }}>{v}</div>
            </div>
          ))}
        </div>

        <div className="af-label" style={{ marginBottom: 8 }}>HOW HARD DID IT FEEL? (0–10)</div>
        <div className="af-rpe-grid" style={{ marginBottom: 8 }}>
          {Array.from({length: 10}, (_, i) => i + 1).map(n => (
            <button key={n} className="af-rpe" data-sel={rpe === n}
              onClick={() => setRpe(n)}>{n}</button>
          ))}
        </div>
        <div className="af-muted af-mono" style={{ fontSize: 10, marginBottom: 22,
          display: 'flex', justifyContent: 'space-between' }}>
          <span>EASY</span><span>MODERATE</span><span>ALL-OUT</span>
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between',
          alignItems: 'center', padding: '12px 0', borderTop: '1px solid var(--border)',
          borderBottom: '1px solid var(--border)', marginBottom: 14 }}>
          <div>
            <div className="af-h3" style={{ fontWeight: 500 }}>Any pain or injury?</div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>
              Coach will adapt next sessions
            </div>
          </div>
          <div className="af-switch" data-on={inj} onClick={() => setInj(!inj)}/>
        </div>

        {inj && (
          <div style={{ marginBottom: 14 }}>
            <div className="af-label" style={{ marginBottom: 6 }}>DESCRIBE (OPTIONAL)</div>
            <textarea className="af-input" rows={3}
              placeholder="e.g. mild right Achilles, 3/10 after rep 3"
              value={notes} onChange={e => setNotes(e.target.value)}
              style={{ resize: 'none', fontFamily: 'var(--font-sans)' }}/>
          </div>
        )}

        <Btn wide size="lg" onClick={submit} disabled={!rpe}>
          Save session
        </Btn>
        <div style={{ height: 4 }}/>
        <Btn wide size="md" variant="ghost" onClick={() => nav('home')}>Skip</Btn>
      </div>
    </>
  );
}

Object.assign(window, {
  HomeScreen, WorkoutsScreen, DetailScreen, PlayerScreen, CompletionScreen,
});
