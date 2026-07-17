/**
 * Daily Driver rework — loop-first IA prototype screens. v3 "reference voice".
 * Visual brief from David's Gymdex + FitSaver screenshots (2026-07-09):
 * true black · one loud lime accent · Poppins-class rounded display type ·
 * glowing pill CTAs · media cards with creator credit · colorful icon chips ·
 * floating tab island with center ＋ FAB.
 * DISPOSABLE PROTOTYPE — validates IA + feel, not a visual commitment.
 */

const DD = {
  lime: 'var(--ready-high)',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', orange: '#F4A24A', purple: '#C58AF4', red: '#F4564A',
};

// ------------------------------------------------------------------ shared
function DDTabBar({ active, nav, set }) {
  const items = [
    { name: 'Today',   icon: 'sun',  to: 'dd-today' },
    { name: 'Library', icon: 'bookmark', to: 'dd-build' },
    { name: 'Profile', icon: 'user', to: 'dd-profile' },
  ];
  return (
    <>
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12, zIndex: 30,
        background: 'rgba(16,16,18,0.96)', border: '1px solid rgba(255,255,255,0.08)',
        borderRadius: 32, padding: '10px 8px 8px', display: 'flex',
        alignItems: 'center', backdropFilter: 'blur(14px)',
        boxShadow: '0 10px 30px rgba(0,0,0,.55)' }}>
        {items.map((it, i) => (
          <div key={it.name} onClick={() => nav(it.to)}
            style={{ flex: 1, display: 'flex', flexDirection: 'column',
              alignItems: 'center', gap: 3, cursor: 'pointer',
              color: i === active ? DD.lime : 'var(--fg-dim)' }}>
            <Icon name={it.icon} size={20}/>
            <span className="dd-display" style={{ fontSize: 10, fontWeight: 600 }}>
              {it.name}</span>
          </div>
        ))}
      </div>
      {/* Floating ＋ — add/import from anywhere */}
      <div className="dd-fab-glow"
        onClick={() => set(s => ({ ...s, createOpen: true }))}
        style={{ position: 'absolute', right: 18, bottom: 92, zIndex: 31,
          width: 56, height: 56, borderRadius: 999, background: DD.lime,
          color: DD.ink, display: 'flex', alignItems: 'center',
          justifyContent: 'center', cursor: 'pointer' }}>
        <Icon name="plus" size={25}/>
      </div>
    </>
  );
}

function ScreenPad({ children }) {
  return (
    <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
      padding: '6px 18px 96px' }}>{children}</div>
  );
}

function IconChip({ name, bg, size = 38 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: Math.round(size * 0.29),
      background: bg, color: '#fff', display: 'flex', alignItems: 'center',
      justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={name} size={Math.round(size * 0.47)}/>
    </div>
  );
}

