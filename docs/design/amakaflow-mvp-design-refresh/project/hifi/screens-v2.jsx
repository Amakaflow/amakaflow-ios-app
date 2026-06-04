/**
 * AmakaFlow v1 polish screens (AMA-1876…1885):
 *  - SignupScreen (with looping animated phone demo)
 *  - EquipmentScreen
 *  - MessagingScreen + MessagingDetailScreen
 *  - LibraryScreen (+ empty state variant)
 *  - CoachScreen (Coach tab — wraps AgentInbox idiom with briefing context)
 *  - DetailFromSource (variant of DetailScreen with external-source banner)
 */

// -------------------------------------------------------- Signup (animated)
function SignupScreen({ nav, setState }) {
  // 5-scene narrative loop. Each scene ~1.5–2s. Total ~9.5s, then fades to s1.
  const SCENES = [
    { id: 's1', dur: 1700 }, // type email + tap Sign-in-with-Apple
    { id: 's2', dur: 2000 }, // choose "Single workout"
    { id: 's3', dur: 2000 }, // AI thinking + workout card slides in
    { id: 's4', dur: 1900 }, // ghost arrow moves card toward Telegram bubble
    { id: 's5', dur: 2000 }, // Telegram bubble with workout preview
  ];
  const [idx, setIdx] = React.useState(0);
  React.useEffect(() => {
    const t = setTimeout(() => setIdx(i => (i + 1) % SCENES.length), SCENES[idx].dur);
    return () => clearTimeout(t);
  }, [idx]);

  return (
    <>
      <div style={{ padding: '10px 16px 0', display: 'flex',
        justifyContent: 'flex-end' }}>
        <span className="af-label" style={{ fontSize: 9 }}>v1.0 BETA</span>
      </div>
      {/* Top 60% — animated demo */}
      <div style={{ height: '58%', display: 'flex', alignItems: 'center',
        justifyContent: 'center', padding: '0 18px',
        background: 'var(--bg-subtle)',
        borderBottom: '1px solid var(--border)' }}>
        <DemoFrame scene={SCENES[idx].id}/>
      </div>

      {/* Bottom 40% — pitch + CTAs */}
      <div style={{ flex: 1, padding: '22px 26px 22px',
        display: 'flex', flexDirection: 'column' }}>
        <div className="af-h1" style={{ fontSize: 26, letterSpacing: '-0.015em',
          lineHeight: 1.15 }}>
          Train on the<br/>right day.
        </div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 10, lineHeight: 1.55 }}>
          Your AI coach adapts every session to today's readiness.
        </div>

        <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <button onClick={() => nav('onboarding')}
            style={{ all: 'unset', cursor: 'pointer', width: '100%',
              background: 'var(--fg)', color: 'var(--bg)',
              padding: '14px 16px', borderRadius: 999,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              gap: 8, fontWeight: 500, fontSize: 14, textAlign: 'center',
              boxSizing: 'border-box' }}>
            <AppleGlyph/> Continue with Apple ID
          </button>
          <Btn variant="ghost" wide size="md" onClick={() => nav('onboarding')}>
            Continue with email
          </Btn>
          <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 6,
            textAlign: 'center', lineHeight: 1.5 }}>
            BY CONTINUING YOU AGREE TO TERMS · PRIVACY
          </div>
        </div>
      </div>
    </>
  );
}

// Generic minimal Apple-style glyph (rounded silhouette, no actual Apple logo).
function AppleGlyph() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"
      style={{ display: 'inline-block' }}>
      <path d="M16.5 12.4c0-2.6 2.1-3.8 2.2-3.9-1.2-1.7-3-2-3.7-2-1.6-.2-3 .9-3.8.9-.8 0-2-.9-3.3-.9-1.7 0-3.3 1-4.2 2.5C2 12.1 3.3 17.3 5 20c.8 1.3 1.8 2.8 3.1 2.8 1.2 0 1.7-.8 3.2-.8s1.9.8 3.2.8c1.3 0 2.2-1.3 3-2.6.9-1.5 1.3-3 1.3-3.1-.1 0-2.6-1-2.6-3.7zM14.2 4.2C14.9 3.3 15.4 2 15.3 .7c-1.1 0-2.5.8-3.2 1.7-.7.8-1.3 2.1-1.1 3.3 1.3.1 2.5-.6 3.2-1.5z"/>
    </svg>
  );
}

