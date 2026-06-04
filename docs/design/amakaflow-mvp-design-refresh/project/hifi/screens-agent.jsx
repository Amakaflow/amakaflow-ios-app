/**
 * AmakaFlow agent-visibility screens — Mental Model, Plan Reveal,
 * Weekly Review, Watch Delivery States, Agent Event Inbox.
 * Plus 3 Home banner variants (Replan / Red-flag / Low-confidence).
 */

// ------------------------------------------------------------- Mental Model
function MentalModelScreen({ nav }) {
  return (
    <>
      <div style={{ padding: '14px 20px 0', display: 'flex',
        justifyContent: 'space-between', alignItems: 'center' }}>
        <span className="af-label">STEP 6 OF 6</span>
        <span className="af-label">SETUP</span>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '32px 28px 20px', display: 'flex', flexDirection: 'column' }}>
        <div className="af-eyebrow" style={{ color: 'var(--fg-muted)' }}>HOW AMAKAFLOW WORKS</div>
        <div className="af-h1" style={{ marginTop: 12, fontSize: 26,
          letterSpacing: '-0.015em', lineHeight: 1.2 }}>
          Three places.<br/>One coach.
        </div>
        <div className="af-muted" style={{ fontSize: 14, marginTop: 14, lineHeight: 1.55 }}>
          Your coach lives in Telegram. Your workouts live on your watch. The app is for setup and review.
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 0,
          marginTop: 28, borderTop: '1px solid var(--border)' }}>
          {[
            { e: '💬', t: 'Morning briefing via Telegram',
              s: 'Each day at 6am, your coach DMs you the plan and reasoning.' },
            { e: '⌚', t: 'Workout pushed to your watch',
              s: 'Intervals, targets, and HR zones load automatically.' },
            { e: '📊', t: 'App shows your history',
              s: 'Open the app to review trends, swap days, or check load.' },
          ].map((r, i) => (
            <div key={i} style={{ padding: '20px 0', display: 'flex', gap: 16,
              alignItems: 'flex-start',
              borderBottom: '1px solid var(--border)' }}>
              <div style={{ fontSize: 26, lineHeight: 1, width: 36, textAlign: 'center' }}>
                {r.e}
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500 }}>{r.t}</div>
                <div className="af-muted" style={{ fontSize: 12, marginTop: 4,
                  lineHeight: 1.5 }}>{r.s}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px' }}>
        <Btn wide size="lg" onClick={() => nav('pairing')}>
          Got it — set up my watch <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

// ------------------------------------------------------------- Plan Reveal
function PlanRevealScreen({ nav, state }) {
  const [phase, setPhase] = React.useState(state?.planRevealPhase || 'loading');
  React.useEffect(() => {
    if (phase === 'loading') {
      const t = setTimeout(() => setPhase('ready'), 2200);
      return () => clearTimeout(t);
    }
  }, [phase]);

  if (phase === 'loading') {
    return (
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', padding: '0 32px' }}>
        <div style={{ width: 56, height: 56, borderRadius: 999,
          border: '2.5px solid var(--border)',
          borderTopColor: 'var(--fg)',
          animation: 'af-spin 0.9s linear infinite', marginBottom: 28 }}/>
        <style>{`@keyframes af-spin { to { transform: rotate(360deg); } }`}</style>
        <div className="af-h2" style={{ textAlign: 'center' }}>Building your plan…</div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 10,
          textAlign: 'center', lineHeight: 1.55 }}>
          Analysing your goals, HRV, and calendar.
        </div>
        <div style={{ marginTop: 28, display: 'flex', flexDirection: 'column',
          gap: 8, fontSize: 11, color: 'var(--fg-muted)',
          fontFamily: 'var(--font-mono)' }}>
          {[
            ['✓', 'Goal: Hyrox · 12 weeks out'],
            ['✓', 'Baseline HRV · 14d window'],
            ['…', 'Periodising 4-week blocks'],
          ].map(([m, t], i) => (
            <div key={i} style={{ display: 'flex', gap: 8 }}>
              <span style={{ width: 10, color: m === '✓' ? 'var(--ready-high)' : 'var(--fg-muted)' }}>{m}</span>
              <span>{t}</span>
            </div>
          ))}
        </div>
      </div>
    );
  }

  const blocks = [
    { name: 'Base',  load: 'Easy',     sessions: 5, when: 'Wk 1–2',
      note: 'Aerobic capacity + technique. 80% Z2.' },
    { name: 'Build', load: 'Moderate', sessions: 6, when: 'Wk 3–6',
      note: 'Add threshold + race-specific strength.' },
    { name: 'Peak',  load: 'Heavy',    sessions: 6, when: 'Wk 7–10',
      note: 'Race-pace efforts, brick sessions.' },
    { name: 'Taper', load: 'Easy',     sessions: 4, when: 'Wk 11–12',
      note: 'Volume drops 50%. Sharpen, recover.' },
  ];
  const loadColor = l => l === 'Easy' ? 'var(--ready-high)'
    : l === 'Moderate' ? 'var(--ready-mod)' : 'var(--ready-low)';

  return (
    <>
      <TopBar
        left={<Icon name="chevL" size={18}/>} onLeft={() => nav('mental-model')}
        right={<span className="af-label">12-WEEK PLAN</span>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 16px' }}>
        <div className="af-eyebrow">YOUR PLAN</div>
        <div className="af-h1" style={{ marginTop: 8, fontSize: 24 }}>
          Hyrox · 12 weeks
        </div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 8, lineHeight: 1.55 }}>
          Four blocks, periodised around your work calendar and recovery patterns.
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10,
          marginTop: 22 }}>
          {blocks.map((b, i) => (
            <Card key={i} style={{ padding: 16 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between',
                alignItems: 'flex-start', marginBottom: 10 }}>
                <div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span className="af-mono" style={{ fontSize: 11,
                      color: 'var(--fg-muted)' }}>{String(i + 1).padStart(2, '0')}</span>
                    <span className="af-h3">{b.name}</span>
                  </div>
                  <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 4 }}>
                    {b.when} · {b.sessions} sessions/wk
                  </div>
                </div>
                <Chip style={{ background: 'transparent',
                  border: `1px solid ${loadColor(b.load)}`,
                  color: loadColor(b.load), fontSize: 10 }}>
                  {b.load.toUpperCase()}
                </Chip>
              </div>
              <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.5 }}>
                {b.note}
              </div>
            </Card>
          ))}
        </div>

        <div style={{ marginTop: 18, padding: 14, background: 'var(--bg-subtle)',
          borderRadius: 10, fontSize: 12, lineHeight: 1.55,
          color: 'var(--fg-muted)' }}>
          <span style={{ color: 'var(--fg)', fontWeight: 500 }}>Note: </span>
          Plan adapts every morning. Sessions may shift if HRV drops or you miss a day — your coach reshapes around real life.
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('home')}>
          Looks good — start training <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

