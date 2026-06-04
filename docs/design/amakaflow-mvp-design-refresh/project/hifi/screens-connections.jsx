/**
 * AmakaFlow — Connections hub + per-connection detail.
 * Reuses tokens.css + ui.jsx primitives. No new style language.
 *
 * The hub is the discoverability win: every external integration becomes a
 * status-bearing row (icon · name · what-it-does · live status). One detail
 * template backs Apple Watch, Garmin, Telegram, Sync & delivery, and Calendar.
 */

// ---- Connection registry ------------------------------------------------
// status: 'connected' | 'healthy' | 'off'
const AF_CONNECTIONS = [
  {
    id: 'applewatch', name: 'Apple Watch', icon: 'watch',
    blurb: 'Workouts & heart rate', status: 'connected',
    tile: 'neutral',
    desc: 'Reads your workouts, heart rate, and HRV so the coach can gauge readiness and load.',
    meta: [
      ['Device', 'Apple Watch Series 9'],
      ['Last sync', '2 min ago'],
      ['Reading', 'HR · HRV · Workouts · Sleep'],
    ],
    onLabel: 'Disconnect', offLabel: 'Connect Apple Watch',
  },
  {
    id: 'garmin', name: 'Garmin', icon: 'watch',
    blurb: 'Push workouts to your watch', status: 'off',
    tile: 'neutral', offCta: 'Connect',
    desc: 'Sends each session to your Garmin as a structured workout you can start from the wrist.',
    meta: [
      ['Account', 'Not linked'],
      ['Pushes', 'Structured intervals · targets'],
    ],
    onLabel: 'Disconnect', offLabel: 'Connect Garmin',
  },
  {
    id: 'telegram', name: 'Telegram', icon: 'plane',
    blurb: 'Coach check-ins & briefings', status: 'connected',
    tile: '#29B6F6',
    desc: 'Your morning briefing, evening check-in, and mid-day swap suggestions arrive as a chat.',
    meta: [
      ['Account', '@adaeze'],
      ['Briefings', 'Daily · 6:00 am'],
      ['Last message', 'Today · 6:01 am'],
    ],
    onLabel: 'Disconnect', offLabel: 'Connect Telegram',
  },
  {
    id: 'sync', name: 'Sync & delivery', icon: 'swap',
    blurb: 'Workout delivery status', status: 'healthy',
    tile: 'neutral',
    desc: 'Confirms each session reaches your watch and devices. Tap through for the full delivery timeline.',
    meta: [
      ['Status', 'All caught up'],
      ['Last delivery', "Today's threshold · 1 min ago"],
      ['Queue', 'Nothing pending'],
    ],
    onLabel: 'Pause delivery', offLabel: 'Resume delivery',
    timeline: true,
  },
  {
    id: 'calendar', name: 'Calendar', icon: 'cal',
    blurb: 'Schedule sessions', status: 'off',
    tile: 'neutral', offCta: 'Connect',
    desc: 'Drops each planned session onto your calendar so training fits around the rest of your day.',
    meta: [
      ['Account', 'Not linked'],
      ['Adds', 'Session time · duration · type'],
    ],
    onLabel: 'Disconnect', offLabel: 'Connect calendar',
  },
];

const afConnById = (id) => AF_CONNECTIONS.find(c => c.id === id);

// ---- Status pill (right side of a hub row, and the detail status row) ----
function ConnStatus({ status, offCta }) {
  if (status === 'off') {
    return (
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6,
        color: 'var(--fg-dim)' }}>
        <span style={{ fontSize: 13, fontWeight: 500 }}>{offCta || 'Connect'}</span>
        <Icon name="chevR" size={14}/>
      </span>
    );
  }
  const label = status === 'healthy' ? 'Healthy' : 'Connected';
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
      <span className="af-dot af-dot-high"/>
      <span style={{ fontSize: 13, fontWeight: 500 }}>{label}</span>
    </span>
  );
}

// ---- Icon tile ----------------------------------------------------------
function ConnTile({ conn, size = 38 }) {
  const brand = conn.tile && conn.tile !== 'neutral';
  return (
    <div style={{ width: size, height: size, borderRadius: 999, flexShrink: 0,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: brand ? conn.tile : 'var(--accent-bg)',
      color: brand ? '#fff' : 'var(--fg)' }}>
      <Icon name={conn.icon} size={Math.round(size * 0.46)}/>
    </div>
  );
}

