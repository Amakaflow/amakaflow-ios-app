/**
 * Friends & workout sharing — 2026-08-07. DISPOSABLE. DESIGN-ONLY (David
 * decides after review — not ticketed).
 * Scope v1: add friends (same-app), send workouts from YOUR library to a
 * friend, receive theirs into an inbox → save a COPY to your library.
 * No feed, no history visibility, no comments — sharing, not social.
 *
 * Honesty rules baked into copy:
 *  · privacy contract on the empty state + add screen: friends can SEND you
 *    workouts; they can NOT see your history, stats, or gym
 *  · a share is a SNAPSHOT COPY — "edits are yours, not theirs"; saving
 *    never links back
 *  · requests are explicit: Accept / Decline, sent shows PENDING w/ cancel
 *
 * Mobbin: Locket add-by-username + sent-requests (ed056d5e/8229a051),
 * BeReal invite-link card (d759adc7), yope multi-select send picker w/
 * counted CTA (2ddc79df), Plex share summary (6f712c3e), Hevy Share-Routine
 * menu + Save-as-Routine receive (15cb87a0/98431df5), Goodreads Requests.
 * FR prefix. Panels: teach / add / list / send / inbox / saved.
 */

const FR = {
  lime: 'var(--ready-high)', amber: 'var(--ready-mod)', red: '#F4564A',
  ink: '#0d1200', card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)', blue: '#5AB8F4', purple: '#B58CF4',
};

const FR_FRIENDS = [
  { n: 'Marcus O.', u: '@marcus_lifts', c: FR.blue, shared: '4 WORKOUTS BETWEEN YOU' },
  { n: 'Priya S.', u: '@priya.runs', c: FR.purple, shared: 'ADDED THIS WEEK' },
  { n: 'Tomás R.', u: '@tomas_engine', c: FR.amber, shared: '1 WORKOUT FROM THEM' },
];

function FRAvatar({ name, color, size = 34 }) {
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

function FRPrivacyNote() {
  return (
    <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
      border: '1px dashed var(--border-str)', borderRadius: 12,
      padding: '9px 12px', lineHeight: 1.7 }}>
      FRIENDS CAN SEND YOU WORKOUTS — THEY CAN'T SEE YOUR HISTORY, STATS
      OR GYM. REMOVE ANYONE ANY TIME; THEY AREN'T NOTIFIED.
    </div>
  );
}

// ---------------------------------------------- 1 · empty / teach
function FRTeachScreen({ go }) {
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
          <Icon name="chevL" size={16}/> Settings
        </div>
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
        justifyContent: 'center', padding: '0 18px 60px' }}>
        <div style={{ display: 'flex', justifyContent: 'center',
          marginBottom: 14 }}>
          <div style={{ display: 'flex' }}>
            <FRAvatar name="D A" color={FR.lime} size={42}/>
            <div style={{ marginLeft: -10 }}>
              <FRAvatar name="M O" color={FR.blue} size={42}/></div>
            <div style={{ marginLeft: -10 }}>
              <FRAvatar name="P S" color={FR.purple} size={42}/></div>
          </div>
        </div>
        <div className="dd-display" style={{ fontSize: 22, fontWeight: 800,
          textAlign: 'center', lineHeight: 1.25 }}>
          Train with your people</div>
        <div style={{ fontSize: 12, color: 'var(--fg-muted)', textAlign: 'center',
          marginTop: 8, lineHeight: 1.55 }}>
          Add friends on AmakaFlow and swap workouts — the leg day you built
          lands straight in their library, theirs in yours.
        </div>
        <div className="dd-display dd-glow" onClick={() => go && go('add')}
          style={{ background: FR.lime, color: FR.ink, borderRadius: 999,
            padding: '13px 0', textAlign: 'center', fontSize: 14,
            fontWeight: 700, cursor: 'pointer', marginTop: 18 }}>
          Add a friend
        </div>
        <div style={{ marginTop: 14 }}><FRPrivacyNote/></div>
      </div>
    </>
  );
}

