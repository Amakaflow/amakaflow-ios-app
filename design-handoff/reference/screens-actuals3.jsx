/**
 * Sync additions pass 3 — the CONNECTION flows themselves (2026-08-07).
 * DISPOSABLE. David: "i dont see the connection flow to strava or apple".
 *  · SYAppleFlowScreen — Apple Health: our primer card (exactly which READ
 *    types we ask for, why, and the "Turn On All" coaching — the system
 *    sheet defaults everything OFF) + the mocked iOS Health permission
 *    sheet layered on top. No OAuth — it's a local permission grant.
 *  · SYStravaFlowScreen — Strava (and Garmin, same shape): in-app browser
 *    (ASWebAuthenticationSession) on strava.com/oauth/authorize — scope
 *    list shows READ activity ✓ and UPLOAD explicitly NOT REQUESTED.
 *  · SYLinkedScreen — back from OAuth: sources list flips Strava to
 *    CONNECTED ✓ with a DD Toast "Strava linked — pulling your last 30
 *    days…" → leads straight into the first-sync panel.
 * Garmin note: identical OAuth shape via connect.garmin.com (Connect API
 * consent). Apple is the odd one out (HealthKit sheet, not a browser).
 */

const SY3 = {
  lime: 'var(--ready-high)', amber: 'var(--ready-mod)', ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)', card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', iosBlue: '#0A84FF', orange: '#FC4C02',
};

function SY3Chip({ icon, bg, ink, size = 34 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: 999, background: bg,
      color: ink || '#fff', display: 'flex', alignItems: 'center',
      justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={icon} size={Math.round(size * 0.47)}/>
    </div>
  );
}

// -------- Apple Health — primer + mocked system permission sheet
function SYAppleFlowScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const row = (label, on = true) => (
    <div key={label} style={{ display: 'flex', alignItems: 'center',
      justifyContent: 'space-between', padding: '11px 0',
      borderTop: '1px solid rgba(255,255,255,0.08)' }}>
      <span style={{ fontSize: 13, fontWeight: 500 }}>{label}</span>
      <div style={{ width: 40, height: 24, borderRadius: 999,
        background: on ? '#30D158' : 'rgba(255,255,255,0.18)',
        position: 'relative', transition: 'background .15s' }}>
        <div style={{ width: 20, height: 20, borderRadius: 999,
          background: '#fff', position: 'absolute', top: 2,
          left: on ? 18 : 2 }}/>
      </div>
    </div>
  );
  return (
    <div style={{ position: 'relative', display: 'flex',
      flexDirection: 'column', height: '100%' }}>
      {/* our primer — what we ask, before iOS asks */}
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
          <Icon name="chevL" size={16}/> Connect
        </div>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
          marginTop: 10 }}>Apple Health</div>
        <div style={{ fontSize: 12, color: 'var(--fg-muted)', marginTop: 6,
          lineHeight: 1.55 }}>
          iOS will ask next. We request <b style={{ color: 'var(--fg)' }}>read
          only</b> — three things:
        </div>
        <div style={{ background: SY3.card, border: '1px solid var(--border)',
          borderRadius: 14, padding: '2px 13px', marginTop: 10 }}>
          {[['Workouts', 'THE SESSIONS THEMSELVES'],
            ['Heart rate', 'EFFORT — FEEDS RPE SUGGESTIONS'],
            ['Active energy', 'CALORIES ON YOUR CARDS']].map(([t, why], i) => (
            <div key={t} style={{ display: 'flex', alignItems: 'center',
              gap: 10, padding: '9px 0',
              borderTop: i === 0 ? 'none' : '1px solid var(--border)' }}>
              <Icon name="check" size={13} style={{ color: SY3.lime }}/>
              <span style={{ fontSize: 12.5, fontWeight: 600, flex: 1 }}>{t}</span>
              <span className="af-mono" style={{ fontSize: 7.5,
                color: 'var(--fg-dim)' }}>{why}</span>
            </div>
          ))}
        </div>
        <div style={{ fontSize: 11, color: SY3.amber, marginTop: 10,
          lineHeight: 1.5 }}>
          Apple's sheet starts with everything <b>off</b> — tap “Turn On
          All”, then Allow.
        </div>
      </div>

      {/* mocked iOS Health permission sheet */}
      <div style={{ marginTop: 'auto', background: '#1c1c1e',
        borderRadius: '18px 18px 0 0', padding: '14px 18px 22px',
        boxShadow: '0 -12px 40px rgba(0,0,0,0.6)' }}>
        <div style={{ width: 36, height: 4, borderRadius: 2,
          background: 'rgba(255,255,255,0.25)', margin: '0 auto 12px' }}/>
        <div style={{ display: 'flex', justifyContent: 'space-between',
          alignItems: 'center' }}>
          <span style={{ color: SY3.iosBlue, fontSize: 13,
            cursor: 'pointer' }}
            onClick={() => toast('Denied — sources screen shows NOT CONNECTED, retry any time')}>
            Don't Allow</span>
          <span style={{ fontSize: 13, fontWeight: 600 }}>Health Access</span>
          <span style={{ color: SY3.iosBlue, fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}
            onClick={() => toast('Allowed — linked ✓ pulling your last 30 days… (panel 5)')}>
            Allow</span>
        </div>
        <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)',
          marginTop: 10, lineHeight: 1.45 }}>
          “AmakaFlow” would like to read the following data. App explanation:
          fill your Today feed with finished workouts.
        </div>
        <div style={{ color: SY3.iosBlue, fontSize: 13, margin: '12px 0 2px',
          cursor: 'pointer' }}
          onClick={() => toast('All three toggles on — now Allow')}>
          Turn On All</div>
        {row('Workouts')}{row('Heart Rate')}{row('Active Energy')}
        <div style={{ fontSize: 9.5, color: 'rgba(255,255,255,0.4)',
          marginTop: 10 }}>
          AmakaFlow cannot write or change your Health data.</div>
      </div>
    </div>
  );
}

