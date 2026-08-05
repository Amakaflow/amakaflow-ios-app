/**
 * DD Toast — action confirmations. 2026-08-05. DISPOSABLE.
 * Reference: top-drop capsule w/ check (David's 2026-08-05 screenshot).
 * One toast system for every "did it happen?" moment: workout saved,
 * pushed to Garmin, scheduled on Apple Watch, removed (with Undo).
 *
 * Anatomy: top-center capsule · icon chip · bold line · optional sub
 * · optional action (Undo). Motion (DD tokens): drop-in spring 320ms
 * cubic-bezier(.34,1.4,.64,1) from -24px → hold 1800ms (4000ms when an
 * action button is present) → rise+fade out 240ms ease-in.
 * PUSH variant is a two-phase MORPH: spinner "Sending to Garmin…" →
 * icon crossfades to lime check + text swaps "Sent — open the widget" →
 * dismiss. The toast never claims success before the API returns.
 * Queue: one visible; later toasts wait (no stacking).
 * SwiftUI: .transition(.move(edge:.top).combined(with:.opacity)),
 * .spring(response:0.32, dampingFraction:0.72); morph = content swap in
 * place with matchedGeometryEffect on the capsule.
 */

const TT = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  ink: '#0d1200',
  card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', red: '#F4564A',
};

const TT_HOLD = 1800, TT_HOLD_ACTION = 4000, TT_OUT = 240;

// ------------------------------------------------------------- Toast host
function TTHost({ toast, onDone, onAction }) {
  const [leaving, setLeaving] = React.useState(false);
  React.useEffect(() => {
    if (!toast) return;
    setLeaving(false);
    const hold = toast.action ? TT_HOLD_ACTION : TT_HOLD;
    // phase 1 (pending) never auto-dismisses — it morphs when resolved
    if (toast.pending) return;
    const t1 = setTimeout(() => setLeaving(true), hold);
    const t2 = setTimeout(onDone, hold + TT_OUT);
    return () => { clearTimeout(t1); clearTimeout(t2); };
  }, [toast && toast.id, toast && toast.pending]);
  if (!toast) return null;
  const iconBg = toast.pending ? TT.card2
    : toast.kind === 'undo' ? TT.amber
    : toast.kind === 'device' ? TT.blue : TT.lime;
  return (
    <div style={{ position: 'absolute', top: 54, left: 0, right: 0,
      display: 'flex', justifyContent: 'center', zIndex: 90,
      pointerEvents: 'none' }}>
      <div key={toast.id + (toast.pending ? '-p' : '-r')}
        className={leaving ? 'tt-out' : 'tt-in'}
        style={{ display: 'flex', alignItems: 'center', gap: 10,
          background: 'rgba(24,24,27,0.97)',
          border: '1px solid var(--border-str)', borderRadius: 999,
          padding: toast.sub ? '9px 16px 9px 10px' : '8px 16px 8px 10px',
          boxShadow: '0 12px 34px rgba(0,0,0,.5)', maxWidth: 300,
          pointerEvents: 'auto' }}>
        <div style={{ width: 26, height: 26, borderRadius: 999,
          background: iconBg, color: toast.pending ? 'var(--fg-muted)' : TT.ink,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0, transition: 'background .25s' }}>
          {toast.pending
            ? <div className="tt-spin" style={{ width: 13, height: 13,
                borderRadius: 999, border: '2px solid rgba(255,255,255,0.2)',
                borderTopColor: 'var(--ready-high)' }}/>
            : <span className="tt-icon-pop">
                <Icon name={toast.kind === 'undo' ? 'close'
                  : toast.kind === 'device' ? 'watch' : 'check'} size={14}/>
              </span>}
        </div>
        <div style={{ minWidth: 0 }}>
          <div className="dd-display" style={{ fontSize: 13, fontWeight: 700,
            color: 'var(--fg)', whiteSpace: 'nowrap', overflow: 'hidden',
            textOverflow: 'ellipsis' }}>{toast.text}</div>
          {toast.sub && <div className="af-mono" style={{ fontSize: 8,
            marginTop: 1, color: 'var(--fg-dim)', whiteSpace: 'nowrap',
            overflow: 'hidden', textOverflow: 'ellipsis' }}>{toast.sub}</div>}
        </div>
        {toast.action && !toast.pending && (
          <span className="dd-display" onClick={onAction}
            style={{ fontSize: 12, fontWeight: 700, color: TT.amber,
              cursor: 'pointer', flexShrink: 0, paddingLeft: 2 }}>
            {toast.action}</span>
        )}
      </div>
    </div>
  );
}

