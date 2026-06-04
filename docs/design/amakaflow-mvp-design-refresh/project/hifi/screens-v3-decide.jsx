/**
 * Part B — 12 representative "decide-later" screens.
 * One representative screen each. Marked [DECIDE: keep/cut for v1] in canvas.
 */

// =================================================================== B1 — Social feed
function SocialFeedScreen({ state, nav, setState }) {
  const [tab, setTab] = React.useState('Following');
  const posts = [
    { who: 'Marcus K.', when: '12m', avatar: 'M', tone: 'oklch(0.65 0.16 35)',
      title: 'Long ride · 84 km', meta: '2h 48m · 1240 elev', kudos: 12 },
    { who: 'Sara T.', when: '1h', avatar: 'S', tone: 'oklch(0.65 0.16 220)',
      title: 'PR! 5K · 22:14', meta: 'New personal best · -18s', kudos: 34, pr: true },
    { who: 'Coach Idris', when: '3h', avatar: 'I', tone: 'oklch(0.55 0.16 290)',
      title: 'Strength · Posterior chain', meta: '52m · RPE 7', kudos: 8 },
    { who: 'Jess M.', when: '5h', avatar: 'J', tone: 'oklch(0.62 0.13 130)',
      title: 'Recovery spin', meta: '40m · Z1', kudos: 4 },
  ];
  return (
    <>
      <TopBar title="Teammates" right={<Icon name="plus" size={18}/>}/>
      <div style={{ padding: '0 18px 8px' }}>
        <div className="af-seg">
          {['Following','Discover'].map(t => (
            <div key={t} className="af-seg-item" data-on={tab === t}
              onClick={() => setTab(t)}>{t}</div>
          ))}
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 18px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {posts.map((p, i) => (
          <Card key={i} style={{ padding: 14 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10 }}>
              <div style={{ width: 30, height: 30, borderRadius: 999,
                background: p.tone, color: '#fff', display: 'flex',
                alignItems: 'center', justifyContent: 'center',
                fontWeight: 600, fontSize: 12, fontFamily: 'var(--font-mono)' }}>{p.avatar}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 500 }}>{p.who}</div>
                <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 1 }}>
                  {p.when.toUpperCase()} AGO
                </div>
              </div>
              {p.pr && <Chip style={{ fontSize: 9,
                background: 'color-mix(in oklch, var(--ready-high), transparent 70%)',
                borderColor: 'var(--ready-high)' }}>PR</Chip>}
            </div>
            <div style={{ fontSize: 13.5, fontWeight: 500 }}>{p.title}</div>
            <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>
              {p.meta.toUpperCase()}
            </div>
            <div style={{ display: 'flex', gap: 14, marginTop: 12, paddingTop: 10,
              borderTop: '1px solid var(--border)', alignItems: 'center' }}>
              <button style={{ all: 'unset', cursor: 'pointer', display: 'flex',
                alignItems: 'center', gap: 5, fontSize: 12, color: 'var(--fg-muted)' }}>
                <span style={{ fontSize: 14 }}>👏</span> {p.kudos}
              </button>
              <button style={{ all: 'unset', cursor: 'pointer', display: 'flex',
                alignItems: 'center', gap: 5, fontSize: 12, color: 'var(--fg-muted)' }}>
                <Icon name="msg" size={13}/> Reply
              </button>
              <div style={{ flex: 1 }}/>
              <Icon name="share" size={14} style={{ color: 'var(--fg-muted)' }}/>
            </div>
          </Card>
        ))}
      </div>
    </>
  );
}

// =================================================================== B2 — PR celebration modal
function PRCelebrationScreen({ state, nav }) {
  return (
    <>
      <div style={{ flex: 1, background: 'rgba(0,0,0,0.55)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 22, position: 'relative', overflow: 'hidden' }}>
        {/* Confetti dots */}
        {[...Array(24)].map((_, i) => (
          <div key={i} style={{
            position: 'absolute', width: 6, height: 8,
            background: ['var(--ready-high)','oklch(0.7 0.17 35)','oklch(0.65 0.16 220)','oklch(0.7 0.18 300)'][i % 4],
            top: `${(i * 13) % 80 + 4}%`, left: `${(i * 23) % 90 + 3}%`,
            transform: `rotate(${i * 27}deg)`, borderRadius: 1,
            opacity: 0.8,
          }}/>
        ))}
        <div style={{ position: 'relative', width: '100%', background: 'var(--bg)',
          borderRadius: 18, padding: '32px 22px 22px', textAlign: 'center',
          boxShadow: '0 30px 80px rgba(0,0,0,0.3)' }}>
          {/* Medal */}
          <div style={{ width: 90, height: 90, borderRadius: 999,
            background: 'linear-gradient(135deg, oklch(0.78 0.16 85), oklch(0.55 0.16 60))',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            margin: '0 auto 18px', color: '#fff', fontSize: 38,
            boxShadow: '0 12px 30px color-mix(in oklch, oklch(0.65 0.16 60), transparent 50%)' }}>
            🏅
          </div>
          <div className="af-label" style={{ fontSize: 10,
            color: 'var(--ready-high)', letterSpacing: '0.1em' }}>NEW PERSONAL RECORD</div>
          <div className="af-h1" style={{ fontSize: 26, marginTop: 6 }}>5K · 22:14</div>
          <div className="af-mono" style={{ fontSize: 13, color: 'var(--ready-high)',
            marginTop: 4 }}>−18s vs previous</div>
          <div className="af-muted" style={{ fontSize: 12, marginTop: 14, lineHeight: 1.55 }}>
            That's the fastest 5K in 8 months. Your last block of threshold work paid off.
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 22 }}>
            <Btn wide size="lg" onClick={() => nav('history')}>
              <Icon name="share" size={14}/> Share
            </Btn>
            <Btn wide variant="ghost" size="sm" onClick={() => nav('history')}>Dismiss</Btn>
          </div>
        </div>
      </div>
    </>
  );
}