// ------------------------------------------------------------- Weekly Review
function WeeklyReviewScreen({ nav }) {
  const days = [
    { d: 'Mon', dt: 'Apr 21', title: 'Lower body posterior',  type: 'Lift', dur: '52m', rpe: 7, done: true },
    { d: 'Tue', dt: 'Apr 22', title: 'Aerobic base run',      type: 'Run',  dur: '48m', rpe: 4, done: true },
    { d: 'Wed', dt: 'Apr 23', title: 'Recovery spin',         type: 'Ride', dur: '40m', rpe: 3, done: true },
    { d: 'Thu', dt: 'Apr 24', title: '4×8 min @ threshold',   type: 'Run',  dur: '64m', rpe: 8, done: true },
    { d: 'Fri', dt: 'Apr 25', title: 'Upper body — pull',     type: 'Lift', dur: '—',   rpe: null, done: false, missed: true },
    { d: 'Sat', dt: 'Apr 26', title: 'Long endurance ride',   type: 'Ride', dur: '2h 14m', rpe: 5, done: true },
    { d: 'Sun', dt: 'Apr 27', title: 'Rest / mobility',       type: 'Rest', dur: '20m', rpe: 2, done: true },
  ];
  return (
    <>
      <TopBar
        left={<Icon name="chevL" size={18}/>} onLeft={() => nav('home')}
        right={<Icon name="close" size={18}/>} onRight={() => nav('home')}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 16px' }}>
        <div className="af-eyebrow">WEEK · APR 21 – 27</div>
        <div className="af-h1" style={{ marginTop: 6 }}>Sunday review</div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10,
          margin: '20px 0', padding: '16px 14px',
          background: 'var(--bg-subtle)', borderRadius: 12 }}>
          {[
            ['SESSIONS', '5/6'],
            ['LOAD',     '342', 'TSS'],
            ['AVG RPE',  '3.4'],
          ].map(([k, v, u]) => (
            <div key={k} style={{ textAlign: 'center' }}>
              <div className="af-label" style={{ fontSize: 9 }}>{k}</div>
              <div className="af-mono" style={{ fontSize: 22, fontWeight: 500,
                marginTop: 4, letterSpacing: '-0.015em' }}>{v}</div>
              {u && <div className="af-muted af-mono" style={{ fontSize: 10 }}>{u}</div>}
            </div>
          ))}
        </div>

        <div className="af-label" style={{ marginBottom: 8 }}>SESSIONS</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0,
          borderTop: '1px solid var(--border)' }}>
          {days.map((s, i) => (
            <div key={i} style={{ padding: '12px 0', display: 'flex',
              alignItems: 'center', gap: 12,
              borderBottom: '1px solid var(--border)',
              opacity: s.missed ? 0.6 : 1 }}>
              <div style={{ width: 36, textAlign: 'left' }}>
                <div className="af-label" style={{ fontSize: 9 }}>{s.d.toUpperCase()}</div>
                <div className="af-mono" style={{ fontSize: 11, color: 'var(--fg-muted)',
                  marginTop: 2 }}>{s.dt.split(' ')[1]}</div>
              </div>
              <div style={{ width: 18, height: 18, borderRadius: 999,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: s.done ? 'var(--ready-high)'
                  : s.missed ? 'transparent' : 'var(--border)',
                border: s.missed ? '1px dashed var(--border-str)' : 'none',
                color: 'var(--bg)', flexShrink: 0 }}>
                {s.done && <Icon name="check" size={10}/>}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 500, whiteSpace: 'nowrap',
                  overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.title}</div>
                <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>
                  {s.type} · {s.dur}
                </div>
              </div>
              {s.rpe ? (
                <Chip style={{ fontSize: 10 }}>RPE {s.rpe}</Chip>
              ) : (
                <Chip outline style={{ fontSize: 10, color: 'var(--destructive)',
                  borderColor: 'var(--destructive)' }}>MISSED</Chip>
              )}
            </div>
          ))}
        </div>

        {/* Coach note */}
        <div style={{ marginTop: 22, padding: 16, borderRadius: 12,
          background: 'var(--bg-subtle)', border: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <span style={{ fontSize: 14 }}>💬</span>
            <span className="af-label">COACH NOTE</span>
          </div>
          <div style={{ fontSize: 13, lineHeight: 1.6 }}>
            Strong week — you held threshold pace through rep 4, which is new. Friday's lift slipping is fine; I'm rolling pull volume into next Monday. Saturday's long ride pushed weekly load to 342 TSS, right at the top of optimal. Take it easy Sunday evening.
          </div>
        </div>

        {/* Next week preview */}
        <div className="af-label" style={{ marginTop: 22, marginBottom: 8 }}>NEXT WEEK</div>
        <Card tight style={{ padding: 14 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between',
            alignItems: 'center', marginBottom: 10 }}>
            <div style={{ fontSize: 13, fontWeight: 500 }}>Build · week 4 of 12</div>
            <Chip style={{ fontSize: 10, background: 'transparent',
              border: '1px solid var(--ready-mod)', color: 'var(--ready-mod)' }}>MODERATE</Chip>
          </div>
          <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.5,
            marginBottom: 10 }}>
            6 sessions · target 380 TSS. Threshold reps move to 5×6 min. One brick session Saturday.
          </div>
          <div style={{ display: 'flex', gap: 4 }}>
            {['L','R','R','I','L','B','—'].map((c, i) => (
              <div key={i} style={{ flex: 1, aspectRatio: '1',
                borderRadius: 6, background: c === '—' ? 'transparent' : 'var(--accent-bg)',
                border: c === '—' ? '1px dashed var(--border-str)' : 'none',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 10, fontFamily: 'var(--font-mono)',
                color: 'var(--fg-muted)' }}>
                {c}
              </div>
            ))}
          </div>
        </Card>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('workouts')}>
          See this week's plan <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