// ---------------------------------------------- 2 · add friend
function FRAddScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
          <Icon name="chevL" size={16}/> Friends
        </div>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
          marginTop: 10 }}>Add a friend</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 20px' }}>
        {/* search by username */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 9,
          background: FR.card2, borderRadius: 12, padding: '10px 13px' }}>
          <Icon name="search" size={14} style={{ color: 'var(--fg-dim)' }}/>
          <span style={{ fontSize: 13 }}>priya<span style={{
            borderRight: '1.5px solid ' + FR.lime }}>​</span></span>
        </div>
        {/* result */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 11,
          background: FR.card, border: '1px solid var(--border)',
          borderRadius: 14, padding: '11px 13px', marginTop: 10 }}>
          <FRAvatar name="P S" color={FR.purple}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 13.5,
              fontWeight: 700 }}>Priya S.</div>
            <div className="af-mono" style={{ fontSize: 8.5, marginTop: 2,
              color: 'var(--fg-dim)' }}>@priya.runs</div>
          </div>
          <div className="dd-display"
            onClick={() => toast('Request sent — Priya has to accept')}
            style={{ background: FR.lime, color: FR.ink, borderRadius: 999,
              padding: '8px 16px', fontSize: 12, fontWeight: 700,
              cursor: 'pointer' }}>Request</div>
        </div>

        {/* invite link — BeReal card */}
        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '16px 0 7px' }}>
          NOT ON AMAKAFLOW YET?</div>
        <div onClick={() => toast('Link copied — adds you both when they join')}
          style={{ display: 'flex', alignItems: 'center', gap: 11,
            background: FR.card, border: '1px solid var(--border)',
            borderRadius: 14, padding: '11px 13px', cursor: 'pointer' }}>
          <Icon name="link" size={15} style={{ color: FR.lime }}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 12.5,
              fontWeight: 700 }}>Share your invite link</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
              color: 'var(--fg-dim)' }}>AMAKAFLOW.COM/ADD/DAVID · ADDS YOU BOTH
              WHEN THEY JOIN</div>
          </div>
          <Icon name="share" size={14} style={{ color: 'var(--fg-dim)' }}/>
        </div>

        {/* requests — Goodreads/Locket */}
        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '16px 0 7px' }}>REQUESTS</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11,
          background: FR.card, border: '1px solid var(--border)',
          borderRadius: 14, padding: '11px 13px', marginBottom: 8 }}>
          <FRAvatar name="J K" color={FR.blue}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 13,
              fontWeight: 700 }}>Jonas K.</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
              color: FR.amber }}>WANTS TO ADD YOU · @jonas.k</div>
          </div>
          <div className="dd-display"
            onClick={() => toast('Jonas added — you can swap workouts now')}
            style={{ background: FR.lime, color: FR.ink, borderRadius: 999,
              padding: '7px 13px', fontSize: 11.5, fontWeight: 700,
              cursor: 'pointer' }}>Accept</div>
          <span onClick={() => toast('Declined — Jonas is not told')}
            className="dd-display" style={{ fontSize: 11.5, fontWeight: 700,
              color: 'var(--fg-dim)', cursor: 'pointer' }}>Decline</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11,
          background: FR.card, border: '1px dashed var(--border-str)',
          borderRadius: 14, padding: '11px 13px', opacity: 0.8 }}>
          <FRAvatar name="S B" color={FR.amber}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="dd-display" style={{ fontSize: 13,
              fontWeight: 700 }}>Sara B.</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
              color: 'var(--fg-dim)' }}>YOU ASKED · PENDING</div>
          </div>
          <span onClick={() => toast('Request cancelled')}
            className="dd-display" style={{ fontSize: 11.5, fontWeight: 700,
              color: 'var(--fg-dim)', cursor: 'pointer' }}>Cancel</span>
        </div>

        <div style={{ marginTop: 16 }}><FRPrivacyNote/></div>
      </div>
    </>
  );
}

