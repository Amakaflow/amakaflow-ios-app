/**
 * Part C — 10 secondary screens. Each is a complete-enough rep
 * to validate the idea; built on existing primitives only.
 */

// =================================================================== C1 — Analytics
function AnalyticsScreen({ state, nav }) {
  const [range, setRange] = React.useState('30d');
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('history')} title="Analytics"/>
      <div style={{ padding: '0 18px 12px' }}>
        <div className="af-seg">
          {['7d','30d','90d','1y'].map(r => (
            <div key={r} className="af-seg-item" data-on={range === r}
              onClick={() => setRange(r)}>{r}</div>
          ))}
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '6px 18px 18px' }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
          {[
            { k: 'TSS · WEEKLY AVG', v: '412', delta: '+8%',
              points: [380,395,360,420,400,415,412], color: 'oklch(0.65 0.18 25)' },
            { k: 'DISTANCE · KM', v: '142', delta: '+12%',
              points: [120,128,135,138,140,138,142], color: 'oklch(0.72 0.16 85)' },
            { k: 'CONSISTENCY', v: '88%', delta: '+4%',
              points: [80,82,85,84,86,87,88], color: 'var(--ready-high)' },
            { k: 'AVG HRV', v: '68 ms', delta: '+5%',
              points: [60,62,64,65,66,67,68], color: 'oklch(0.65 0.10 230)' },
            { k: 'SLEEP · 7D AVG', v: '7h 24m', delta: '+18m',
              points: [6.5,6.8,7,7.1,7.2,7.3,7.4], color: 'oklch(0.55 0.16 290)' },
            { k: 'ZONE 2 SHARE', v: '64%', delta: '+6%',
              points: [55,58,60,61,62,63,64], color: 'oklch(0.62 0.13 130)' },
          ].map(t => (
            <Card key={t.k} style={{ padding: 12 }}>
              <div className="af-label" style={{ fontSize: 8.5 }}>{t.k}</div>
              <div className="af-mono" style={{ fontSize: 17, fontWeight: 500,
                marginTop: 4, letterSpacing: '-0.01em' }}>{t.v}</div>
              <div className="af-mono" style={{ fontSize: 9, marginTop: 2,
                color: 'var(--ready-high)' }}>{t.delta}</div>
              <Spark points={t.points} w={120} h={28} color={t.color}
                style={{ marginTop: 6 }}/>
            </Card>
          ))}
        </div>

        <div className="af-label" style={{ marginTop: 18, marginBottom: 8 }}>BY MODALITY</div>
        <Card tight style={{ padding: 14 }}>
          {[
            ['Run', 62, 'oklch(0.65 0.18 25)'],
            ['Strength', 22, 'oklch(0.55 0.16 290)'],
            ['Ride', 11, 'oklch(0.65 0.10 230)'],
            ['Mobility', 5, 'oklch(0.62 0.13 130)'],
          ].map(([k, pct, c]) => (
            <div key={k} style={{ marginBottom: 10 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between',
                fontSize: 11, marginBottom: 4 }}>
                <span>{k}</span>
                <span className="af-mono" style={{ color: 'var(--fg-muted)' }}>{pct}%</span>
              </div>
              <div className="af-prog" style={{ height: 6 }}>
                <div className="af-prog-fill" style={{ width: `${pct}%`, background: c }}/>
              </div>
            </div>
          ))}
        </Card>
      </div>
    </>
  );
}