// Mini phone frame for the demo loop. Scenes are absolute-positioned and fade.
function DemoFrame({ scene }) {
  const W = 280, H = 320;
  return (
    <div style={{ width: W, height: H, borderRadius: 26,
      border: '1px solid var(--border-str)', background: 'var(--bg)',
      position: 'relative', overflow: 'hidden',
      boxShadow: '0 10px 40px rgba(0,0,0,0.10)' }}>
      <div style={{ height: 24, display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', padding: '0 14px',
        fontFamily: 'var(--font-mono)', fontSize: 9, color: 'var(--fg)' }}>
        <span>6:14</span><span>●●●● ▲ 100</span>
      </div>
      {['s1','s2','s3','s4','s5'].map(s => (
        <div key={s} style={{ position: 'absolute', inset: '24px 0 0 0',
          opacity: scene === s ? 1 : 0,
          transition: 'opacity 0.45s ease', padding: '14px 18px',
          pointerEvents: 'none' }}>
          {s === 's1' && <DemoScene1/>}
          {s === 's2' && <DemoScene2/>}
          {s === 's3' && <DemoScene3/>}
          {s === 's4' && <DemoScene4/>}
          {s === 's5' && <DemoScene5/>}
        </div>
      ))}
      <style>{`
        @keyframes demo-pulse { 0%, 100% { box-shadow: 0 0 0 0 var(--fg); } 50% { box-shadow: 0 0 0 6px transparent; } }
        @keyframes demo-blink { 0%, 100% { opacity: 0; } 50% { opacity: 1; } }
        @keyframes demo-slide { from { transform: translateY(20px); opacity: 0; } to { transform: translateY(0); opacity: 1; } }
        @keyframes demo-arrow { 0% { transform: translateX(0); } 100% { transform: translateX(70px); } }
        @keyframes demo-dot { 0% { opacity: 0.3; } 33% { opacity: 1; } 66%, 100% { opacity: 0.3; } }
      `}</style>
    </div>
  );
}

function DemoScene1() {
  return (
    <>
      <div className="af-label" style={{ fontSize: 8, marginBottom: 10 }}>SIGN IN</div>
      <div style={{ background: 'var(--input-bg)', borderRadius: 8, padding: '9px 11px',
        fontSize: 11, fontFamily: 'var(--font-mono)', color: 'var(--fg)' }}>
        adaeze@hyrox.co<span style={{ animation: 'demo-blink 0.7s infinite',
          background: 'var(--fg)', display: 'inline-block', width: 1.5, height: 11,
          marginLeft: 2, verticalAlign: 'middle' }}/>
      </div>
      <div style={{ position: 'relative', marginTop: 16,
        background: '#000', color: '#fff', borderRadius: 999, padding: '11px 14px',
        fontSize: 11, fontWeight: 500, display: 'flex', alignItems: 'center',
        justifyContent: 'center', gap: 6, animation: 'demo-pulse 1.2s infinite' }}>
        <AppleGlyph/> Continue with Apple ID
      </div>
      <div style={{ marginTop: 14, fontSize: 10, color: 'var(--fg-muted)',
        textAlign: 'center' }}>or continue with email</div>
    </>
  );
}

function DemoScene2() {
  const opts = [
    { label: 'Full program', sub: '4-week block', on: false },
    { label: 'Single workout', sub: 'Just today', on: true },
    { label: 'Coach picks', sub: 'Surprise me', on: false },
  ];
  return (
    <>
      <div className="af-label" style={{ fontSize: 8, marginBottom: 10 }}>WHAT DO YOU NEED?</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        {opts.map((o, i) => (
          <div key={i} style={{ padding: '10px 12px', borderRadius: 10,
            border: `1px solid ${o.on ? 'var(--fg)' : 'var(--border)'}`,
            background: o.on ? 'color-mix(in oklch, var(--ready-high), transparent 78%)' : 'var(--bg-elev)',
            animation: o.on ? 'demo-pulse 1s infinite' : 'none',
            display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ width: 14, height: 14, borderRadius: 999,
              border: `1.5px solid ${o.on ? 'var(--fg)' : 'var(--border-str)'}`,
              background: o.on ? 'var(--fg)' : 'transparent' }}/>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, fontWeight: 500 }}>{o.label}</div>
              <div className="af-muted" style={{ fontSize: 9, marginTop: 1 }}>{o.sub}</div>
            </div>
          </div>
        ))}
      </div>
    </>
  );
}

