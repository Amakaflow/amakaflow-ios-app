/**
 * Friends — WHERE IT LIVES. v3 (2026-08-07): rebuilt against David's REAL
 * app screenshots (IMG_2267–2270) after two wrong passes. His direction:
 *  · SEND lives on the workout screen's EXISTING action row — Pin / Collect
 *    / To watch / Share — Share opens a sheet with "Send to a friend" on
 *    top + the system share below.
 *  · RECEIVE lives in the ＋ Add-workout sheet (Create with AI / Import
 *    from URL / Screenshot / Build from scratch) — new "From friends" row
 *    with a waiting badge; you review each and decide save / not.
 *  · DEDUPE: a received workout may already be in your library (same reel
 *    import, earlier share). Review shows an amber "you already have this"
 *    match card — Open yours / Save as copy anyway / Not for me. Never
 *    silently duplicate, never silently drop.
 * Ports match the shipped screens: detail hero + pill row + action tiles +
 * You-attribution + block rows + Edit/▸Start; Add-workout sheet row anatomy
 * (icon circle + title + sub). FR2 prefix. DISPOSABLE.
 */

const FR2 = {
  lime: 'var(--ready-high)', amber: 'var(--ready-mod)', ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)', card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', purple: '#C58AF4', red: '#F4564A',
};

const FR2_FRIENDS = [
  ['Marcus O.', FR2.blue], ['Priya S.', FR2.purple], ['Tomás R.', FR2.amber],
];

