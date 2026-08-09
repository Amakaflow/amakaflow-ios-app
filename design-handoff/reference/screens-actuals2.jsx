/**
 * Sync additions — empty-not-connected Today + 3-source consolidation.
 * 2026-08-07 (second pass on screens-actuals). DISPOSABLE.
 *  · SYEmptyTodayScreen — Today with NO connections: teaching empty state
 *    (source chips, one Connect CTA, manual-＋ alternative). Replaces the
 *    bare "Sessions land here as they happen" line.
 *  · SYMergeAskScreen — UNCERTAIN duplicate: "Same session?" prompt card
 *    on Today (97% overlap) with Merge / Keep both. We never silently
 *    guess when unsure — same rule as clarify.
 *  · SYMergedScreen — CONFIDENT 3-way merge (Apple+Garmin+Strava):
 *    counts once, per-field provenance (best-of stats w/ source tags),
 *    per-recording roles, and a "Not the same? Split" escape hatch.
 * Merge rules (stated in UI): same window (start ± 2 min, similar
 * duration) → auto-merge; watch beats phone; richest streams become
 * primary; others attach. Partial overlap → ask, never guess.
 */

const SY2 = {
  lime: 'var(--ready-high)',
  amber: 'var(--ready-mod)',
  ink: '#0d1200',
  card: 'rgba(255,255,255,0.055)',
  card2: 'rgba(255,255,255,0.09)',
  blue: '#5AB8F4', orange: '#FC4C02', red: '#F4564A',
};

function SY2Chip({ icon, bg, ink, size = 34 }) {
  return (
    <div style={{ width: size, height: size, borderRadius: 999, background: bg,
      color: ink || '#fff', display: 'flex', alignItems: 'center',
      justifyContent: 'center', flexShrink: 0 }}>
      <Icon name={icon} size={Math.round(size * 0.47)}/>
    </div>
  );
}

// ------------------------- Today · empty + nothing connected — teach it
function SYEmptyTodayScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '8px 18px 6px', display: 'flex',
        alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>
          Today</div>
      </div>
      <div style={{ display: 'flex', gap: 6, padding: '6px 18px 4px' }}>
        {[['S', 2], ['M', 3], ['T', 4], ['W', 5], ['T', 6], ['F', 7, true], ['S', 8]].map(([d, n, today], i) => (
          <div key={i} style={{ flex: 1, textAlign: 'center',
            padding: '8px 0 7px', borderRadius: 12,
            background: today ? SY2.card2 : 'transparent',
            border: today ? '1px solid var(--border-str)' : '1px solid transparent',
            opacity: today ? 1 : 0.4 }}>
            <div className="af-mono" style={{ fontSize: 9,
              color: 'var(--fg-muted)' }}>{d}</div>
            <div className="dd-display" style={{ fontSize: 13,
              fontWeight: 700, marginTop: 2 }}>{n}</div>
          </div>
        ))}
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column',
        justifyContent: 'center', padding: '0 18px 80px' }}>
        <div style={{ background: SY2.card, border: '1px solid var(--border)',
          borderRadius: 20, padding: '22px 18px', textAlign: 'center' }}>
          {/* overlapping source chips */}
          <div style={{ display: 'flex', justifyContent: 'center',
            marginBottom: 14 }}>
            <div style={{ display: 'flex' }}>
              <SY2Chip icon="watch" bg={SY2.card2} size={40}/>
              <div style={{ marginLeft: -10 }}>
                <SY2Chip icon="watch" bg={SY2.blue} size={40}/></div>
              <div style={{ marginLeft: -10 }}>
                <SY2Chip icon="run" bg={SY2.orange} size={40}/></div>
            </div>
          </div>
          <div className="dd-display" style={{ fontSize: 17, fontWeight: 800,
            lineHeight: 1.3 }}>
            Your finished workouts can land here by themselves</div>
          <div style={{ fontSize: 11.5, color: 'var(--fg-muted)', marginTop: 8,
            lineHeight: 1.55 }}>
            Connect Apple Health, Garmin or Strava — sessions show up minutes
            after you finish, ready to log.
          </div>
          <div className="dd-display dd-glow"
            onClick={() => toast('Opens Connect sources (panel 2)')}
            style={{ background: SY2.lime, color: SY2.ink, borderRadius: 999,
              padding: '13px 0', textAlign: 'center', fontSize: 14,
              fontWeight: 700, cursor: 'pointer', marginTop: 16 }}>
            Connect a source
          </div>
          <div className="af-mono" style={{ fontSize: 8, marginTop: 10,
            color: 'var(--fg-dim)' }}>~30 SECONDS · READ-ONLY · UNPLUG ANYTIME</div>
        </div>
        <div style={{ fontSize: 11, color: 'var(--fg-dim)', textAlign: 'center',
          marginTop: 14 }}>
          or log a session manually with ＋
        </div>
      </div>
    </>
  );
}