// ---------------------------------------------- 3 · friends list
function FRListScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '10px 18px 0', display: 'flex',
        alignItems: 'center' }}>
        <div style={{ flex: 1 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
            <Icon name="chevL" size={16}/> Settings
          </div>
          <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
            marginTop: 8 }}>Friends</div>
        </div>
        <div onClick={() => toast('Opens Add a friend (panel 2)')}
          style={{ width: 34, height: 34, borderRadius: 999,
            background: FR.card2, display: 'flex', alignItems: 'center',
            justifyContent: 'center', cursor: 'pointer' }}>
          <Icon name="plus" size={16} style={{ color: FR.lime }}/>
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 20px' }}>
        {/* inbox teaser — unread from friends */}
        <div onClick={() => toast('Opens From your people (panel 5)')}
          style={{ display: 'flex', alignItems: 'center', gap: 11,
            background: 'color-mix(in oklch, var(--ready-high), transparent 90%)',
            border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)',
            borderRadius: 14, padding: '11px 13px', marginBottom: 14,
            cursor: 'pointer' }}>
          <Icon name="inbox" size={16} style={{ color: FR.lime }}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 13,
              fontWeight: 700 }}>From your people</div>
            <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
              color: 'var(--fg-muted)' }}>2 WORKOUTS WAITING · MARCUS, TOMÁS</div>
          </div>
          <span className="dd-display" style={{ background: FR.lime,
            color: FR.ink, borderRadius: 999, minWidth: 20, height: 20,
            display: 'inline-flex', alignItems: 'center',
            justifyContent: 'center', fontSize: 11, fontWeight: 800 }}>2</span>
        </div>

        {FR_FRIENDS.map(f => (
          <div key={f.u} style={{ display: 'flex', alignItems: 'center',
            gap: 11, background: FR.card, border: '1px solid var(--border)',
            borderRadius: 14, padding: '12px 13px', marginBottom: 8 }}>
            <FRAvatar name={f.n} color={f.c}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="dd-display" style={{ fontSize: 13.5,
                fontWeight: 700 }}>{f.n}</div>
              <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
                color: 'var(--fg-dim)' }}>{f.u} · {f.shared}</div>
            </div>
            <div className="dd-display"
              onClick={() => toast('Opens the send picker with ' + f.n.split(' ')[0] + ' pre-selected')}
              style={{ border: '1px solid var(--border-str)',
                borderRadius: 999, padding: '7px 14px', fontSize: 11.5,
                fontWeight: 700, cursor: 'pointer' }}>Send ▸</div>
          </div>
        ))}
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          textAlign: 'center', marginTop: 10 }}>
          SWIPE A FRIEND TO REMOVE — THEY AREN'T NOTIFIED</div>
      </div>
    </>
  );
}