// -------- Strava (and Garmin) — in-app browser OAuth authorize
function SYStravaFlowScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const scope = (ok, t, sub) => (
    <div style={{ display: 'flex', gap: 10, padding: '10px 0',
      borderTop: '1px solid rgba(0,0,0,0.08)', alignItems: 'flex-start' }}>
      <span style={{ fontSize: 13, lineHeight: '18px',
        color: ok ? '#2c9e3f' : '#b0b3ba' }}>{ok ? '✓' : '✕'}</span>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 12.5, fontWeight: 600,
          color: ok ? '#1d1f24' : '#9a9da6',
          textDecoration: ok ? 'none' : 'line-through' }}>{t}</div>
        <div style={{ fontSize: 10, color: '#8a8d96', marginTop: 2 }}>{sub}</div>
      </div>
    </div>
  );
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* in-app browser chrome (ASWebAuthenticationSession) */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10,
        padding: '10px 14px', borderBottom: '1px solid var(--border)' }}>
        <span onClick={() => toast('Cancelled — back to Connect, nothing linked')}
          style={{ color: SY3.iosBlue, fontSize: 13, cursor: 'pointer' }}>Cancel</span>
        <div style={{ flex: 1, background: SY3.card2, borderRadius: 10,
          padding: '6px 0', textAlign: 'center' }}>
          <span className="af-mono" style={{ fontSize: 9.5,
            color: 'var(--fg-muted)' }}>🔒 strava.com/oauth/authorize</span>
        </div>
        <Icon name="refresh" size={15} style={{ color: 'var(--fg-dim)' }}/>
      </div>

      {/* strava page (light) */}
      <div style={{ flex: 1, background: '#f7f7fa', color: '#1d1f24',
        padding: '18px 18px 16px', display: 'flex',
        flexDirection: 'column' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <SY3Chip icon="run" bg={SY3.orange} size={34}/>
          <div>
            <div style={{ fontSize: 15, fontWeight: 800,
              fontFamily: 'Poppins, sans-serif' }}>Strava</div>
            <div style={{ fontSize: 10, color: '#8a8d96' }}>
              Authorize AmakaFlow to connect to Strava</div>
          </div>
        </div>
        <div style={{ background: '#fff', borderRadius: 14,
          border: '1px solid #e6e7ec', padding: '4px 14px', marginTop: 14 }}>
          {scope(true, 'View data about your activities',
            'Runs, rides, workouts — including those synced from other apps')}
          {scope(true, 'View your profile information', 'Name and units only')}
          {scope(false, 'Upload or edit your activities',
            'NOT REQUESTED — AmakaFlow never posts to Strava')}
        </div>
        <div onClick={() => toast('Authorized → back in app: Strava linked ✓ (panel 5)')}
          style={{ background: SY3.orange, color: '#fff', borderRadius: 8,
            padding: '12px 0', textAlign: 'center', fontSize: 13.5,
            fontWeight: 700, marginTop: 14, cursor: 'pointer' }}>
          Authorize</div>
        <div onClick={() => toast('Cancelled — back to Connect, nothing linked')}
          style={{ textAlign: 'center', fontSize: 12, color: '#8a8d96',
            marginTop: 10, cursor: 'pointer' }}>Cancel</div>
        <div style={{ marginTop: 'auto', fontSize: 9.5, color: '#9a9da6',
          textAlign: 'center', lineHeight: 1.5 }}>
          Signed in as David · not you? Log out on strava.com</div>
      </div>

      <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
        textAlign: 'center', padding: '9px 18px 12px', lineHeight: 1.6 }}>
        GARMIN: SAME FLOW VIA CONNECT.GARMIN.COM · APPLE HEALTH IS A SYSTEM
        PERMISSION, NOT A LOGIN (PANEL 3)</div>
    </div>
  );
}