// =================================================================== C2 — Sources
function SourcesScreen({ state, nav }) {
  const [picker, setPicker] = React.useState(null);
  const [sources, setSources] = React.useState({
    HRV: 'Whoop 4.0', Sleep: 'Apple Watch', RHR: 'Garmin FR965',
    Steps: 'Apple Watch', Workouts: 'Garmin FR965', Strength: 'Manual log',
  });
  const devices = ['Whoop 4.0', 'Apple Watch', 'Garmin FR965', 'Manual log'];
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Data sources"
        sub="Which device feeds which metric"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <Card tight style={{ padding: 0 }}>
          {Object.entries(sources).map(([k, v], i, arr) => (
            <div key={k} onClick={() => setPicker(k)}
              className="af-row" style={{ cursor: 'pointer',
                borderBottom: i < arr.length - 1 ? '1px solid var(--border)' : 'none',
                marginLeft: 14, marginRight: 14 }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{k}</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 2 }}>
                  {v.toUpperCase()}
                </div>
              </div>
              <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          ))}
        </Card>
        <div style={{ marginTop: 14, padding: 12, background: 'var(--bg-subtle)',
          borderRadius: 10, fontSize: 11, lineHeight: 1.5,
          color: 'var(--fg-muted)' }}>
          When two devices report the same metric, the one you pick here wins. Tap a row to change.
        </div>
      </div>
      <Sheet open={!!picker} onClose={() => setPicker(null)}
        title={`Source for ${picker}`}>
        {devices.map(d => (
          <div key={d} onClick={() => {
            setSources(s => ({ ...s, [picker]: d })); setPicker(null);
          }} style={{ padding: '14px 12px', borderRadius: 8,
            display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }}>
            <div style={{ width: 18, height: 18, borderRadius: 999,
              border: `1.5px solid ${sources[picker] === d ? 'var(--fg)' : 'var(--border-str)'}`,
              background: sources[picker] === d ? 'var(--fg)' : 'transparent',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {sources[picker] === d && <div style={{ width: 6, height: 6,
                borderRadius: 999, background: 'var(--bg)' }}/>}
            </div>
            <div style={{ flex: 1, fontSize: 13 }}>{d}</div>
          </div>
        ))}
      </Sheet>
    </>
  );
}

// =================================================================== C3 — Shoe mileage
function ShoeMileageScreen({ state, nav }) {
  const shoes = [
    { name: 'Vaporfly 3', meta: 'Race · Apr 2026', miles: 88, max: 240, color: 'oklch(0.65 0.18 25)' },
    { name: 'Vomero 17',  meta: 'Daily trainer · Jan 2026', miles: 240, max: 400, color: 'oklch(0.65 0.10 230)' },
    { name: 'Pegasus 41', meta: 'Backup · Sep 2025', miles: 380, max: 400, color: 'oklch(0.72 0.16 85)' },
    { name: 'Wave Rider', meta: 'Retired · Aug 2025', miles: 520, max: 500, color: 'var(--fg-muted)', retired: true },
  ];
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Shoe mileage"
        right={<Icon name="plus" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {shoes.map(s => {
            const pct = Math.min(100, (s.miles / s.max) * 100);
            const warn = pct > 80;
            return (
              <Card key={s.name} style={{ padding: 14,
                opacity: s.retired ? 0.55 : 1 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                  <div style={{ width: 40, height: 40, borderRadius: 10,
                    background: 'var(--accent-bg)', color: s.color,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    flexShrink: 0 }}>
                    <Icon name="shoe" size={20}/>
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13, fontWeight: 500 }}>{s.name}</div>
                    <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 2 }}>
                      {s.meta.toUpperCase()}
                    </div>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div className="af-mono" style={{ fontSize: 14, fontWeight: 500 }}>
                      {s.miles}<span className="af-muted" style={{ fontSize: 10 }}>/{s.max}</span>
                    </div>
                    <div className="af-mono" style={{ fontSize: 9, marginTop: 1,
                      color: 'var(--fg-muted)' }}>KM</div>
                  </div>
                </div>
                <div className="af-prog" style={{ marginTop: 12, height: 5 }}>
                  <div className="af-prog-fill" style={{ width: `${pct}%`,
                    background: warn ? 'var(--ready-low)' : s.color }}/>
                </div>
                {warn && !s.retired && (
                  <div style={{ marginTop: 8, fontSize: 10.5, color: 'var(--ready-low)',
                    display: 'flex', alignItems: 'center', gap: 5 }}>
                    <Icon name="info" size={11}/> Retire soon · {s.max - s.miles} km left
                  </div>
                )}
              </Card>
            );
          })}
        </div>
        <Btn variant="ghost" wide size="md" style={{ marginTop: 14 }}>
          <Icon name="plus" size={14}/> Add new pair
        </Btn>
      </div>
    </>
  );
}