// =================================================================== B3 — PR history
function PRHistoryScreen({ state, nav }) {
  const [seg, setSeg] = React.useState('Run');
  const prs = {
    Run: [
      { d: '5K', v: '22:14', when: 'Yesterday', prev: '22:32', trend: [25,24.5,24,23.5,23,22.8,22.6,22.3] },
      { d: '10K', v: '46:08', when: '3 weeks ago', prev: '46:42', trend: [50,49,48,47.5,47,46.8,46.5,46.1] },
      { d: 'Half', v: '1:41:22', when: '2 months ago', prev: '1:43:10', trend: [110,108,106,105,104,103,102,101] },
      { d: 'Mile', v: '6:08', when: '4 months ago', prev: '6:15', trend: [7,6.8,6.6,6.5,6.4,6.3,6.2,6.1] },
    ],
    Lift: [
      { d: 'Back squat', v: '105 kg', when: '6 days ago', prev: '102 kg', trend: [90,92,95,97,100,102,104,105] },
      { d: 'Deadlift', v: '135 kg', when: '2 weeks ago', prev: '130 kg', trend: [115,118,120,125,127,130,132,135] },
    ],
    Hybrid: [
      { d: 'HYROX sim', v: '1:08:20', when: '5 weeks ago', prev: '1:11:15', trend: [78,76,74,72,71,70,69,68.3] },
    ],
  }[seg];
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('history')} title="Personal records"/>
      <div style={{ padding: '0 18px 12px' }}>
        <div className="af-seg">
          {['Run','Lift','Hybrid'].map(t => (
            <div key={t} className="af-seg-item" data-on={seg === t}
              onClick={() => setSeg(t)}>{t}</div>
          ))}
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '4px 18px 18px', display: 'flex', flexDirection: 'column', gap: 6 }}>
        {prs.map((p, i) => (
          <div key={i} className="af-row" style={{ padding: '14px 0' }}>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 500 }}>{p.d}</div>
              <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>
                {p.when.toUpperCase()} · WAS {p.prev.toUpperCase()}
              </div>
            </div>
            <Spark points={p.trend} w={70} h={26} color="var(--ready-high)"/>
            <div className="af-mono" style={{ fontSize: 14, fontWeight: 500,
              minWidth: 60, textAlign: 'right' }}>{p.v}</div>
          </div>
        ))}
      </div>
    </>
  );
}

