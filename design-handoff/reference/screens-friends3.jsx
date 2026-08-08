/**
 * Friends — ORIGIN + MANAGE/REMOVE (2026-08-08). DISPOSABLE.
 * David's final placement call: Friends originates on PROFILE (not the
 * Settings row) — a row between the week dots and the needs-attention
 * card, ported from his live Profile screenshot (identity · 2×2 tiles ·
 * week dots · amber backfill · This week · floating island + FAB).
 * Manage/remove: our own AMA-2375 precedent (Peloton Edit mode, ⊖ rows)
 * + Mobbin: Locket ✕-row + consequence dialog (a168a4f8), Finch "They
 * will not be notified" (18f96553), Slopes Manage section (e0a7d749).
 * FP prefix. Presets: profile / manage.
 */

const FP = {
  lime: 'var(--ready-high)', amber: 'var(--ready-mod)', ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)', card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', purple: '#C58AF4', red: '#F4564A',
};

function FPChip({ name, bg, size = 34 }) {
  return (
    <div style={{ width: size, height: size,
      borderRadius: Math.round(size * 0.29), background: bg, color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      flexShrink: 0 }}>
      <Icon name={name} size={Math.round(size * 0.47)}/>
    </div>
  );
}

function FPAv({ name, color, size = 34 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: 999,
      background: 'color-mix(in oklch, ' + color + ', transparent 72%)',
      color, display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontWeight: 800, fontSize: size * 0.38, flexShrink: 0,
      fontFamily: 'Poppins, sans-serif' }}>
      {name.split(' ').map(w => w[0]).join('').slice(0, 2)}
    </div>
  );
}

function FPTabBar({ toast }) {
  const items = [['sun', 'Today', false], ['bookmark', 'Library', false],
    ['user', 'Profile', true]];
  return (
    <>
      <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
        zIndex: 30, background: 'rgba(16,16,18,0.96)',
        border: '1px solid rgba(255,255,255,0.08)', borderRadius: 32,
        padding: '10px 8px 8px', display: 'flex', alignItems: 'center',
        backdropFilter: 'blur(14px)',
        boxShadow: '0 10px 30px rgba(0,0,0,.55)' }}>
        {items.map(([ic, name, on]) => (
          <div key={name} style={{ flex: 1, display: 'flex',
            flexDirection: 'column', alignItems: 'center', gap: 3,
            color: on ? FP.lime : 'var(--fg-dim)' }}>
            <Icon name={ic} size={20}/>
            <span className="dd-display" style={{ fontSize: 10,
              fontWeight: 600 }}>{name}</span>
          </div>
        ))}
      </div>
      <div onClick={() => toast('＋ — Add workout sheet (unchanged)')}
        style={{ position: 'absolute', right: 18, bottom: 92, zIndex: 31,
          width: 56, height: 56, borderRadius: 999, background: FP.lime,
          color: FP.ink, display: 'flex', alignItems: 'center',
          justifyContent: 'center', cursor: 'pointer',
          boxShadow: '0 0 28px color-mix(in oklch, var(--ready-high), transparent 45%)' }}>
        <Icon name="plus" size={25}/>
      </div>
    </>
  );
}