// =================================================================== Hub
function ConnectionsHubScreen({ nav, state, setState }) {
  const connected = AF_CONNECTIONS.filter(c => c.status !== 'off').length;
  const toSetup = AF_CONNECTIONS.length - connected;

  return (
    <>
      <TopBar left={'<Back'} onLeft={() => nav('settings')}
        title="Connections" sub="Watches, messaging, and delivery"/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 20px' }}>
        {/* Overall summary */}
        <Card style={{ marginBottom: 18, display: 'flex', alignItems: 'center', gap: 12 }}>
          <span className="af-dot af-dot-high" style={{ flexShrink: 0 }}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>
              {connected} connected
              <span className="af-muted" style={{ fontWeight: 400 }}> · {toSetup} to set up</span>
            </div>
            <div className="af-muted" style={{ fontSize: 11, marginTop: 3 }}>
              Watches, messaging, and delivery
            </div>
          </div>
          <span className="af-mono af-muted" style={{ fontSize: 12, flexShrink: 0 }}>
            {connected}/{AF_CONNECTIONS.length}
          </span>
        </Card>

        <div className="af-label" style={{ marginBottom: 8 }}>ALL CONNECTIONS</div>
        <Card tight style={{ padding: 0 }}>
          <div style={{ padding: '0 14px' }}>
            {AF_CONNECTIONS.map(c => (
              <div key={c.id} className="af-row" onClick={() => nav('conn-' + c.id)}
                style={{ cursor: 'pointer' }}>
                <ConnTile conn={c} size={36}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 500 }}>{c.name}</div>
                  <div className="af-muted" style={{ fontSize: 11, marginTop: 2,
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {c.blurb}
                  </div>
                </div>
                <ConnStatus status={c.status} offCta={c.offCta}/>
              </div>
            ))}
          </div>
        </Card>

        <div style={{ marginTop: 18, padding: 12, borderRadius: 10,
          background: 'var(--bg-subtle)', display: 'flex', gap: 10,
          alignItems: 'flex-start' }}>
          <Icon name="info" size={14} style={{ color: 'var(--fg-muted)',
            flexShrink: 0, marginTop: 2 }}/>
          <div className="af-muted" style={{ fontSize: 11, lineHeight: 1.55 }}>
            Connect a watch to read readiness, messaging to hear from your coach, and a calendar to block out sessions.
          </div>
        </div>
      </div>
      <TabBar active={5} onChange={i => setState && setState(s => ({ ...s, tab: i }))}/>
    </>
  );
}

// =================================================================== Detail template
function ConnectionDetailScreen({ conn, nav, setState }) {
  const [on, setOn] = React.useState(conn.status !== 'off');
  const statusNow = on ? (conn.status === 'healthy' ? 'healthy' : 'connected') : 'off';

  const toggle = () => {
    const next = !on;
    setOn(next);
    setState && setState(s => ({ ...s,
      toast: next ? `${conn.name} connected` : `${conn.name} disconnected` }));
  };

  return (
    <>
      <TopBar left={'<Connections'} onLeft={() => nav('connections')}
        title={conn.name}/>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '0 20px 24px' }}>
        {/* Header: tile + one-line description */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center',
          textAlign: 'center', padding: '8px 0 22px' }}>
          <ConnTile conn={conn} size={64}/>
          <div className="af-h2" style={{ marginTop: 14 }}>{conn.name}</div>
          <div className="af-muted" style={{ fontSize: 12.5, marginTop: 6,
            lineHeight: 1.55, maxWidth: 260 }}>{conn.desc}</div>
        </div>

        {/* Status row */}
        <Card tight style={{ padding: '0 14px', marginBottom: 14 }}>
          <div className="af-row">
            <div style={{ flex: 1 }}>
              <div className="af-label">STATUS</div>
            </div>
            <ConnStatus status={statusNow} offCta={conn.offCta}/>
          </div>
        </Card>

        {/* Account / device info — only when connected */}
        {on && (
          <>
            <div className="af-label" style={{ marginBottom: 8 }}>
              {conn.id === 'telegram' ? 'ACCOUNT' : conn.id === 'sync' ? 'DELIVERY' : 'DEVICE'}
            </div>
            <Card tight style={{ padding: '0 14px', marginBottom: 14 }}>
              {conn.meta.map(([k, v], i) => (
                <div key={k} className="af-row">
                  <div className="af-muted" style={{ fontSize: 12.5, flex: 1 }}>{k}</div>
                  <div className="af-mono" style={{ fontSize: 12 }}>{v}</div>
                </div>
              ))}
            </Card>
            {conn.timeline && (
              <div style={{ marginBottom: 14 }}>
                <Btn variant="ghost" wide size="md" onClick={() => nav('watch-delivery')}>
                  <Icon name="list" size={14}/> View delivery timeline
                </Btn>
              </div>
            )}
          </>
        )}

        {/* Primary action */}
        <Btn variant={on ? 'ghost' : 'primary'} wide size="lg" onClick={toggle}
          style={on ? { color: 'var(--destructive)', borderColor: 'var(--border-str)' } : undefined}>
          {on ? conn.onLabel : conn.offLabel}
        </Btn>

        {/* Calm one-sentence footnote */}
        <div className="af-muted" style={{ fontSize: 11, lineHeight: 1.55,
          textAlign: 'center', marginTop: 14, padding: '0 8px' }}>
          {on
            ? 'You can disconnect any time — your history stays in AmakaFlow.'
            : 'Connecting takes a few seconds and you can disconnect whenever you like.'}
        </div>
      </div>
    </>
  );
}

// ---- Per-connection wrappers (one template, five configs) ---------------
const ConnAppleWatch = (p) => <ConnectionDetailScreen {...p} conn={afConnById('applewatch')}/>;
const ConnGarmin     = (p) => <ConnectionDetailScreen {...p} conn={afConnById('garmin')}/>;
const ConnTelegram   = (p) => <ConnectionDetailScreen {...p} conn={afConnById('telegram')}/>;
const ConnSync       = (p) => <ConnectionDetailScreen {...p} conn={afConnById('sync')}/>;
const ConnCalendar   = (p) => <ConnectionDetailScreen {...p} conn={afConnById('calendar')}/>;

Object.assign(window, {
  ConnectionsHubScreen, ConnectionDetailScreen,
  ConnAppleWatch, ConnGarmin, ConnTelegram, ConnSync, ConnCalendar,
  AF_CONNECTIONS,
});