// =================================================================== B4 — XP / Level
function LevelScreen({ state, nav }) {
  const xp = 1420, xpMax = 2000, level = 14;
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Level"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <Card style={{ padding: 18, marginBottom: 16, textAlign: 'center' }}>
          <div className="af-mono" style={{ fontSize: 10,
            color: 'var(--fg-muted)' }}>LEVEL</div>
          <div style={{ fontSize: 48, fontWeight: 600, marginTop: 4,
            letterSpacing: '-0.02em', fontFamily: 'var(--font-mono)' }}>{level}</div>
          <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>Threshold Climber</div>
          <div className="af-prog" style={{ marginTop: 16, height: 8 }}>
            <div className="af-prog-fill" style={{ width: `${(xp/xpMax)*100}%`,
              background: 'linear-gradient(90deg, var(--ready-high), oklch(0.65 0.16 130))' }}/>
          </div>
          <div className="af-mono" style={{ fontSize: 10, marginTop: 6,
            color: 'var(--fg-muted)' }}>{xp} / {xpMax} XP · 580 TO LEVEL 15</div>
        </Card>

        <div className="af-label" style={{ marginBottom: 8 }}>UNLOCKS</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { lvl: 15, t: 'Advanced metrics', s: 'Power-duration curves, intensity factor', locked: true },
            { lvl: 14, t: 'Coach personalities', s: 'Pick a coaching voice', locked: false, just: true },
            { lvl: 12, t: 'Multi-watch routing', s: 'Roles per device', locked: false },
            { lvl: 10, t: 'Custom programs', s: 'Build your own block', locked: false },
            { lvl:  5, t: 'Library tags',  s: 'Organize your saves', locked: false },
          ].map(u => (
            <Card key={u.lvl} style={{ padding: 12, opacity: u.locked ? 0.55 : 1,
              display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ width: 36, height: 36, borderRadius: 8,
                background: u.locked ? 'var(--bg-subtle)' : 'var(--accent-bg)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: 'var(--font-mono)', fontWeight: 600, fontSize: 13,
                flexShrink: 0 }}>{u.lvl}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 500,
                  display: 'flex', alignItems: 'center', gap: 6 }}>
                  {u.t}
                  {u.just && <Chip style={{ fontSize: 8,
                    background: 'color-mix(in oklch, var(--ready-high), transparent 65%)',
                    borderColor: 'var(--ready-high)' }}>NEW</Chip>}
                </div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{u.s}</div>
              </div>
              {u.locked && <Chip outline style={{ fontSize: 9 }}>LOCKED</Chip>}
            </Card>
          ))}
        </div>
      </div>
    </>
  );
}

// =================================================================== B5 — Nutrition
function NutritionScreen({ state, nav }) {
  const kcal = 1840, kcalGoal = 2400;
  const macros = [
    { k: 'Protein', v: 124, goal: 160, color: 'oklch(0.65 0.18 25)' },
    { k: 'Carbs',   v: 215, goal: 280, color: 'oklch(0.72 0.16 85)' },
    { k: 'Fat',     v:  62, goal:  80, color: 'oklch(0.65 0.10 230)' },
  ];
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('home')}
        title="Nutrition" right={<Icon name="plus" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <Card style={{ padding: 16, marginBottom: 14 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <Ring value={Math.round((kcal/kcalGoal)*100)} size={84} stroke={6}/>
            <div style={{ flex: 1 }}>
              <div className="af-label" style={{ fontSize: 9 }}>TODAY</div>
              <div style={{ fontSize: 22, fontWeight: 500, marginTop: 4,
                letterSpacing: '-0.01em' }}>
                <span className="af-mono">{kcal}</span>
                <span className="af-muted af-mono" style={{ fontSize: 13 }}> / {kcalGoal} kcal</span>
              </div>
              <div className="af-mono" style={{ fontSize: 10, marginTop: 4,
                color: 'var(--fg-muted)' }}>{kcalGoal - kcal} REMAINING</div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            {macros.map(m => (
              <div key={m.k} style={{ flex: 1 }}>
                <div className="af-label" style={{ fontSize: 8 }}>{m.k.toUpperCase()}</div>
                <div className="af-mono" style={{ fontSize: 13, fontWeight: 500, marginTop: 3 }}>
                  {m.v}<span className="af-muted" style={{ fontSize: 10 }}>/{m.goal}g</span>
                </div>
                <div className="af-prog" style={{ marginTop: 4, height: 4 }}>
                  <div className="af-prog-fill" style={{ width: `${(m.v/m.goal)*100}%`,
                    background: m.color }}/>
                </div>
              </div>
            ))}
          </div>
        </Card>

        <div className="af-label" style={{ marginBottom: 8 }}>MEALS</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {[
            { t: 'Breakfast', d: 'Oats, banana, almond butter', kcal: 480, e: '🌅' },
            { t: 'Pre-workout', d: 'Date + coffee', kcal: 110, e: '⚡', accent: true },
            { t: 'Lunch', d: 'Chicken bowl, brown rice', kcal: 620, e: '🥗' },
            { t: 'Post-workout', d: 'Whey + banana', kcal: 280, e: '💪', accent: true },
            { t: 'Dinner', d: '— add meal', kcal: null, e: '🍽️' },
          ].map(m => (
            <Card key={m.t} style={{ padding: 12, display: 'flex',
              alignItems: 'center', gap: 12,
              borderColor: m.accent ? 'color-mix(in oklch, var(--ready-high), transparent 60%)' : 'var(--border)',
              opacity: m.kcal === null ? 0.6 : 1 }}>
              <div style={{ fontSize: 18, width: 30, textAlign: 'center' }}>{m.e}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 500 }}>{m.t}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{m.d}</div>
              </div>
              <div className="af-mono" style={{ fontSize: 12, fontWeight: 500 }}>
                {m.kcal !== null ? `${m.kcal} kcal` : '+'}
              </div>
            </Card>
          ))}
        </div>
      </div>
    </>
  );
}