// -------- ORIGIN · Profile (real anatomy) + the Friends row
function FPProfileScreen({ set }) {
  const toast = (t) => set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '8px 18px 0', display: 'flex',
        alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>
          Profile</div>
        <div style={{ marginLeft: 'auto', width: 38, height: 38,
          borderRadius: 999, background: FP.card2, display: 'flex',
          alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="gear" size={18}/>
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '6px 18px 96px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12,
          marginTop: 10 }}>
          <div className="dd-display" style={{ width: 44, height: 44,
            borderRadius: 999, background: FP.lime, color: FP.ink,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontSize: 17, fontWeight: 800 }}>D</div>
          <div>
            <div className="dd-display" style={{ fontSize: 16,
              fontWeight: 800 }}>David</div>
            <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
              marginTop: 1 }}>Hyrox prep · Week 3 of 12</div>
          </div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8,
          marginTop: 14 }}>
          {[['2/5', 'sessions this week', FP.lime],
            ['1h 7m', 'training time', '#fff'],
            ['1 🔥', 'day streak · best 1', '#fff'],
            ['2', 'sessions in August', '#fff']].map(([v, k, c]) => (
            <div key={k} style={{ background: FP.card,
              border: '1px solid var(--border)', borderRadius: 16,
              padding: '13px 14px', display: 'flex', alignItems: 'center',
              gap: 8 }}>
              <div style={{ flex: 1 }}>
                <div className="dd-display" style={{ fontSize: 21,
                  fontWeight: 800, color: c }}>{v}</div>
                <div style={{ fontSize: 10, color: 'var(--fg-muted)',
                  marginTop: 2 }}>{k}</div>
              </div>
              <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 6, justifyContent: 'center',
          marginTop: 12 }}>
          {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, i) => (
            <div key={i} className="dd-display" style={{ width: 28,
              height: 28, borderRadius: 999, display: 'flex',
              alignItems: 'center', justifyContent: 'center',
              fontSize: 10.5, fontWeight: 700,
              background: i === 5 ? FP.lime : FP.card2,
              color: i === 5 ? FP.ink : 'var(--fg-dim)' }}>{d}</div>
          ))}
        </div>

        {/* THE FRIENDS ROW — the origin. This-week row anatomy. */}
        <div onClick={() => toast('Opens Friends (manage panel next)')}
          style={{ display: 'flex', alignItems: 'center', gap: 12,
            background: FP.card, border: '1px solid var(--border)',
            borderRadius: 16, padding: '11px 13px', marginTop: 14,
            cursor: 'pointer' }}>
          <FPChip name="users" bg={FP.purple} size={34}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 13.5,
              fontWeight: 600 }}>Friends</div>
            <div className="af-mono" style={{ fontSize: 9, marginTop: 3,
              color: 'var(--fg-dim)' }}>3 FRIENDS · 2 WORKOUTS WAITING</div>
          </div>
          <span className="dd-display" style={{ background: FP.lime,
            color: FP.ink, borderRadius: 999, minWidth: 20, height: 20,
            display: 'inline-flex', alignItems: 'center',
            justifyContent: 'center', fontSize: 11, fontWeight: 800,
            padding: '0 6px' }}>2</span>
          <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>
        </div>

        <div style={{ marginTop: 10, padding: '12px 14px', borderRadius: 16,
          display: 'flex', alignItems: 'center', gap: 12,
          background: 'color-mix(in oklch, var(--ready-mod), transparent 86%)',
          border: '1px solid color-mix(in oklch, var(--ready-mod), transparent 55%)' }}>
          <FPChip name="lift" bg={'var(--ready-mod)'} size={30}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 13,
              fontWeight: 700 }}>Monday's strength needs weights</div>
            <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
              marginTop: 1 }}>2-minute backfill</div>
          </div>
          <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
        </div>

        <div style={{ display: 'flex', alignItems: 'center',
          margin: '20px 0 10px' }}>
          <span className="dd-display" style={{ fontSize: 15,
            fontWeight: 700 }}>This week</span>
        </div>
        {[['Lunch Run', 'run', FP.blue, '8.2', 'KM', 'SAT · 59 MIN · 143 BPM · GARMIN'],
          ['Lunch Workout', 'bolt', FP.blue, '8', 'MIN', 'SAT · 8 MIN · STRAVA']].map(([t, ic, bg, big, unit, meta]) => (
          <div key={t} style={{ display: 'flex', alignItems: 'center',
            gap: 12, background: FP.card, border: '1px solid var(--border)',
            borderRadius: 16, padding: '11px 13px', marginBottom: 8 }}>
            <FPChip name={ic} bg={bg} size={34}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="dd-display" style={{ fontSize: 13.5,
                fontWeight: 600 }}>{t}</div>
              <div className="af-mono" style={{ fontSize: 9, marginTop: 3,
                color: 'var(--fg-dim)' }}>{meta}</div>
            </div>
            <div style={{ textAlign: 'right', flexShrink: 0 }}>
              <span className="dd-display" style={{ fontSize: 18,
                fontWeight: 800 }}>{big}</span>
              <span className="af-mono" style={{ fontSize: 8.5,
                color: 'var(--fg-dim)', marginLeft: 2 }}>{unit}</span>
            </div>
            <Icon name="chevR" size={13} style={{ color: 'var(--fg-dim)' }}/>
          </div>
        ))}
      </div>
      <FPTabBar toast={toast}/>
    </>
  );
}