// =================================================================== C4 — Data export
function DataExportScreen({ state, nav }) {
  const [fmt, setFmt] = React.useState('CSV');
  const [range, setRange] = React.useState('Last 90 days');
  const [email, setEmail] = React.useState('adaeze@hyrox.co');
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Export data"
        sub="Get a copy of your training history"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <FieldGroup label="FORMAT">
          <div style={{ display: 'flex', gap: 6 }}>
            {['CSV','JSON','GPX'].map(f => (
              <Chip key={f} outline={fmt !== f} onClick={() => setFmt(f)}
                style={{ fontSize: 11, flex: 1, cursor: 'pointer',
                  textAlign: 'center', justifyContent: 'center',
                  background: fmt === f ? 'var(--fg)' : 'transparent',
                  color: fmt === f ? 'var(--bg)' : 'var(--fg)',
                  borderColor: fmt === f ? 'var(--fg)' : 'var(--border-str)' }}>{f}</Chip>
            ))}
          </div>
        </FieldGroup>
        <div className="af-muted" style={{ fontSize: 11, marginTop: -10, marginBottom: 14,
          lineHeight: 1.5 }}>
          {fmt === 'CSV' && 'Spreadsheet-friendly. One row per workout.'}
          {fmt === 'JSON' && 'Full schema, ideal for developers.'}
          {fmt === 'GPX' && 'Geo tracks for runs and rides. Re-importable to Strava.'}
        </div>

        <FieldGroup label="DATE RANGE">
          <div className="af-seg">
            {['Last 30d','Last 90d','1 year','All time'].map(r => (
              <div key={r} className="af-seg-item" data-on={range.endsWith(r.replace('Last ',''))}
                onClick={() => setRange('Last ' + r.replace('Last ',''))}>{r}</div>
            ))}
          </div>
        </FieldGroup>

        <FieldGroup label="EMAIL TO">
          <input className="af-input" value={email} onChange={e => setEmail(e.target.value)}/>
        </FieldGroup>

        <Card tight style={{ padding: 12, marginTop: 6 }}>
          <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
            <Icon name="info" size={14} style={{ color: 'var(--fg-muted)', marginTop: 1 }}/>
            <div className="af-muted" style={{ fontSize: 11, lineHeight: 1.55 }}>
              We'll send a link by email. Files larger than 50 MB are split. Link expires in 7 days.
            </div>
          </div>
        </Card>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('settings')}>
          <Icon name="download" size={14}/> Export {fmt}
        </Btn>
      </div>
    </>
  );
}