// =================================================================== B6 — Strava OAuth
function StravaOAuthScreen({ state, nav }) {
  const [phase, setPhase] = React.useState('brand'); // brand → auth → success
  React.useEffect(() => {
    if (phase === 'brand') {
      const t = setTimeout(() => setPhase('auth'), 1200);
      return () => clearTimeout(t);
    }
    if (phase === 'auth') {
      const t = setTimeout(() => setPhase('success'), 1600);
      return () => clearTimeout(t);
    }
  }, [phase]);
  const ORANGE = 'oklch(0.65 0.20 35)';
  return (
    <>
      {phase === 'brand' && (
        <div style={{ flex: 1, background: ORANGE,
          display: 'flex', flexDirection: 'column', alignItems: 'center',
          justifyContent: 'center', color: '#fff' }}>
          <div style={{ width: 80, height: 80, borderRadius: 18,
            background: '#fff', color: ORANGE, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            fontWeight: 700, fontFamily: 'var(--font-mono)', fontSize: 36 }}>S</div>
          <div style={{ marginTop: 20, fontSize: 18, fontWeight: 500 }}>Connecting…</div>
        </div>
      )}
      {phase === 'auth' && (
        <>
          <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('settings')}
            title="Authorize Strava"/>
          <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
            <div style={{ display: 'flex', alignItems: 'center',
              justifyContent: 'center', gap: 12, padding: '16px 0 22px' }}>
              <div style={{ width: 56, height: 56, borderRadius: 14,
                background: 'var(--accent-bg)', display: 'flex',
                alignItems: 'center', justifyContent: 'center',
                fontWeight: 600, fontSize: 24 }}>A</div>
              <div style={{ display: 'flex', gap: 4 }}>
                {[0,1,2].map(i => <span key={i} style={{ width: 5, height: 5,
                  borderRadius: 999, background: 'var(--fg-muted)' }}/>)}
              </div>
              <div style={{ width: 56, height: 56, borderRadius: 14,
                background: ORANGE, color: '#fff', display: 'flex',
                alignItems: 'center', justifyContent: 'center',
                fontWeight: 700, fontFamily: 'var(--font-mono)', fontSize: 22 }}>S</div>
            </div>
            <div className="af-h2" style={{ textAlign: 'center' }}>AmakaFlow wants access to your Strava</div>
            <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[
                ['Read your activities', 'Past 12 months'],
                ['Read your profile', 'Name, photo, FTP'],
                ['Write activities', 'Push completed workouts'],
              ].map(([t, s]) => (
                <div key={t} className="af-row" style={{ padding: '10px 0' }}>
                  <Icon name="check" size={14} style={{ color: 'var(--ready-high)' }}/>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 12.5 }}>{t}</div>
                    <div className="af-muted" style={{ fontSize: 11, marginTop: 1 }}>{s}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
          <div style={{ padding: '12px 20px 18px' }}>
            <Btn wide size="lg" style={{ background: ORANGE, borderColor: ORANGE, color: '#fff' }}
              onClick={() => setPhase('success')}>Authorize</Btn>
            <div style={{ height: 6 }}/>
            <Btn wide variant="ghost" size="sm" onClick={() => nav('settings')}>Cancel</Btn>
          </div>
        </>
      )}
      {phase === 'success' && (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', padding: '0 28px' }}>
          <div style={{ width: 64, height: 64, borderRadius: 999,
            background: 'color-mix(in oklch, var(--ready-high), transparent 70%)',
            color: 'var(--ready-high)', display: 'flex', alignItems: 'center',
            justifyContent: 'center', marginBottom: 18 }}>
            <Icon name="check" size={28}/>
          </div>
          <div className="af-h2" style={{ textAlign: 'center' }}>Strava connected</div>
          <div className="af-muted" style={{ fontSize: 12.5, marginTop: 10,
            textAlign: 'center', lineHeight: 1.55 }}>
            Imported <span className="af-mono">142</span> activities from the last 12 months. Workouts will sync automatically going forward.
          </div>
          <div style={{ marginTop: 28, width: '100%' }}>
            <Btn wide size="lg" onClick={() => nav('settings')}>Done</Btn>
          </div>
        </div>
      )}
    </>
  );
}