// ---------------------------------------------- 4 · send picker (LIVE)
function FRSendScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const [sel, setSel] = React.useState({ '@marcus_lifts': true });
  const n = Object.values(sel).filter(Boolean).length;
  return (
    <>
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{ width: 36, height: 4, borderRadius: 2,
          background: 'rgba(255,255,255,0.18)', margin: '0 auto 10px' }}/>
        <div className="dd-display" style={{ fontSize: 19, fontWeight: 800 }}>
          Send to a friend</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '10px 18px 0' }}>
        {/* what you're sending — Plex summary */}
        <div style={{ background: FR.card, border: '1px solid var(--border)',
          borderRadius: 14, padding: '11px 13px' }}>
          <div className="af-mono" style={{ fontSize: 7.5,
            color: 'var(--fg-dim)', marginBottom: 5 }}>FROM YOUR LIBRARY</div>
          <div className="dd-display" style={{ fontSize: 14.5,
            fontWeight: 700 }}>Lower body — posterior</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5,
            marginTop: 7 }}>
            {['5 EXERCISES', '3 × 5 MAIN', '52 MIN', 'BARBELL + BAND'].map(p => (
              <span key={p} className="af-mono" style={{ fontSize: 7.5,
                color: 'var(--fg-muted)', background: FR.card2,
                borderRadius: 999, padding: '3px 8px' }}>{p}</span>
            ))}
          </div>
        </div>

        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '13px 0 7px' }}>TO</div>
        {FR_FRIENDS.map(f => {
          const on = !!sel[f.u];
          return (
            <div key={f.u} onClick={() => setSel(s => ({ ...s, [f.u]: !on }))}
              style={{ display: 'flex', alignItems: 'center', gap: 11,
                background: FR.card,
                border: on
                  ? '1px solid color-mix(in oklch, var(--ready-high), transparent 45%)'
                  : '1px solid var(--border)',
                borderRadius: 14, padding: '10px 13px', marginBottom: 7,
                cursor: 'pointer' }}>
              <FRAvatar name={f.n} color={f.c} size={30}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="dd-display" style={{ fontSize: 13,
                  fontWeight: 700 }}>{f.n}</div>
              </div>
              <div style={{ width: 20, height: 20, borderRadius: 999,
                border: on ? 'none' : '1.5px solid var(--border-str)',
                background: on ? FR.lime : 'transparent', display: 'flex',
                alignItems: 'center', justifyContent: 'center' }}>
                {on && <Icon name="check" size={12} style={{ color: FR.ink }}/>}
              </div>
            </div>
          );
        })}

        {/* optional note */}
        <div style={{ background: FR.card2, borderRadius: 12,
          padding: '10px 13px', margin: '6px 0 10px', fontSize: 12,
          color: 'var(--fg-muted)' }}>
          “the posterior day I promised”</div>
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          lineHeight: 1.6, marginBottom: 10 }}>
          THEY GET A COPY — YOUR ORIGINAL STAYS YOURS; THEIR EDITS DON'T
          TOUCH IT.</div>
      </div>
      <div style={{ padding: '10px 18px 14px',
        borderTop: '1px solid var(--border)' }}>
        <div className="dd-display"
          onClick={() => n > 0 && toast('Sending… → Sent to ' + n + ' ✓ (DD Toast morph)')}
          style={{ background: n > 0 ? FR.lime : FR.card2,
            color: n > 0 ? FR.ink : 'var(--fg-dim)', borderRadius: 999,
            padding: '13px 0', textAlign: 'center', fontSize: 14,
            fontWeight: 700, cursor: n > 0 ? 'pointer' : 'default',
            boxShadow: n > 0
              ? '0 0 26px color-mix(in oklch, var(--ready-high), transparent 50%)'
              : 'none' }}>
          {n > 0 ? `Send to ${n} friend${n > 1 ? 's' : ''}` : 'Pick a friend'}
        </div>
      </div>
    </>
  );
}

// ---------------------------------------------- 5 · inbox
function FRInboxScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const item = (from, c, title, note, meta, unread) => (
    <div style={{ background: FR.card,
      border: unread
        ? '1px solid color-mix(in oklch, var(--ready-high), transparent 55%)'
        : '1px solid var(--border)',
      borderRadius: 16, padding: '12px 13px', marginBottom: 9 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
        <FRAvatar name={from} color={c} size={26}/>
        <span className="af-mono" style={{ fontSize: 8, fontWeight: 700,
          color: unread ? FR.lime : 'var(--fg-dim)', flex: 1 }}>
          FROM {from.split(' ')[0].toUpperCase()} · {unread ? 'NEW' : 'SAVED ✓'}</span>
      </div>
      <div className="dd-display" style={{ fontSize: 15, fontWeight: 700,
        marginTop: 7 }}>{title}</div>
      {note && <div style={{ fontSize: 11, color: 'var(--fg-muted)',
        marginTop: 3 }}>“{note}”</div>}
      <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
        marginTop: 5 }}>{meta}</div>
      {unread && (
        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          <div className="dd-display"
            onClick={() => toast('Opens preview → Save to Library (panel 6)')}
            style={{ flex: 1.4, background: FR.lime, color: FR.ink,
              borderRadius: 999, padding: '9px 0', textAlign: 'center',
              fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
            Look inside</div>
          <div className="dd-display"
            onClick={() => toast('Dismissed — sender is not told')}
            style={{ flex: 1, background: FR.card2,
              border: '1px solid var(--border-str)', borderRadius: 999,
              padding: '9px 0', textAlign: 'center', fontSize: 12,
              fontWeight: 700, cursor: 'pointer' }}>Not for me</div>
        </div>
      )}
    </div>
  );
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
          <Icon name="chevL" size={16}/> Friends
        </div>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
          marginTop: 10 }}>From your people</div>
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          margin: '4px 0 12px' }}>SAVING PUTS A COPY IN YOUR LIBRARY — EDITS
          ARE YOURS, NOT THEIRS</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '0 18px 20px' }}>
        {item('Marcus O.', FR.blue, 'Engine EMOM · 24 min',
          'the one that wrecked me tuesday', '6 EXERCISES · EMOM 24 · KB + ROW', true)}
        {item('Tomás R.', FR.amber, 'Zone 2 + strides',
          null, 'RUN · 45 MIN · 6 × 20S STRIDES', true)}
        {item('Priya S.', FR.purple, 'Hip mobility reset',
          'do this after your posterior day', '5 STEPS · 12 MIN', false)}
      </div>
    </>
  );
}