// ------------------- Uncertain duplicate — ask, never guess (on Today)
function SYMergeAskScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  return (
    <>
      <div style={{ padding: '8px 18px 10px', display: 'flex',
        alignItems: 'center' }}>
        <div className="dd-display" style={{ fontSize: 32, fontWeight: 800 }}>
          Today</div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '4px 18px 96px' }}>
        {/* the two candidate recordings */}
        {[['run', SY2.orange, 'Lunch Run / 8.2 km', '12:53 · 59M · 677 CAL', 'STRAVA'],
          ['run', SY2.blue, 'Run', '12:54 · 58M · GPS + LAPS', 'GARMIN']].map(([ic, bg, t, meta, src]) => (
          <div key={src} style={{ display: 'flex', alignItems: 'center',
            gap: 12, background: SY2.card,
            border: '1px dashed var(--border-str)', borderRadius: 16,
            padding: '11px 13px', marginBottom: 8, opacity: 0.85 }}>
            <SY2Chip icon={ic} bg={bg} size={32}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div className="dd-display" style={{ fontSize: 13.5,
                fontWeight: 700 }}>{t}</div>
              <div className="af-mono" style={{ fontSize: 8.5, marginTop: 2,
                color: 'var(--fg-dim)' }}>{meta} · {src}</div>
            </div>
          </div>
        ))}

        {/* the ask */}
        <div style={{ background: 'color-mix(in oklch, var(--ready-mod), transparent 88%)',
          border: '1px solid color-mix(in oklch, var(--ready-mod), transparent 55%)',
          borderRadius: 16, padding: '13px 14px' }}>
          <div className="dd-display" style={{ fontSize: 13.5,
            fontWeight: 700 }}>Same session?</div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 4,
            lineHeight: 1.55 }}>
            These two overlap 97% — started a minute apart, same distance.
            We don't merge without you when it's not certain.
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <div className="dd-display"
              onClick={() => toast('Merged — counts once · see panel 5')}
              style={{ flex: 1.3, background: SY2.lime, color: SY2.ink,
                borderRadius: 999, padding: '11px 0', textAlign: 'center',
                fontSize: 13, fontWeight: 700, cursor: 'pointer' }}>
              Merge — it's one session</div>
            <div className="dd-display"
              onClick={() => toast('Kept separate — both count')}
              style={{ flex: 1, background: SY2.card2,
                border: '1px solid var(--border-str)', borderRadius: 999,
                padding: '11px 0', textAlign: 'center', fontSize: 13,
                fontWeight: 700, cursor: 'pointer' }}>
              Keep both</div>
          </div>
        </div>
        <div className="af-mono" style={{ fontSize: 8, color: 'var(--fg-dim)',
          textAlign: 'center', marginTop: 10, lineHeight: 1.6 }}>
          CERTAIN DUPLICATES (SAME WINDOW ± 2 MIN, SAME SHAPE) MERGE
          AUTOMATICALLY — YOU'LL SEE “MERGED · N SOURCES” ON THE CARD.
        </div>
      </div>
    </>
  );
}