// =================================================================== B7 — URL ingestion
function URLIngestScreen({ state, nav }) {
  const [phase, setPhase] = React.useState('paste'); // paste → parsing → preview
  React.useEffect(() => {
    if (phase === 'parsing') {
      const t = setTimeout(() => setPhase('preview'), 1600);
      return () => clearTimeout(t);
    }
  }, [phase]);
  return (
    <>
      <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('workouts')}
        title="Import workout"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        {phase === 'paste' && (
          <>
            <FieldGroup label="URL OR TEXT">
              <textarea className="af-input" rows={4}
                placeholder="Paste a workout link or write it out…"
                style={{ resize: 'none',
                  fontFamily: 'var(--font-mono)', fontSize: 11 }}
                defaultValue="https://fastcrew.run/sessions/4x8-threshold"/>
            </FieldGroup>
            <div className="af-muted" style={{ fontSize: 11, lineHeight: 1.55, marginTop: 4 }}>
              We support most coaching sites, blog posts, and free-form text. AI extracts sets, reps, and pace.
            </div>
            <Btn wide size="lg" style={{ marginTop: 18 }}
              onClick={() => setPhase('parsing')}>
              <Icon name="sparkle" size={14}/> Parse with AI
            </Btn>
          </>
        )}
        {phase === 'parsing' && (
          <div style={{ padding: '60px 0', textAlign: 'center' }}>
            <div style={{ display: 'inline-flex', gap: 4, marginBottom: 16 }}>
              {[0,1,2].map(i => (
                <div key={i} style={{ width: 8, height: 8, borderRadius: 999,
                  background: 'var(--fg)',
                  animation: `demo-dot 1.2s ${i * 0.15}s infinite` }}/>
              ))}
            </div>
            <div className="af-h3">Reading the page…</div>
            <div className="af-muted" style={{ fontSize: 12, marginTop: 8 }}>
              Extracting sets, reps, and pace
            </div>
          </div>
        )}
        {phase === 'preview' && (
          <>
            <div style={{ padding: '10px 12px', borderRadius: 8,
              background: 'color-mix(in oklch, var(--ready-high), transparent 82%)',
              border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)',
              fontSize: 11.5, display: 'flex', alignItems: 'center', gap: 8,
              marginBottom: 14 }}>
              <Icon name="sparkle" size={14} style={{ color: 'var(--ready-high)' }}/>
              <span>Parsed from <span className="af-mono">fastcrew.run</span>. Edit anything that looks off.</span>
            </div>
            <FieldGroup label="NAME">
              <input className="af-input" defaultValue="4×8 min threshold"/>
            </FieldGroup>
            <FieldGroup label="TYPE">
              <div style={{ display: 'flex', gap: 6 }}>
                {['Run','Strength','Hybrid'].map(t => (
                  <Chip key={t} outline={t !== 'Run'} style={{ fontSize: 11, flex: 1,
                    textAlign: 'center', justifyContent: 'center',
                    background: t === 'Run' ? 'var(--fg)' : 'transparent',
                    color: t === 'Run' ? 'var(--bg)' : 'var(--fg)',
                    borderColor: t === 'Run' ? 'var(--fg)' : 'var(--border-str)' }}>{t}</Chip>
                ))}
              </div>
            </FieldGroup>
            <Card style={{ padding: 14, marginBottom: 14 }}>
              <div className="af-label" style={{ fontSize: 9 }}>EXTRACTED BLOCKS</div>
              {[
                ['Warmup', '15 min easy · Z1'],
                ['Main set', '4 × 8 min @ 4:38/km · 3 min rest'],
                ['Cooldown', '5 min easy'],
              ].map(([t, s]) => (
                <div key={t} style={{ padding: '8px 0', display: 'flex',
                  alignItems: 'center', gap: 10, borderTop: '1px solid var(--border)' }}>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 12.5, fontWeight: 500 }}>{t}</div>
                    <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 1 }}>{s}</div>
                  </div>
                  <Icon name="edit" size={12} style={{ color: 'var(--fg-dim)' }}/>
                </div>
              ))}
            </Card>
          </>
        )}
      </div>
      {phase === 'preview' && (
        <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
          <Btn wide size="lg" onClick={() => nav('workouts')}>Save to library</Btn>
        </div>
      )}
    </>
  );
}