// ------------------------------------------------------ Demo playground
const TT_DEMOS = [
  { id: 'save', label: 'Save workout', btn: 'Save to Library',
    toast: { kind: 'ok', text: 'Saved to Library',
      sub: 'CHEST PUMP — 45 · IN UNCATEGORIZED' } },
  { id: 'garmin', label: 'Push to Garmin', btn: 'Push to Garmin',
    pendingText: 'Sending to Garmin…',
    toast: { kind: 'device', text: 'Sent to Garmin',
      sub: 'OPEN THE AMAKAFLOW WIDGET TO DOWNLOAD' } },
  { id: 'apple', label: 'Schedule on Apple Watch', btn: 'Schedule on watch',
    pendingText: 'Scheduling…',
    toast: { kind: 'device', text: 'On your Apple Watch',
      sub: 'WORKOUT APP · 11 STEPS · 8 SLOTS FREE' } },
  { id: 'remove', label: 'Remove from watch', btn: 'Remove from watch',
    toast: { kind: 'undo', text: 'Removed from watch',
      sub: 'LIBRARY UNTOUCHED', action: 'Undo' } },
];

function TTPlaygroundScreen({ set, auto = false, speed = 1 }) {
  const [toast, setToast] = React.useState(null);
  const seq = React.useRef(0);
  const autoIdx = React.useRef(0);

  const fire = (demo) => {
    seq.current += 1;
    const id = seq.current;
    if (demo.pendingText) {
      setToast({ id, pending: true, kind: demo.toast.kind,
        text: demo.pendingText });
      setTimeout(() => setToast(t => t && t.id === id
        ? { ...demo.toast, id, pending: false } : t), 900 / speed);
    } else {
      setToast({ ...demo.toast, id, pending: false });
    }
  };

  // auto-demo: cycle all four forever
  React.useEffect(() => {
    if (!auto) return;
    const step = () => {
      fire(TT_DEMOS[autoIdx.current % TT_DEMOS.length]);
      autoIdx.current += 1;
    };
    const first = setTimeout(step, 600);
    const loop = setInterval(step, 3600 / speed);
    return () => { clearTimeout(first); clearInterval(loop); };
  }, [auto, speed]);

  return (
    <>
      {/* backdrop: the detail screen, dimmed — toasts float above app UI */}
      <div style={{ padding: '14px 18px', opacity: 0.45 }}>
        <div className="dd-display" style={{ fontSize: 26, fontWeight: 800,
          marginTop: 26 }}>Chest Pump — 45</div>
        <div className="af-mono" style={{ fontSize: 9.5, marginTop: 6,
          color: 'var(--fg-muted)' }}>5 EXERCISES + WU · STRENGTH · FITS HOME GYM</div>
        <div style={{ marginTop: 16, background: 'rgba(255,255,255,0.055)',
          border: '1px solid var(--border)', borderRadius: 16,
          padding: '13px 14px' }}>
          <div className="dd-display" style={{ fontSize: 14, fontWeight: 700 }}>
            Bench press</div>
          <div className="af-mono" style={{ fontSize: 9.5, marginTop: 3,
            color: 'var(--fg-muted)' }}>3 × 8 · 77 KG · 90S REST</div>
        </div>
      </div>

      {/* trigger dock (playground only) */}
      {!auto && (
        <div style={{ position: 'absolute', left: 12, right: 12, bottom: 12,
          zIndex: 30, display: 'flex', flexDirection: 'column', gap: 7 }}>
          <div className="af-mono" style={{ fontSize: 8.5, textAlign: 'center',
            color: 'var(--fg-dim)', marginBottom: 2 }}>
            TAP AN ACTION — WATCH THE TOAST</div>
          {TT_DEMOS.map(d => (
            <div key={d.id} className="dd-display" onClick={() => fire(d)}
              style={{ background: 'rgba(255,255,255,0.09)',
                border: '1px solid var(--border-str)', borderRadius: 999,
                padding: '11px 0', textAlign: 'center', fontSize: 13,
                fontWeight: 700, cursor: 'pointer' }}>{d.btn}</div>
          ))}
        </div>
      )}
      {auto && (
        <div className="af-mono" style={{ position: 'absolute', left: 0,
          right: 0, bottom: 22, textAlign: 'center', fontSize: 8.5,
          color: 'var(--fg-dim)' }}>AUTO-DEMO · CYCLES ALL FOUR</div>
      )}

      <TTHost toast={toast}
        onDone={() => setToast(null)}
        onAction={() => { setToast(null);
          set && set(s => ({ ...s, toast: 'Undone — back on the watch' })); }}/>
    </>
  );
}

function DDToastScreen({ dd, set, nav, preset }) {
  if (preset === 'auto') return <TTPlaygroundScreen set={set} auto/>;
  if (preset === 'auto-half')
    return <TTPlaygroundScreen set={set} auto speed={0.5}/>;
  return <TTPlaygroundScreen set={set}/>;
}

Object.assign(window, { DDToastScreen, TTHost, TTPlaygroundScreen });