// ------------------------------------------------------------------ Today
// A completed-only diary. NO scheduling, NO planned hero, NO Start here —
// the day fills itself from Strava/Garmin pulls, watch sessions and phone
// sessions as they finish. Timeline voice from David's reference (2026-07-10),
// not copied: our rail is honest-state-first (source + RPE debt on each card).
function DDTimelineCard({ icon, iconBg, time, title, stats, source, action, onOpen,
  label }) {
  return (
    <div style={{ display: 'flex', gap: 12 }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <div style={{ width: 34, height: 34, borderRadius: 999, background: iconBg,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0, zIndex: 2 }}>
          <Icon name={icon} size={15}/>
        </div>
        <div style={{ width: 2, flex: 1, background: 'var(--border)', marginTop: 4 }}/>
      </div>
      <div style={{ flex: 1, paddingBottom: title ? 18 : 22, minWidth: 0 }}>
        <div style={{ padding: '8px 0 8px', display: 'flex', alignItems: 'baseline',
          gap: 10 }}>
          <span className="af-mono" style={{ fontSize: 11, color: 'var(--fg-muted)',
            flexShrink: 0 }}>{time}</span>
          {label && <span className="af-mono" style={{ fontSize: 10,
            color: 'var(--fg-dim)', whiteSpace: 'nowrap', overflow: 'hidden',
            textOverflow: 'ellipsis' }}>{label}</span>}
        </div>
        {title && (
          <div style={{ background: DD.card, border: '1px solid var(--border)',
            borderRadius: 16, padding: '13px 14px' }}>
            <div onClick={onOpen} style={{ display: 'flex', alignItems: 'center',
              cursor: onOpen ? 'pointer' : 'default' }}>
              <div className="dd-display" style={{ fontSize: 15, fontWeight: 700,
                flex: 1 }}>{title}</div>
              {onOpen && <Icon name="chevR" size={15}
                style={{ color: 'var(--fg-dim)' }}/>}
            </div>
            {stats && <div className="af-mono" style={{ fontSize: 10.5, marginTop: 6,
              color: 'var(--fg-muted)', display: 'flex', gap: 12 }}>
              {stats.map(([ic, v]) => (
                <span key={v} style={{ display: 'inline-flex', alignItems: 'center',
                  gap: 4 }}><Icon name={ic} size={11}/>{v}</span>
              ))}
            </div>}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 10 }}>
              {source && <span className="af-mono" style={{ fontSize: 8.5,
                padding: '4px 9px', borderRadius: 999, background: DD.card2,
                color: 'var(--fg-muted)' }}>{source.toUpperCase()}</span>}
              <span style={{ marginLeft: 'auto' }}>{action}</span>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function DDTodayScreen({ dd, set, nav }) {
  const [rpeOpen, setRpeOpen] = React.useState(false);
  const [rpe, setRpe] = React.useState(null);
  const days = [['M', 7, true], ['T', 8, true], ['W', 9, true], ['T', 10, 'today'],
    ['F', 11, false], ['S', 12, false], ['S', 13, false]];
  const hyroxDone = dd.push === 'done' || dd.push === 'logged';

  return (
    <>
      <div style={{ padding: '8px 18px 6px', display: 'flex', alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>Today</div>
        <div onClick={() => nav('dd-device')} style={{ marginLeft: 'auto',
          display: 'flex', alignItems: 'center', gap: 6, cursor: 'pointer',
          background: DD.card, border: '1px solid var(--border)', borderRadius: 999,
          padding: '7px 12px' }}>
          <span className="af-dot af-dot-high" style={{ width: 6, height: 6 }}/>
          <Icon name="watch" size={13}/>
          <span className="af-mono" style={{ fontSize: 11, fontWeight: 600 }}>78%</span>
        </div>
      </div>

      {/* Day scrubber — dots = something happened that day */}
      <div style={{ display: 'flex', gap: 6, padding: '6px 18px 4px' }}>
        {days.map(([d, n, state], i) => (
          <div key={i} onClick={() => state && state !== 'today' &&
              set(s => ({ ...s, toast: `Jul ${n} — would open that day's diary` }))}
            style={{ flex: 1, textAlign: 'center', padding: '8px 0 7px',
              borderRadius: 12, cursor: state && state !== 'today' ? 'pointer' : 'default',
              background: state === 'today' ? DD.card2 : 'transparent',
              border: state === 'today' ? '1px solid var(--border-str)' : '1px solid transparent',
              opacity: state ? 1 : 0.4 }}>
            <div className="af-mono" style={{ fontSize: 9, color: 'var(--fg-muted)' }}>{d}</div>
            <div className="dd-display" style={{ fontSize: 13, fontWeight: 700,
              marginTop: 2 }}>{n}</div>
            <div style={{ width: 4, height: 4, borderRadius: 99, margin: '4px auto 0',
              background: state === 'today'
                ? (dd.runRPE || hyroxDone ? DD.lime : 'var(--fg-dim)')
                : state ? DD.lime : 'transparent' }}/>
          </div>
        ))}
      </div>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '14px 18px 96px' }}>
        {/* Tonight's phone/watch session appears once it exists */}
        {hyroxDone && (
          <DDTimelineCard icon="flame" iconBg={DD.lime} time="18:10 – 18:54"
            title="Hyrox Sim — Stations 1–4"
            stats={[['clock', '44M'], ['flame', '486 CAL'], ['heart', '151 BPM']]}
            source="Verified · T-Rex 3 + Strava"
            onOpen={() => { set(s => ({ ...s, activityId: 'matched' }));
              nav('dd-activity'); }}
            action={dd.push === 'logged'
              ? <span className="af-mono" style={{ fontSize: 10,
                  color: DD.lime }}>RPE 8 ✓</span>
              : <span className="dd-display"
                  onClick={() => set(s => ({ ...s, push: 'logged',
                    toast: 'Logged — RPE 8' }))}
                  style={{ fontSize: 12, fontWeight: 700, cursor: 'pointer',
                    color: 'var(--ready-mod)' }}>Log RPE</span>}/>
        )}

        <DDTimelineCard icon="run" iconBg={DD.blue} time="12:53 – 13:52"
          title="Lunch Run / 8.2 km"
          stats={[['clock', '59M'], ['flame', '677 CAL'], ['heart', '143 BPM']]}
          source="Imported from Strava"
          onOpen={() => { set(s => ({ ...s, activityId: 'run' }));
            nav('dd-activity'); }}
          action={dd.runRPE
            ? <span className="af-mono" style={{ fontSize: 10,
                color: DD.lime }}>RPE {dd.runRPE} ✓</span>
            : <span className="dd-display" onClick={() => setRpeOpen(true)}
                style={{ fontSize: 12, fontWeight: 700, cursor: 'pointer',
                  color: 'var(--ready-mod)' }}>Log RPE</span>}/>

        <DDTimelineCard icon="lift" iconBg={DD.card2} time="12:44 – 12:52"
          title="Lunch Workout"
          stats={[['clock', '8M'], ['flame', '50 CAL']]}
          source="Imported from Strava"
          onOpen={() => { set(s => ({ ...s, activityId: 'blank' }));
            nav('dd-activity'); }}
          action={<span className="dd-display"
            onClick={() => { set(s => ({ ...s, activityId: 'blank' }));
              nav('dd-activity'); }}
            style={{ fontSize: 12, fontWeight: 700, cursor: 'pointer',
              color: 'var(--ready-mod)' }}>What was this?</span>}/>

        <DDTimelineCard icon="watch" iconBg={DD.card2} time="07:41"
          title={null} label="GARMIN SYNCED · 2 ACTIVITIES PULLED"/>

        <DDTimelineCard icon="sun" iconBg={DD.card2} time="06:58"
          title={null} label="DAY STARTED"/>

        {!hyroxDone && (
          <div style={{ marginTop: 26, textAlign: 'center' }}>
            <div style={{ fontSize: 12, color: 'var(--fg-dim)' }}>
              Sessions land here as they happen — or add one with ＋
            </div>
          </div>
        )}
      </div>

      <DDTabBar active={0} nav={nav} set={set}/>

      <Sheet open={rpeOpen} onClose={() => setRpeOpen(false)} title="Lunch Run — RPE">
        <div className="af-rpe-grid" style={{ marginBottom: 16 }}>
          {Array.from({ length: 10 }, (_, i) => i + 1).map(n => (
            <button key={n} className="af-rpe" data-sel={rpe === n}
              onClick={() => setRpe(n)}>{n}</button>
          ))}
        </div>
        <Btn wide onClick={() => { setRpeOpen(false);
          set(s => ({ ...s, runRPE: rpe, toast: `Logged — RPE ${rpe}` })); }}
          disabled={!rpe}>Save</Btn>
      </Sheet>

      <CreateSheet dd={dd} set={set} nav={nav}/>
      <StartSheet dd={dd} set={set} nav={nav}/>
    </>
  );
}

// ------------------------------------------------------------------ Create sheet (4 doors)
// Import-from-URL gets a real processing state: paste step → animated parse
// (spinning lime ring, cycling step text, progress bar) → lands on dd-detail.
function CreateSheet({ dd, set, nav }) {
  const [phase, setPhase] = React.useState('doors'); // doors | url | processing
  const [step, setStep] = React.useState(0);
  const steps = ['Fetching your link…', 'Reading caption & video…',
    'Extracting exercises & sets…', 'Building your workout…'];
  const reset = () => { setPhase('doors'); setStep(0); };
  const close = () => { set(s => ({ ...s, createOpen: false })); reset(); };

  React.useEffect(() => {
    if (phase !== 'processing') return;
    if (step >= steps.length - 1) {
      const t = setTimeout(() => {
        set(s => ({ ...s, createOpen: false,
          toast: 'Imported ✓ — review & save', detailId: 'amrap' }));
        reset();
        nav('dd-detail');
      }, 900);
      return () => clearTimeout(t);
    }
    const t = setTimeout(() => setStep(n => n + 1), 850);
    return () => clearTimeout(t);
  }, [phase, step]);

  const door = (label, delay) => () => {
    set(s => ({ ...s, createOpen: false, toast: label, detailId: 'amrap' }));
    setTimeout(() => nav('dd-detail'), delay);
  };
  const doors = [
    { icon: 'link', bg: DD.lime, ink: DD.ink, t: 'Import from URL',
      d: 'Instagram, TikTok, or YouTube', go: () => setPhase('url') },
    { icon: 'camera', bg: DD.purple, t: 'Screenshot',
      d: 'Photo of a workout → draft', go: door('Reading your screenshot…', 1400) },
    { icon: 'mic', bg: DD.blue, t: 'Speak or describe it',
      d: 'Coach turns it into a draft', go: door('Coach is drafting…', 1500) },
    { icon: 'edit', bg: DD.card2, t: 'Create manually',
      d: 'From scratch, exercise by exercise',
      go: () => { set(s => ({ ...s, createOpen: false })); nav('dd-editor-new'); } },
  ];
  if (phase === 'url') return (
    <Sheet open={dd.createOpen} onClose={close} title="Import from URL">
      <div style={{ display: 'flex', alignItems: 'center', gap: 11,
        background: DD.card, border: '1px solid var(--border)',
        borderRadius: 999, padding: '12px 16px', marginBottom: 8,
        color: 'var(--fg-muted)' }}>
        <Icon name="link" size={15}/>
        <span style={{ flex: 1, fontSize: 12.5, whiteSpace: 'nowrap',
          overflow: 'hidden', textOverflow: 'ellipsis' }}>
          instagram.com/reel/dY3kQzT…</span>
        <span className="dd-display" style={{ fontSize: 11, fontWeight: 700,
          color: DD.lime, cursor: 'pointer' }}>Paste</span>
      </div>
      <div style={{ fontSize: 10.5, color: 'var(--fg-dim)', marginBottom: 16,
        padding: '0 4px' }}>
        Instagram, TikTok, or YouTube — we pull the workout out of the post.
      </div>
      <Btn wide onClick={() => setPhase('processing')}>Import workout</Btn>
    </Sheet>
  );

  if (phase === 'processing') return (
    <Sheet open={dd.createOpen} onClose={close} title="Importing…">
      <div style={{ textAlign: 'center', padding: '22px 6px 8px' }}>
        {/* pulsing link icon inside a spinning lime arc */}
        <div style={{ position: 'relative', width: 84, height: 84,
          margin: '0 auto 18px' }}>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 999,
            border: '2.5px solid rgba(255,255,255,0.08)' }}/>
          <div style={{ position: 'absolute', inset: 0, borderRadius: 999,
            border: '2.5px solid transparent', borderTopColor: DD.lime,
            animation: 'dd-spin .9s linear infinite' }}/>
          <div style={{ position: 'absolute', inset: 15, borderRadius: 999,
            background: DD.lime, color: DD.ink, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            animation: 'dd-pulse 1.6s ease-in-out infinite' }}>
            <Icon name="link" size={22}/>
          </div>
        </div>
        <div key={step} className="dd-display" style={{ fontSize: 15,
          fontWeight: 700, animation: 'dd-step-in .35s cubic-bezier(.2,.8,.2,1)' }}>
          {steps[step]}</div>
        <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 4 }}>
          instagram.com/reel/dY3kQzT…</div>
        <div style={{ height: 4, borderRadius: 999,
          background: 'rgba(255,255,255,0.08)', margin: '18px 8px 8px',
          overflow: 'hidden' }}>
          <div style={{ height: '100%', borderRadius: 999, background: DD.lime,
            width: `${((step + 1) / steps.length) * 100}%`,
            transition: 'width .6s cubic-bezier(.2,.8,.2,1)',
            boxShadow: '0 0 12px color-mix(in oklch, var(--ready-high), transparent 40%)' }}/>
        </div>
        <div className="af-mono" style={{ fontSize: 9.5, color: 'var(--fg-dim)' }}>
          STEP {step + 1} OF {steps.length}</div>
      </div>
    </Sheet>
  );

  return (
    <Sheet open={dd.createOpen} onClose={close}
      title="Add workout">
      {doors.map((o) => (
        <div key={o.t} onClick={o.go}
          style={{ display: 'flex', alignItems: 'center', gap: 14,
            background: DD.card, border: '1px solid var(--border)',
            borderRadius: 999, padding: '12px 16px', marginBottom: 10,
            cursor: 'pointer' }}>
          <div style={{ width: 36, height: 36, borderRadius: 999, background: o.bg,
            color: o.ink || '#fff', display: 'flex', alignItems: 'center',
            justifyContent: 'center' }}>
            <Icon name={o.icon} size={17}/>
          </div>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 14.5, fontWeight: 700 }}>{o.t}</div>
            <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 1 }}>{o.d}</div>
          </div>
        </div>
      ))}
      <div style={{ fontSize: 11, color: 'var(--fg-muted)', lineHeight: 1.5,
        padding: '2px 4px 0' }}>
        Every door lands in the same editor — always editable, always saveable.
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ Start sheet
// THE single start flow: every workout starts here. Pick WHERE you are
// (gym — equipment swaps adapt to it) and ON WHAT (phone or a watch).
// No pre-baked destinations on cards; defaults come from Settings.
function StartSheet({ dd, set, nav }) {
  const [gym, setGym] = React.useState('Home gym');
  const gyms = ['Home gym', '24hr Katy', 'Hotel'];
  const close = () => set(s => ({ ...s, startOpen: false }));
  const onPhone = () => { close(); nav('dd-player'); };
  const onTrex = () => {
    close();
    set(s => ({ ...s, push: 'pushing' }));
    setTimeout(() => set(s => ({ ...s, push: 'onwatch',
      toast: 'On your T-Rex 3 ✓' })), 1400);
  };
  const onGarmin = () => { close();
    set(s => ({ ...s, toast: 'Sent to Garmin via FIT ✓' })); };
  const dev = (icon, bg, t, d, fn, tag) => (
    <div onClick={fn} style={{ display: 'flex', alignItems: 'center', gap: 13,
      background: DD.card, border: '1px solid var(--border)', borderRadius: 999,
      padding: '11px 15px', marginBottom: 9, cursor: 'pointer' }}>
      <div style={{ width: 34, height: 34, borderRadius: 999, background: bg,
        color: bg === DD.lime ? DD.ink : '#fff', display: 'flex',
        alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={16}/>
      </div>
      <div style={{ flex: 1 }}>
        <div className="dd-display" style={{ fontSize: 14, fontWeight: 700 }}>{t}</div>
        <div style={{ fontSize: 10.5, color: 'var(--fg-muted)', marginTop: 1 }}>{d}</div>
      </div>
      {tag && <span className="af-mono" style={{ fontSize: 8.5,
        color: DD.lime }}>{tag}</span>}
    </div>
  );
  return (
    <Sheet open={!!dd.startOpen} onClose={close} title="Start session">
      <div className="af-mono" style={{ fontSize: 10, color: 'var(--fg-muted)',
        marginBottom: 8 }}>WHERE ARE YOU?</div>
      <div style={{ display: 'flex', gap: 7, marginBottom: 6, flexWrap: 'wrap' }}>
        {gyms.map(g => (
          <span key={g} className="dd-display" onClick={() => setGym(g)}
            style={{ padding: '9px 15px', borderRadius: 999, fontSize: 12.5,
              fontWeight: 600, cursor: 'pointer',
              background: gym === g ? DD.lime : DD.card,
              color: gym === g ? DD.ink : 'var(--fg-muted)',
              border: gym === g ? 'none' : '1px solid var(--border)' }}>{g}</span>
        ))}
      </div>
      <div style={{ fontSize: 10.5, color: gym === 'Home gym'
          ? 'var(--ready-mod)' : 'var(--fg-dim)', marginBottom: 16 }}>
        {gym === 'Home gym'
          ? '2 swaps applied — no barbell, no sled here'
          : 'All exercises fit — no swaps needed'}
      </div>
      <div className="af-mono" style={{ fontSize: 10, color: 'var(--fg-muted)',
        marginBottom: 8 }}>ON WHAT?</div>
      {dev('msg', DD.card2, 'This phone', 'Follow-along player · always works', onPhone)}
      {dev('watch', DD.lime, 'Amazfit T-Rex 3', 'Synced 2m · 78%', onTrex, 'DEFAULT · HIIT')}
      {dev('watch', DD.blue, 'Garmin', 'Push via FIT', onGarmin)}
      <div style={{ fontSize: 10, color: 'var(--fg-dim)', marginTop: 4 }}>
        Defaults come from Settings › Connected wearables.
      </div>
    </Sheet>
  );
}

// ------------------------------------------------------------------ Library (ported from amakaflow-ui unified workouts)
// The web app's Workouts page: search + WorkoutFilterBar (filter by source
// type / platform) over a unified list. Every saved workout wears its
// provenance: Instagram, TikTok, Manual, Coach, AI, Device sync.
// Creation is SEPARATE — the ＋ FAB (Add sheet) or header ＋.
const DD_PLATFORM = {
  INSTAGRAM: { c: '#C58AF4', icon: 'camera' },
  TIKTOK:    { c: '#4AD9D9', icon: 'play'   },
  YOUTUBE:   { c: '#F4564A', icon: 'play'   },
  MANUAL:    { c: 'rgba(255,255,255,0.45)', icon: 'edit' },
  COACH:     { c: '#F4A24A', icon: 'user'   },
  AI:        { c: '#5AB8F4', icon: 'sparkle' },
  GARMIN:    { c: '#5AB8F4', icon: 'watch'  },
};

function DDBuildScreen({ dd, set, nav }) {
  const [q, setQ] = React.useState('');
  const [pill, setPill] = React.useState('All');
  const lib = [
    { id: 'hyrox', t: 'Hyrox Sim — Stations 1–4', by: 'you',
      grad: ['#2A3505', '#0f1202'], icon: 'flame',
      meta: '8 blocks · 45 min', src: 'MANUAL' },
    { id: 'amrap', t: 'DB Full-body AMRAP', by: 'gospelofgainz',
      grad: ['#3A1145', '#12041a'], icon: 'bolt',
      meta: '5 rounds · 20 min', src: 'INSTAGRAM' },
    { id: 'glute', t: 'Glute-Focused Lower Body', by: 'lindkvistfeliciaa',
      grad: ['#0d3830', '#04140f'], icon: 'lift',
      meta: '4 exercises · 35 min', src: 'TIKTOK' },
    { id: 'run', t: 'Zone 2 base run', by: 'you',
      grad: ['#0d2438', '#050d14'], icon: 'run',
      meta: '48 min · HR cap 148', src: 'MANUAL' },
    { id: 'lower', t: 'Lower body — posterior', by: 'Coach Mike',
      grad: ['#33240a', '#120c03'], icon: 'lift',
      meta: '6 exercises · 52 min', src: 'COACH' },
    { id: 'hyrox', t: 'Engine builder — 30 min', by: 'AmakaFlow AI',
      grad: ['#101c30', '#060a12'], icon: 'sparkle',
      meta: 'EMOM · 30 min', src: 'AI' },
  ];
  const pills = ['All', 'Instagram', 'TikTok', 'Manual', 'Coach', 'AI'];
  const shown = lib.filter(w =>
    (pill === 'All' || w.src === pill.toUpperCase()) &&
    (!q || w.t.toLowerCase().includes(q.toLowerCase())
      || w.by.toLowerCase().includes(q.toLowerCase())));

  return (
    <>
      <div style={{ padding: '8px 18px 4px', display: 'flex', alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>Library</div>
        <div onClick={() => set(s => ({ ...s, createOpen: true }))}
          style={{ marginLeft: 'auto', width: 38, height: 38, borderRadius: 999,
            background: DD.lime, color: DD.ink, display: 'flex',
            alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
          <Icon name="plus" size={19}/>
        </div>
      </div>

      <ScreenPad>
        <input className="af-input" placeholder="Search workouts, creators..."
          value={q} onChange={(e) => setQ(e.target.value)}
          style={{ marginTop: 8, borderRadius: 999, padding: '11px 16px' }}/>

        {/* Source filter — the WorkoutFilterBar, pillified */}
        <div style={{ display: 'flex', gap: 7, marginTop: 10, flexWrap: 'nowrap',
          overflowX: 'auto', paddingBottom: 2 }} className="af-scroll">
          {pills.map(p => (
            <span key={p} className="dd-display" onClick={() => setPill(p)}
              style={{ padding: '8px 15px', borderRadius: 999, fontSize: 12.5,
                fontWeight: 600, whiteSpace: 'nowrap', cursor: 'pointer',
                background: pill === p ? DD.lime : DD.card,
                color: pill === p ? DD.ink : 'var(--fg-muted)',
                border: pill === p ? 'none' : '1px solid var(--border)' }}>
              {p}</span>
          ))}
        </div>

        {/* Unified list — every row says where it came from */}
        <div style={{ marginTop: 14 }}>
          {shown.map((w, i) => {
            const P = DD_PLATFORM[w.src];
            return (
              <div key={i} onClick={() => { set(s => ({ ...s, detailId: w.id }));
                  nav('dd-detail'); }}
                style={{ display: 'flex', alignItems: 'center', gap: 12,
                  background: DD.card, border: '1px solid var(--border)',
                  borderRadius: 16, padding: 10, marginBottom: 9,
                  cursor: 'pointer' }}>
                <div style={{ width: 56, height: 56, borderRadius: 12,
                  background: `linear-gradient(145deg, ${w.grad[0]}, ${w.grad[1]})`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  flexShrink: 0 }}>
                  <Icon name={w.icon} size={22} style={{ opacity: 0.9 }}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div className="dd-display" style={{ fontSize: 13.5,
                    fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden',
                    textOverflow: 'ellipsis' }}>{w.t}</div>
                  <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
                    marginTop: 3 }}>{w.meta} · by {w.by}</div>
                  <span className="af-mono" style={{ display: 'inline-flex',
                    alignItems: 'center', gap: 4, marginTop: 6, fontSize: 8,
                    fontWeight: 700, padding: '3px 8px', borderRadius: 999,
                    background: `color-mix(in srgb, ${P.c}, transparent 84%)`,
                    color: P.c }}>
                    <Icon name={P.icon} size={9}/> {w.src}</span>
                </div>
                <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
              </div>
            );
          })}
          {shown.length === 0 && (
            <div style={{ textAlign: 'center', padding: '30px 0', fontSize: 12,
              color: 'var(--fg-dim)' }}>
              Nothing matches — clear the filter or import something new with ＋
            </div>
          )}
        </div>
      </ScreenPad>
      <DDTabBar active={1} nav={nav} set={set}/>
      <CreateSheet dd={dd} set={set} nav={nav}/>
    </>
  );
}

// ------------------------------------------------------------------ Builder (ported from amakaflow-ui StructureWorkout)
// Mobile port of the CANONICAL web builder (src/app/WorkflowView.tsx →
// StructureWorkout + useStructureWorkout): single-column accordion of
// structure blocks, "What type of block?" chip picker, per-structure
// config steppers (getStructureDefaults preserved verbatim), tabbed
// exercise editor (Sets/Reps · Duration · Distance · Calories) with
// timed/lap-button rest. Reorder via chevrons (mobile stand-in for dnd-kit).
const DD_STRUCTURES = {
  circuit:   { label: 'Circuit',   emoji: '🟢', color: '#4AD97F',
    defaults: { rounds: 3, rest_between_rounds_sec: 90 } },
  emom:      { label: 'EMOM',      emoji: '🔵', color: '#5AB8F4',
    defaults: { rounds: 10, time_cap_sec: 1200 } },
  amrap:     { label: 'AMRAP',     emoji: '🟠', color: '#F4A24A',
    defaults: { time_cap_sec: 600 } },
  tabata:    { label: 'Tabata',    emoji: '🔴', color: '#F4564A',
    defaults: { rounds: 8, time_work_sec: 20, time_rest_sec: 10 } },
  'for-time': { label: 'For Time', emoji: '🟣', color: '#C58AF4',
    defaults: { time_cap_sec: 1800 } },
  sets:      { label: 'Sets',      emoji: '⚫', color: 'rgba(255,255,255,0.35)',
    defaults: { sets: 4, rest_between_sets_sec: 120 } },
  superset:  { label: 'Superset',  emoji: '🟡', color: 'var(--ready-mod)',
    defaults: { rounds: 3, rest_between_rounds_sec: 60 } },
  rounds:    { label: 'Rounds',    emoji: '🟢', color: '#4AD97F',
    defaults: { rounds: 3, rest_between_rounds_sec: 60 } },
  warmup:    { label: 'Warm-up',   emoji: '⬜', color: '#8890A0',
    defaults: { warmup_duration_sec: 300, warmup_activity: 'Stretching' } },
  cooldown:  { label: 'Cool-down', emoji: '⬜', color: '#8890A0',
    defaults: { warmup_duration_sec: 300, warmup_activity: 'Stretching' } },
};
const DD_ACTIVITIES_WU = ['Stretching', 'Jump Rope', 'Air Bike', 'Treadmill',
  'Stairmaster', 'Rowing', 'Custom'];

function ddFmtSec(s) {
  if (s == null) return '—';
  if (s === 0) return 'No cap';
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60), r = s % 60;
  return r ? `${m}m ${r}s` : `${m} min`;
}
function ddKeyMetric(b) {
  const S = b.structure;
  if (S === 'tabata') return `${b.time_work_sec}s on · ${b.time_rest_sec}s off · ${b.rounds} rounds`;
  if (S === 'emom') return `${b.rounds} rounds · ${ddFmtSec(b.time_cap_sec)}`;
  if (S === 'amrap') return `Cap ${ddFmtSec(b.time_cap_sec)}`;
  if (S === 'for-time') return `Cap ${ddFmtSec(b.time_cap_sec)}`;
  if (S === 'sets' || S === 'regular') return `${b.sets} sets · ${ddFmtSec(b.rest_between_sets_sec)} rest`;
  if (S === 'superset') return `${b.rounds} rounds · ${ddFmtSec(b.rest_between_rounds_sec)} after pair`;
  if (S === 'warmup' || S === 'cooldown') return `${ddFmtSec(b.warmup_duration_sec)} · ${b.warmup_activity}`;
  if (b.rounds) return `${b.rounds} rounds · ${ddFmtSec(b.rest_between_rounds_sec)} rest/round`;
  return null;
}
function ddExSummary(e) {
  const p = [];
  if (e.sets) p.push(`${e.sets} sets`);
  if (e.reps_range) p.push(`${e.reps_range} reps`);
  else if (e.reps) p.push(`${e.reps} reps`);
  if (e.duration_sec) p.push(ddFmtSec(e.duration_sec));
  if (e.distance_m) p.push(`${e.distance_m} m`);
  if (e.calories) p.push(`${e.calories} cal`);
  if (e.weight) p.push(`${e.weight} kg`);
  if (e.rest_sec != null) p.push(e.rest_type === 'button' ? 'rest: lap ▸' : `rest ${e.rest_sec}s`);
  return p.join(' · ');
}

// Small −/＋ stepper (mobile stand-in for BlockConfigRow's Stepper)
function DDStepper({ label, value, onChange, min = 0, max = 999, step = 1, fmt }) {
  const bump = (d) => onChange(Math.min(max, Math.max(min, (value || 0) + d * step)));
  return (
    <div style={{ flex: 1, minWidth: 96, background: DD.card2, borderRadius: 12,
      padding: '8px 10px' }}>
      <div className="af-mono" style={{ fontSize: 8.5, color: 'var(--fg-muted)' }}>
        {label.toUpperCase()}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
        <span onClick={() => bump(-1)} style={{ cursor: 'pointer', fontSize: 16,
          fontWeight: 700, color: 'var(--fg-muted)', padding: '0 4px' }}>−</span>
        <span className="af-mono" style={{ flex: 1, textAlign: 'center',
          fontSize: 13.5, fontWeight: 600 }}>{fmt ? fmt(value) : value}</span>
        <span onClick={() => bump(1)} style={{ cursor: 'pointer', fontSize: 16,
          fontWeight: 700, color: 'var(--fg-muted)', padding: '0 4px' }}>＋</span>
      </div>
    </div>
  );
}

// Per-structure config fields (BlockConfigRow port)
function DDBlockConfig({ b, up }) {
  const S = b.structure;
  const rows = [];
  if (S === 'circuit' || S === 'rounds')
    rows.push(['Rounds', 'rounds', 1, 99, 1, null],
      ['Rest / round', 'rest_between_rounds_sec', 0, 600, 5, ddFmtSec]);
  else if (S === 'emom')
    rows.push(['Rounds', 'rounds', 1, 99, 1, null],
      ['Time cap', 'time_cap_sec', 60, 7200, 60, ddFmtSec]);
  else if (S === 'amrap')
    rows.push(['Time cap', 'time_cap_sec', 60, 3600, 60, ddFmtSec]);
  else if (S === 'tabata')
    rows.push(['Work', 'time_work_sec', 5, 300, 5, ddFmtSec],
      ['Rest', 'time_rest_sec', 0, 300, 5, ddFmtSec],
      ['Rounds', 'rounds', 1, 40, 1, null]);
  else if (S === 'for-time')
    rows.push(['Time cap (opt)', 'time_cap_sec', 0, 7200, 60, ddFmtSec]);
  else if (S === 'sets' || S === 'regular')
    rows.push(['Sets', 'sets', 1, 20, 1, null],
      ['Rest / set', 'rest_between_sets_sec', 0, 600, 5, ddFmtSec]);
  else if (S === 'superset')
    rows.push(['Rounds', 'rounds', 1, 20, 1, null],
      ['Rest after pair', 'rest_between_rounds_sec', 0, 600, 5, ddFmtSec]);
  else if (S === 'warmup' || S === 'cooldown')
    rows.push(['Duration', 'warmup_duration_sec', 60, 3600, 60, ddFmtSec]);
  return (
    <div style={{ marginTop: 10 }}>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        {rows.map(([lab, key, mn, mx, st, fmt]) => (
          <DDStepper key={key} label={lab} value={b[key]} min={mn} max={mx}
            step={st} fmt={fmt} onChange={(v) => up({ [key]: v })}/>
        ))}
        {(S === 'warmup' || S === 'cooldown') && (
          <div onClick={() => {
              const i = DD_ACTIVITIES_WU.indexOf(b.warmup_activity);
              up({ warmup_activity: DD_ACTIVITIES_WU[(i + 1) % DD_ACTIVITIES_WU.length] });
            }}
            style={{ flex: 1, minWidth: 96, background: DD.card2, borderRadius: 12,
              padding: '8px 10px', cursor: 'pointer' }}>
            <div className="af-mono" style={{ fontSize: 8.5,
              color: 'var(--fg-muted)' }}>ACTIVITY</div>
            <div style={{ fontSize: 13, fontWeight: 600, marginTop: 6,
              textAlign: 'center' }}>{b.warmup_activity} ▸</div>
          </div>
        )}
      </div>
    </div>
  );
}

// ------------------------------------------------------------------ Editor
function DDEditorScreen({ dd, set, nav, mode }) {
  const mkEx = (n, over) => ({ n, sets: 3, reps: 10, reps_range: null,
    duration_sec: null, distance_m: null, calories: null, weight: null,
    rest_sec: 60, rest_type: 'timed', notes: '', ...over });
  const initBlocks = mode === 'new' ? [] : mode === 'backfill' ? [
    { structure: 'sets', label: 'Main lifts', sets: 3, rest_between_sets_sec: 120,
      open: true, ex: [
        mkEx('Back squat', { sets: 3, reps: 5, weight: 85, ghost: true }),
        mkEx('Romanian deadlift', { sets: 3, reps: 8, weight: 70, ghost: true }),
        mkEx('Split squat', { sets: 2, reps: 10, weight: 20, ghost: true }),
      ]},
  ] : mode === 'import' ? [
    { structure: 'amrap', label: 'AMRAP', time_cap_sec: 600, open: true, ex: [
        mkEx('Wall balls', { sets: null, reps: 20, rest_sec: null }),
        mkEx('Barbell thrusters', { sets: null, reps: 12, weight: 40, rest_sec: null,
          flag: 'No barbell — swap to DB thrusters 2×16?',
          swapTo: { n: 'DB thrusters', weight: 16 } }),
        mkEx('Burpee broad jumps', { sets: null, reps: 10, rest_sec: null }),
      ]},
    { structure: 'for-time', label: 'Finisher', time_cap_sec: 240, open: false, ex: [
        mkEx('Sled push', { sets: null, reps: null, distance_m: 40, rest_sec: null,
          flag: 'No sled — swap to heavy farmer carry?',
          swapTo: { n: 'Heavy farmer carry', distance_m: 60 } }),
      ]},
  ] : [
    { structure: 'circuit', label: 'Stations 1–4', rounds: 2,
      rest_between_rounds_sec: 90, open: true, ex: [
        mkEx('SkiErg', { sets: null, reps: null, distance_m: 250, rest_sec: 30 }),
        mkEx('Sled push', { sets: null, reps: null, distance_m: 40, weight: 80,
          rest_sec: 30 }),
        mkEx('Burpee broad jumps', { sets: null, reps: 10, rest_sec: 30 }),
        mkEx('Rower', { sets: null, reps: null, distance_m: 500, rest_sec: 60 }),
      ]},
    { structure: 'rounds', label: 'Run intervals', rounds: 4,
      rest_between_rounds_sec: 60, open: false, ex: [
        mkEx('Run', { sets: null, reps: null, distance_m: 400, rest_sec: null }),
      ]},
  ];
  const [title, setTitle] = React.useState(mode === 'new' ? ''
    : mode === 'backfill' ? 'Lower body — posterior'
    : mode === 'import' ? 'DB Full-body AMRAP' : 'Hyrox Sim — Stations 1–4');
  const [blocks, setBlocks] = React.useState(initBlocks);
  const [pickerOpen, setPickerOpen] = React.useState(mode === 'new');
  const [configIdx, setConfigIdx] = React.useState(null);
  const [exSheet, setExSheet] = React.useState(null); // {bi, ei} | {bi, add:true}
  const flags = blocks.reduce((n, b) => n + b.ex.filter(e => e.flag).length, 0);

  const upBlock = (i, patch) => setBlocks(bs => bs.map((b, j) =>
    j === i ? { ...b, ...patch } : b));
  const delBlock = (i) => setBlocks(bs => bs.filter((_, j) => j !== i));
  const moveBlock = (i, d) => setBlocks(bs => {
    const t = i + d; if (t < 0 || t >= bs.length) return bs;
    const c = [...bs]; [c[i], c[t]] = [c[t], c[i]]; return c;
  });
  const addBlock = (key) => {
    const s = DD_STRUCTURES[key];
    setBlocks(bs => [...bs, { structure: key, label: s.label,
      ...s.defaults, open: true, ex: [] }]);
    setPickerOpen(false);
  };
  const upEx = (bi, ei, patch) => setBlocks(bs => bs.map((b, j) => j === bi
    ? { ...b, ex: b.ex.map((e, k) => k === ei ? { ...e, ...patch } : e) } : b));
  const delEx = (bi, ei) => setBlocks(bs => bs.map((b, j) => j === bi
    ? { ...b, ex: b.ex.filter((_, k) => k !== ei) } : b));
  const moveEx = (bi, ei, d) => setBlocks(bs => bs.map((b, j) => {
    if (j !== bi) return b;
    const t = ei + d; if (t < 0 || t >= b.ex.length) return b;
    const c = [...b.ex]; [c[ei], c[t]] = [c[t], c[ei]];
    return { ...b, ex: c };
  }));
  const addEx = (bi, name) => {
    // web parity: addExercise defaults {sets:3, reps:10, rest_sec:60}
    setBlocks(bs => bs.map((b, j) => j === bi
      ? { ...b, ex: [...b.ex, mkEx(name)] } : b));
    setExSheet(null);
  };
  const collapseAll = (open) => setBlocks(bs => bs.map(b => ({ ...b, open })));

  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div onClick={() => nav(mode === 'backfill' ? 'dd-profile' : 'dd-build')}
            style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
              color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
              cursor: 'pointer' }}>
            <Icon name="chevL" size={16}/> Back
          </div>
          <div style={{ marginLeft: 'auto', display: 'flex', gap: 14 }}>
            <span className="af-mono" onClick={() => collapseAll(false)}
              style={{ fontSize: 10, color: 'var(--fg-muted)',
                cursor: 'pointer' }}>COLLAPSE ALL</span>
            <span className="af-mono" onClick={() => collapseAll(true)}
              style={{ fontSize: 10, color: 'var(--fg-muted)',
                cursor: 'pointer' }}>EXPAND ALL</span>
          </div>
        </div>
        <input value={title} onChange={(e) => setTitle(e.target.value)}
          placeholder="Workout title"
          className="dd-display"
          style={{ all: 'unset', display: 'block', width: '100%', fontSize: 24,
            fontWeight: 800, marginTop: 10, fontFamily: 'Poppins, Geist, sans-serif',
            letterSpacing: '-0.02em', color: 'var(--fg)' }}/>
        <div className="af-mono" style={{ fontSize: 9.5, marginTop: 6,
          color: flags ? 'var(--ready-mod)' : 'var(--fg-dim)' }}>
          {flags ? `⚠ ${flags} SWAP SUGGESTIONS` : 'DEFAULT REST 60S · APPLIED UNLESS OVERRIDDEN'}
        </div>
      </div>

      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 120px' }}>
        {blocks.length === 0 && !pickerOpen && (
          <div style={{ textAlign: 'center', padding: '40px 0', fontSize: 12.5,
            color: 'var(--fg-dim)' }}>
            Add your first block to start building
          </div>
        )}

        {blocks.map((b, bi) => {
          const S = DD_STRUCTURES[b.structure] || DD_STRUCTURES.sets;
          return (
            <div key={bi} style={{ background: DD.card,
              border: '1px solid var(--border)',
              borderLeft: `3px solid ${S.color}`, borderRadius: 16,
              marginBottom: 10, overflow: 'hidden' }}>
              {/* Block header */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 8,
                padding: '11px 12px' }}>
                <div style={{ display: 'flex', flexDirection: 'column',
                  color: 'var(--fg-dim)', marginRight: 2 }}>
                  <div onClick={() => moveBlock(bi, -1)}
                    style={{ cursor: 'pointer', padding: 1 }}>
                    <Icon name="chevU" size={11}/></div>
                  <div onClick={() => moveBlock(bi, 1)}
                    style={{ cursor: 'pointer', padding: 1 }}>
                    <Icon name="chevD" size={11}/></div>
                </div>
                <span onClick={() => { setConfigIdx(null);
                    set(s => ({ ...s, toast: 'Structure — change via ＋ Add block for now' })); }}
                  className="af-mono" style={{ fontSize: 9, fontWeight: 700,
                    padding: '4px 8px', borderRadius: 999, flexShrink: 0,
                    background: `color-mix(in srgb, ${S.color}, transparent 82%)`,
                    color: S.color, cursor: 'pointer' }}>
                  {S.label.toUpperCase()}</span>
                <div style={{ flex: 1, minWidth: 0 }}
                  onClick={() => upBlock(bi, { open: !b.open })}>
                  <div className="dd-display" style={{ fontSize: 13.5,
                    fontWeight: 700, whiteSpace: 'nowrap', overflow: 'hidden',
                    textOverflow: 'ellipsis', cursor: 'pointer' }}>{b.label}</div>
                  <div className="af-mono" style={{ fontSize: 8.5, marginTop: 2,
                    color: 'var(--fg-dim)' }}>
                    {b.ex.length} EXERCISES{ddKeyMetric(b) ? ` · ${ddKeyMetric(b).toUpperCase()}` : ''}
                  </div>
                </div>
                <div onClick={() => setConfigIdx(configIdx === bi ? null : bi)}
                  style={{ cursor: 'pointer', padding: 4,
                    color: configIdx === bi ? DD.lime : 'var(--fg-dim)' }}>
                  <Icon name="sliders" size={15}/></div>
                <div onClick={() => delBlock(bi)}
                  style={{ cursor: 'pointer', padding: 4, color: 'var(--fg-dim)' }}>
                  <Icon name="close" size={14}/></div>
                <div onClick={() => upBlock(bi, { open: !b.open })}
                  style={{ cursor: 'pointer', padding: 4, color: 'var(--fg-dim)' }}>
                  <Icon name={b.open ? 'chevU' : 'chevD'} size={15}/></div>
              </div>

              {configIdx === bi && (
                <div style={{ padding: '0 12px 12px' }}>
                  <DDBlockConfig b={b} up={(p) => upBlock(bi, p)}/>
                </div>
              )}

              {b.open && (
                <div style={{ borderTop: '1px solid var(--border)',
                  background: 'rgba(0,0,0,0.3)', padding: '4px 12px 10px' }}>
                  {b.ex.length === 0 && (
                    <div style={{ fontSize: 11.5, color: 'var(--fg-dim)',
                      textAlign: 'center', padding: '14px 0' }}>
                      No exercises yet — add one below
                    </div>
                  )}
                  {b.ex.map((e, ei) => (
                    <div key={ei} style={{ display: 'flex', gap: 10,
                      alignItems: 'flex-start', padding: '10px 0',
                      borderTop: ei === 0 ? 'none' : '1px solid var(--border)' }}>
                      <div style={{ display: 'flex', flexDirection: 'column',
                        color: 'var(--fg-dim)', paddingTop: 2 }}>
                        <div onClick={() => moveEx(bi, ei, -1)}
                          style={{ cursor: 'pointer', padding: 1 }}>
                          <Icon name="chevU" size={11}/></div>
                        <div onClick={() => moveEx(bi, ei, 1)}
                          style={{ cursor: 'pointer', padding: 1 }}>
                          <Icon name="chevD" size={11}/></div>
                      </div>
                      <div style={{ flex: 1, minWidth: 0, cursor: 'pointer' }}
                        onClick={() => setExSheet({ bi, ei })}>
                        <div style={{ fontSize: 13.5, fontWeight: 600 }}>{e.n}</div>
                        <div className="af-mono" style={{ fontSize: 10,
                          marginTop: 3,
                          color: e.ghost ? 'var(--fg-dim)' : 'var(--fg-muted)' }}>
                          {ddExSummary(e).toUpperCase()}{e.ghost ? ' · LAST TIME' : ''}
                        </div>
                        {e.flag && (
                          <div style={{ display: 'flex', alignItems: 'center',
                            gap: 8, marginTop: 7, fontSize: 11,
                            color: 'var(--ready-mod)', lineHeight: 1.4 }}>
                            <span style={{ flex: 1 }}>{e.flag}</span>
                            <span className="dd-display"
                              onClick={(ev) => { ev.stopPropagation();
                                upEx(bi, ei, { ...e.swapTo, flag: null,
                                  swapTo: null }); }}
                              style={{ background: 'var(--ready-mod)',
                                color: '#1a1200', borderRadius: 999,
                                padding: '5px 11px', fontSize: 11,
                                fontWeight: 700, cursor: 'pointer' }}>Swap</span>
                          </div>
                        )}
                      </div>
                      <div onClick={() => setExSheet({ bi, ei })}
                        style={{ cursor: 'pointer', padding: 3,
                          color: 'var(--fg-dim)' }}>
                        <Icon name="edit" size={13}/></div>
                      <div onClick={() => delEx(bi, ei)}
                        style={{ cursor: 'pointer', padding: 3,
                          color: 'var(--fg-dim)' }}>
                        <Icon name="close" size={13}/></div>
                    </div>
                  ))}
                  <div className="dd-display" onClick={() => setExSheet({ bi, add: true })}
                    style={{ textAlign: 'center',
                      border: '1.5px dashed var(--border-str)', borderRadius: 12,
                      padding: '10px 0', fontSize: 12.5, fontWeight: 700,
                      color: 'var(--fg-muted)', cursor: 'pointer', marginTop: 8 }}>
                    ＋ Add exercise
                  </div>
                </div>
              )}
            </div>
          );
        })}

        {/* Add block — the AddBlockTypePicker chips */}
        {pickerOpen ? (
          <div style={{ background: DD.card, border: '1px solid var(--border)',
            borderRadius: 16, padding: 14, marginTop: 4 }}>
            <div className="dd-display" style={{ fontSize: 14, fontWeight: 700,
              marginBottom: 10 }}>What type of block?</div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
              {Object.entries(DD_STRUCTURES).map(([key, s]) => (
                <span key={key} className="dd-display" onClick={() => addBlock(key)}
                  style={{ padding: '9px 13px', borderRadius: 999, fontSize: 12.5,
                    fontWeight: 600, cursor: 'pointer', background: DD.card2,
                    border: `1px solid color-mix(in srgb, ${s.color}, transparent 55%)` }}>
                  {s.emoji} {s.label}</span>
              ))}
            </div>
            <div className="dd-display" onClick={() => setPickerOpen(false)}
              style={{ textAlign: 'center', fontSize: 12, fontWeight: 700,
                color: 'var(--fg-muted)', cursor: 'pointer', marginTop: 12 }}>
              Cancel</div>
          </div>
        ) : (
          <div className="dd-display" onClick={() => setPickerOpen(true)}
            style={{ textAlign: 'center', border: '1.5px dashed var(--border-str)',
              borderRadius: 16, padding: '13px 0', fontSize: 13.5, fontWeight: 700,
              color: 'var(--fg-muted)', cursor: 'pointer' }}>
            ＋ Add block
          </div>
        )}
      </div>

      {/* Footer */}
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
        display: 'flex', gap: 8, zIndex: 30 }}>
        {mode === 'backfill'
          ? <div className="dd-display dd-glow" onClick={() => {
              set(s => ({ ...s, backfilled: true,
                toast: "Weights saved to Monday's log" }));
              nav('dd-profile'); }}
              style={{ flex: 1, background: DD.lime, color: DD.ink,
                borderRadius: 999, padding: '16px 0', textAlign: 'center',
                fontSize: 15, fontWeight: 700, cursor: 'pointer' }}>Save log</div>
          : <div className="dd-display dd-glow" onClick={() => {
                set(s => ({ ...s, toast: title
                  ? `Saved “${title}” to My Workouts` : 'Saved to My Workouts' }));
                nav('dd-build'); }}
              style={{ flex: 1, background: DD.lime, color: DD.ink,
                borderRadius: 999, padding: '16px 0', textAlign: 'center',
                fontSize: 15, fontWeight: 700, cursor: 'pointer' }}>
              Save workout</div>}
      </div>

      <DDExerciseSheet exSheet={exSheet} setExSheet={setExSheet} blocks={blocks}
        upEx={upEx} addEx={addEx}/>
    </>
  );
}