// =================================================================== C5 — Debug log
function DebugLogScreen({ state, nav }) {
  const [verbose, setVerbose] = React.useState(false);
  const lines = [
    ['06:14:02', 'INFO', 'app:boot version=1.4.2 build=4188'],
    ['06:14:02', 'INFO', 'auth:session restored uid=u_4f81'],
    ['06:14:03', 'INFO', 'sync:garmin start since=2026-04-23T22:18Z'],
    ['06:14:04', 'DEBUG', 'sync:garmin polling … attempt=1'],
    ['06:14:04', 'DEBUG', 'sync:garmin polling … attempt=2'],
    ['06:14:05', 'INFO', 'sync:garmin ok 1 activity, 0 conflicts'],
    ['06:14:05', 'INFO', 'sync:whoop ok hrv=72 rhr=48 sleep=27240s'],
    ['06:14:06', 'INFO', 'readiness:recompute score=84 confidence=high'],
    ['06:14:06', 'INFO', 'plan:revisit no changes'],
    ['06:14:11', 'WARN', 'telegram:webhook unreachable retry=300s'],
    ['06:14:38', 'DEBUG', 'ui:render home in 42ms'],
    ['06:14:39', 'DEBUG', 'ui:render home in 11ms'],
    ['06:14:51', 'ERROR', 'apns:push 410 token=…2af expired'],
    ['06:14:52', 'INFO', 'apns:token rotate ok'],
    ['06:15:04', 'INFO', 'session:end duration=62s'],
  ];
  const visible = verbose ? lines : lines.filter(l => l[1] !== 'DEBUG');
  const color = (lvl) => ({
    INFO: 'var(--fg-muted)', DEBUG: 'var(--fg-dim)',
    WARN: 'oklch(0.7 0.16 65)', ERROR: 'var(--destructive)',
  }[lvl]);
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Debug log"
        right={<Icon name="download" size={16}/>}/>
      <div style={{ padding: '0 18px 12px', display: 'flex',
        gap: 10, alignItems: 'center' }}>
        <div style={{ flex: 1, fontSize: 11.5 }}>Verbose</div>
        <div className="af-switch" data-on={verbose}
          onClick={() => setVerbose(v => !v)}/>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '0 12px 14px', background: 'var(--bg-subtle)',
        margin: '0 14px', borderRadius: 10, border: '1px solid var(--border)' }}>
        <div style={{ padding: 10, fontFamily: 'var(--font-mono)', fontSize: 10.5,
          lineHeight: 1.6 }}>
          {visible.map((l, i) => (
            <div key={i} style={{ display: 'flex', gap: 6 }}>
              <span style={{ color: 'var(--fg-dim)' }}>{l[0]}</span>
              <span style={{ color: color(l[1]), width: 44, flexShrink: 0 }}>{l[1]}</span>
              <span>{l[2]}</span>
            </div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px' }}>
        <Btn variant="ghost" wide size="md">Copy all to clipboard</Btn>
      </div>
    </>
  );
}

// =================================================================== C6 — Biometric consent
function BiometricConsentScreen({ state, nav }) {
  const items = [
    { k: 'hk',   t: 'HealthKit', s: 'Heart, sleep, steps from Apple Health',
      e: '💚', granted: true },
    { k: 'noti', t: 'Notifications', s: 'Morning briefings + replan alerts',
      e: '🔔', granted: true },
    { k: 'loc',  t: 'Location', s: 'Map your runs and rides',
      e: '📍', granted: false },
    { k: 'mic',  t: 'Microphone', s: 'Voice logging',
      e: '🎙️', granted: false },
    { k: 'cam',  t: 'Camera', s: 'QR pairing + reel import',
      e: '📷', granted: true },
  ];
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Permissions"
        sub="What AmakaFlow can access"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {items.map(i => (
            <Card key={i.k} style={{ padding: 14, display: 'flex',
              alignItems: 'center', gap: 12 }}>
              <div style={{ width: 40, height: 40, borderRadius: 10,
                background: 'var(--accent-bg)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontSize: 18, flexShrink: 0 }}>{i.e}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{i.t}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{i.s}</div>
              </div>
              {i.granted ? (
                <Chip style={{ fontSize: 9,
                  background: 'color-mix(in oklch, var(--ready-high), transparent 78%)',
                  borderColor: 'var(--ready-high)' }}>
                  <Icon name="check" size={9}/> Granted
                </Chip>
              ) : (
                <Btn size="sm" variant="ghost">Allow</Btn>
              )}
            </Card>
          ))}
        </div>
        <div className="af-muted" style={{ fontSize: 11, marginTop: 18,
          lineHeight: 1.55 }}>
          AmakaFlow never sells or shares your biometric data. Revoke anything in iOS Settings → AmakaFlow.
        </div>
      </div>
    </>
  );
}

// =================================================================== C7 — Fatigue history
function FatigueHistoryScreen({ state, nav }) {
  const [range, setRange] = React.useState('30d');
  // Sample series
  const points = Array.from({ length: 30 }, (_, i) =>
    65 + Math.sin(i / 3) * 8 + Math.cos(i / 5) * 5);
  const annotations = [
    { i: 6, label: '5K test' },
    { i: 14, label: 'Threshold' },
    { i: 22, label: 'Long ride' },
  ];
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')} title="Fatigue history"/>
      <div style={{ padding: '0 18px 12px' }}>
        <div className="af-seg">
          {['30d','90d','1y'].map(r => (
            <div key={r} className="af-seg-item" data-on={range === r}
              onClick={() => setRange(r)}>{r}</div>
          ))}
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '4px 18px 18px' }}>
        {/* Big chart */}
        <Card style={{ padding: 14, marginBottom: 12 }}>
          <div className="af-label" style={{ fontSize: 9 }}>HRV · MS</div>
          <div style={{ position: 'relative', height: 120, marginTop: 8 }}>
            <Spark points={points} w={320} h={120} color="oklch(0.65 0.10 230)"
              style={{ width: '100%', height: '100%' }}/>
            {/* Annotations */}
            {annotations.map(a => (
              <div key={a.i} style={{ position: 'absolute',
                left: `${(a.i / points.length) * 100}%`, top: 0, bottom: 0,
                width: 1, background: 'var(--ready-low)', opacity: 0.5 }}/>
            ))}
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between',
            marginTop: 8, fontSize: 9, color: 'var(--fg-muted)',
            fontFamily: 'var(--font-mono)' }}>
            <span>30D AGO</span><span>TODAY</span>
          </div>
        </Card>

        <Card style={{ padding: 14, marginBottom: 12 }}>
          <div className="af-label" style={{ fontSize: 9 }}>TRAINING LOAD · TSS/D</div>
          <Spark points={[40,55,72,68,82,90,75,88,95,82,78,68,72,84,92]}
            w={320} h={70} color="oklch(0.65 0.18 25)"
            style={{ width: '100%', height: 70, marginTop: 8 }}/>
        </Card>

        <Card style={{ padding: 14 }}>
          <div className="af-label" style={{ fontSize: 9 }}>SLEEP · HOURS</div>
          <Spark points={[6.2,7,7.4,6.8,7.6,7.2,7.8,7.4,8,7.2,7.5,6.8,7.6,7.8,7.5]}
            w={320} h={70} color="oklch(0.55 0.16 290)"
            style={{ width: '100%', height: 70, marginTop: 8 }}/>
        </Card>

        <div className="af-label" style={{ marginTop: 18, marginBottom: 8 }}>HARD SESSIONS ANNOTATED</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
          {annotations.map(a => (
            <div key={a.i} className="af-row" style={{ padding: '10px 0' }}>
              <div style={{ width: 4, height: 28, background: 'var(--ready-low)' }}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12.5, fontWeight: 500 }}>{a.label}</div>
                <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 1 }}>
                  {a.i} DAYS AGO · HRV DIP 12%
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