// =================================================================== B8 — Reel ingestion
function ReelIngestScreen({ state, nav }) {
  return (
    <>
      <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('library')}
        title="Import from reel"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ display: 'flex', gap: 12, marginBottom: 16 }}>
          <div style={{ width: 110, aspectRatio: '9/16', borderRadius: 12,
            background: 'linear-gradient(135deg, oklch(0.55 0.18 320), oklch(0.45 0.16 260))',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontSize: 32, flexShrink: 0,
            border: '1px solid var(--border)' }}>▶</div>
          <div style={{ flex: 1 }}>
            <Chip outline style={{ fontSize: 9, marginBottom: 6 }}>REEL · 0:42</Chip>
            <div style={{ fontSize: 12.5, fontWeight: 500, lineHeight: 1.4 }}>
              "Full body HYROX prep — 4 rounds, no equipment"
            </div>
            <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 6 }}>
              @COACHIDRIS
            </div>
            <div style={{ padding: '6px 10px', borderRadius: 6,
              background: 'color-mix(in oklch, var(--ready-high), transparent 82%)',
              fontSize: 10.5, marginTop: 10,
              border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)' }}>
              <Icon name="sparkle" size={11} style={{ marginRight: 4,
                color: 'var(--ready-high)' }}/>
              <span>AI detected <span className="af-mono">8 exercises</span></span>
            </div>
          </div>
        </div>

        <div className="af-label" style={{ marginBottom: 8 }}>DETECTED EXERCISES · EDIT ANY</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {[
            { t: 'Wall ball', s: '20 reps · 9 kg' },
            { t: 'Burpee broad jump', s: '10 reps' },
            { t: 'KB swing', s: '15 reps · 24 kg' },
            { t: 'Sled push', s: '20 m · 50 kg' },
            { t: 'Farmer carry', s: '40 m · 2×24 kg' },
            { t: 'Box jump', s: '10 reps · 60 cm' },
            { t: 'Lunges', s: '20 reps' },
            { t: 'Plank', s: '60 sec' },
          ].map((ex, i) => (
            <div key={i} className="af-row" style={{ padding: '10px 12px',
              background: 'var(--bg-elev)', borderRadius: 8,
              border: '1px solid var(--border)' }}>
              <div className="af-mono" style={{ fontSize: 10,
                color: 'var(--fg-muted)', width: 20 }}>{i + 1}.</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12, fontWeight: 500 }}>{ex.t}</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 1 }}>{ex.s}</div>
              </div>
              <Icon name="edit" size={12} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('library')}>Save as workout</Btn>
      </div>
    </>
  );
}

// =================================================================== B9 — QR scanner
function QRScannerScreen({ state, nav }) {
  return (
    <>
      <div style={{ flex: 1, background: '#000', position: 'relative',
        display: 'flex', flexDirection: 'column' }}>
        <div style={{ padding: '14px 18px', display: 'flex',
          justifyContent: 'space-between', alignItems: 'center', color: '#fff',
          position: 'relative', zIndex: 2 }}>
          <button onClick={() => nav('library')} style={{ all: 'unset', cursor: 'pointer',
            width: 30, height: 30, borderRadius: 999, background: 'rgba(255,255,255,0.15)',
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="close" size={16}/>
          </button>
          <div style={{ fontSize: 13, fontWeight: 500 }}>Scan QR</div>
          <div style={{ width: 30 }}/>
        </div>

        {/* "Camera" placeholder */}
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center',
          background: 'radial-gradient(circle at 30% 30%, oklch(0.25 0 0), #000 70%)',
          position: 'relative' }}>
          {/* Reticle */}
          <div style={{ width: 220, height: 220, position: 'relative' }}>
            {/* Corners */}
            {[['tl', '0', '0', '0','auto','auto','0'],
              ['tr', '0', 'auto', '0','auto','0','auto'],
              ['bl', 'auto', '0', 'auto', '0','auto','0'],
              ['br', 'auto', 'auto', 'auto', '0','0','auto']].map(([k, t, l, b, r, R, L]) => (
              <div key={k} style={{ position: 'absolute',
                top: t, left: l, bottom: b, right: r,
                width: 32, height: 32,
                borderTop: t === '0' ? '3px solid #fff' : 'none',
                borderBottom: b === '0' ? '3px solid #fff' : 'none',
                borderLeft: l === '0' ? '3px solid #fff' : 'none',
                borderRight: r === '0' ? '3px solid #fff' : 'none',
                borderRadius: 6 }}/>
            ))}
            {/* Scanning line */}
            <div style={{ position: 'absolute', left: 12, right: 12, top: '50%',
              height: 2, background: 'var(--ready-high)',
              boxShadow: '0 0 16px var(--ready-high)' }}/>
          </div>
          <div style={{ position: 'absolute', bottom: 80, left: 0, right: 0,
            textAlign: 'center', color: '#fff', fontSize: 12, opacity: 0.8 }}>
            Point the camera at a QR code
          </div>
        </div>

        <div style={{ padding: '16px 20px 26px', background: '#0d0d0d',
          color: '#fff' }}>
          <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.6)', marginBottom: 8 }}>OR ENTER MANUALLY</div>
          <input style={{ width: '100%', height: 40, borderRadius: 8,
            background: 'rgba(255,255,255,0.08)', border: '1px solid rgba(255,255,255,0.15)',
            padding: '0 12px', color: '#fff', boxSizing: 'border-box',
            fontFamily: 'var(--font-mono)', fontSize: 11 }}
            placeholder="Paste code or URL"/>
        </div>
      </div>
    </>
  );
}