function DemoScene3() {
  return (
    <>
      <div className="af-label" style={{ fontSize: 8, marginBottom: 10 }}>BUILDING…</div>
      <div style={{ display: 'flex', gap: 4, marginBottom: 16 }}>
        {[0,1,2].map(i => (
          <div key={i} style={{ width: 6, height: 6, borderRadius: 999,
            background: 'var(--fg)',
            animation: `demo-dot 1.2s ${i * 0.15}s infinite` }}/>
        ))}
      </div>
      <div style={{ animation: 'demo-slide 0.4s 0.4s both',
        padding: '12px 12px', borderRadius: 10, border: '1px solid var(--border)',
        background: 'var(--bg-elev)' }}>
        <div className="af-label" style={{ fontSize: 8 }}>THRESHOLD RUN</div>
        <div style={{ fontSize: 12, fontWeight: 500, marginTop: 4 }}>
          4×8 min @ threshold
        </div>
        <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 3 }}>
          64m · Z3–4 · TSS 78
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
          gap: 6, marginTop: 9, paddingTop: 8, borderTop: '1px solid var(--border)' }}>
          {[['4x','REPS'],['8m','EACH'],['3m','REST']].map(([v,k]) => (
            <div key={k}>
              <div className="af-mono" style={{ fontSize: 11, fontWeight: 500 }}>{v}</div>
              <div className="af-label" style={{ fontSize: 7 }}>{k}</div>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}

function DemoScene4() {
  return (
    <>
      <div className="af-label" style={{ fontSize: 8, marginBottom: 10 }}>SENDING…</div>
      <div style={{ position: 'relative', padding: '12px 12px', borderRadius: 10,
        border: '1px solid var(--border)', background: 'var(--bg-elev)' }}>
        <div className="af-label" style={{ fontSize: 8 }}>THRESHOLD RUN</div>
        <div style={{ fontSize: 12, fontWeight: 500, marginTop: 4 }}>
          4×8 min @ threshold
        </div>
        <div className="af-muted af-mono" style={{ fontSize: 9, marginTop: 3 }}>
          64m · Z3–4
        </div>
      </div>
      {/* Ghost arrow moving up-right */}
      <div style={{ position: 'absolute', top: 28, right: 18,
        display: 'flex', alignItems: 'center', gap: 4,
        animation: 'demo-arrow 1.6s ease-out forwards',
        color: 'var(--fg-muted)', fontSize: 16 }}>
        →
      </div>
      {/* Telegram bubble target */}
      <div style={{ position: 'absolute', top: 0, right: -4,
        width: 26, height: 26, borderRadius: 999,
        background: '#29B6F6', display: 'flex', alignItems: 'center',
        justifyContent: 'center', color: '#fff', fontSize: 14 }}>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
          <path d="M2 12l20-9-4 19-7-5-3 4-1-7L2 12z"/>
        </svg>
      </div>
    </>
  );
}

function DemoScene5() {
  return (
    <>
      <div className="af-label" style={{ fontSize: 8, marginBottom: 8 }}>TELEGRAM · 6:14</div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'flex-end' }}>
        <div style={{ width: 26, height: 26, borderRadius: 999,
          background: '#29B6F6', flexShrink: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff' }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor">
            <path d="M2 12l20-9-4 19-7-5-3 4-1-7L2 12z"/>
          </svg>
        </div>
        <div style={{ background: 'var(--bg-elev)', border: '1px solid var(--border)',
          borderRadius: 14, borderBottomLeftRadius: 4, padding: '10px 12px',
          maxWidth: 200, animation: 'demo-slide 0.4s both' }}>
          <div style={{ fontSize: 11, fontWeight: 500 }}>Today's session ready 👇</div>
          <div style={{ marginTop: 8, padding: '8px 9px',
            background: 'var(--bg-subtle)', borderRadius: 8 }}>
            <div className="af-label" style={{ fontSize: 7 }}>THRESHOLD RUN</div>
            <div style={{ fontSize: 10, fontWeight: 500, marginTop: 3 }}>
              4×8 min @ threshold
            </div>
            <div className="af-muted af-mono" style={{ fontSize: 8, marginTop: 2 }}>
              64m · TSS 78
            </div>
          </div>
        </div>
      </div>
    </>
  );
}

// -------------------------------------------------------- Equipment Profile
function EquipmentScreen({ nav, state, setState }) {
  const [q, setQ] = React.useState('');
  const [items, setItems] = React.useState({
    treadmill: false, bike: false, rower: false, assault: false, ski: false,
    barbell: false, dumbbell: true, kettlebell: false, plates: false, rack: false, bench: false,
    pullup: true, rings: false, paralettes: false,
    foam: true, ball: false, bands: false,
  });
  const [dbRange, setDbRange] = React.useState(35);
  const [where, setWhere] = React.useState('home');
  const [open, setOpen] = React.useState({ cardio: true, strength: true, body: true, mob: false });

  const toggle = (k) => setItems(it => ({ ...it, [k]: !it[k] }));

  const Cat = ({ id, title, children }) => (
    <div style={{ borderRadius: 12, border: '1px solid var(--border)',
      background: 'var(--bg-elev)', overflow: 'hidden', marginBottom: 8 }}>
      <button onClick={() => setOpen(o => ({ ...o, [id]: !o[id] }))}
        style={{ all: 'unset', cursor: 'pointer', width: '100%',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 14px', boxSizing: 'border-box' }}>
        <span style={{ fontSize: 13, fontWeight: 500 }}>{title}</span>
        <Icon name={open[id] ? 'chevU' : 'chevD'} size={14}
          style={{ color: 'var(--fg-muted)' }}/>
      </button>
      {open[id] && (
        <div style={{ padding: '0 14px 14px', borderTop: '1px solid var(--border)' }}>
          {children}
        </div>
      )}
    </div>
  );

  const Item = ({ id, label, sub }) => {
    const on = items[id];
    if (q && !label.toLowerCase().includes(q.toLowerCase())) return null;
    return (
      <button onClick={() => toggle(id)}
        style={{ all: 'unset', cursor: 'pointer', width: '100%',
          padding: '10px 0', display: 'flex', alignItems: 'center', gap: 10,
          borderBottom: '1px solid var(--border)', boxSizing: 'border-box' }}>
        <div style={{ width: 18, height: 18, borderRadius: 4,
          border: `1.5px solid ${on ? 'var(--fg)' : 'var(--border-str)'}`,
          background: on ? 'var(--fg)' : 'transparent',
          color: 'var(--bg)', display: 'flex', alignItems: 'center',
          justifyContent: 'center', flexShrink: 0 }}>
          {on && <Icon name="check" size={12}/>}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 13 }}>{label}</div>
          {sub && <div className="af-muted" style={{ fontSize: 10, marginTop: 1 }}>{sub}</div>}
        </div>
      </button>
    );
  };

  const wheres = [
    { v: 'home', e: '🏠', label: 'Home' },
    { v: 'gym', e: '🏢', label: 'Commercial' },
    { v: 'out', e: '🏞️', label: 'Outdoor' },
    { v: 'travel', e: '🚐', label: 'Travelling' },
  ];

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav && nav('settings')}
        title="What do you train with?"
        sub="We'll only suggest workouts that match your gear."/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ position: 'relative', marginBottom: 14 }}>
          <Icon name="search" size={14} style={{ position: 'absolute',
            left: 12, top: '50%', transform: 'translateY(-50%)',
            color: 'var(--fg-muted)' }}/>
          <input className="af-input" placeholder="Search equipment"
            value={q} onChange={e => setQ(e.target.value)}
            style={{ paddingLeft: 34 }}/>
        </div>

        <Cat id="cardio" title="Cardio">
          <Item id="treadmill" label="Treadmill"/>
          <Item id="bike" label="Stationary bike"/>
          <Item id="rower" label="Concept2 rower"/>
          <Item id="assault" label="Assault bike"/>
          <Item id="ski" label="Ski erg"/>
        </Cat>

        <Cat id="strength" title="Strength">
          <Item id="barbell" label="Barbell + plates"/>
          <Item id="dumbbell" label="Dumbbells"
            sub={items.dumbbell ? `Range · ${5}–${dbRange}kg` : null}/>
          {items.dumbbell && (
            <div style={{ padding: '8px 0 12px' }}>
              <input type="range" min="10" max="100" step="5" value={dbRange}
                onChange={e => setDbRange(+e.target.value)}
                style={{ width: '100%', accentColor: 'var(--fg)' }}/>
              <div className="af-mono" style={{ display: 'flex',
                justifyContent: 'space-between', fontSize: 9,
                color: 'var(--fg-muted)', marginTop: 4 }}>
                <span>5kg</span><span>{dbRange}kg max</span><span>100kg</span>
              </div>
            </div>
          )}
          <Item id="kettlebell" label="Kettlebells"/>
          <Item id="plates" label="Loose plates"/>
          <Item id="rack" label="Squat rack"/>
          <Item id="bench" label="Bench"/>
        </Cat>

        <Cat id="body" title="Bodyweight">
          <Item id="pullup" label="Pull-up bar"/>
          <Item id="rings" label="Gymnastic rings"/>
          <Item id="paralettes" label="Paralettes"/>
        </Cat>

        <Cat id="mob" title="Mobility">
          <Item id="foam" label="Foam roller"/>
          <Item id="ball" label="Lacrosse / massage ball"/>
          <Item id="bands" label="Resistance bands"/>
        </Cat>

        <div className="af-label" style={{ marginTop: 16, marginBottom: 8 }}>WHERE DO YOU TRAIN?</div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {wheres.map(w => {
            const on = where === w.v;
            return (
              <Chip key={w.v} outline={!on} onClick={() => setWhere(w.v)}
                style={{ fontSize: 12, padding: '8px 12px',
                  background: on ? 'var(--fg)' : 'transparent',
                  color: on ? 'var(--bg)' : 'var(--fg)',
                  borderColor: on ? 'var(--fg)' : 'var(--border-str)' }}>
                <span style={{ fontSize: 13 }}>{w.e}</span> {w.label}
              </Chip>
            );
          })}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav && nav('home')}>
          Save equipment <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