// =================================================================== C8 — Completion detail
function CompletionDetailScreen({ state, nav }) {
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('history')}
        right={<Icon name="kebab" size={16}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 0 20px' }}>
        <div style={{ padding: '4px 20px 0' }}>
          <Chip outline style={{ fontSize: 9, marginBottom: 6 }}>THU · APR 24 · 06:34</Chip>
          <div className="af-h1" style={{ fontSize: 22 }}>4×8 min @ threshold</div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 4 }}>
            10.2 KM · 1:04:12 · TSS 78 · RPE 7
          </div>
        </div>

        {/* Splits */}
        <div style={{ padding: '18px 20px 0' }}>
          <div className="af-label" style={{ marginBottom: 8 }}>SPLITS</div>
          <Card tight style={{ padding: 0 }}>
            {[
              { i: 1, pace: '4:36', hr: 168, dur: '8:00' },
              { i: 2, pace: '4:38', hr: 172, dur: '8:00' },
              { i: 3, pace: '4:35', hr: 176, dur: '8:00' },
              { i: 4, pace: '4:34', hr: 178, dur: '8:00', best: true },
            ].map(s => (
              <div key={s.i} style={{ padding: '12px 14px',
                borderBottom: s.i < 4 ? '1px solid var(--border)' : 'none',
                display: 'flex', alignItems: 'center', gap: 12 }}>
                <div className="af-mono" style={{ width: 26, fontSize: 11,
                  color: 'var(--fg-muted)' }}>#{s.i}</div>
                <div className="af-mono" style={{ flex: 1, fontSize: 13,
                  fontWeight: s.best ? 600 : 500 }}>
                  {s.pace}/km
                  {s.best && <Chip style={{ marginLeft: 8, fontSize: 8,
                    background: 'color-mix(in oklch, var(--ready-high), transparent 65%)',
                    borderColor: 'var(--ready-high)' }}>BEST</Chip>}
                </div>
                <div className="af-mono" style={{ fontSize: 11,
                  color: 'var(--fg-muted)' }}>{s.hr} BPM</div>
                <div className="af-mono" style={{ fontSize: 11,
                  color: 'var(--fg-muted)' }}>{s.dur}</div>
              </div>
            ))}
          </Card>
        </div>

        {/* Zones */}
        <div style={{ padding: '20px 20px 0' }}>
          <div className="af-label" style={{ marginBottom: 8 }}>TIME IN ZONE</div>
          <Card style={{ padding: 14 }}>
            {[
              ['Z1', 8, 'oklch(0.62 0.13 130)'],
              ['Z2', 22, 'oklch(0.72 0.16 85)'],
              ['Z3', 32, 'oklch(0.65 0.18 25)'],
              ['Z4', 35, 'oklch(0.55 0.20 25)'],
              ['Z5', 3,  'oklch(0.45 0.20 25)'],
            ].map(([z, pct, c]) => (
              <div key={z} style={{ marginBottom: 8 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between',
                  fontSize: 11 }}>
                  <span className="af-mono">{z}</span>
                  <span className="af-mono" style={{ color: 'var(--fg-muted)' }}>{pct}%</span>
                </div>
                <div className="af-prog" style={{ marginTop: 4, height: 5 }}>
                  <div className="af-prog-fill" style={{ width: `${pct}%`, background: c }}/>
                </div>
              </div>
            ))}
          </Card>
        </div>

        {/* Weather + notes */}
        <div style={{ padding: '20px 20px 0' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
            <Metric k="TEMP" v="14°C"/>
            <Metric k="WIND" v="8 kph"/>
            <Metric k="CONDITIONS" v="Clear"/>
          </div>
          <div className="af-label" style={{ marginTop: 16, marginBottom: 6 }}>NOTES</div>
          <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.6 }}>
            Last rep felt the strongest. Calves a little tight by the cooldown — book mobility tomorrow.
          </div>
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('detail')}>Repeat this workout</Btn>
      </div>
    </>
  );
}