// ---------------- Confident 3-way merge — provenance + Split escape
function SYMergedScreen({ set }) {
  const toast = (t) => set && set(s => ({ ...s, toast: t }));
  const stat = (v, k, src) => (
    <div style={{ background: SY2.card, border: '1px solid var(--border)',
      borderRadius: 14, padding: '10px 4px', textAlign: 'center' }}>
      <div className="dd-display" style={{ fontSize: 18, fontWeight: 800 }}>{v}</div>
      <div className="af-mono" style={{ fontSize: 7.5, color: 'var(--fg-dim)',
        marginTop: 3 }}>{k}</div>
      <div className="af-mono" style={{ fontSize: 6.5, color: 'var(--fg-dim)',
        marginTop: 2, opacity: 0.8 }}>{src}</div>
    </div>
  );
  return (
    <>
      <div style={{ padding: '10px 18px 0' }}>
        <div onClick={() => toast('Back to Today')}
          style={{ display: 'inline-flex', alignItems: 'center', gap: 4,
            color: 'var(--fg-muted)', fontSize: 13, fontWeight: 600,
            cursor: 'pointer' }}>
          <Icon name="chevL" size={16}/> Today
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12,
          marginTop: 10 }}>
          <SY2Chip icon="flame" bg={SY2.lime} ink={SY2.ink}/>
          <div style={{ flex: 1 }}>
            <div className="dd-display" style={{ fontSize: 22,
              fontWeight: 800 }}>Hyrox Sim — Stations 1–4</div>
            <div className="af-mono" style={{ fontSize: 9, marginTop: 3,
              color: 'var(--fg-dim)' }}>18:10 – 18:54 · MERGED · 3 SOURCES</div>
          </div>
        </div>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto',
        padding: '12px 18px 96px' }}>
        <div style={{ padding: '11px 13px', borderRadius: 14,
          background: 'color-mix(in oklch, var(--ready-high), transparent 88%)',
          border: '1px solid color-mix(in oklch, var(--ready-high), transparent 60%)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <Icon name="check" size={14} style={{ color: SY2.lime }}/>
            <span className="dd-display" style={{ fontSize: 13,
              fontWeight: 700, color: SY2.lime }}>One session, three recordings</span>
          </div>
          <div style={{ fontSize: 11, color: 'var(--fg-muted)', marginTop: 5,
            lineHeight: 1.5 }}>
            Apple Watch, Garmin and Strava all caught this. We merged them —
            it counts once, and each stat comes from whoever measured it best.
          </div>
        </div>

        {/* best-of stats with per-field provenance */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr',
          gap: 8, marginTop: 12 }}>
          {stat('44', 'MIN', 'ALL AGREE')}
          {stat('486', 'CAL', 'APPLE WATCH')}
          {stat('151', 'BPM', 'APPLE WATCH')}
          {stat('8', 'LAPS', 'GARMIN')}
        </div>

        <div className="af-mono" style={{ fontSize: 8.5,
          color: 'var(--fg-dim)', margin: '14px 0 8px' }}>
          THE THREE RECORDINGS — WHAT EACH CONTRIBUTED</div>
        <div style={{ background: SY2.card, border: '1px solid var(--border)',
          borderRadius: 16, padding: '4px 14px' }}>
          {[['watch', SY2.card2, 'Apple Watch', 'PRIMARY · HEART RATE + CALORIES', SY2.lime],
            ['watch', SY2.blue, 'Garmin', 'ATTACHED · LAPS + ROUTE', 'var(--fg-muted)'],
            ['run', SY2.orange, 'Strava', 'DUPLICATE · HIDDEN — NOTHING COUNTED TWICE', 'var(--fg-dim)']].map(([ic, bg, n, role, c], i) => (
            <div key={n} style={{ display: 'flex', alignItems: 'center',
              gap: 11, padding: '11px 0',
              borderTop: i === 0 ? 'none' : '1px solid var(--border)' }}>
              <SY2Chip icon={ic} bg={bg} size={28}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="dd-display" style={{ fontSize: 13,
                  fontWeight: 700 }}>{n}</div>
                <div className="af-mono" style={{ fontSize: 8, marginTop: 2,
                  color: c }}>{role}</div>
              </div>
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: 18, justifyContent: 'center',
          marginTop: 14 }}>
          <span className="dd-display"
            onClick={() => toast('Split — three separate sessions again; pick which count')}
            style={{ fontSize: 12, fontWeight: 700, color: 'var(--ready-mod)',
              cursor: 'pointer' }}>Not the same? Split</span>
          <span className="dd-display"
            onClick={() => toast('Opens fill-in actuals')}
            style={{ fontSize: 12, fontWeight: 700, color: 'var(--fg-muted)',
              cursor: 'pointer' }}>Fill in actuals ›</span>
        </div>
      </div>
    </>
  );
}

function DDActuals2Screen({ dd, set, nav, preset }) {
  if (preset === 'mergeask') return <SYMergeAskScreen set={set}/>;
  if (preset === 'merged') return <SYMergedScreen set={set}/>;
  return <SYEmptyTodayScreen set={set}/>;
}

Object.assign(window, { DDActuals2Screen, SYEmptyTodayScreen,
  SYMergeAskScreen, SYMergedScreen });