// -------------------------------------------------------- Messaging Integrations
function MessagingScreen({ nav, setState, state }) {
  const initial = [
    { id: 'tg', name: 'Telegram', handle: '@adaeze', icon: 'plane', tone: '#29B6F6', on: true },
  ];
  const [channels, setChannels] = React.useState(
    (state && state.messagingChannels) ? state.messagingChannels : initial
  );
  // Pick up newly-added Telegram channel after returning from setup
  React.useEffect(() => {
    if (state && state.justConnectedTelegram && !channels.find(c => c.id === 'tg')) {
      setChannels(cs => [...cs,
        { id: 'tg', name: 'Telegram', handle: '@adaeze', icon: 'plane', tone: '#29B6F6', on: true }]);
      setState && setState(s => ({ ...s, justConnectedTelegram: false,
        toast: 'Telegram connected · briefings on' }));
    }
  }, [state && state.justConnectedTelegram]);
  const [addOpen, setAddOpen] = React.useState(false);
  const [detail, setDetail] = React.useState(null);

  const toggleChannel = (id) => setChannels(cs => cs.map(c =>
    c.id === id ? { ...c, on: !c.on } : c
  ));

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav && nav('settings')}
        title="Messaging" sub="Where your coach reaches you"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div className="af-label" style={{ marginBottom: 8 }}>CONNECTED CHANNELS</div>
        {channels.map(c => (
          <Card key={c.id} onClick={() => setDetail(c)}
            style={{ padding: 14, marginBottom: 8, display: 'flex',
              alignItems: 'center', gap: 12 }}>
            <div style={{ width: 36, height: 36, borderRadius: 999,
              background: c.tone, color: '#fff', display: 'flex',
              alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <Icon name={c.icon} size={16}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14, fontWeight: 500 }}>{c.name}</div>
              <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 2 }}>
                {c.handle.toUpperCase()} · {c.on ? 'ACTIVE' : 'PAUSED'}
              </div>
            </div>
            <div className="af-switch" data-on={c.on}
              onClick={(e) => { e.stopPropagation(); toggleChannel(c.id); }}/>
          </Card>
        ))}

        <div style={{ marginTop: 14 }}>
          <Btn variant="ghost" wide size="md" onClick={() => setAddOpen(true)}>
            <Icon name="plus" size={14}/> Add channel
          </Btn>
        </div>

        <div className="af-label" style={{ marginTop: 22, marginBottom: 8 }}>WHAT YOU GET</div>
        <Card tight style={{ padding: 0 }}>
          {[
            ['Morning briefing', 'Today\'s session at 6am'],
            ['Evening check-in', 'How did it feel?'],
            ['Swap suggestions', 'When readiness drops mid-day'],
          ].map(([t, s], i, arr) => (
            <div key={t} style={{ padding: '12px 14px',
              borderBottom: i < arr.length - 1 ? '1px solid var(--border)' : 'none',
              display: 'flex', gap: 10, alignItems: 'center' }}>
              <Icon name="check" size={14} style={{ color: 'var(--ready-high)' }}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13 }}>{t}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{s}</div>
              </div>
            </div>
          ))}
        </Card>
      </div>

      <Sheet open={addOpen} onClose={() => setAddOpen(false)} title="Add channel">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[
            { v: 'tg', name: 'Telegram', sub: '2-tap connect', live: true,
              tone: '#29B6F6', icon: 'plane' },  { v: 'wa', name: 'WhatsApp', sub: 'Coming soon', live: false,
              tone: 'oklch(0.65 0.18 145)', icon: 'msg' },
            { v: 'sl', name: 'Slack',    sub: 'Coming soon', live: false,
              tone: 'oklch(0.65 0.16 300)', icon: 'msg' },
          ].map(o => (
            <div key={o.v} onClick={() => {
                if (!o.live) return;
                if (o.v === 'tg') {
                  // Push to Telegram setup flow (idle → polling → done) and return to messaging
                  setAddOpen(false);
                  nav && nav('telegram-setup-from-messaging');
                } else {
                  setAddOpen(false);
                }
              }}
              style={{ padding: '14px 14px', borderRadius: 12,
                border: '1px solid var(--border)',
                opacity: o.live ? 1 : 0.6,
                cursor: o.live ? 'pointer' : 'not-allowed',
                display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ width: 36, height: 36, borderRadius: 999,
                background: o.tone, color: '#fff',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0 }}>
                <Icon name={o.icon} size={16}/>
              </div>
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

      <Sheet open={!!detail} onClose={() => setDetail(null)}
        title={detail ? `${detail.name} preferences` : ''}>
        {detail && <ChannelDetail channel={detail}
          onDisconnect={() => { setChannels(cs => cs.filter(c => c.id !== detail.id)); setDetail(null); }}/>}
      </Sheet>
    </>
  );
}