// =================================================================== C9 — Rest day
function RestDayScreen({ state, nav, setState }) {
  return (
    <>
      <TopBar
        left={<div onClick={() => {}} style={{ color: 'var(--fg-muted)', width: 28 }}>
          <Icon name="chevL" size={20}/></div>}
        title="Today" sub="Rest day · planned"
        right={<Icon name="gear" size={18}/>} onRight={() => nav('settings')}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 16px' }}>
        <Card style={{ padding: 18, marginBottom: 14,
          background: 'linear-gradient(135deg, color-mix(in oklch, oklch(0.65 0.10 230), transparent 70%) 0%, color-mix(in oklch, oklch(0.65 0.10 230), transparent 90%) 100%)',
          border: '1px solid color-mix(in oklch, oklch(0.65 0.10 230), transparent 60%)' }}>
          <div style={{ fontSize: 38, textAlign: 'center' }}>🌙</div>
          <div className="af-h2" style={{ fontSize: 19, textAlign: 'center', marginTop: 8 }}>
            Rest day
          </div>
          <div className="af-muted" style={{ fontSize: 12.5, textAlign: 'center',
            marginTop: 8, lineHeight: 1.55 }}>
            Three solid sessions this week. Threshold work tomorrow needs a fresh nervous system.
          </div>
        </Card>

        <div className="af-label" style={{ marginBottom: 6 }}>WHY TODAY</div>
        <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.6, marginBottom: 18 }}>
          You're at +12% training load over the rolling average. Your last hard session was 36 hours ago. The plan calls for one full rest per micro-cycle and this is the spot.
        </div>

        <Card tight style={{ padding: 14 }}>
          <div className="af-label" style={{ fontSize: 9 }}>OPTIONAL · LIGHT MOBILITY</div>
          <div style={{ fontSize: 13, fontWeight: 500, marginTop: 4 }}>20 min · hip + ankle</div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 3 }}>
            Foam roller · band-assisted ankle work · 90/90 hip
          </div>
          <Btn variant="ghost" size="sm" wide style={{ marginTop: 10 }}
            onClick={() => nav('player')}>Open mobility flow</Btn>
        </Card>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" variant="ghost"
          onClick={() => nav('home')}>Got it · see you tomorrow</Btn>
      </div>
      <TabBar active={0}/>
    </>
  );
}