// Exercise sheet — EditExerciseDialog port: name, type tabs
// (Sets/Reps · Duration · Distance · Calories), rest (timed/lap), notes.
// Also doubles as Add-exercise (search against equipment-aware library).
function DDExerciseSheet({ exSheet, setExSheet, blocks, upEx, addEx }) {
  const isAdd = exSheet && exSheet.add;
  const e = exSheet && !isAdd ? blocks[exSheet.bi].ex[exSheet.ei] : null;
  const [q, setQ] = React.useState('');
  React.useEffect(() => { if (isAdd) setQ(''); }, [exSheet]);
  const kind = e ? (e.duration_sec != null && e.duration_sec > 0 ? 'Duration'
    : e.distance_m ? 'Distance' : e.calories ? 'Calories' : 'Sets/Reps') : null;
  const setKind = (k) => {
    // web parity: switching tabs clears other-type fields
    const cleared = { duration_sec: null, distance_m: null, calories: null };
    if (k === 'Sets/Reps') upEx(exSheet.bi, exSheet.ei, { ...cleared, sets: e.sets || 3, reps: e.reps || 10 });
    if (k === 'Duration') upEx(exSheet.bi, exSheet.ei, { ...cleared, sets: null, reps: null, duration_sec: 60 });
    if (k === 'Distance') upEx(exSheet.bi, exSheet.ei, { ...cleared, sets: null, reps: null, distance_m: 100 });
    if (k === 'Calories') upEx(exSheet.bi, exSheet.ei, { ...cleared, sets: null, reps: null, calories: 15 });
  };
  const LIB = [
    ['Wall balls', 'CONDITIONING · MED BALL ✓'],
    ['DB thrusters', 'FULL BODY · DUMBBELLS ✓'],
    ['Burpee broad jumps', 'BODYWEIGHT ✓'],
    ['Rower', 'MACHINE · ROWER ✓'],
    ['KB swing', 'POSTERIOR · KETTLEBELL ✓'],
    ['Barbell back squat', 'STRENGTH · BARBELL — NOT IN YOUR GYM'],
  ].filter(([n]) => !q || n.toLowerCase().includes(q.toLowerCase()));
  const up = (patch) => upEx(exSheet.bi, exSheet.ei, patch);

  return (
    <Sheet open={!!exSheet} onClose={() => setExSheet(null)}
      title={isAdd ? 'Add exercise' : 'Edit exercise'}>
      {isAdd ? (
        <>
          <input className="af-input" placeholder="Search exercises..."
            value={q} onChange={(ev) => setQ(ev.target.value)}
            style={{ marginBottom: 10 }}/>
          {LIB.map(([n, meta]) => (
            <div key={n} onClick={() => addEx(exSheet.bi, n)}
              style={{ display: 'flex', alignItems: 'center', gap: 11,
                padding: '11px 2px', borderBottom: '1px solid var(--border)',
                cursor: 'pointer' }}>
              <IconChip name="lift" bg={DD.card2} size={28}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 13.5, fontWeight: 600 }}>{n}</div>
                <div className="af-mono" style={{ fontSize: 8.5, marginTop: 2,
                  color: meta.includes('NOT IN') ? 'var(--ready-mod)'
                    : 'var(--fg-dim)' }}>{meta}</div>
              </div>
              <Icon name="plus" size={14} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          ))}
          {q && <div className="dd-display" onClick={() => addEx(exSheet.bi, q)}
            style={{ textAlign: 'center', padding: '12px 0', fontSize: 12.5,
              fontWeight: 700, color: DD.lime, cursor: 'pointer' }}>
            ＋ Create “{q}”</div>}
        </>
      ) : e && (
        <>
          <input className="af-input" value={e.n}
            onChange={(ev) => up({ n: ev.target.value })}
            style={{ marginBottom: 12, fontWeight: 600 }}/>
          <div className="af-seg" style={{ marginBottom: 12 }}>
            {['Sets/Reps', 'Duration', 'Distance', 'Calories'].map(k => (
              <div key={k} className="af-seg-item" data-on={kind === k}
                onClick={() => setKind(k)} style={{ fontSize: 10.5,
                  padding: '6px 4px' }}>{k}</div>
            ))}
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap',
            marginBottom: 12 }}>
            {kind === 'Sets/Reps' && <>
              <DDStepper label="Sets" value={e.sets || 0} min={0} max={10}
                onChange={(v) => up({ sets: v })}/>
              <DDStepper label="Reps" value={e.reps || 0} min={0} max={50}
                onChange={(v) => up({ reps: v })}/>
              <DDStepper label="Weight kg" value={e.weight || 0} min={0} max={300}
                step={2.5} onChange={(v) => up({ weight: v })}/>
            </>}
            {kind === 'Duration' &&
              <DDStepper label="Duration" value={e.duration_sec || 0} min={0}
                max={600} step={5} fmt={ddFmtSec}
                onChange={(v) => up({ duration_sec: v })}/>}
            {kind === 'Distance' &&
              <DDStepper label="Distance m" value={e.distance_m || 0} min={0}
                max={5000} step={50} onChange={(v) => up({ distance_m: v })}/>}
            {kind === 'Calories' &&
              <DDStepper label="Calories" value={e.calories || 0} min={0}
                max={500} step={5} onChange={(v) => up({ calories: v })}/>}
          </div>
          <div className="af-mono" style={{ fontSize: 9,
            color: 'var(--fg-muted)', marginBottom: 6 }}>REST AFTER EXERCISE</div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center',
            marginBottom: 14 }}>
            <div className="af-seg" style={{ flex: 1 }}>
              {[['timed', 'Timed'], ['button', 'Lap button']].map(([v, l]) => (
                <div key={v} className="af-seg-item" data-on={e.rest_type === v}
                  onClick={() => up({ rest_type: v })}
                  style={{ fontSize: 11 }}>{l}</div>
              ))}
            </div>
            {e.rest_type === 'timed' &&
              <div style={{ width: 120 }}>
                <DDStepper label="Rest" value={e.rest_sec || 0} min={0} max={300}
                  step={5} fmt={ddFmtSec} onChange={(v) => up({ rest_sec: v })}/>
              </div>}
          </div>
          {e.rest_type === 'button' &&
            <div style={{ fontSize: 10.5, color: 'var(--fg-dim)',
              marginBottom: 12 }}>
              Press lap button when ready to continue to next exercise.
            </div>}
          <Btn wide onClick={() => setExSheet(null)}>Done</Btn>
        </>
      )}
    </Sheet>
  );
}
// ------------------------------------------------------------------ Profile (merged with Progress)
// Organized as tappable summary modules: stat tiles up top (each one goes
// somewhere), a compact This-week list whose rows open activity details,
// the calendar collapsed behind a summary row. No flat mega-scroll.
function DDProfileScreen({ dd, set, nav }) {
  const [calOpen, setCalOpen] = React.useState(false);
  const [weekAll, setWeekAll] = React.useState(false);
  const entries = [
    ...(dd.push === 'logged' ? [{ t: 'Hyrox Sim — Stations 1–4', icon: 'flame',
      bg: DD.lime, big: '44', unit: 'MIN', meta: 'TODAY · RPE 8 · VERIFIED',
      act: 'matched' }] : []),
    ...(dd.runRPE ? [{ t: 'Lunch Run', icon: 'run', bg: DD.blue,
      big: '8.2', unit: 'KM', meta: `TODAY · 59 MIN · RPE ${dd.runRPE} · STRAVA`,
      act: 'run' }] : []),
    ...(dd.backfilled ? [{ t: 'Lower body — posterior', icon: 'lift', bg: DD.purple,
      big: '52', unit: 'MIN', meta: 'MON · WEIGHTS ✓ · GARMIN', act: 'blank' }] : []),
    { t: 'Easy shakeout', icon: 'run', bg: DD.blue, big: '5.1', unit: 'KM',
      meta: 'MON · 32 MIN · RPE 3 · GARMIN', act: 'run' },
    { t: 'DB Full-body AMRAP', icon: 'bolt', bg: DD.purple, big: '21', unit: 'MIN',
      meta: 'SUN · RPE 7 · FROM IG · ON PHONE', act: 'blank' },
    { t: 'Long endurance run', icon: 'run', bg: DD.blue, big: '14.6', unit: 'KM',
      meta: 'SAT · 1H 38M · RPE 6 · GARMIN', act: 'run' },
  ];
  const doneCount = 1 + (dd.runRPE ? 1 : 0) + (dd.push === 'logged' ? 1 : 0);
  const shown = weekAll ? entries : entries.slice(0, 3);
  const openAct = (id) => { set(s => ({ ...s, activityId: id })); nav('dd-activity'); };
  const sectionHead = (title, right, onRight) => (
    <div style={{ display: 'flex', alignItems: 'center', margin: '20px 0 10px' }}>
      <span className="dd-display" style={{ fontSize: 15, fontWeight: 700 }}>{title}</span>
      {right && <span className="dd-display" onClick={onRight}
        style={{ marginLeft: 'auto', fontSize: 12, fontWeight: 700,
          color: 'var(--fg-muted)', cursor: 'pointer' }}>{right}</span>}
    </div>
  );

  return (
    <>
      <div style={{ padding: '8px 18px 0', display: 'flex', alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>Profile</div>
        <div onClick={() => nav('dd-settings')}
          style={{ marginLeft: 'auto', width: 38, height: 38, borderRadius: 999,
            background: DD.card2, display: 'flex', alignItems: 'center',
            justifyContent: 'center', cursor: 'pointer' }}>
          <Icon name="gear" size={18}/>
        </div>
      </div>
      <ScreenPad>
        {/* Identity — compact, one line */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 10 }}>
          <div className="dd-display" style={{ width: 44, height: 44,
            borderRadius: 999, background: DD.lime, color: DD.ink,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 17, fontWeight: 800 }}>D</div>
          <div>
            <div className="dd-display" style={{ fontSize: 16, fontWeight: 800 }}>David</div>
            <div style={{ fontSize: 10.5, color: 'var(--fg-muted)', marginTop: 1 }}>
              Hyrox prep · Week 3 of 12</div>
          </div>
        </div>

        {/* Summary tiles — every tile is a door */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8,
          marginTop: 14 }}>
          {[
            [`${doneCount}/5`, 'sessions this week', DD.lime,
              () => { setWeekAll(true); set(s => ({ ...s,
                toast: 'This week — expanded below' })); }],
            ['2h 14m', 'training time', '#fff',
              () => set(s => ({ ...s, toast: 'Time — would open weekly volume' }))],
            ['3 🔥', 'day streak · best 6', '#fff',
              () => set(s => ({ ...s, toast: 'Streak — would open history' }))],
            ['9', 'sessions in July', '#fff', () => setCalOpen(o => !o)],
          ].map(([v, k, c, fn]) => (
            <div key={k} onClick={fn}
              style={{ background: DD.card, border: '1px solid var(--border)',
                borderRadius: 16, padding: '13px 14px', cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 8 }}>
              <div style={{ flex: 1 }}>
                <div className="dd-display" style={{ fontSize: 21, fontWeight: 800,
                  color: c }}>{v}</div>
                <div style={{ fontSize: 10, color: 'var(--fg-muted)', marginTop: 2 }}>{k}</div>
              </div>
              <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          ))}
        </div>

        {/* Week-dot row lives with the streak story, quiet */}
        <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginTop: 12 }}>
          {['M','T','W','T','F','S','S'].map((d, i) => (
            <div key={i} className="dd-display" style={{ width: 28, height: 28,
              borderRadius: 999, display: 'flex', alignItems: 'center',
              justifyContent: 'center', fontSize: 10.5, fontWeight: 700,
              background: i < 2 || (i === 3 && dd.push === 'logged') ? DD.lime : DD.card2,
              color: i < 2 || (i === 3 && dd.push === 'logged') ? DD.ink : 'var(--fg-dim)' }}>
              {d}</div>
          ))}
        </div>

        {/* Needs attention */}
        {!dd.backfilled && (
          <div onClick={() => nav('dd-editor-backfill')}
            style={{ marginTop: 14, padding: '12px 14px', borderRadius: 16,
              cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 12,
              background: 'color-mix(in oklch, var(--ready-mod), transparent 86%)',
              border: '1px solid color-mix(in oklch, var(--ready-mod), transparent 55%)' }}>
            <IconChip name="lift" bg={'var(--ready-mod)'} size={30}/>
            <div style={{ flex: 1 }}>
              <div className="dd-display" style={{ fontSize: 13, fontWeight: 700 }}>
                Monday's strength needs weights</div>
              <div style={{ fontSize: 10.5, color: 'var(--fg-muted)', marginTop: 1 }}>
                2-minute backfill</div>
            </div>
            <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        )}

        {/* This week — rows open the activity detail */}
        {sectionHead('This week', weekAll ? 'Show less' : `See all (${entries.length})`,
          () => setWeekAll(a => !a))}
        {shown.map((e, i) => (
          <div key={i} onClick={() => openAct(e.act)}
            style={{ display: 'flex', alignItems: 'center', gap: 12,
              background: DD.card, border: '1px solid var(--border)',
              borderRadius: 16, padding: '11px 13px', marginBottom: 8,
              cursor: 'pointer' }}>
            <IconChip name={e.icon} bg={e.bg} size={34}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="dd-display" style={{ fontSize: 13.5, fontWeight: 600 }}>{e.t}</div>
              <div className="af-mono" style={{ fontSize: 9, marginTop: 3,
                color: 'var(--fg-dim)', whiteSpace: 'nowrap', overflow: 'hidden',
                textOverflow: 'ellipsis' }}>{e.meta}</div>
            </div>
            <div style={{ textAlign: 'right', flexShrink: 0 }}>
              <span className="dd-display" style={{ fontSize: 18, fontWeight: 800 }}>{e.big}</span>
              <span className="af-mono" style={{ fontSize: 8.5, color: 'var(--fg-dim)',
                marginLeft: 2 }}>{e.unit}</span>
            </div>
            <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}

        {/* Month — collapsed behind its summary row */}
        {sectionHead('July', calOpen ? 'Hide' : 'Calendar ›', () => setCalOpen(o => !o))}
        {calOpen && (
          <div style={{ background: DD.card, border: '1px solid var(--border)',
            borderRadius: 22, padding: '16px', marginBottom: 4 }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 5 }}>
              {Array.from({ length: 31 }, (_, i) => i + 1).map(d => {
                const trained = [1, 2, 4, 6, 7, 8].includes(d);
                const today = d === 10;
                return (
                  <div key={d} className="dd-display"
                    onClick={() => trained && set(s => ({ ...s,
                      toast: `Jul ${d} — would open that day's diary` }))}
                    style={{ aspectRatio: '1', borderRadius: 10, display: 'flex',
                      alignItems: 'center', justifyContent: 'center',
                      fontSize: 11.5, fontWeight: 600,
                      cursor: trained ? 'pointer' : 'default',
                      background: trained ? DD.lime : 'transparent',
                      color: trained ? DD.ink : d <= 10 ? 'var(--fg)' : 'var(--fg-dim)',
                      border: today ? `1.5px solid ${'var(--ready-mod)'}` : 'none' }}>
                    {d}</div>
                );
              })}
            </div>
          </div>
        )}
        {!calOpen && (
          <div onClick={() => setCalOpen(true)}
            style={{ display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer',
              background: DD.card, border: '1px solid var(--border)',
              borderRadius: 16, padding: '12px 14px' }}>
            <IconChip name="cal" bg={DD.card2} size={30}/>
            <span style={{ flex: 1, fontSize: 13, fontWeight: 600 }}>
              9 sessions · best week 5</span>
            <Icon name="chevD" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        )}

        {/* All time — one quiet tappable row */}
        {sectionHead('All time')}
        <div onClick={() => set(s => ({ ...s, toast: 'Would open lifetime stats' }))}
          style={{ display: 'flex', background: DD.card, cursor: 'pointer',
            border: '1px solid var(--border)', borderRadius: 16, padding: '13px 6px' }}>
          {[['47', 'workouts'], ['12', 'imports'], ['6', 'best streak']].map(([v, k]) => (
            <div key={k} style={{ flex: 1, textAlign: 'center' }}>
              <div className="dd-display" style={{ fontSize: 19, fontWeight: 800 }}>{v}</div>
              <div style={{ fontSize: 9.5, color: 'var(--fg-muted)', marginTop: 2 }}>{k}</div>
            </div>
          ))}
        </div>
      </ScreenPad>
      <DDTabBar active={2} nav={nav} set={set}/>
      <CreateSheet dd={dd} set={set} nav={nav}/>
    </>
  );
}
// ------------------------------------------------------------------ Settings (own screen)
// Groups are collapsible accordions — header shows an icon, a live summary,
// and a count, so the whole menu fits one screen collapsed.
function DDSettingsGroup({ title, summary, icon, iconBg, rows, defaultOpen, set }) {
  const [open, setOpen] = React.useState(!!defaultOpen);
  return (
    <div style={{ borderRadius: 16, marginTop: 10, overflow: 'hidden',
      background: DD.card,
      border: open
        ? '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)'
        : '1px solid var(--border)' }}>
      {/* Group header — stays visually dominant; tinted while open */}
      <div onClick={() => setOpen(o => !o)}
        style={{ display: 'flex', alignItems: 'center', gap: 12,
          padding: '13px 14px', cursor: 'pointer',
          background: open
            ? 'color-mix(in oklch, var(--ready-high), transparent 90%)'
            : 'transparent' }}>
        <IconChip name={icon} bg={iconBg}/>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div className="dd-display" style={{ fontSize: 14.5, fontWeight: 700 }}>
            {title}</div>
          {!open && <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
            marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden',
            textOverflow: 'ellipsis' }}>{summary}</div>}
        </div>
        {!open && <span className="af-mono" style={{ fontSize: 10,
          color: 'var(--fg-dim)' }}>{rows.length}</span>}
        <Icon name={open ? 'chevU' : 'chevD'} size={15}
          style={{ color: open ? 'var(--ready-high)' : 'var(--fg-dim)' }}/>
      </div>
      {/* Children — indented interior with a rail; smaller, lighter, no big chips */}
      {open && (
        <div style={{ background: 'rgba(0,0,0,0.35)',
          borderTop: '1px solid var(--border)',
          padding: '4px 14px 6px 18px' }}>
          <div style={{ borderLeft: '2px solid color-mix(in oklch, var(--ready-high), transparent 72%)',
            paddingLeft: 14 }}>
            {rows.map(([t, d, ic, c, right, fn], i) => (
              <div key={t}
                onClick={fn || (() => set(s => ({ ...s, toast: `${t} — tap would open` })))}
                style={{ display: 'flex', alignItems: 'center', gap: 10,
                  padding: '11px 0',
                  borderTop: i === 0 ? 'none' : '1px solid var(--border)',
                  cursor: 'pointer' }}>
                <IconChip name={ic} bg={c} size={26}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 13, fontWeight: 600,
                    fontFamily: 'var(--font-sans)',
                    color: c === DD.red ? DD.red : 'var(--fg)' }}>{t}</div>
                  {d && <div style={{ fontSize: 10, color: 'var(--fg-dim)',
                    marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden',
                    textOverflow: 'ellipsis' }}>{d}</div>}
                </div>
                {right === 'on' || right === 'off'
                  ? <div className="af-switch" data-on={right === 'on'}/>
                  : right ? <span className="af-mono" style={{ fontSize: 10,
                      color: 'var(--fg-dim)' }}>{right}</span>
                  : <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function DDSettingsScreen({ dd, set, nav }) {
  const group = (title, rows, note) =>
    <DDSettingsGroup title={title} summary={note} icon="gear" iconBg={DD.card2}
      rows={rows} set={set}/>;
  const goGym = () => nav('dd-gym');
  const goDev = () => nav('dd-device');
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => nav('dd-profile')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Profile
        </div>
        <div className="dd-display" style={{ fontSize: 28, fontWeight: 800,
          marginTop: 8 }}>Settings</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '2px 18px 30px' }}>
        <DDSettingsGroup title="My Gyms" icon="home" iconBg={DD.orange} set={set}
          summary="Home gym active · builder adapts to it"
          rows={[
            ['Home gym', 'ACTIVE · DBs to 32 · KB 24 · rower · private', 'home',
              DD.lime, null, goGym],
            ['24 Hour Fitness — Katy', 'Shared · 12 members keep it in sync', 'map',
              DD.blue, null, goGym],
            ['Hotel / travel', 'Bodyweight + bands preset', 'bookmark', DD.card2,
              null, goGym],
            ['＋ Add gym', 'Scan the room once — everyone after you skips it', 'plus',
              DD.card2, null,
              () => set(s => ({ ...s, toast: 'New gym — name it, tick equipment, done' }))],
          ]}/>
        <DDSettingsGroup title="Connected wearables" icon="watch" iconBg={DD.lime}
          set={set} summary="T-Rex 3 + Garmin · sessions set per watch"
          rows={[
            ['Amazfit T-Rex 3', 'Hyrox / HIIT · synced 2m · 78%', 'watch', DD.lime,
              null, goDev],
            ['Garmin', 'Runs + strength · pulled 7:41 AM', 'watch', DD.blue,
              null, goDev],
            ['＋ Pair a wearable', 'Optional — the phone covers everything', 'plus',
              DD.card2, null,
              () => set(s => ({ ...s, toast: 'Pair a wearable — optional' }))],
          ]}/>
        <DDSettingsGroup title="Connected apps" icon="link" iconBg={DD.blue} set={set}
          summary="Garmin pull ON · Strava off · Telegram"
          rows={[
            ['Garmin activities', 'Pulls runs into Progress', 'download', DD.blue, 'on'],
            ['Strava', 'Not connected', 'run', DD.orange, 'off'],
            ['Telegram', 'Coach + friction log', 'msg', DD.purple, null],
          ]}/>
        <DDSettingsGroup title="App" icon="sliders" iconBg={DD.purple} set={set}
          summary="Notifications · kg/km · dark"
          rows={[
            ['Notifications', 'Session reminders · push results', 'info', DD.lime, null],
            ['Units', 'kg · km', 'sliders', DD.card2, null],
            ['Appearance', 'Dark', 'moon', DD.card2, null],
          ]}/>
        <DDSettingsGroup title="Account & data" icon="user" iconBg={DD.card2} set={set}
          summary="soopergeri@gmail.com"
          rows={[
            ['Account', 'soopergeri@gmail.com', 'user', DD.card2, null],
            ['Export my data', null, 'download', DD.card2, null],
            ['Sign out', null, 'close', DD.red, null],
          ]}/>
      </div>
    </>
  );
}

// ------------------------------------------------------------------ Gym detail
// David's crowdsource idea: a gym = place + equipment list. Share it once,
// everyone who trains there inherits it — nobody re-enters a gym twice.
// (SmartGym has per-location equipment lists but NO sharing — this is ours.)
function DDGymScreen({ dd, set, nav }) {
  const [shared, setShared] = React.useState(true);
  const cat = (title, items) => (
    <div style={{ marginTop: 14 }}>
      <div className="af-mono" style={{ fontSize: 10, color: 'var(--fg-muted)',
        marginBottom: 8 }}>{title.toUpperCase()}</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7 }}>
        {items.map(([t, have]) => (
          <span key={t} className="dd-display"
            onClick={() => set(s => ({ ...s, toast: have ? `${t} — tap to remove` : `${t} — tap to add` }))}
            style={{ padding: '8px 13px', borderRadius: 999, fontSize: 12,
              fontWeight: 600, cursor: 'pointer',
              background: have ? DD.card2 : 'transparent',
              color: have ? 'var(--fg)' : 'var(--fg-dim)',
              border: have ? '1px solid var(--border-str)' : '1px dashed var(--border)' }}>
            {have ? t : `＋ ${t}`}</span>
        ))}
      </div>
    </div>
  );
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => nav('dd-settings')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> My Gyms
        </div>
      </div>
      <ScreenPad>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 8 }}>
          <IconChip name="map" bg={DD.blue}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 22, fontWeight: 800 }}>
              24 Hour Fitness — Katy</div>
            <div className="af-mono" style={{ fontSize: 9.5, color: 'var(--fg-dim)',
              marginTop: 3 }}>KATY, TX · 1.2 MI AWAY</div>
          </div>
        </div>

        {/* The crowdsource block — the differentiator */}
        <div style={{ marginTop: 14, borderRadius: 16, padding: '13px 14px',
          background: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
          border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ flex: 1 }}>
              <div className="dd-display" style={{ fontSize: 13.5, fontWeight: 700 }}>
                Shared gym</div>
              <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 2,
                lineHeight: 1.5 }}>
                12 members keep this list in sync — new machines show up for
                everyone. Nobody enters this gym twice.
              </div>
            </div>
            <div className="af-switch" data-on={shared}
              onClick={() => { setShared(!shared);
                set(s => ({ ...s, toast: shared ? 'Now private — your copy only'
                  : 'Shared — members keep it in sync' })); }}/>
          </div>
          <div className="af-mono" style={{ fontSize: 9.5, marginTop: 9,
            color: 'var(--fg-muted)' }}>
            LAST UPDATE · “CABLE CROSSOVER ADDED” · MARIA R · 2D AGO
          </div>
        </div>

        <div className="dd-display" onClick={() => set(s => ({ ...s,
            toast: 'Now the active gym — builder + swaps adapt to it' }))}
          style={{ marginTop: 12, background: DD.lime, color: DD.ink,
            borderRadius: 999, padding: '14px 0', textAlign: 'center',
            fontSize: 14.5, fontWeight: 700, cursor: 'pointer' }}>
          Set as active gym
        </div>

        {cat('Free weights', [['Dumbbells to 50 kg', true], ['Barbells + plates', true],
          ['Kettlebells', true], ['EZ bar', false]])}
        {cat('Machines', [['Cable crossover', true], ['Leg press', true],
          ['Lat pulldown', true], ['Chest-supported row', true], ['Hack squat', false]])}
        {cat('Cardio & conditioning', [['Rower', true], ['SkiErg', true],
          ['Assault bike', true], ['Sled + turf', false], ['Treadmill', true]])}
      </ScreenPad>
    </>
  );
}