// -------- MANAGE · Friends list w/ Edit mode + remove confirm
function FPManageScreen({ set }) {
  const toast = (t) => set(s => ({ ...s, toast: t }));
  const [editing, setEditing] = React.useState(true);
  const [confirming, setConfirming] = React.useState('Priya S.');
  const friends = [
    ['Marcus O.', '@marcus_lifts', FP.blue, '4 WORKOUTS BETWEEN YOU'],
    ['Priya S.', '@priya.runs', FP.purple, 'ADDED THIS WEEK'],
    ['Tomás R.', '@tomas_engine', FP.amber, '1 WORKOUT FROM THEM'],
  ];
  return (
    <>
      <div style={{ padding: '10px 18px 0', display: 'flex',
        alignItems: 'flex-start' }}>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
            <Icon name="chevL" size={16}/> Profile
          </div>
          <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
            marginTop: 8 }}>Friends</div>
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
          <span onClick={() => setEditing(e => !e)} className="dd-display"
            style={{ fontSize: 12.5, fontWeight: 700,
              color: editing ? FP.lime : 'var(--fg-muted)',
              border: '1px solid var(--border-str)', borderRadius: 999,
              padding: '7px 14px', cursor: 'pointer' }}>
            {editing ? 'Done' : 'Edit'}</span>
          <div onClick={() => toast('Opens Add a friend (username / link / requests)')}
            style={{ width: 32, height: 32, borderRadius: 999,
              background: FP.card2, display: 'flex', alignItems: 'center',
              justifyContent: 'center', cursor: 'pointer' }}>
            <Icon name="plus" size={15} style={{ color: FP.lime }}/>
          </div>
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 20px' }}>
        {friends.map(([n, u, c, rel]) => (
          <React.Fragment key={u}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 11,
              background: FP.card,
              border: confirming === n && editing
                ? '1px solid color-mix(in oklch, #F4564A, transparent 55%)'
                : '1px solid var(--border)',
              borderRadius: 14, padding: '12px 13px', marginBottom: 8 }}>
              {editing && (
                <div onClick={() => setConfirming(n)}
                  style={{ width: 22, height: 22, borderRadius: 999,
                    background: 'color-mix(in oklch, #F4564A, transparent 78%)',
                    color: FP.red, display: 'flex', alignItems: 'center',
                    justifyContent: 'center', cursor: 'pointer',
                    fontWeight: 800, fontSize: 14, flexShrink: 0 }}>⊖</div>
              )}
              <FPAv name={n} color={c}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="dd-display" style={{ fontSize: 13.5,
                  fontWeight: 700 }}>{n}</div>
                <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
                  color: 'var(--fg-dim)' }}>{u} · {rel}</div>
              </div>
              {!editing && (
                <div className="dd-display"
                  onClick={() => toast('Opens send picker · ' + n.split(' ')[0] + ' pre-selected')}
                  style={{ border: '1px solid var(--border-str)',
                    borderRadius: 999, padding: '7px 14px', fontSize: 11.5,
                    fontWeight: 700, cursor: 'pointer' }}>Send ▸</div>
              )}
            </div>
            {/* inline remove confirm — Finch/Locket copy */}
            {editing && confirming === n && (
              <div style={{ background: 'color-mix(in oklch, #F4564A, transparent 92%)',
                border: '1px solid color-mix(in oklch, #F4564A, transparent 60%)',
                borderRadius: 14, padding: '11px 13px', margin: '-2px 0 10px' }}>
                <div className="dd-display" style={{ fontSize: 13,
                  fontWeight: 700 }}>Remove {n.split(' ')[0]}?</div>
                <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
                  marginTop: 3, lineHeight: 1.5 }}>
                  They won't be notified. Workouts you saved from them stay
                  yours. You can add them again any time.</div>
                <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
                  <div className="dd-display"
                    onClick={() => { setConfirming(null);
                      toast(n.split(' ')[0] + ' removed — not notified'); }}
                    style={{ flex: 1, background: FP.red, color: '#fff',
                      borderRadius: 999, padding: '9px 0',
                      textAlign: 'center', fontSize: 12, fontWeight: 700,
                      cursor: 'pointer' }}>Remove</div>
                  <div className="dd-display"
                    onClick={() => setConfirming(null)}
                    style={{ flex: 1, background: FP.card2,
                      border: '1px solid var(--border-str)',
                      borderRadius: 999, padding: '9px 0',
                      textAlign: 'center', fontSize: 12, fontWeight: 700,
                      cursor: 'pointer' }}>Cancel</div>
                </div>
              </div>
            )}
          </React.Fragment>
        ))}
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          textAlign: 'center', marginTop: 8, lineHeight: 1.7 }}>
          FRIENDS CAN SEND YOU WORKOUTS — THEY CAN'T SEE YOUR HISTORY, STATS
          OR GYM. REMOVING IS SILENT.</div>
      </div>
    </>
  );
}

function DDFriends3Screen({ preset }) {
  const [st, set] = React.useState({ toast: null });
  React.useEffect(() => {
    if (!st.toast) return;
    const t = setTimeout(() => set(s => ({ ...s, toast: null })), 2600);
    return () => clearTimeout(t);
  }, [st.toast]);
  const body = preset === 'manage'
    ? <FPManageScreen set={set}/> : <FPProfileScreen set={set}/>;
  return (
    <div style={{ position: 'relative', display: 'flex',
      flexDirection: 'column', height: '100%' }}>
      {body}
      {st.toast && (
        <div style={{ position: 'absolute', bottom: 84, left: 14, right: 14,
          zIndex: 40, background: '#17181c',
          border: '1px solid var(--border-str)', borderRadius: 12,
          padding: '9px 13px', fontSize: 10.5, color: 'var(--fg-muted)',
          boxShadow: '0 10px 30px rgba(0,0,0,0.55)' }}>{st.toast}</div>
      )}
    </div>
  );
}

Object.assign(window, { DDFriends3Screen });