// -------- Back from OAuth — linked ✓ + first pull kicks off
function SYLinkedScreen() {
  const src = (icon, bg, name, sub, right) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12,
      background: SY3.card, border: '1px solid var(--border)',
      borderRadius: 16, padding: '13px 14px', marginBottom: 9 }}>
      <SY3Chip icon={icon} bg={bg}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="dd-display" style={{ fontSize: 14.5,
          fontWeight: 700 }}>{name}</div>
        <div className="af-mono" style={{ fontSize: 8, marginTop: 3,
          color: 'var(--fg-dim)', lineHeight: 1.5 }}>{sub}</div>
      </div>
      {right}
    </div>
  );
  const linked = (fresh) => (
    <span className="af-mono" style={{ fontSize: 8.5, color: SY3.lime,
      fontWeight: 700 }}>{fresh ? 'LINKED ✓ JUST NOW' : 'CONNECTED ✓'}</span>
  );
  return (
    <div style={{ position: 'relative', display: 'flex',
      flexDirection: 'column', height: '100%' }}>
      {/* DD Toast — pull already running */}
      <div style={{ position: 'absolute', top: 10, left: 16, right: 16,
        zIndex: 5, background: '#17181c',
        border: '1px solid var(--border-str)', borderRadius: 999,
        padding: '10px 16px', display: 'flex', alignItems: 'center', gap: 10,
        boxShadow: '0 10px 30px rgba(0,0,0,0.55)' }}>
        <Icon name="check" size={15} style={{ color: SY3.lime }}/>
        <div style={{ flex: 1 }}>
          <div className="dd-display" style={{ fontSize: 12.5,
            fontWeight: 700 }}>Strava linked</div>
          <div className="af-mono" style={{ fontSize: 7.5,
            color: 'var(--fg-dim)', marginTop: 1 }}>
            PULLING YOUR LAST 30 DAYS…</div>
        </div>
      </div>

      <div style={{ padding: '54px 18px 0' }}>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800 }}>
          Pull your training in</div>
        <div style={{ fontSize: 11.5, color: 'var(--fg-muted)',
          margin: '6px 0 14px' }}>All three connected — Today fills itself
          from here.</div>
        {src('watch', SY3.card2, 'Apple Health',
          'WORKOUTS FROM YOUR APPLE WATCH · HEART RATE + CALORIES', linked())}
        {src('watch', SY3.blue, 'Garmin',
          'RUNS + STRENGTH · PULLED AUTOMATICALLY AFTER SYNC', linked())}
        {src('run', SY3.orange, 'Strava',
          'EVERYTHING YOU RECORD THERE · INCL. OTHER APPS VIA STRAVA',
          linked(true))}
        <div className="af-mono" style={{ fontSize: 8,
          color: 'var(--fg-dim)', border: '1px dashed var(--border-str)',
          borderRadius: 12, padding: '9px 12px', lineHeight: 1.7 }}>
          SAME WORKOUT FROM TWO SOURCES? WE KEEP ONE — WATCH BEATS PHONE,
          RICHER DATA WINS. NOTHING COUNTS TWICE.</div>
      </div>
    </div>
  );
}

function DDActuals3Screen({ preset }) {
  const [st, set] = React.useState({ toast: null });
  React.useEffect(() => {
    if (!st.toast) return;
    const t = setTimeout(() => set(s => ({ ...s, toast: null })), 2600);
    return () => clearTimeout(t);
  }, [st.toast]);
  let body;
  if (preset === 'strava') body = <SYStravaFlowScreen set={set}/>;
  else if (preset === 'linked') body = <SYLinkedScreen/>;
  else body = <SYAppleFlowScreen set={set}/>;
  return (
    <div style={{ position: 'relative', display: 'flex',
      flexDirection: 'column', height: '100%' }}>
      {body}
      {st.toast && (
        <div style={{ position: 'absolute', bottom: 18, left: 14, right: 14,
          zIndex: 9, background: '#17181c',
          border: '1px solid var(--border-str)', borderRadius: 12,
          padding: '9px 13px', fontSize: 10.5, color: 'var(--fg-muted)',
          boxShadow: '0 10px 30px rgba(0,0,0,0.55)' }}>{st.toast}</div>
      )}
    </div>
  );
}

Object.assign(window, { DDActuals3Screen, SYAppleFlowScreen,
  SYStravaFlowScreen, SYLinkedScreen });