// =================================================================== C10 — Add knowledge
function AddKnowledgeScreen({ state, nav }) {
  const [cat, setCat] = React.useState('Injury');
  const [note, setNote] = React.useState('');
  const cats = [
    { v: 'Injury',   e: '🩹', sub: 'A flare-up, surgery, or chronic issue' },
    { v: 'Schedule', e: '📅', sub: 'Travel, work crunch, race date' },
    { v: 'Goal',     e: '🎯', sub: 'A new outcome you\'re aiming for' },
    { v: 'Preference', e: '⚙️', sub: 'Likes, dislikes, training style' },
  ];
  const examples = {
    Injury:    ['Strained left calf after Tuesday\'s long run. Easing back this week.',
                'Chronic IT band on the right.', 'Surgery on right shoulder, May 2025.'],
    Schedule:  ['In Tokyo Apr 28 – May 4, can only train mornings.',
                'Race date May 18 — taper Apr 30.', 'Work crunch first 2 weeks of June.'],
    Goal:      ['Sub-1:30 half marathon by October.', 'Hyrox Doubles podium, regional.',
                'Get back to bodyweight pull-ups × 10.'],
    Preference:['Prefer mornings, never after 8pm.', 'Hate burpees.',
                'Like long runs on Saturdays, not Sundays.'],
  };
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')}
        title="Tell your coach"
        sub="Things Coach should remember when planning"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ display: 'flex', gap: 6, marginBottom: 16, flexWrap: 'wrap' }}>
          {cats.map(c => (
            <Chip key={c.v} outline={cat !== c.v} onClick={() => setCat(c.v)}
              style={{ fontSize: 11, cursor: 'pointer', padding: '7px 11px',
                background: cat === c.v ? 'var(--fg)' : 'transparent',
                color: cat === c.v ? 'var(--bg)' : 'var(--fg)',
                borderColor: cat === c.v ? 'var(--fg)' : 'var(--border-str)' }}>
              <span style={{ fontSize: 13 }}>{c.e}</span> {c.v}
            </Chip>
          ))}
        </div>
        <div className="af-muted" style={{ fontSize: 11.5, lineHeight: 1.5,
          marginBottom: 14 }}>
          {cats.find(c => c.v === cat).sub}
        </div>

        <FieldGroup label={`TELL COACH · ${cat.toUpperCase()}`}>
          <textarea className="af-input" rows={4} value={note}
            onChange={e => setNote(e.target.value)}
            placeholder={examples[cat][0]}
            style={{ resize: 'none', fontFamily: 'inherit' }}/>
        </FieldGroup>

        <div className="af-label" style={{ marginBottom: 8 }}>EXAMPLES</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {examples[cat].map(e => (
            <div key={e} onClick={() => setNote(e)}
              style={{ padding: '10px 12px', borderRadius: 8, cursor: 'pointer',
                background: 'var(--bg-subtle)', fontSize: 11.5,
                color: 'var(--fg-muted)', lineHeight: 1.5,
                border: '1px solid var(--border)' }}>"{e}"</div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('settings')}
          disabled={!note.trim()}>Save</Btn>
      </div>
    </>
  );
}

Object.assign(window, {
  AnalyticsScreen, SourcesScreen, ShoeMileageScreen, DataExportScreen,
  DebugLogScreen, BiometricConsentScreen, FatigueHistoryScreen,
  CompletionDetailScreen, RestDayScreen, AddKnowledgeScreen,
});