// ------------------------------------------------------------------ Workout detail
// THE one canonical workout screen. Every workout — imported, manual, trainer —
// renders exactly this format; only the credit row's content differs.
// Synthesized from Ladder (block sections) + Bevel (Edit/Start dual CTA).
// Edit is MANUAL — our editor, no AI gate.
const DD_DETAILS = {
  amrap: {
    title: 'DB Full-body AMRAP',
    desc: 'Five rounds of full-body conditioning — wall balls, thrusters and jumps, with a sled finisher. Parsed from the reel; nothing saved yet.',
    pills: ['FROM INSTAGRAM', '5 ROUNDS · ~20 MIN', 'HIIT'],
    grad: 'linear-gradient(150deg, #3A1145 0%, #1a0a22 60%, #0a0a0b 100%)',
    media: 'play',
    credit: { initial: 'g', bg: '#C58AF4', name: 'gospelofgainz',
      sub: 'Workout by', action: 'Open in Instagram' },
    blocks: [
      { name: 'Round 1–3', note: '3 rounds · ~12 min', ex: [
        { n: 'Wall balls', d: '20 reps · med ball 6 kg', m: 'Quads · Shoulders' },
        { n: 'Barbell thrusters', d: '12 reps · 40 kg', m: 'Full body' },
        { n: 'Burpee broad jumps', d: '10 reps · bodyweight', m: 'Full body' },
      ]},
      { name: 'Finisher', note: '1 round · ~4 min', ex: [
        { n: 'Sled push', d: '2 × 20 m · 80 kg', m: 'Legs · Core' },
      ]},
    ],
  },
  glute: {
    title: 'Glute-Focused Lower Body',
    desc: 'Hip thrusts, Bulgarian split squats, step-ups and kickbacks — strength and shape. Parsed from the TikTok.',
    pills: ['FROM TIKTOK', '4 EXERCISES · ~35 MIN', 'STRENGTH'],
    grad: 'linear-gradient(150deg, #0d3830 0%, #062019 60%, #0a0a0b 100%)',
    media: 'play',
    credit: { initial: 'l', bg: '#4AD9D9', ink: '#00211f', name: 'lindkvistfeliciaa',
      sub: 'Workout by', action: 'Open in TikTok' },
    blocks: [
      { name: 'Main block', note: '4 exercises · ~35 min', ex: [
        { n: 'Hip thrust', d: '3 × 10 · barbell', m: 'Glutes' },
        { n: 'Bulgarian split squat', d: '4 × 8 · DBs', m: 'Glutes · Quads' },
        { n: 'Step-ups', d: '3 × 12 · box', m: 'Glutes · Quads' },
        { n: 'Glute kickbacks', d: '3 × 15 · cable', m: 'Glutes' },
      ]},
    ],
  },
  hyrox: {
    title: 'Hyrox Sim — Stations 1–4',
    desc: 'Race-pace simulation of the first four stations with run intervals between each. Built for Thursday sessions.',
    pills: ['CREATED BY YOU', '8 BLOCKS · ~45 MIN', 'HYROX'],
    grad: 'linear-gradient(150deg, #2A3505 0%, #141b03 60%, #0a0a0b 100%)',
    media: 'flame',
    credit: { initial: 'D', bg: 'var(--ready-high)', ink: '#0d1200', name: 'You',
      sub: 'Created manually · Jul 6', action: null },
    blocks: [
      { name: 'Stations 1–4', note: '2 rounds · ~32 min', ex: [
        { n: 'SkiErg', d: '250 m hard', m: 'Full body' },
        { n: 'Sled push', d: '2 × 20 m · 80 kg', m: 'Legs · Core' },
        { n: 'Burpee broad jumps', d: '10 reps', m: 'Full body' },
        { n: 'Rower', d: '500 m', m: 'Full body' },
      ]},
      { name: 'Run intervals', note: 'between stations · ~13 min', ex: [
        { n: 'Run', d: '400 m @ race pace', m: 'Aerobic' },
      ]},
    ],
  },
  run: {
    title: 'Zone 2 base run',
    desc: 'Aerobic base builder — keep heart rate under the cap the whole way.',
    pills: ['CREATED BY YOU', '48 MIN', 'RUN'],
    grad: 'linear-gradient(150deg, #0d2438 0%, #071522 60%, #0a0a0b 100%)',
    media: 'run',
    credit: { initial: 'D', bg: 'var(--ready-high)', ink: '#0d1200', name: 'You',
      sub: 'Created manually · Jun 28', action: null },
    blocks: [
      { name: 'Steady state', note: '1 block · 48 min', ex: [
        { n: 'Easy run', d: '48 min · HR cap 148', m: 'Aerobic' },
      ]},
    ],
  },
  lower: {
    title: 'Lower body — posterior',
    desc: 'Posterior-chain strength: squat, hinge, single-leg. From your trainer.',
    pills: ['FROM TRAINER', '6 EXERCISES · ~52 MIN', 'STRENGTH'],
    grad: 'linear-gradient(150deg, #33240a 0%, #1d1405 60%, #0a0a0b 100%)',
    media: 'lift',
    credit: { initial: 'T', bg: '#F4A24A', name: 'Coach Mike',
      sub: 'Shared with you · Jul 1', action: 'Message' },
    blocks: [
      { name: 'Main lifts', note: '~35 min', ex: [
        { n: 'Back squat', d: '3 × 5 · build to heavy', m: 'Quads · Glutes' },
        { n: 'Romanian deadlift', d: '3 × 8 · 70 kg', m: 'Hamstrings' },
      ]},
      { name: 'Accessories', note: '~17 min', ex: [
        { n: 'Split squat', d: '2 × 10 · DB 2×20', m: 'Quads · Glutes' },
        { n: 'Nordic curl', d: '2 × 6 · slow', m: 'Hamstrings' },
      ]},
    ],
  },
};