function ChannelDetail({ channel, onDisconnect }) {
  const [prefs, setPrefs] = React.useState({
    briefing: true, checkin: true, swap: true,
    quietStart: '22:00', quietEnd: '06:00',
  });
  const Row = ({ k, label, sub }) => (
    <div className="af-row">
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 13 }}>{label}</div>
        {sub && <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{sub}</div>}
      </div>
      <div className="af-switch" data-on={prefs[k]}
        onClick={() => setPrefs(p => ({ ...p, [k]: !p[k] }))}/>
    </div>
  );
  return (
    <div>
      <div style={{ marginBottom: 8 }}>
        <Row k="briefing" label="Morning briefing" sub="Today's session at 6am"/>
        <Row k="checkin"  label="Evening check-in" sub="How did the workout feel?"/>
        <Row k="swap"     label="Swap suggestions" sub="When readiness drops"/>
      </div>
      <div className="af-label" style={{ marginBottom: 8, marginTop: 14 }}>QUIET HOURS</div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginBottom: 18 }}>
        <input className="af-input af-mono" value={prefs.quietStart}
          onChange={e => setPrefs(p => ({ ...p, quietStart: e.target.value }))}
          style={{ flex: 1, textAlign: 'center' }}/>
        <span className="af-muted">to</span>
        <input className="af-input af-mono" value={prefs.quietEnd}
          onChange={e => setPrefs(p => ({ ...p, quietEnd: e.target.value }))}
          style={{ flex: 1, textAlign: 'center' }}/>
      </div>
      <button onClick={onDisconnect}
        style={{ all: 'unset', cursor: 'pointer', width: '100%',
          padding: '12px', borderRadius: 999, textAlign: 'center',
          color: 'var(--destructive)', border: '1px solid var(--destructive)',
          fontSize: 13, fontWeight: 500, boxSizing: 'border-box' }}>
        Disconnect {channel.name}
      </button>
    </div>
  );
}