// ---------------------------------------------- 6 · received detail → saved
function FRSavedScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
          <Icon name="chevL" size={16}/> From your people
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9,
          marginTop: 10 }}>
          <FRAvatar name="Marcus O." color={FR.blue} size={28}/>
          <span className="af-mono" style={{ fontSize: 8.5, fontWeight: 700,
            color: 'var(--fg-muted)' }}>FROM MARCUS · “the one that wrecked
            me tuesday”</span>
        </div>
        <div className="dd-display" style={{ fontSize: 22, fontWeight: 800,
          marginTop: 8 }}>Engine EMOM · 24 min</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 0' }}>
        <div className="af-mono" style={{ fontSize: 8, fontWeight: 700,
          color: FR.amber, borderLeft: '3px solid ' + FR.amber,
          padding: '3px 0 3px 9px', background: FR.card,
          borderRadius: '0 8px 8px 0' }}>EMOM · EVERY 1:00 × 24</div>
        {['Kettlebell swing — 15', 'Row — 12 cal', 'Burpee — 10',
          'Goblet squat — 12', 'Ski erg — 10 cal', 'Rest minute'].map((r, i) => (
          <div key={r} style={{ display: 'flex', gap: 10, alignItems: 'center',
            padding: '9px 2px 9px 12px',
            borderBottom: '1px solid var(--border)' }}>
            <span className="af-mono" style={{ fontSize: 8.5,
              color: 'var(--fg-dim)', width: 12 }}>{i + 1}</span>
            <span style={{ fontSize: 12.5, fontWeight: 500 }}>{r}</span>
          </div>
        ))}
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          margin: '12px 0', lineHeight: 1.6 }}>
          A SNAPSHOT FROM MARCUS'S LIBRARY — SAVING MAKES IT YOURS. YOUR
          EDITS NEVER CHANGE HIS COPY.</div>
      </div>
      <div style={{ padding: '10px 18px 14px',
        borderTop: '1px solid var(--border)' }}>
        <div className="dd-display dd-glow"
          onClick={() => toast('Saved ✓ — in your library · collections/watch from there')}
          style={{ background: FR.lime, color: FR.ink, borderRadius: 999,
            padding: '13px 0', textAlign: 'center', fontSize: 14,
            fontWeight: 700, cursor: 'pointer' }}>
          Save to Library</div>
        <div style={{ textAlign: 'center', marginTop: 9 }}>
          <span className="dd-display"
            onClick={() => toast('Dismissed — Marcus is not told')}
            style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-dim)',
              cursor: 'pointer' }}>Not for me</span>
        </div>
      </div>
    </>
  );
}

function DDFriendsScreen({ preset }) {
  const [st, set] = React.useState({ toast: null });
  React.useEffect(() => {
    if (!st.toast) return;
    const t = setTimeout(() => set(s => ({ ...s, toast: null })), 2600);
    return () => clearTimeout(t);
  }, [st.toast]);
  let body;
  if (preset === 'add') body = <FRAddScreen set={set}/>;
  else if (preset === 'list') body = <FRListScreen set={set}/>;
  else if (preset === 'send') body = <FRSendScreen set={set}/>;
  else if (preset === 'inbox') body = <FRInboxScreen set={set}/>;
  else if (preset === 'saved') body = <FRSavedScreen set={set}/>;
  else body = <FRTeachScreen go={() => set(s => ({ ...s,
    toast: 'Opens Add a friend (panel 2)' }))}/>;
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

Object.assign(window, { DDFriendsScreen });