// =================================================================== B10 — Voice logging
function VoiceLogScreen({ state, nav }) {
  return (
    <>
      <TopBar left={<Icon name="close" size={20}/>} onLeft={() => nav('history')}
        title="Voice log"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <Card style={{ padding: 18, marginBottom: 14, textAlign: 'center' }}>
          <div className="af-mono" style={{ fontSize: 9,
            color: 'var(--ready-high)', letterSpacing: '0.1em' }}>● RECORDING</div>
          <div style={{ marginTop: 14, height: 60,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            gap: 3 }}>
            {[...Array(28)].map((_, i) => (
              <div key={i} style={{ width: 3, height: 8 + Math.abs(Math.sin(i)) * 40,
                background: 'var(--fg)',
                opacity: 0.6 + Math.abs(Math.cos(i)) * 0.4,
                borderRadius: 2 }}/>
            ))}
          </div>
          <div className="af-mono" style={{ fontSize: 16, marginTop: 10, fontWeight: 500 }}>
            0:24
          </div>
        </Card>

        <div className="af-label" style={{ marginBottom: 6 }}>LIVE TRANSCRIPT</div>
        <div style={{ padding: '14px 14px', borderRadius: 10,
          background: 'var(--bg-subtle)', border: '1px solid var(--border)',
          fontSize: 13, lineHeight: 1.65 }}>
          Just finished the threshold session — felt pretty good actually. Hit 4:36 average on the four reps, last one was a fight but I held the pace.{' '}
          <span style={{ color: 'var(--fg-muted)' }}>Heart rate maxed out at one seventy-eight on the third…</span>
          <span style={{ animation: 'demo-blink 0.8s infinite',
            background: 'var(--fg)', display: 'inline-block', width: 2, height: 13,
            marginLeft: 2, verticalAlign: 'middle' }}/>
        </div>

        <div className="af-label" style={{ marginTop: 18, marginBottom: 8 }}>QUICK TEMPLATES</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {[
            ['Quick log', '"Did a 5K, felt great"'],
            ['How I felt', '"RPE 7, legs heavy, mood good"'],
            ['Replan request', '"Move tomorrow to Saturday"'],
          ].map(([t, ex]) => (
            <div key={t} className="af-row" style={{ padding: '12px 14px',
              borderRadius: 10, background: 'var(--bg-elev)',
              border: '1px solid var(--border)', cursor: 'pointer' }}>
              <Icon name="mic" size={14} style={{ color: 'var(--fg-muted)' }}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 500 }}>{t}</div>
                <div className="af-muted" style={{ fontSize: 10.5, marginTop: 2 }}>{ex}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)',
        display: 'flex', gap: 8, alignItems: 'center' }}>
        <button style={{ all: 'unset', cursor: 'pointer', width: 48, height: 48,
          borderRadius: 999, background: 'var(--ready-high)',
          color: '#0d1208', display: 'flex', alignItems: 'center',
          justifyContent: 'center', flexShrink: 0 }}>
          <Icon name="stop" size={18}/>
        </button>
        <Btn wide size="lg" onClick={() => nav('history')}>Done · log it</Btn>
      </div>
    </>
  );
}

// =================================================================== B11 — Follow-along player
function FollowAlongScreen({ state, nav }) {
  return (
    <>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column' }}>
        {/* Video tile */}
        <div style={{ aspectRatio: '16/9', background: '#000',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          position: 'relative', color: '#fff' }}>
          <div style={{ fontSize: 56, opacity: 0.5 }}>▶</div>
          <div style={{ position: 'absolute', top: 10, left: 12,
            display: 'flex', alignItems: 'center', gap: 8 }}>
            <button onClick={() => nav('workouts')} style={{ all: 'unset', cursor: 'pointer',
              width: 30, height: 30, borderRadius: 999, background: 'rgba(0,0,0,0.4)',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="close" size={16}/>
            </button>
          </div>
          <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0,
            height: 3, background: 'rgba(255,255,255,0.2)' }}>
            <div style={{ height: '100%', width: '38%', background: 'var(--ready-high)' }}/>
          </div>
          <div style={{ position: 'absolute', bottom: 8, right: 12, fontSize: 11,
            fontFamily: 'var(--font-mono)', color: '#fff', opacity: 0.85 }}>
            4:38 / 12:00
          </div>
        </div>

        {/* Now on */}
        <div style={{ padding: '14px 20px 0', flexShrink: 0 }}>
          <div className="af-label" style={{ fontSize: 9 }}>NOW · EXERCISE 3 OF 8</div>
          <div className="af-h2" style={{ fontSize: 19, marginTop: 4 }}>Wall ball · 20 reps</div>
          <div className="af-mono" style={{ fontSize: 11, color: 'var(--fg-muted)',
            marginTop: 4 }}>9 KG · CHEST TO TARGET</div>
        </div>

        {/* Timeline */}
        <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
          padding: '14px 20px 20px' }}>
          <div className="af-label" style={{ marginBottom: 8 }}>TIMELINE</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
            {[
              { i: 1, t: 'Warmup', s: '0:00 – 2:30', done: true },
              { i: 2, t: 'Burpee broad jump · 10', s: '2:30 – 4:00', done: true },
              { i: 3, t: 'Wall ball · 20 reps', s: '4:00 – 5:30', now: true },
              { i: 4, t: 'KB swing · 15', s: '5:30 – 7:00' },
              { i: 5, t: 'Sled push · 20m', s: '7:00 – 8:30' },
              { i: 6, t: 'Farmer carry · 40m', s: '8:30 – 10:00' },
              { i: 7, t: 'Box jump · 10', s: '10:00 – 11:00' },
              { i: 8, t: 'Plank · 60s', s: '11:00 – 12:00' },
            ].map(s => (
              <div key={s.i} style={{ padding: '10px 0', display: 'flex',
                alignItems: 'center', gap: 12,
                borderBottom: '1px solid var(--border)',
                opacity: !s.now && !s.done ? 0.55 : 1 }}>
                <div className="af-mono" style={{ width: 22, fontSize: 10,
                  textAlign: 'center', color: 'var(--fg-muted)',
                  fontWeight: s.now ? 600 : 400 }}>
                  {s.done ? <Icon name="check" size={12} style={{ color: 'var(--ready-high)' }}/> : s.i}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ fontSize: 12.5, fontWeight: s.now ? 600 : 400,
                    color: s.now ? 'var(--fg)' : 'var(--fg-muted)' }}>{s.t}</div>
                </div>
                <div className="af-mono" style={{ fontSize: 9.5, color: 'var(--fg-muted)' }}>{s.s}</div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}