function DDDetailScreen({ dd, set, nav }) {
  const w = DD_DETAILS[dd.detailId] || DD_DETAILS.amrap;
  const { blocks } = w;
  return (
    <>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        paddingBottom: 120 }}>
        {/* Media hero — same slot for every workout: reel thumb if imported,
            type glyph if created */}
        <div style={{ height: 190, position: 'relative', background: w.grad }}>
          <div onClick={() => nav('dd-build')}
            style={{ position: 'absolute', top: 12, left: 14, width: 36, height: 36,
              borderRadius: 999, background: 'rgba(0,0,0,0.5)', display: 'flex',
              alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <Icon name="close" size={16}/>
          </div>
          <div style={{ position: 'absolute', bottom: 12, left: 16, display: 'flex',
            gap: 7 }}>
            {w.pills.map(p => (
              <span key={p} className="af-mono" style={{ fontSize: 8.5,
                padding: '4px 9px', borderRadius: 999, background: 'rgba(0,0,0,0.5)',
                color: '#fff' }}>{p}</span>
            ))}
          </div>
          <div style={{ position: 'absolute', inset: 0, display: 'flex',
            alignItems: 'center', justifyContent: 'center', opacity: 0.7 }}>
            <Icon name={w.media} size={38}/>
          </div>
        </div>

        <div style={{ padding: '16px 18px 0' }}>
          <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
            lineHeight: 1.15 }}>{w.title}</div>
          <div style={{ fontSize: 12.5, color: 'var(--fg-muted)', marginTop: 8,
            lineHeight: 1.55 }}>{w.desc}</div>

          {/* Credit row — identical card for every source; content varies */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 12,
            background: DD.card, border: '1px solid var(--border)', borderRadius: 12,
            padding: '9px 12px' }}>
            <div className="dd-display" style={{ width: 32, height: 32,
              borderRadius: 999, background: w.credit.bg,
              color: w.credit.ink || '#fff',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 13, fontWeight: 800 }}>{w.credit.initial}</div>
            <div style={{ flex: 1 }}>
              <div className="dd-display" style={{ fontSize: 12.5, fontWeight: 700 }}>
                {w.credit.name}</div>
              <div style={{ fontSize: 10, color: 'var(--fg-muted)' }}>{w.credit.sub}</div>
            </div>
            {w.credit.action && <span className="dd-display" style={{ fontSize: 11,
              fontWeight: 700, background: DD.card2, borderRadius: 999,
              padding: '7px 12px', cursor: 'pointer' }}
              onClick={() => set(s => ({ ...s, toast: `Would: ${w.credit.action}` }))}>
              {w.credit.action}</span>}
          </div>

          {/* Blocks — Ladder's sectioned structure. Same format for every
              workout, imported or created; gym fit is resolved at Start. */}
          {blocks.map(b => (
            <div key={b.name} style={{ marginTop: 18 }}>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                <span className="dd-display" style={{ fontSize: 14.5,
                  fontWeight: 700 }}>{b.name}</span>
                <span className="af-mono" style={{ fontSize: 9.5,
                  color: 'var(--fg-muted)', marginLeft: 'auto' }}>{b.note.toUpperCase()}</span>
              </div>
              <div style={{ marginTop: 8, background: DD.card,
                border: '1px solid var(--border)', borderRadius: 16,
                padding: '2px 13px' }}>
                {b.ex.map((e, i) => (
                  <div key={e.n} style={{ display: 'flex', alignItems: 'center',
                    gap: 11, padding: '11px 0',
                    borderTop: i === 0 ? 'none' : '1px solid var(--border)' }}>
                    <IconChip name="lift" bg={DD.card2} size={30}/>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="dd-display" style={{ fontSize: 13.5,
                        fontWeight: 600 }}>{e.n}</div>
                      <div className="af-mono" style={{ fontSize: 10, marginTop: 2,
                        color: 'var(--fg-muted)' }}>{e.d.toUpperCase()}</div>
                    </div>
                    <span style={{ fontSize: 9.5, color: 'var(--fg-dim)' }}>{e.m}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}

        </div>
      </div>

      {/* Bevel's dual CTA — Edit is manual (no AI gate); Start opens the
          one start flow shared by every workout */}
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
        display: 'flex', gap: 8, zIndex: 30 }}>
        <div className="dd-display" onClick={() => nav('dd-editor-import')}
          style={{ flex: 1, background: 'rgba(16,16,18,0.96)', color: 'var(--fg)',
            border: '1px solid var(--border-str)', borderRadius: 999,
            padding: '16px 0', textAlign: 'center', fontSize: 15, fontWeight: 700,
            cursor: 'pointer' }}>
          <Icon name="edit" size={14}/> Edit
        </div>
        <div className="dd-display dd-glow"
          onClick={() => set(s => ({ ...s, startOpen: true,
            toast: 'Saved to My Workouts' }))}
          style={{ flex: 1.2, background: DD.lime, color: DD.ink, borderRadius: 999,
            padding: '16px 0', textAlign: 'center', fontSize: 15, fontWeight: 700,
            cursor: 'pointer' }}>
          <Icon name="play" size={13}/> Start
        </div>
      </div>
      <StartSheet dd={dd} set={set} nav={nav}/>
    </>
  );
}

// ------------------------------------------------------------------ Completed activity detail
// Tapping a diary entry opens THIS — metrics first (Gentler-Streak voice:
// zone summary, big numbers), never a structure editor. The action depends
// on match state:
//   matched  → verified: we pushed it, the watch ran it, Strava confirmed it.
//   typed    → offer to MAP it to a known workout (Stryd, My Workouts).
//   blank    → "what was this?" → map it, or add what you did manually.
const DD_ACTIVITIES = {
  matched: {
    title: 'Hyrox Sim — Stations 1–4', time: '18:10 – 18:54', kind: 'HIIT',
    icon: 'flame', iconBg: 'var(--ready-high)',
    stats: [['44', 'MIN'], ['486', 'CAL'], ['151', 'AVG BPM'], ['178', 'MAX BPM']],
    zones: [4, 9, 14, 12, 5], zoneNote: 'Most time in Zone 3–4',
    state: 'matched',
    matchNote: 'Pushed from AmakaFlow · completed on T-Rex 3 · confirmed by Strava',
    structure: ['SkiErg 250 m', 'Sled push 2×20 m', 'Burpee broad jumps ×10',
      'Rower 500 m', '+ 4 more blocks'],
  },
  run: {
    title: 'Lunch Run', time: '12:53 – 13:52', kind: 'RUN',
    icon: 'run', iconBg: '#5AB8F4',
    stats: [['8.2', 'KM'], ['59', 'MIN'], ['677', 'CAL'], ['143', 'AVG BPM']],
    zones: [8, 21, 24, 5, 1], zoneNote: 'Most time in Zone 3',
    state: 'typed',
    candidates: [
      { t: 'Tempo 40/20s', src: 'STRYD · 12:50 TODAY', icon: 'run' },
      { t: 'Zone 2 base run', src: 'MY WORKOUTS', icon: 'run' },
    ],
  },
  blank: {
    title: 'Lunch Workout', time: '12:44 – 12:52', kind: 'UNKNOWN',
    icon: 'lift', iconBg: 'rgba(255,255,255,0.09)',
    stats: [['8', 'MIN'], ['50', 'CAL'], ['—', 'AVG BPM'], ['—', 'MAX BPM']],
    zones: null, zoneNote: null,
    state: 'blank',
    candidates: [
      { t: 'Lower body — posterior', src: 'MY WORKOUTS · FROM COACH MIKE', icon: 'lift' },
      { t: 'DB Full-body AMRAP', src: 'MY WORKOUTS · FROM IG', icon: 'bolt' },
    ],
  },
};

function DDActivityScreen({ dd, set, nav }) {
  const a = DD_ACTIVITIES[dd.activityId] || DD_ACTIVITIES.run;
  const [mapOpen, setMapOpen] = React.useState(false);
  const [mappedTo, setMappedTo] = React.useState(null);
  const zoneColors = ['#5AB8F4', '#4AD97F', 'var(--ready-high)', 'var(--ready-mod)', '#F4564A'];
  const zTotal = a.zones ? a.zones.reduce((x, y) => x + y, 0) : 0;

  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => nav('dd-today')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Today
        </div>
      </div>
      <ScreenPad>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 8 }}>
          <IconChip name={a.icon} bg={a.iconBg}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 22, fontWeight: 800 }}>
              {a.title}</div>
            <div className="af-mono" style={{ fontSize: 10, color: 'var(--fg-dim)',
              marginTop: 3 }}>{a.time} · {a.kind} · IMPORTED FROM STRAVA</div>
          </div>
        </div>

        {/* Match state — the honest header */}
        {a.state === 'matched' && (
          <div style={{ marginTop: 12, padding: '11px 13px', borderRadius: 14,
            background: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
            border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="check" size={14} style={{ color: 'var(--ready-high)' }}/>
              <span className="dd-display" style={{ fontSize: 13, fontWeight: 700,
                color: 'var(--ready-high)' }}>Verified workout</span>
            </div>
            <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 5,
              lineHeight: 1.5 }}>{a.matchNote}</div>
          </div>
        )}
        {a.state !== 'matched' && !mappedTo && (
          <div style={{ marginTop: 12, padding: '11px 13px', borderRadius: 14,
            background: 'color-mix(in oklch, var(--ready-mod), transparent 88%)',
            border: '1px solid color-mix(in oklch, var(--ready-mod), transparent 60%)' }}>
            <div className="dd-display" style={{ fontSize: 13, fontWeight: 700 }}>
              {a.state === 'blank' ? 'What was this?' : 'Not linked to a workout yet'}
            </div>
            <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 4,
              lineHeight: 1.5 }}>
              {a.state === 'blank'
                ? 'Strava only sent time and calories. Map it to a workout you know, or add what you did.'
                : 'Map it to the workout it actually was — Stryd has one at the same time.'}
            </div>
          </div>
        )}
        {mappedTo && (
          <div style={{ marginTop: 12, padding: '11px 13px', borderRadius: 14,
            background: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
            border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="check" size={14} style={{ color: 'var(--ready-high)' }}/>
              <span className="dd-display" style={{ fontSize: 13, fontWeight: 700,
                color: 'var(--ready-high)' }}>Mapped to “{mappedTo}”</span>
            </div>
          </div>
        )}

        {/* Metrics grid */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr', gap: 8,
          marginTop: 14 }}>
          {a.stats.map(([v, k]) => (
            <div key={k} style={{ background: DD.card,
              border: '1px solid var(--border)', borderRadius: 14,
              padding: '12px 4px', textAlign: 'center' }}>
              <div className="dd-display" style={{ fontSize: 20, fontWeight: 800 }}>{v}</div>
              <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
                marginTop: 3 }}>{k}</div>
            </div>
          ))}
        </div>

        {/* HR zones — summary line + segment bar (Gentler-Streak voice) */}
        {a.zones && (
          <div style={{ background: DD.card, border: '1px solid var(--border)',
            borderRadius: 16, padding: '13px 14px', marginTop: 10 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <Icon name="heart" size={14} style={{ color: '#F4564A' }}/>
              <span className="dd-display" style={{ fontSize: 13, fontWeight: 700 }}>
                {a.zoneNote}</span>
              <span className="af-mono" style={{ marginLeft: 'auto', fontSize: 9,
                color: 'var(--fg-dim)' }}>HR ZONES</span>
            </div>
            <div style={{ display: 'flex', gap: 3, marginTop: 11, height: 10,
              borderRadius: 99, overflow: 'hidden' }}>
              {a.zones.map((z, i) => (
                <div key={i} style={{ flex: z, background: zoneColors[i],
                  opacity: z === Math.max(...a.zones) ? 1 : 0.45 }}/>
              ))}
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between',
              marginTop: 6 }}>
              {a.zones.map((z, i) => (
                <span key={i} className="af-mono" style={{ fontSize: 8.5,
                  color: 'var(--fg-dim)' }}>Z{i + 1} · {Math.round(z / zTotal * 100)}%</span>
              ))}
            </div>
          </div>
        )}

        {/* Verified structure (matched only) */}
        {a.structure && (
          <div style={{ background: DD.card, border: '1px solid var(--border)',
            borderRadius: 16, padding: '4px 14px', marginTop: 10 }}>
            {a.structure.map((s, i) => (
              <div key={s} style={{ display: 'flex', alignItems: 'center', gap: 10,
                padding: '10px 0',
                borderTop: i === 0 ? 'none' : '1px solid var(--border)' }}>
                <span className="af-mono" style={{ fontSize: 10,
                  color: 'var(--fg-dim)', width: 18 }}>{String(i + 1).padStart(2, '0')}</span>
                <span style={{ fontSize: 13, fontWeight: 500 }}>{s}</span>
              </div>
            ))}
          </div>
        )}

        {/* Actions by state — mapping instead of editing */}
        {a.state !== 'matched' && !mappedTo && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 16 }}>
            <div className="dd-display dd-glow" onClick={() => setMapOpen(true)}
              style={{ background: DD.lime, color: DD.ink, borderRadius: 999,
                padding: '14px 0', textAlign: 'center', fontSize: 14.5,
                fontWeight: 700, cursor: 'pointer' }}>
              Map to a workout
            </div>
            <div className="dd-display" onClick={() => nav('dd-editor-backfill')}
              style={{ background: DD.card2, borderRadius: 999, padding: '14px 0',
                textAlign: 'center', fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
              {a.state === 'blank'
                ? 'Create as strength workout + add exercises'
                : 'Add details manually'}
            </div>
          </div>
        )}
        {(a.state === 'matched' || mappedTo) && (
          <div style={{ fontSize: 11, color: 'var(--fg-dim)', textAlign: 'center',
            marginTop: 16 }}>
            Counted as a real workout in Progress ✓
          </div>
        )}
      </ScreenPad>

      {/* Map sheet — candidates from other sources at matching times */}
      <Sheet open={mapOpen} onClose={() => setMapOpen(false)} title="Map to a workout">
        <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginBottom: 12,
          lineHeight: 1.5 }}>
          Same-day workouts from your sources. Mapping attaches the structure to
          this activity — nothing is duplicated.
        </div>
        {(a.candidates || []).map(c => (
          <div key={c.t} onClick={() => { setMapOpen(false); setMappedTo(c.t);
              set(s => ({ ...s, toast: `Mapped — “${c.t}” now owns these metrics` })); }}
            style={{ display: 'flex', alignItems: 'center', gap: 12,
              background: DD.card, border: '1px solid var(--border)',
              borderRadius: 16, padding: '12px 14px', marginBottom: 8,
              cursor: 'pointer' }}>
            <IconChip name={c.icon} bg={DD.card2} size={32}/>
            <div style={{ flex: 1 }}>
              <div className="dd-display" style={{ fontSize: 13.5, fontWeight: 700 }}>{c.t}</div>
              <div className="af-mono" style={{ fontSize: 9, color: 'var(--fg-dim)',
                marginTop: 2 }}>{c.src}</div>
            </div>
            <Icon name="link" size={14} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}
        <div className="dd-display" onClick={() => { setMapOpen(false);
            set(s => ({ ...s, toast: 'Would search all workouts' })); }}
          style={{ textAlign: 'center', padding: '12px 0', fontSize: 12.5,
            fontWeight: 700, color: 'var(--fg-muted)', cursor: 'pointer' }}>
          Search all workouts…
        </div>
      </Sheet>
    </>
  );
}