function FR2Av({ name, color, size = 30 }) {
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

// ---- 1 · Workout detail (real anatomy) → Share sheet w/ Send to a friend
function FR2DetailScreen({ set }) {
  const toast = (t) => set(s => ({ ...s, toast: t }));
  const [share, setShare] = React.useState(true);
  const [sel, setSel] = React.useState({ 'Marcus O.': true });
  const n = Object.values(sel).filter(Boolean).length;
  const tile = (icon, label, active) => (
    <div key={label} onClick={() => label === 'Share' && setShare(true)}
      style={{ flex: 1, borderRadius: 16, padding: '13px 0 11px',
        background: active ? FR2.lime : FR2.card,
        color: active ? FR2.ink : 'var(--fg)', textAlign: 'center',
        cursor: 'pointer', border: active ? 'none' : '1px solid var(--border)' }}>
      <Icon name={icon} size={17}/>
      <div className="dd-display" style={{ fontSize: 11.5, fontWeight: 700,
        marginTop: 5 }}>{label}</div>
    </div>
  );
  return (
    <>
      {/* hero */}
      <div style={{ background: 'linear-gradient(145deg, #2A3505, #0f1202)',
        padding: '12px 16px 14px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
          <div style={{ width: 32, height: 32, borderRadius: 999,
            background: 'rgba(0,0,0,0.4)', display: 'flex',
            alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="x" size={15}/></div>
          <div style={{ width: 32, height: 32, borderRadius: 999,
            background: 'rgba(0,0,0,0.4)', display: 'flex',
            alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="trash" size={14}/></div>
        </div>
        <div style={{ textAlign: 'center', padding: '16px 0 18px' }}>
          <Icon name="lift" size={34} style={{ opacity: 0.9 }}/>
        </div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {['CREATED BY YOU', '3 ROUNDS · ~17 MIN', 'STRENGTH'].map(p => (
            <span key={p} className="af-mono" style={{ fontSize: 8,
              fontWeight: 700, background: 'rgba(0,0,0,0.45)',
              borderRadius: 999, padding: '5px 10px' }}>{p}</span>
          ))}
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 16px 90px' }}>
        <div className="dd-display" style={{ fontSize: 26, fontWeight: 800,
          lineHeight: 1.15 }}>Full Body Aesthetics Session</div>
        <div style={{ display: 'flex', gap: 8, marginTop: 13 }}>
          {tile('pin', 'Pin', true)}{tile('collect', 'Collect')}
          {tile('watch', 'To watch')}{tile('share', 'Share')}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11,
          background: FR2.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '12px 13px', marginTop: 12 }}>
          <div className="dd-display" style={{ width: 34, height: 34,
            borderRadius: 999, background: FR2.lime, color: FR2.ink,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontWeight: 800, fontSize: 14 }}>Y</div>
          <div>
            <div className="dd-display" style={{ fontSize: 14.5,
              fontWeight: 700 }}>You</div>
            <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
              marginTop: 1 }}>Created manually</div>
          </div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11,
          background: FR2.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '12px 13px', marginTop: 10 }}>
          <div style={{ width: 34, height: 34, borderRadius: 10,
            background: FR2.card2, display: 'flex', alignItems: 'center',
            justifyContent: 'center' }}><Icon name="lift" size={15}/></div>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 14.5,
              fontWeight: 700 }}>Jump Rope</div>
            <div style={{ fontSize: 10.5, color: 'var(--fg-muted)',
              marginTop: 1 }}>1</div>
          </div>
          <Icon name="chevR" size={14} style={{ color: 'var(--fg-dim)' }}/>
        </div>
      </div>

      {/* Share sheet — Send to a friend on top, system share below */}
      {share && (
        <div style={{ position: 'absolute', inset: 0, zIndex: 20,
          background: 'rgba(0,0,0,0.55)', display: 'flex',
          alignItems: 'flex-end' }}>
          <div style={{ width: '100%', background: '#141416',
            borderRadius: '20px 20px 0 0', padding: '10px 18px 18px',
            boxShadow: '0 -14px 44px rgba(0,0,0,0.7)' }}>
            <div style={{ width: 36, height: 4, borderRadius: 2,
              background: 'rgba(255,255,255,0.22)', margin: '0 auto 12px' }}/>
            <div className="dd-display" style={{ fontSize: 19,
              fontWeight: 800 }}>Share</div>
            <div className="af-mono" style={{ fontSize: 8.5,
              color: 'var(--fg-dim)', margin: '12px 0 7px' }}>
              SEND TO A FRIEND — LANDS IN THEIR ＋ · FROM FRIENDS</div>
            {FR2_FRIENDS.map(([f, c]) => {
              const on = !!sel[f];
              return (
                <div key={f} onClick={() => setSel(s => ({ ...s, [f]: !on }))}
                  style={{ display: 'flex', alignItems: 'center', gap: 11,
                    background: FR2.card,
                    border: on
                      ? '1px solid color-mix(in oklch, var(--ready-high), transparent 45%)'
                      : '1px solid var(--border)',
                    borderRadius: 14, padding: '9px 12px', marginBottom: 6,
                    cursor: 'pointer' }}>
                  <FR2Av name={f} color={c}/>
                  <span className="dd-display" style={{ fontSize: 13,
                    fontWeight: 700, flex: 1 }}>{f}</span>
                  <div style={{ width: 19, height: 19, borderRadius: 999,
                    border: on ? 'none' : '1.5px solid var(--border-str)',
                    background: on ? FR2.lime : 'transparent',
                    display: 'flex', alignItems: 'center',
                    justifyContent: 'center' }}>
                    {on && <Icon name="check" size={11}
                      style={{ color: FR2.ink }}/>}
                  </div>
                </div>
              );
            })}
            <div className="dd-display"
              onClick={() => n > 0 && toast('Sending… → Sent to ' + n + ' ✓ — DD Toast morph')}
              style={{ background: n > 0 ? FR2.lime : FR2.card2,
                color: n > 0 ? FR2.ink : 'var(--fg-dim)', borderRadius: 999,
                padding: '12px 0', textAlign: 'center', fontSize: 13.5,
                fontWeight: 700, marginTop: 8,
                cursor: n > 0 ? 'pointer' : 'default' }}>
              {n > 0 ? `Send to ${n} friend${n > 1 ? 's' : ''}` : 'Pick a friend'}
            </div>
            <div onClick={() => toast('System share sheet — link, Messages, etc. (unchanged)')}
              style={{ display: 'flex', alignItems: 'center', gap: 10,
                padding: '12px 2px 2px', marginTop: 6,
                borderTop: '1px solid var(--border)', cursor: 'pointer' }}>
              <Icon name="share" size={14} style={{ color: 'var(--fg-muted)' }}/>
              <span style={{ fontSize: 12.5, color: 'var(--fg-muted)',
                fontWeight: 600 }}>Share elsewhere — link, Messages…</span>
            </div>
          </div>
        </div>
      )}
    </>
  );
}