// -------------------------------------------------------- Library
function LibraryScreen({ state, nav, setState }) {
  const { tab } = state;
  const [empty, setEmpty] = React.useState(false);
  const [kinds, setKinds] = React.useState(['All']);
  const [tag, setTag] = React.useState('Running');

  const items = [
    { kind: 'Video', title: 'Threshold pacing for hybrid athletes',
      domain: 'youtube.com', tags: ['Running', 'HYROX prep'], thumb: 'video' },
    { kind: 'Article', title: 'How HRV-guided training reshapes a Hyrox block',
      domain: 'fastcrew.run', tags: ['Running', 'Recovery'], thumb: 'article' },
    { kind: 'Workout', title: 'Quick brick — 4×500m row + 10 thrusters',
      domain: 'amakaflow', tags: ['HYROX prep', 'Strength'], thumb: 'workout' },
    { kind: 'Plan', title: 'Sub-1:30 half marathon · 10 weeks',
      domain: 'runnersworld', tags: ['Running'], thumb: 'plan' },
    { kind: 'Video', title: 'Mobility before threshold day',
      domain: 'mobilitywod', tags: ['Recovery'], thumb: 'video' },
  ];

  const toggleKind = (k) => {
    if (k === 'All') return setKinds(['All']);
    setKinds(ks => {
      const without = ks.filter(x => x !== 'All' && x !== k);
      return ks.includes(k) ? (without.length ? without : ['All']) : [...without, k];
    });
  };

  const filtered = items.filter(it => {
    if (kinds.includes('All')) return true;
    return kinds.includes(it.kind);
  }).filter(it => !tag || tag === 'All' || it.tags.includes(tag));

  return (
    <>
      <div style={{ padding: '14px 18px 12px', display: 'flex',
        alignItems: 'center', justifyContent: 'space-between' }}>
        <div>
          <div className="af-h1" style={{ fontSize: 22 }}>Library</div>
          <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 2 }}>
            {empty ? 'EMPTY' : `${items.length} SAVED`}
          </div>
        </div>
        <div style={{ display: 'flex', gap: 6 }}>
          <button onClick={() => setEmpty(e => !e)}
            style={{ all: 'unset', cursor: 'pointer', width: 32, height: 32,
              borderRadius: 999, border: '1px solid var(--border-str)',
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="plus" size={14}/>
          </button>
          <button style={{ all: 'unset', cursor: 'pointer', width: 32, height: 32,
            borderRadius: 999, border: '1px solid var(--border-str)',
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="funnel" size={14}/>
          </button>
        </div>
      </div>

      {empty ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center',
          padding: '0 40px 40px', textAlign: 'center' }}>
          <div style={{ width: 64, height: 64, borderRadius: 16,
            background: 'var(--bg-subtle)', border: '1px solid var(--border)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: 'var(--fg-muted)', marginBottom: 18 }}>
            <Icon name="bookmark" size={28}/>
          </div>
          <div className="af-h2" style={{ fontSize: 17 }}>Save workouts and ideas as you find them</div>
          <div className="af-muted" style={{ fontSize: 12, marginTop: 10, lineHeight: 1.55 }}>
            Paste a link, share to AmakaFlow from any app, or save a coach suggestion.
          </div>
          <div style={{ marginTop: 22, width: '100%' }}>
            <Btn wide size="lg" onClick={() => setEmpty(false)}>
              <Icon name="link" size={14}/> Paste a link
            </Btn>
          </div>
        </div>
      ) : (
        <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
          padding: '0 18px 18px' }}>
          {/* Kind chips — multi */}
          <div style={{ display: 'flex', gap: 6, marginBottom: 8,
            overflowX: 'auto', paddingBottom: 4 }} className="af-scroll">
            {['All','Workouts','Videos','Articles','Plans'].map(k => {
              const on = kinds.includes(k);
              return (
                <Chip key={k} outline={!on} onClick={() => toggleKind(k)}
                  style={{ fontSize: 11, padding: '6px 11px', flexShrink: 0,
                    background: on ? 'var(--fg)' : 'transparent',
                    color: on ? 'var(--bg)' : 'var(--fg)',
                    borderColor: on ? 'var(--fg)' : 'var(--border-str)' }}>
                  {k}
                </Chip>
              );
            })}
          </div>
          {/* Tag chips — single */}
          <div style={{ display: 'flex', gap: 6, marginBottom: 14,
            overflowX: 'auto', paddingBottom: 4 }} className="af-scroll">
            {['All','Running','Strength','HYROX prep','Recovery'].map(t => {
              const on = tag === t || (t === 'All' && tag === 'All');
              return (
                <Chip key={t} outline={!on} onClick={() => setTag(t)}
                  style={{ fontSize: 10, padding: '5px 10px', flexShrink: 0,
                    background: on ? 'color-mix(in oklch, var(--ready-high), transparent 65%)' : 'transparent',
                    borderColor: on ? 'var(--ready-high)' : 'var(--border-str)' }}>
                  #{t}
                </Chip>
              );
            })}
          </div>

          {/* Saved items */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {filtered.map((it, i) => (
              <LibraryCard key={i} item={it}/>
            ))}
            {filtered.length === 0 && (
              <div style={{ padding: 32, textAlign: 'center',
                color: 'var(--fg-muted)', fontSize: 12 }}>
                Nothing matches those filters.
              </div>
            )}
          </div>
        </div>
      )}

      <TabBar active={tab} onChange={i => setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

function LibraryCard({ item }) {
  const thumbBg = {
    video:   'linear-gradient(135deg, oklch(0.65 0.18 25) 0%, oklch(0.45 0.16 25) 100%)',
    article: 'linear-gradient(135deg, oklch(0.65 0.10 230) 0%, oklch(0.40 0.08 230) 100%)',
    workout: 'linear-gradient(135deg, var(--ready-high) 0%, oklch(0.55 0.18 135) 100%)',
    plan:    'linear-gradient(135deg, oklch(0.72 0.13 85) 0%, oklch(0.45 0.13 85) 100%)',
  }[item.thumb];
  const glyph = {
    video: '▶', article: '◊', workout: '◆', plan: '☰',
  }[item.thumb];
  return (
    <Card style={{ padding: 0, overflow: 'hidden' }}>
      <div style={{ aspectRatio: '16/9', background: thumbBg,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#fff', fontSize: 42, fontWeight: 600,
        position: 'relative' }}>
        <span style={{ textShadow: '0 2px 12px rgba(0,0,0,0.2)' }}>{glyph}</span>
        <Chip style={{ position: 'absolute', top: 10, left: 10,
          fontSize: 9, background: 'rgba(0,0,0,0.5)', color: '#fff' }}>
          {item.kind.toUpperCase()}
        </Chip>
      </div>
      <div style={{ padding: '12px 14px' }}>
        <div style={{ fontSize: 13, fontWeight: 500, lineHeight: 1.35 }}>{item.title}</div>
        <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 4 }}>
          {item.domain.toUpperCase()}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6,
          marginTop: 10 }}>
          <div style={{ display: 'flex', gap: 5, flex: 1, flexWrap: 'wrap' }}>
            {item.tags.map(t => (
              <Chip key={t} outline style={{ fontSize: 9, padding: '2px 6px' }}>
                #{t}
              </Chip>
            ))}
          </div>
          <div style={{ color: 'var(--fg-muted)', cursor: 'pointer' }}>
            <Icon name="bookmark" size={14}
              style={{ fill: 'currentColor', stroke: 'none' }}/>
          </div>
          <div style={{ color: 'var(--fg-muted)', cursor: 'pointer' }}>
            <Icon name="kebab" size={14}/>
          </div>
        </div>
      </div>
    </Card>
  );
}