// ------------------------------------------------------------- Watch Delivery States
function WatchDeliveryScreen({ nav }) {
  const states = [
    { e: '⚙️', name: 'Building',
      sub: 'Compiling intervals for your watch',
      tone: 'grey', time: 'NOW' },
    { e: '📡', name: 'Sent to watch',
      sub: 'Pushed via Connect IQ — awaiting handshake',
      tone: 'purple', time: '0:04 AGO' },
    { e: '⌚', name: 'Loaded on watch',
      sub: 'Available in AmakaFlow app · open to start',
      tone: 'amber', time: '0:18 AGO',
      action: 'Resend to watch' },
    { e: '✅', name: 'Ready on watch',
      sub: 'Confirmed — start when you are',
      tone: 'green', time: '1:02 AGO' },
    { e: '⚠️', name: 'Delivery failed',
      sub: 'Bluetooth lost contact during sync',
      tone: 'red', time: '4:11 AGO',
      action: 'Resend to watch' },
  ];
  const toneColor = (t) => ({
    grey:   { bg: 'var(--bg-subtle)',    bd: 'var(--border)',     fg: 'var(--fg-muted)' },
    purple: { bg: 'color-mix(in oklch, oklch(0.62 0.18 290), transparent 88%)',
              bd: 'oklch(0.62 0.18 290)', fg: 'oklch(0.62 0.18 290)' },
    amber:  { bg: 'color-mix(in oklch, var(--ready-mod), transparent 88%)',
              bd: 'var(--ready-mod)', fg: 'var(--ready-mod)' },
    green:  { bg: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
              bd: 'var(--ready-high)', fg: 'var(--ready-high)' },
    red:    { bg: 'color-mix(in oklch, var(--destructive), transparent 88%)',
              bd: 'var(--destructive)', fg: 'var(--destructive)' },
  }[t]);

  return (
    <>
      <TopBar
        left={<Icon name="chevL" size={18}/>} onLeft={() => nav('home')}
        title="Watch delivery"
        sub="Today's threshold workout · 4×8 min"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-label" style={{ marginBottom: 10 }}>DELIVERY TIMELINE</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {states.map((s, i) => {
            const c = toneColor(s.tone);
            return (
              <div key={i} style={{ padding: '14px 14px',
                background: c.bg, border: `1px solid ${c.bd}`, borderRadius: 12,
                display: 'flex', gap: 12, alignItems: 'flex-start' }}>
                <div style={{ fontSize: 22, lineHeight: 1, width: 28, textAlign: 'center',
                  marginTop: 1 }}>{s.e}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center',
                    justifyContent: 'space-between', gap: 8 }}>
                    <span style={{ fontSize: 14, fontWeight: 500, color: c.fg }}>
                      {s.name}
                    </span>
                    <span className="af-mono" style={{ fontSize: 9,
                      color: 'var(--fg-muted)', flexShrink: 0, whiteSpace: 'nowrap' }}>{s.time}</span>
                  </div>
                  <div style={{ fontSize: 12, marginTop: 4, color: 'var(--fg-muted)',
                    lineHeight: 1.5 }}>{s.sub}</div>
                  {s.action && (
                    <div style={{ marginTop: 10 }}>
                      <Btn variant="ghost" size="sm">
                        <Icon name="swap" size={12}/> {s.action}
                      </Btn>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        <div style={{ marginTop: 18, padding: 12, borderRadius: 10,
          background: 'var(--bg-subtle)', display: 'flex', gap: 10,
          alignItems: 'flex-start' }}>
          <Icon name="info" size={14} style={{ color: 'var(--fg-muted)',
            flexShrink: 0, marginTop: 2 }}/>
          <div className="af-muted" style={{ fontSize: 11, lineHeight: 1.55 }}>
            Delivery confirms when your watch boots the AmakaFlow Connect IQ app. Bluetooth must be enabled within 2m of pairing.
          </div>
        </div>
      </div>
    </>
  );
}

// ------------------------------------------------------------- Agent Event Inbox
function AgentInboxScreen({ nav, state, setState }) {
  const events = [
    { e: '☀️', kind: 'Briefing', time: 'Today · 6:01 am',
      copy: 'Threshold day. HRV +8, sleep 7h 42m. Hold 4:38/km — last rep should feel hard but sustainable.' },
    { e: '✅', kind: 'Check-in',  time: 'Yesterday · 5:42 pm',
      copy: 'Logged: Recovery spin · 40m · RPE 3. Nice and easy. Good prep for tomorrow.' },
    { e: '🔄', kind: 'Replan',   time: 'Yesterday · 6:00 am',
      copy: 'Sleep dropped to 6h 12m last night. Moved hill repeats to Saturday and pulled today back to Z2.' },
    { e: '📊', kind: 'Weekly review', time: 'Sun · 9:00 am',
      copy: 'Week 3 of 12 done. 5/6 sessions, 342 TSS. Threshold pace dropped 3 sec/km — strong sign.' },
    { e: '🔴', kind: 'Red flag',  time: 'Apr 19 · 6:02 am',
      copy: 'HRV dropped 18% — replaced today\'s tempo with a 30 min recovery walk. Push tomorrow if it rebounds.' },
    { e: '☀️', kind: 'Briefing', time: 'Apr 19 · 6:00 am',
      copy: 'Easy day on the docket. 48 min Z2 run. Keep heart rate under 145.' },
    { e: '✅', kind: 'Check-in',  time: 'Apr 18 · 4:18 pm',
      copy: 'Lift complete. RPE 6, no pain noted. Block 1 strength target hit.' },
  ];
  return (
    <>
      <TopBar title="Agent activity" sub={`${events.length} events · last 14 days`}
        right={<Icon name="info" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-seg" style={{ marginBottom: 14 }}>
          <div className="af-seg-item" data-on={true}>All</div>
          <div className="af-seg-item" data-on={false}>Briefings</div>
          <div className="af-seg-item" data-on={false}>Replans</div>
          <div className="af-seg-item" data-on={false}>Flags</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0,
          borderTop: '1px solid var(--border)' }}>
          {events.map((ev, i) => (
            <div key={i} style={{ padding: '14px 0', display: 'flex', gap: 12,
              alignItems: 'flex-start',
              borderBottom: '1px solid var(--border)' }}>
              <div style={{ fontSize: 16, lineHeight: 1.2, width: 22,
                textAlign: 'center', flexShrink: 0, marginTop: 1 }}>{ev.e}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: 'flex', alignItems: 'center',
                  justifyContent: 'space-between', gap: 6, marginBottom: 4 }}>
                  <span style={{ fontSize: 12, fontWeight: 500 }}>{ev.kind}</span>
                  <span className="af-mono" style={{ fontSize: 10,
                    color: 'var(--fg-muted)', flexShrink: 0, whiteSpace: 'nowrap' }}>{ev.time}</span>
                </div>
                <div style={{ fontSize: 12, lineHeight: 1.55,
                  color: 'var(--fg-muted)' }}>{ev.copy}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

// ------------------------------------------------------------- Home variants with banners
function makeHomeVariant(banner) {
  return function HomeVariant({ state, nav, setState }) {
    return (
      <>
        <HomeWithBanner banner={banner}
          state={state} nav={nav} setState={setState}/>
      </>
    );
  };
}

function HomeWithBanner({ banner, state, nav, setState }) {
  // Render a stripped Home with the banner injected at top of scroll.
  const tones = {
    replan:  { bd: 'var(--ready-mod)',  e: '🔄', label: 'REPLAN PROPOSED' },
    redflag: { bd: 'var(--destructive)', e: '🔴', label: 'RED FLAG' },
    lowconf: { bd: 'oklch(0.62 0.18 260)', e: 'ℹ️', label: 'LOW CONFIDENCE' },
  };
  const t = tones[banner];
  const copy = {
    replan:  "You missed Thursday — I've shifted intervals to Sunday and dropped Friday's lift. Approve?",
    redflag: "HRV dropped 18% — today's session replaced with a recovery walk.",
    lowconf: "No HRV data from last 3 days. Plan is based on your 14-day baseline.",
  }[banner];

  return (
    <>
      <TopBar
        left={<span className="af-eyebrow">THU · APR 24</span>}
        right={<Icon name="bolt" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px' }}>
        {/* Banner */}
        <div style={{ padding: '14px 14px', borderRadius: 12,
          borderLeft: `3px solid ${t.bd}`,
          background: 'var(--bg-subtle)',
          border: '1px solid var(--border)',
          borderLeftWidth: 3, borderLeftStyle: 'solid', borderLeftColor: t.bd,
          marginBottom: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <span style={{ fontSize: 13 }}>{t.e}</span>
            <span className="af-label" style={{ color: t.bd, fontSize: 9 }}>{t.label}</span>
            <span className="af-mono" style={{ fontSize: 9, color: 'var(--fg-muted)',
              marginLeft: 'auto' }}>5:58 AM</span>
          </div>
          <div style={{ fontSize: 13, lineHeight: 1.5, marginBottom: banner === 'replan' ? 12 : 8 }}>
            {copy}
          </div>
          {banner === 'replan' && (
            <div style={{ display: 'flex', gap: 8 }}>
              <Btn size="sm" wide>Approve</Btn>
              <Btn size="sm" variant="ghost" wide>Edit</Btn>
            </div>
          )}
          {banner === 'redflag' && (
            <div onClick={() => nav && nav('detail')} style={{ fontSize: 12,
              color: t.bd, fontWeight: 500, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', gap: 4 }}>
              Safe to continue <Icon name="chevR" size={12}/>
            </div>
          )}
        </div>

        {/* Compact today card (banner-context) */}
        <Card style={{ padding: 0, overflow: 'hidden', marginBottom: 14 }}>
          <div style={{ padding: '14px 16px' }}>
            <div className="af-label" style={{ fontSize: 9 }}>
              {banner === 'redflag' ? 'TODAY · REPLACEMENT'
                : banner === 'replan' ? 'TODAY · ORIGINAL'
                : 'TODAY · BASELINE PLAN'}
            </div>
            <div className="af-h2" style={{ marginTop: 4 }}>
              {banner === 'redflag' ? '30 min recovery walk'
                : '4×8 min @ threshold'}
            </div>
            <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 4 }}>
              {banner === 'redflag' ? '30m · Z1 · easy'
                : '64m · Z3–4 · TSS 78'}
            </div>
          </div>
          <div style={{ padding: '10px 16px', borderTop: '1px solid var(--border)',
            background: 'var(--bg-subtle)' }}>
            <Btn wide size="md">
              Start workout <Icon name="chevR" size={14}/>
            </Btn>
          </div>
        </Card>

        {/* Mini readiness summary */}
        <Card tight style={{ padding: 14, display: 'flex', alignItems: 'center',
          gap: 12, marginBottom: 16 }}>
          <Ring value={banner === 'redflag' ? 38 : banner === 'lowconf' ? 64 : 72}
            size={56} stroke={5}/>
          <div style={{ flex: 1 }}>
            <div className="af-label" style={{ fontSize: 9 }}>READINESS</div>
            <div className="af-h3" style={{ marginTop: 2 }}>
              {banner === 'redflag' ? 'Recover' : banner === 'lowconf' ? 'Estimated' : 'Moderate'}
            </div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>
              {banner === 'redflag' ? 'HRV 42 ms · −18% vs 7d'
                : banner === 'lowconf' ? 'No watch data 3d · using baseline'
                : 'HRV +1 vs 7d · sleep 7h 02m'}
            </div>
          </div>
        </Card>
      </div>
      <TabBar active={0} onChange={i => setState && setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

const HomeReplan  = makeHomeVariant('replan');
const HomeRedFlag = makeHomeVariant('redflag');
const HomeLowConf = makeHomeVariant('lowconf');

// ------------------------------------------------------------- Telegram Setup
// Onboarding step shown after Garmin pairing. 3 states: idle → polling → done.
// In the prototype, "Open Telegram →" advances to polling, then auto-advances
// to done after ~2.4s. The static canvas frames render via the `forceState`
// prop so we can show all three side by side.
const TG_BLUE = '#29B6F6';

function TelegramSetupScreen({ nav, forceState }) {
  // Forced state for canvas frames; live state for prototype use.
  const [internal, setInternal] = React.useState('idle');
  const phase = forceState || internal;

  // Auto-advance polling → done in prototype mode only.
  React.useEffect(() => {
    if (forceState) return;
    if (phase === 'polling') {
      const t = setTimeout(() => setInternal('done'), 2400);
      return () => clearTimeout(t);
    }
  }, [phase, forceState]);

  const PaperPlane = ({ size = 56, color = TG_BLUE }) => (
    <svg width={size} height={size} viewBox="0 0 48 48"
      style={{ display: 'block' }}>
      <circle cx="24" cy="24" r="24" fill={color}/>
      <path d="M11 23.4 L37 13.2 c1.4-.5 2.6.6 2.2 2 L34.8 35.2 c-.3 1.2-1.6 1.5-2.5.8 L25.6 30.7 l-3.4 3.3 c-.4.4-.8.6-1.3.4 l.4-6.5 12-10.8 c.5-.5-.1-.7-.8-.3 L18 23.5 l-6.7-2.1 c-1.4-.4-1.4-1.4.7-2z"
        fill="#fff"/>
    </svg>
  );

  const Body = () => {
    if (phase === 'idle') {
      return (
        <>
          <PaperPlane/>
          <div className="af-h1" style={{ fontSize: 26, marginTop: 26,
            letterSpacing: '-0.015em', textAlign: 'center' }}>
            Connect Telegram
          </div>
          <div className="af-muted" style={{ fontSize: 14, marginTop: 14,
            textAlign: 'center', lineHeight: 1.6, maxWidth: 280 }}>
            Your morning briefings, evening check-ins, and workout swaps all happen in Telegram. Two taps to connect.
          </div>
          <div style={{ display: 'flex', flexDirection: 'column',
            gap: 4, marginTop: 36, width: '100%', alignItems: 'center' }}>
            <button onClick={() => setInternal('polling')}
              className="af-btn af-btn-lg af-btn-wide"
              style={{ background: TG_BLUE, color: '#000',
                border: '1px solid transparent', maxWidth: 280, fontWeight: 500,
                cursor: 'pointer', display: 'inline-flex', alignItems: 'center',
                justifyContent: 'center', gap: 8 }}>
              Open Telegram <Icon name="chevR" size={14}/>
            </button>
            <button onClick={() => nav && nav('home')}
              style={{ all: 'unset', cursor: 'pointer', marginTop: 14,
                fontSize: 13, color: 'var(--fg-muted)', padding: '6px 12px' }}>
              Skip for now
            </button>
          </div>
        </>
      );
    }
    if (phase === 'polling') {
      return (
        <>
          <PaperPlane/>
          <div className="af-h1" style={{ fontSize: 26, marginTop: 26,
            letterSpacing: '-0.015em', textAlign: 'center' }}>
            Connect Telegram
          </div>
          <div className="af-muted" style={{ fontSize: 14, marginTop: 14,
            textAlign: 'center', lineHeight: 1.6, maxWidth: 280 }}>
            Your morning briefings, evening check-ins, and workout swaps all happen in Telegram. Two taps to connect.
          </div>
          <div style={{ marginTop: 36, display: 'flex', alignItems: 'center',
            gap: 12, padding: '14px 18px', borderRadius: 999,
            background: 'var(--bg-subtle)', border: '1px solid var(--border)' }}>
            <div style={{ width: 16, height: 16, borderRadius: 999,
              border: '2px solid var(--border)', borderTopColor: TG_BLUE,
              animation: 'af-spin 0.85s linear infinite' }}/>
            <style>{`@keyframes af-spin { to { transform: rotate(360deg); } }`}</style>
            <span className="af-muted" style={{ fontSize: 13 }}>
              Waiting for Telegram confirmation…
            </span>
          </div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 14,
            textAlign: 'center', maxWidth: 240, lineHeight: 1.5 }}>
            Tap <span style={{ color: 'var(--fg)', fontWeight: 500 }}>START</span> in the AmakaFlow Telegram chat to confirm.
          </div>
        </>
      );
    }
    // done
    return (
      <>
        <div style={{ width: 64, height: 64, borderRadius: 999,
          background: 'color-mix(in oklch, var(--ready-high), transparent 82%)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ width: 44, height: 44, borderRadius: 999,
            background: 'var(--ready-high)', display: 'flex',
            alignItems: 'center', justifyContent: 'center', color: '#000' }}>
            <Icon name="check" size={22}/>
          </div>
        </div>
        <div className="af-h1" style={{ fontSize: 24, marginTop: 22,
          color: 'var(--ready-high)', fontWeight: 600,
          textAlign: 'center', letterSpacing: '-0.015em' }}>
          Telegram connected
        </div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 12,
          textAlign: 'center', lineHeight: 1.6, maxWidth: 260 }}>
          You'll get your first briefing tomorrow at 6am. Reply any time to swap, log, or ask a question.
        </div>
        <div style={{ marginTop: 36, width: '100%', display: 'flex',
          justifyContent: 'center' }}>
          <button onClick={() => nav && nav('home')}
            className="af-btn af-btn-lg af-btn-primary af-btn-wide"
            style={{ maxWidth: 280, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center',
              justifyContent: 'center', gap: 8 }}>
            Continue <Icon name="chevR" size={14}/>
          </button>
        </div>
      </>
    );
  };

  return (
    <>
      <TopBar
        left={phase === 'polling' ? null : <Icon name="chevL" size={18}/>}
        onLeft={phase === 'polling' ? null : () => nav && nav('pairing')}
        right={phase === 'idle'
          ? <span className="af-label">STEP 5 OF 6</span>
          : null}/>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        padding: '0 28px 40px' }}>
        <Body/>
      </div>
    </>
  );
}

const TelegramIdle    = (p) => <TelegramSetupScreen {...p} forceState="idle"/>;
const TelegramPolling = (p) => <TelegramSetupScreen {...p} forceState="polling"/>;
const TelegramDone    = (p) => <TelegramSetupScreen {...p} forceState="done"/>;

Object.assign(window, {
  MentalModelScreen, PlanRevealScreen, WeeklyReviewScreen,
  WatchDeliveryScreen, AgentInboxScreen,
  HomeReplan, HomeRedFlag, HomeLowConf,
  TelegramSetupScreen, TelegramIdle, TelegramPolling, TelegramDone,
});