// =================================================================== B12 — Share card
function ShareCardScreen({ state, nav }) {
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('history')} title="Share workout"/>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
        alignItems: 'center', padding: '8px 20px 18px', overflowY: 'auto' }}
        className="af-scroll">
        {/* The card preview */}
        <div style={{ width: 320, aspectRatio: '4/5',
          background: 'linear-gradient(165deg, oklch(0.18 0 0) 0%, oklch(0.08 0 0) 100%)',
          color: '#fff', borderRadius: 16, padding: '24px 24px 26px',
          display: 'flex', flexDirection: 'column',
          boxShadow: '0 20px 60px rgba(0,0,0,0.25)' }}>
          <div style={{ display: 'flex', alignItems: 'center',
            justifyContent: 'space-between' }}>
            <div className="af-mono" style={{ fontSize: 9, letterSpacing: '0.1em',
              opacity: 0.6 }}>AMAKAFLOW</div>
            <div className="af-mono" style={{ fontSize: 9, letterSpacing: '0.05em',
              opacity: 0.6 }}>APR 24 · THU</div>
          </div>
          <div style={{ marginTop: 14 }}>
            <div style={{ fontSize: 12, opacity: 0.75 }}>Threshold run</div>
            <div style={{ fontSize: 32, fontWeight: 600, marginTop: 4,
              letterSpacing: '-0.02em' }}>4×8 min @ 4:36/km</div>
          </div>

          {/* Mini "map" stripe */}
          <div style={{ marginTop: 18, height: 80, borderRadius: 8,
            background: 'rgba(255,255,255,0.06)',
            border: '1px solid rgba(255,255,255,0.1)',
            position: 'relative', overflow: 'hidden' }}>
            <svg viewBox="0 0 320 80" width="100%" height="100%"
              preserveAspectRatio="none">
              <path d="M0 60 Q40 20 80 38 T160 30 T240 50 T320 22"
                stroke="oklch(0.78 0.16 130)" strokeWidth="2.5" fill="none"
                strokeLinecap="round"/>
            </svg>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
            gap: 12, marginTop: 'auto', paddingTop: 18,
            borderTop: '1px solid rgba(255,255,255,0.1)' }}>
            {[['10.2 km','DIST'], ['1:04:12','TIME'], ['TSS 78','LOAD']].map(([v, k]) => (
              <div key={k}>
                <div style={{ fontSize: 9, opacity: 0.55, letterSpacing: '0.08em',
                  fontFamily: 'var(--font-mono)' }}>{k}</div>
                <div style={{ fontFamily: 'var(--font-mono)', fontSize: 16,
                  fontWeight: 500, marginTop: 4 }}>{v}</div>
              </div>
            ))}
          </div>
        </div>

        <div style={{ width: '100%', marginTop: 18, display: 'flex',
          flexDirection: 'column', gap: 8 }}>
          <Btn wide size="lg" onClick={() => nav('history')}>
            <Icon name="share" size={14}/> Share
          </Btn>
          <Btn wide variant="ghost" size="md">
            <Icon name="download" size={14}/> Save image
          </Btn>
        </div>
      </div>
    </>
  );
}

Object.assign(window, {
  SocialFeedScreen, PRCelebrationScreen, PRHistoryScreen, LevelScreen,
  NutritionScreen, StravaOAuthScreen, URLIngestScreen, ReelIngestScreen,
  QRScannerScreen, VoiceLogScreen, FollowAlongScreen, ShareCardScreen,
});