// -------------------------------------------------------- Coach tab
function CoachScreen({ state, nav, setState }) {
  const { tab } = state;
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
      copy: 'HRV dropped 18% — replaced today\'s tempo with a 30 min recovery walk.' },
  ];
  return (
    <>
      <TopBar title="Coach" sub="Briefings, check-ins, replans"
        right={<Icon name="sliders" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '0 20px 16px' }}>
        {/* Quick reply */}
        <Card style={{ padding: 14, marginBottom: 14,
          background: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
          borderColor: 'color-mix(in oklch, var(--ready-high), transparent 70%)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
            <span style={{ fontSize: 14 }}>💬</span>
            <span className="af-label">ASK YOUR COACH</span>
          </div>
          <div className="af-muted" style={{ fontSize: 12, lineHeight: 1.5, marginBottom: 10 }}>
            Reply any time. Swap a workout, ask why, log how you feel.
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {['Move today to Saturday', 'Why threshold?', 'I felt off'].map(s => (
              <Chip key={s} outline style={{ fontSize: 11, cursor: 'pointer',
                padding: '5px 9px' }}>{s}</Chip>
            ))}
          </div>
        </Card>

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
      <TabBar active={tab} onChange={i => setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

// -------------------------------------------------------- External-source detail
function DetailFromSourceScreen({ state, nav }) {
  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('workouts')}
        right={<Icon name="swap" size={18}/>}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        <div style={{ padding: '12px 14px',
          background: 'color-mix(in oklch, oklch(0.72 0.16 55), transparent 88%)',
          border: '1px solid color-mix(in oklch, oklch(0.72 0.16 55), transparent 65%)',
          borderRadius: 10, marginBottom: 14,
          display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 22, height: 22, borderRadius: 999,
            background: 'oklch(0.72 0.16 55)', color: '#fff',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 11, fontWeight: 700, fontFamily: 'var(--font-mono)' }}>S</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 12, fontWeight: 500 }}>From Stryd · Today's run · 1 hour</div>
            <div className="af-muted" style={{ fontSize: 10, marginTop: 1 }}>
              Powered by Stryd Pace Pilot
            </div>
          </div>
          <span style={{ fontSize: 11, color: 'oklch(0.55 0.16 55)',
            fontWeight: 500, cursor: 'pointer',
            textDecoration: 'underline' }}>Open in Stryd</span>
        </div>

        <div className="af-label">EASY POWER RUN · TUE</div>
        <div className="af-h1" style={{ marginTop: 6 }}>60 min @ 220–240W</div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 8, lineHeight: 1.5 }}>
          Sustain easy power band. Pace driven by Stryd footpod; HR is secondary. Targets pulled from your Stryd profile.
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
          gap: 10, margin: '18px 0', padding: '14px 0',
          borderTop: '1px solid var(--border)', borderBottom: '1px solid var(--border)' }}>
          {[['TIME','60m'],['POWER','230W'],['CP','278W'],['TSS','62']].map(([k,v]) => (
            <div key={k}>
              <div className="af-label">{k}</div>
              <div className="af-mono" style={{ fontSize: 15, fontWeight: 500, marginTop: 3 }}>{v}</div>
            </div>
          ))}
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)' }}>
        <Btn wide size="lg" onClick={() => nav('player')}>
          Start workout <Icon name="chevR" size={14}/>
        </Btn>
      </div>
    </>
  );
}

Object.assign(window, {
  SignupScreen, EquipmentScreen, MessagingScreen, LibraryScreen, CoachScreen,
  DetailFromSourceScreen,
  DemoFrame, DemoScene1, DemoScene2, DemoScene3, DemoScene4, DemoScene5,
});