// ---- 2 · ＋ Add workout sheet (real anatomy) + From friends row
function FR2AddScreen({ set }) {
  const toast = (t) => set(s => ({ ...s, toast: t }));
  const row = (iconBg, icon, iconInk, title, sub, extra, onTap) => (
    <div key={title} onClick={onTap}
      style={{ display: 'flex', alignItems: 'center', gap: 13,
        background: 'rgba(255,255,255,0.06)', borderRadius: 22,
        padding: '14px 15px', marginBottom: 10, cursor: 'pointer' }}>
      <div style={{ width: 42, height: 42, borderRadius: 999,
        background: iconBg, color: iconInk || '#fff', display: 'flex',
        alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon name={icon} size={18}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div className="dd-display" style={{ fontSize: 16.5,
          fontWeight: 800 }}>{title}</div>
        <div style={{ fontSize: 11.5, color: 'var(--fg-muted)',
          marginTop: 2 }}>{sub}</div>
      </div>
      {extra}
    </div>
  );
  return (
    <>
      {/* dimmed Library behind — real header */}
      <div style={{ opacity: 0.35, padding: '8px 16px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div className="dd-display" style={{ fontSize: 30, fontWeight: 800,
            flex: 1 }}>Library</div>
          <div style={{ position: 'relative', width: 36, height: 36,
            borderRadius: 999, background: FR2.card2, display: 'flex',
            alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="watch" size={16}/>
            <span className="dd-display" style={{ position: 'absolute',
              top: -3, right: -3, background: FR2.lime, color: FR2.ink,
              borderRadius: 999, width: 15, height: 15, fontSize: 9,
              fontWeight: 800, display: 'flex', alignItems: 'center',
              justifyContent: 'center' }}>2</span>
          </div>
          <div style={{ width: 36, height: 36, borderRadius: 999,
            background: FR2.lime, color: FR2.ink, display: 'flex',
            alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="plus" size={18}/></div>
        </div>
        <div className="dd-display" style={{ fontSize: 15, fontWeight: 700,
          margin: '16px 0 8px', color: 'var(--fg-muted)' }}>Collections</div>
        <div style={{ display: 'flex', gap: 10 }}>
          {['Abs', 'Emoms'].map(cn => (
            <div key={cn} style={{ flex: 1, background: FR2.card,
              borderRadius: 16, padding: 8 }}>
              <div style={{ display: 'grid',
                gridTemplateColumns: '1fr 1fr', gap: 3 }}>
                <div style={{ height: 34, borderRadius: 6,
                  background: 'linear-gradient(145deg,#2A3505,#0f1202)' }}/>
                <div style={{ height: 34, borderRadius: 6,
                  background: FR2.card2 }}/>
                <div style={{ height: 34, borderRadius: 6,
                  background: FR2.card2 }}/>
                <div style={{ height: 34, borderRadius: 6,
                  background: FR2.card2 }}/>
              </div>
              <div className="dd-display" style={{ fontSize: 13,
                fontWeight: 800, marginTop: 7 }}>{cn}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Add workout sheet — real anatomy + From friends */}
      <div style={{ marginTop: 'auto', background: '#161618',
        borderRadius: '24px 24px 0 0', padding: '12px 16px 16px',
        boxShadow: '0 -14px 44px rgba(0,0,0,0.7)' }}>
        <div style={{ width: 36, height: 4, borderRadius: 2,
          background: 'rgba(255,255,255,0.22)', margin: '0 auto 12px' }}/>
        <div className="dd-display" style={{ fontSize: 24, fontWeight: 800,
          marginBottom: 14 }}>Add workout</div>
        {row(FR2.lime, 'sparkle', FR2.ink, 'Create with AI',
          'Describe it — the coach drafts it', null,
          () => toast('Unchanged'))}
        {row('#7BC96F', 'link', FR2.ink, 'Import from URL',
          'Instagram, TikTok, or YouTube', null, () => toast('Unchanged'))}
        {row('#C58AF4', 'camera', FR2.ink, 'Screenshot',
          'Photo of a workout → draft', null, () => toast('Unchanged'))}
        {row(FR2.card2, 'edit', '#fff', 'Build from scratch',
          'From scratch, exercise by exercise', null, () => toast('Unchanged'))}
        {row(FR2.blue, 'users', FR2.ink, 'From friends',
          'Marcus, Tomás sent you workouts',
          <span className="dd-display" style={{ background: FR2.lime,
            color: FR2.ink, borderRadius: 999, minWidth: 22, height: 22,
            display: 'inline-flex', alignItems: 'center',
            justifyContent: 'center', fontSize: 12, fontWeight: 800 }}>2</span>,
          () => toast('NEW — opens the review list (panel 7); save or skip each'))}
        <div style={{ textAlign: 'center', fontSize: 12,
          color: 'var(--fg-dim)', marginTop: 4 }}>
          🎙 Speak it — coming soon</div>
      </div>
    </>
  );
}

// ---- 3 · Received review — duplicate detected (dedupe honesty)
function FR2DupScreen({ set }) {
  const toast = (t) => set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600 }}>
          <Icon name="chevL" size={16}/> From friends
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9,
          marginTop: 10 }}>
          <FR2Av name="Marcus O." color={FR2.blue} size={26}/>
          <span className="af-mono" style={{ fontSize: 8.5, fontWeight: 700,
            color: 'var(--fg-muted)' }}>FROM MARCUS · “the hyrox lower day”</span>
        </div>
        <div className="dd-display" style={{ fontSize: 22, fontWeight: 800,
          marginTop: 8 }}>HYROX — Lower body workout</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 0' }}>
        {/* the dedupe card */}
        <div style={{ background: 'color-mix(in oklch, var(--ready-mod), transparent 88%)',
          border: '1px solid color-mix(in oklch, var(--ready-mod), transparent 55%)',
          borderRadius: 16, padding: '12px 13px' }}>
          <div className="dd-display" style={{ fontSize: 13.5,
            fontWeight: 700 }}>You already have this one</div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 4,
            lineHeight: 1.55 }}>
            Matches “HYROX – Lower body work…” in your library — same
            structure, imported from the same reel. Saving again would
            duplicate it.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 11 }}>
            <div className="dd-display"
              onClick={() => toast('Opens YOUR copy in the library')}
              style={{ flex: 1.2, background: FR2.lime, color: FR2.ink,
                borderRadius: 999, padding: '10px 0', textAlign: 'center',
                fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
              Open yours ›</div>
            <div className="dd-display"
              onClick={() => toast('Saved as a separate copy — “… (from Marcus)”')}
              style={{ flex: 1.3, background: FR2.card2,
                border: '1px solid var(--border-str)', borderRadius: 999,
                padding: '10px 0', textAlign: 'center', fontSize: 12,
                fontWeight: 700, cursor: 'pointer' }}>Save copy anyway</div>
          </div>
        </div>

        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          margin: '13px 0 6px' }}>WHAT MARCUS SENT — 7 BLOCKS · ~45 MIN</div>
        {['Sled push — 4 × 25 m', 'Walking lunge — 3 × 20',
          'Back squat — 4 × 8 · 100 kg', 'Wall balls — 3 × 25'].map((r, i) => (
          <div key={r} style={{ display: 'flex', gap: 10,
            alignItems: 'center', padding: '9px 2px 9px 12px',
            borderBottom: '1px solid var(--border)' }}>
            <span className="af-mono" style={{ fontSize: 8.5,
              color: 'var(--fg-dim)', width: 12 }}>{i + 1}</span>
            <span style={{ fontSize: 12.5, fontWeight: 500 }}>{r}</span>
          </div>
        ))}
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          margin: '12px 0', lineHeight: 1.6 }}>
          MATCH RULE: SAME SOURCE (REEL/SHARE ORIGIN) OR SAME TITLE +
          STRUCTURE. WE FLAG — YOU DECIDE. NOTHING IS DROPPED SILENTLY.</div>
      </div>
      <div style={{ padding: '10px 18px 14px',
        borderTop: '1px solid var(--border)', textAlign: 'center' }}>
        <span className="dd-display"
          onClick={() => toast('Dismissed — Marcus is not told')}
          style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-dim)',
            cursor: 'pointer' }}>Not for me</span>
      </div>
    </>
  );
}

function DDFriends2Screen({ preset }) {
  const [st, set] = React.useState({ toast: null });
  React.useEffect(() => {
    if (!st.toast) return;
    const t = setTimeout(() => set(s => ({ ...s, toast: null })), 2600);
    return () => clearTimeout(t);
  }, [st.toast]);
  let body;
  if (preset === 'add') body = <FR2AddScreen set={set}/>;
  else if (preset === 'dup') body = <FR2DupScreen set={set}/>;
  else body = <FR2DetailScreen set={set}/>;
  return (
    <div style={{ position: 'relative', display: 'flex',
      flexDirection: 'column', height: '100%' }}>
      {body}
      {st.toast && (
        <div style={{ position: 'absolute', bottom: 18, left: 14, right: 14,
          zIndex: 40, background: '#17181c',
          border: '1px solid var(--border-str)', borderRadius: 12,
          padding: '9px 13px', fontSize: 10.5, color: 'var(--fg-muted)',
          boxShadow: '0 10px 30px rgba(0,0,0,0.55)' }}>{st.toast}</div>
      )}
    </div>
  );
}

Object.assign(window, { DDFriends2Screen });