// ------------------------------------------------------------------ Phone player
// Apple Fitness voice: black stats stage with giant colorful mono numerals,
// detached rounded control dock — big center pause like a music player.
function DDPlayerScreen({ dd, set, nav }) {
  const BLOCKS = [
    { n: 'SkiErg', detail: '250 m hard', secs: 90 },
    { n: 'Sled push', detail: '2 × 20 m · 80 kg', secs: 120 },
    { n: 'Burpee broad jumps', detail: '10 reps', secs: 100 },
    { n: 'Rower', detail: '500 m', secs: 110 },
    { n: 'Wall balls', detail: '20 reps · 6 kg', secs: 90 },
    { n: 'DB thrusters', detail: '12 reps · 2×16', secs: 90 },
    { n: 'Farmer carry', detail: '2 × 30 m · 2×32', secs: 100 },
    { n: 'Rower — finisher', detail: '400 m all-out', secs: 90 },
  ];
  const [bi, setBi] = React.useState(2);            // current block index
  const [left, setLeft] = React.useState(74);       // seconds left in block
  const [total, setTotal] = React.useState(9 * 60 + 42);
  const [paused, setPaused] = React.useState(false);
  const [endOpen, setEndOpen] = React.useState(false);

  React.useEffect(() => {
    if (paused) return;
    const t = setInterval(() => {
      setTotal(x => x + 1);
      setLeft(x => {
        if (x > 1) return x - 1;
        setBi(b => Math.min(b + 1, BLOCKS.length - 1));
        return BLOCKS[Math.min(bi + 1, BLOCKS.length - 1)].secs;
      });
    }, 1000);
    return () => clearInterval(t);
  }, [paused, bi]);

  const mmss = (s) => `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  const jump = (d) => {
    const t = Math.min(Math.max(bi + d, 0), BLOCKS.length - 1);
    setBi(t); setLeft(BLOCKS[t].secs);
  };
  const RoundBtn = ({ children, onClick, size = 54, bg = DD.card2, color = 'var(--fg)' }) => (
    <div onClick={onClick} style={{ width: size, height: size, borderRadius: 999,
      background: bg, color, display: 'flex', alignItems: 'center',
      justifyContent: 'center', cursor: 'pointer', flexShrink: 0 }}>{children}</div>
  );
  const b = BLOCKS[bi];

  return (
    <>
      {/* Stats stage */}
      <div style={{ flex: 1, background: '#000', padding: '10px 20px 0',
        display: 'flex', flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <div className="dd-display" onClick={() => setEndOpen(true)}
            style={{ width: 40, height: 40, borderRadius: 999, background: DD.card2,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: 'pointer' }}>
            <Icon name="chevD" size={18}/>
          </div>
          <span className="af-mono" style={{ marginLeft: 'auto', fontSize: 10.5,
            color: 'var(--fg-muted)' }}>HYROX SIM · ON PHONE · NO WATCH NEEDED</span>
        </div>

        <div style={{ marginTop: 26 }}>
          <div className="af-mono" style={{ fontSize: 12, color: 'var(--fg-muted)' }}>
            BLOCK <span style={{ color: '#fff' }}>{bi + 1}</span> OF {BLOCKS.length}
          </div>
          <div className="dd-display" style={{ fontSize: 30, fontWeight: 800,
            marginTop: 6, color: '#fff' }}>{b.n}</div>
          <div className="dd-display" style={{ fontSize: 16, fontWeight: 600,
            marginTop: 4, color: DD.blue }}>{b.detail}</div>
        </div>

        {/* The giant numeral — block countdown */}
        <div style={{ marginTop: 24 }}>
          <div className="af-mono" style={{ fontSize: 76, fontWeight: 600,
            letterSpacing: '-0.04em', lineHeight: 1,
            color: paused ? 'var(--fg-dim)' : DD.lime,
            fontVariantNumeric: 'tabular-nums' }}>
            {mmss(left)}
          </div>
          <div className="af-mono" style={{ fontSize: 11, color: 'var(--fg-muted)',
            marginTop: 8 }}>THIS BLOCK{paused ? ' · PAUSED' : ''}</div>
        </div>

        <div style={{ marginTop: 'auto', paddingBottom: 14 }}>
          <div className="af-mono" style={{ fontSize: 12, color: 'var(--fg-muted)' }}>
            NEXT · <span style={{ color: '#fff' }}>
              {bi < BLOCKS.length - 1 ? `${BLOCKS[bi + 1].n.toUpperCase()} — ${BLOCKS[bi + 1].detail.toUpperCase()}` : 'DONE — LOG IT'}
            </span>
          </div>
          {/* Block progress dots */}
          <div style={{ display: 'flex', gap: 5, marginTop: 12 }}>
            {BLOCKS.map((_, i) => (
              <div key={i} style={{ flex: 1, height: 4, borderRadius: 99,
                background: i < bi ? DD.lime : i === bi ? '#fff' : DD.card2 }}/>
            ))}
          </div>
        </div>
      </div>

      {/* Control dock — music-player anatomy */}
      <div style={{ background: '#101012', borderRadius: '26px 26px 0 0',
        padding: '10px 18px calc(16px)', borderTop: '1px solid var(--border)' }}>
        <div style={{ width: 36, height: 4, borderRadius: 99, background: DD.card2,
          margin: '0 auto 12px' }}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10,
          marginBottom: 14 }}>
          <div style={{ width: 30, height: 30, borderRadius: 999, background: DD.card2,
            display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="flame" size={15} style={{ color: DD.lime }}/>
          </div>
          <span className="af-mono" style={{ fontSize: 24, fontWeight: 600,
            color: '#F5D90A', fontVariantNumeric: 'tabular-nums' }}>{mmss(total)}</span>
          <span className="af-mono" style={{ fontSize: 10, color: 'var(--fg-muted)' }}>
            ELAPSED</span>
          <span className="af-mono" style={{ marginLeft: 'auto', fontSize: 11,
            color: DD.red }}>♥ 152</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center',
          justifyContent: 'center', gap: 22 }}>
          <RoundBtn onClick={() => jump(-1)}>
            <Icon name="chevL" size={22}/>
          </RoundBtn>
          <RoundBtn onClick={() => setPaused(p => !p)} size={78} bg={DD.lime}
            color={DD.ink}>
            <Icon name={paused ? 'play' : 'pause'} size={30}/>
          </RoundBtn>
          <RoundBtn onClick={() => jump(1)}>
            <Icon name="chevR" size={22}/>
          </RoundBtn>
        </div>
        {endOpen ? (
          <div className="dd-display" onClick={() => {
              set(s => ({ ...s, push: 'done', toast: 'Session ended — log it on Today' }));
              nav('dd-today'); }}
            style={{ marginTop: 14, background: 'color-mix(in srgb, var(--destructive), transparent 82%)',
              border: '1px solid color-mix(in srgb, var(--destructive), transparent 50%)',
              color: DD.red, borderRadius: 999, padding: '13px 0', textAlign: 'center',
              fontSize: 14, fontWeight: 700, cursor: 'pointer' }}>
            ✕ End workout
          </div>
        ) : (
          <div className="dd-display" onClick={() => setEndOpen(true)}
            style={{ marginTop: 14, textAlign: 'center', fontSize: 12,
              fontWeight: 600, color: 'var(--fg-muted)', cursor: 'pointer' }}>
            End workout
          </div>
        )}
      </div>
    </>
  );
}

// ------------------------------------------------------------------ Device page
function DDDeviceScreen({ dd, set, nav }) {
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => nav('dd-today')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600, cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Back
        </div>
      </div>
      <ScreenPad>
        <div className="af-mono" style={{ fontSize: 10.5, color: DD.lime, marginTop: 8 }}>
          ● CONNECTED · SYNCED 2M AGO
        </div>
        <div className="dd-display" style={{ fontSize: 28, fontWeight: 800, marginTop: 6 }}>
          Amazfit T-Rex 3
        </div>

        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 18 }}>
          <span className="dd-display" style={{ fontSize: 64, fontWeight: 800,
            lineHeight: 1, color: DD.lime }}>78</span>
          <span className="dd-display" style={{ fontSize: 20, color: DD.lime }}>%</span>
          <span style={{ fontSize: 12, color: 'var(--fg-muted)', marginLeft: 8 }}>
            battery — enough for tonight
          </span>
        </div>

        <div className="dd-display" style={{ fontSize: 15, fontWeight: 700,
          margin: '24px 0 10px' }}>Queue</div>
        <div style={{ background: DD.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '12px 14px', display: 'flex',
          alignItems: 'center', gap: 12 }}>
          <IconChip name="check" bg={DD.lime}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 13, fontWeight: 700 }}>
              Hyrox Sim — Stations 1–4</div>
            <div className="af-mono" style={{ fontSize: 9.5, color: DD.lime,
              marginTop: 2 }}>DELIVERED 6:14 PM</div>
          </div>
        </div>
        <div style={{ background: DD.card, borderRadius: 16, padding: '12px 14px',
          marginTop: 8,
          border: '1px solid color-mix(in srgb, var(--destructive), transparent 55%)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <IconChip name="close" bg={DD.red}/>
            <div style={{ flex: 1 }}>
              <div className="dd-display" style={{ fontSize: 13, fontWeight: 700 }}>
                DB Full-body AMRAP</div>
              <div className="af-mono" style={{ fontSize: 9.5,
                color: 'var(--destructive)', marginTop: 2 }}>FAILED</div>
            </div>
          </div>
          <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 9,
            lineHeight: 1.5 }}>
            Block 4 uses “open reps” — the follow-along needs a fixed count or time.
          </div>
          <div className="dd-display" onClick={() => nav('dd-editor-import')}
            style={{ marginTop: 10, background: DD.card2, borderRadius: 999,
              padding: '9px 0', textAlign: 'center', fontSize: 12.5, fontWeight: 700,
              cursor: 'pointer' }}>
            Fix in editor →
          </div>
        </div>

        <div className="dd-display" style={{ fontSize: 15, fontWeight: 700,
          margin: '20px 0 2px' }}>Sessions on this watch</div>
        <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginBottom: 10 }}>
          Toggled-off types default to your other watch or the phone. Override
          per workout with a long-press on Push.
        </div>
        <div style={{ background: DD.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '4px 14px' }}>
          {[['Hyrox / HIIT', 'flame', DD.lime, true],
            ['Runs', 'run', DD.blue, false],
            ['Strength', 'lift', DD.purple, false],
            ['Everything else', 'msg', DD.card2, false]].map(([t, ic, c, on], i) => (
            <DDWatchSessionRow key={t} t={t} ic={ic} c={c} initial={on}
              first={i === 0} set={set}/>
          ))}
        </div>
      </ScreenPad>
    </>
  );
}

function DDWatchSessionRow({ t, ic, c, initial, first, set }) {
  const [on, setOn] = React.useState(initial);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0',
      borderTop: first ? 'none' : '1px solid var(--border)' }}>
      <IconChip name={ic} bg={c}/>
      <span className="dd-display" style={{ fontSize: 14, fontWeight: 700,
        flex: 1 }}>{t}</span>
      <div className="af-switch" data-on={on}
        onClick={() => { setOn(!on);
          set(s => ({ ...s, toast: on
            ? `${t} — now defaults to Garmin or phone`
            : `${t} — now lands on this watch` })); }}/>
    </div>
  );
}

Object.assign(window, {
  DDTabBar, DDTodayScreen, DDBuildScreen, DDEditorScreen,
  DDProfileScreen, DDSettingsScreen, DDDeviceScreen, DDPlayerScreen, DDGymScreen,
  DDDetailScreen, DDActivityScreen, CreateSheet,
});
