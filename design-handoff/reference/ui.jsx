/**
 * AmakaFlow hi-fi UI kit — shadcn-parity primitives, CSS-class-driven.
 * Tokens come from tokens.css. Works in both light + dark via [data-theme].
 */

// Icons — small, 1.5px stroke, neutral
function Icon({ name, size = 16, style }) {
  const s = { width: size, height: size, strokeWidth: 1.5, fill: 'none',
    stroke: 'currentColor', strokeLinecap: 'round', strokeLinejoin: 'round' };
  const paths = {
    chevR: <polyline {...s} points="9 6 15 12 9 18"/>,
    chevL: <polyline {...s} points="15 6 9 12 15 18"/>,
    chevD: <polyline {...s} points="6 9 12 15 18 9"/>,
    chevU: <polyline {...s} points="6 15 12 9 18 15"/>,
    close: <><line x1="18" y1="6" x2="6" y2="18" {...s}/><line x1="6" y1="6" x2="18" y2="18" {...s}/></>,
    plus:  <><line x1="12" y1="5" x2="12" y2="19" {...s}/><line x1="5" y1="12" x2="19" y2="12" {...s}/></>,
    play:  <polygon points="6 4 20 12 6 20 6 4" {...s} fill="currentColor"/>,
    pause: <><rect x="6" y="4" width="4" height="16" {...s}/><rect x="14" y="4" width="4" height="16" {...s}/></>,
    stop:  <rect x="6" y="6" width="12" height="12" {...s} fill="currentColor"/>,
    check: <polyline points="20 6 9 17 4 12" {...s}/>,
    swap:  <><polyline points="7 10 3 6 7 2" {...s}/><line x1="3" y1="6" x2="21" y2="6" {...s}/><polyline points="17 14 21 18 17 22" {...s}/><line x1="21" y1="18" x2="3" y2="18" {...s}/></>,
    edit:  <><path d="M12 20h9" {...s}/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" {...s}/></>,
    heart: <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78L12 21.23l8.84-8.84a5.5 5.5 0 0 0 0-7.78z" {...s}/>,
    run:   <><circle cx="17" cy="5" r="2" {...s}/><path d="M4 22l4-5 2-6 4 2 3 4" {...s}/><path d="M8 11l-2 5" {...s}/></>,
    lift:  <><path d="M6 6v12M18 6v12M3 8v8M21 8v8M6 12h12" {...s}/></>,
    moon:  <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" {...s}/>,
    sun:   <><circle cx="12" cy="12" r="4" {...s}/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41" {...s}/></>,
    bolt:  <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" {...s} fill="currentColor" stroke="none"/>,
    flag:  <><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" {...s}/><line x1="4" y1="22" x2="4" y2="15" {...s}/></>,
    bike:  <><circle cx="5.5" cy="17.5" r="3.5" {...s}/><circle cx="18.5" cy="17.5" r="3.5" {...s}/><path d="M15 6a1 1 0 1 0 0-2 1 1 0 0 0 0 2zm-3 11.5V14l-3-3 4-3 2 3h2" {...s}/></>,
    watch: <><rect x="6" y="6" width="12" height="12" rx="2" {...s}/><path d="M9 6V3h6v3M9 18v3h6v-3" {...s}/></>,
    home:  <path d="M3 12l9-9 9 9M5 10v10h14V10" {...s}/>,
    cal:   <><rect x="3" y="4" width="18" height="18" rx="2" {...s}/><line x1="16" y1="2" x2="16" y2="6" {...s}/><line x1="8" y1="2" x2="8" y2="6" {...s}/><line x1="3" y1="10" x2="21" y2="10" {...s}/></>,
    clock: <><circle cx="12" cy="12" r="9" {...s}/><polyline points="12 7 12 12 15 14" {...s}/></>,
    user:  <><circle cx="12" cy="8" r="4" {...s}/><path d="M4 21a8 8 0 0 1 16 0" {...s}/></>,
    info:  <><circle cx="12" cy="12" r="9" {...s}/><line x1="12" y1="16" x2="12" y2="12" {...s}/><line x1="12" y1="8" x2="12.01" y2="8" {...s}/></>,
    bookmark: <path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" {...s}/>,
    chatSpark: <><path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5" {...s}/><polygon points="19 2 20.2 4.8 23 6 20.2 7.2 19 10 17.8 7.2 15 6 17.8 4.8" {...s} fill="currentColor" stroke="none"/></>,
    funnel: <polygon points="3 4 21 4 14 13 14 20 10 20 10 13" {...s}/>,
    search: <><circle cx="11" cy="11" r="7" {...s}/><line x1="21" y1="21" x2="16.5" y2="16.5" {...s}/></>,
    gear:  <><circle cx="12" cy="12" r="3" {...s}/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" {...s}/></>,
    msg:   <path d="M21 11.5a8.5 8.5 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.5 8.5 0 0 1-3.8-.9L3 21l1.9-5.7a8.5 8.5 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.5 8.5 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8z" {...s}/>,
    link:  <><path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7" {...s}/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7" {...s}/></>,
    plane: <><line x1="22" y1="2" x2="11" y2="13" {...s}/><polygon points="22 2 15 22 11 13 2 9" {...s}/></>,
    sliders: <><line x1="4" y1="21" x2="4" y2="14" {...s}/><line x1="4" y1="10" x2="4" y2="3" {...s}/><line x1="12" y1="21" x2="12" y2="12" {...s}/><line x1="12" y1="8" x2="12" y2="3" {...s}/><line x1="20" y1="21" x2="20" y2="16" {...s}/><line x1="20" y1="12" x2="20" y2="3" {...s}/><line x1="1" y1="14" x2="7" y2="14" {...s}/><line x1="9" y1="8" x2="15" y2="8" {...s}/><line x1="17" y1="16" x2="23" y2="16" {...s}/></>,
    kebab: <><circle cx="12" cy="5" r="1.4" {...s} fill="currentColor"/><circle cx="12" cy="12" r="1.4" {...s} fill="currentColor"/><circle cx="12" cy="19" r="1.4" {...s} fill="currentColor"/></>,
    grid:  <><rect x="3" y="3" width="7" height="7" {...s}/><rect x="14" y="3" width="7" height="7" {...s}/><rect x="3" y="14" width="7" height="7" {...s}/><rect x="14" y="14" width="7" height="7" {...s}/></>,
    camera: <><path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z" {...s}/><circle cx="12" cy="13" r="4" {...s}/></>,
    grip: <><circle cx="9" cy="6" r="1.4" {...s} fill="currentColor"/><circle cx="15" cy="6" r="1.4" {...s} fill="currentColor"/><circle cx="9" cy="12" r="1.4" {...s} fill="currentColor"/><circle cx="15" cy="12" r="1.4" {...s} fill="currentColor"/><circle cx="9" cy="18" r="1.4" {...s} fill="currentColor"/><circle cx="15" cy="18" r="1.4" {...s} fill="currentColor"/></>,
    mic: <><rect x="9" y="2" width="6" height="12" rx="3" {...s}/><path d="M5 11a7 7 0 0 0 14 0M12 18v3" {...s}/></>,
    trophy: <><path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z" {...s}/><path d="M7 5H4a2 2 0 0 0 0 4h3M17 5h3a2 2 0 0 1 0 4h-3" {...s}/></>,
    chart: <><polyline points="3 17 9 11 13 15 21 7" {...s}/><polyline points="14 7 21 7 21 14" {...s}/></>,
    download: <><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3" {...s}/></>,
    flame: <path d="M12 2s4 4 4 8a4 4 0 0 1-8 0c0-2 2-4 2-4M12 22a6 6 0 0 0 6-6c0-3-3-6-6-10-3 4-6 7-6 10a6 6 0 0 0 6 6z" {...s}/>,
    qr: <><rect x="3" y="3" width="7" height="7" {...s}/><rect x="14" y="3" width="7" height="7" {...s}/><rect x="3" y="14" width="7" height="7" {...s}/><line x1="14" y1="14" x2="14" y2="14.01" {...s}/><line x1="21" y1="14" x2="21" y2="14.01" {...s}/><line x1="14" y1="21" x2="14" y2="21.01" {...s}/><line x1="21" y1="21" x2="21" y2="21.01" {...s}/><line x1="17" y1="17" x2="17" y2="17.01" {...s}/></>,
    shoe: <path d="M2 17h2l3-2 4 1 6-1 5 1 .5 2a2 2 0 0 1-2 2h-17a1 1 0 0 1-1-1v-1zM4 15l3-7 4 2 3-3 5 4 1 4" {...s}/>,
    share: <><circle cx="18" cy="5" r="3" {...s}/><circle cx="6" cy="12" r="3" {...s}/><circle cx="18" cy="19" r="3" {...s}/><line x1="8.6" y1="13.5" x2="15.4" y2="17.5" {...s}/><line x1="15.4" y1="6.5" x2="8.6" y2="10.5" {...s}/></>,
    food: <><circle cx="12" cy="12" r="9" {...s}/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18" {...s}/></>,
    sparkle: <><polygon points="12 2 14 9 21 11 14 13 12 20 10 13 3 11 10 9" {...s} fill="currentColor" stroke="none"/></>,
    medal: <><circle cx="12" cy="15" r="6" {...s}/><polyline points="9 3 9 8 12 6 15 8 15 3" {...s}/></>,
    eye: <><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" {...s}/><circle cx="12" cy="12" r="3" {...s}/></>,
    list: <><line x1="8" y1="6" x2="21" y2="6" {...s}/><line x1="8" y1="12" x2="21" y2="12" {...s}/><line x1="8" y1="18" x2="21" y2="18" {...s}/><line x1="3" y1="6" x2="3.01" y2="6" {...s}/><line x1="3" y1="12" x2="3.01" y2="12" {...s}/><line x1="3" y1="18" x2="3.01" y2="18" {...s}/></>,
    map:  <><polygon points="1 6 8 3 16 6 23 3 23 18 16 21 8 18 1 21 1 6" {...s}/><line x1="8" y1="3" x2="8" y2="18" {...s}/><line x1="16" y1="6" x2="16" y2="21" {...s}/></>,
  };
  return <svg viewBox="0 0 24 24" style={{ display: 'inline-block', ...style }}
    width={size} height={size}>{paths[name]}</svg>;
}

function Btn({ children, variant = 'primary', size = 'md', wide, onClick, style, disabled }) {
  return (
    <button onClick={disabled ? undefined : onClick} disabled={disabled}
      className={`af-btn af-btn-${size} af-btn-${variant} ${wide ? 'af-btn-wide' : ''}`}
      style={{ opacity: disabled ? 0.4 : 1, cursor: disabled ? 'not-allowed' : 'pointer', ...style }}>
      {children}
    </button>
  );
}

function Chip({ children, outline, style, onClick }) {
  return (
    <span onClick={onClick}
      className={`af-chip ${outline ? 'af-chip-outline' : ''}`}
      style={{ cursor: onClick ? 'pointer' : 'default', ...style }}>{children}</span>
  );
}

function Card({ children, style, tight, onClick }) {
  return <div onClick={onClick}
    className={`af-card ${tight ? 'af-card-tight' : ''}`}
    style={{ cursor: onClick ? 'pointer' : 'default', ...style }}>{children}</div>;
}

function Phone({ children, statusbar = true, time = '6:14' }) {
  return (
    <div className="af-phone">
      <div className="af-phone-body">
        {statusbar && (
          <div className="af-statusbar">
            <span>{time}</span>
            <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
              <span style={{ fontSize: 10 }}>●●●●</span>
              <span style={{ fontSize: 10 }}>▲</span>
              <span style={{ marginLeft: 2 }}>100</span>
            </span>
          </div>
        )}
        {children}
      </div>
    </div>
  );
}

function Desk({ children, url = 'amakaflow.app' }) {
  return (
    <div className="af-desk">
      <div className="af-desk-chrome">
        <div className="dot"/><div className="dot"/><div className="dot"/>
        <div className="af-desk-url">{url}</div>
      </div>
      <div style={{ flex: 1, overflow: 'hidden' }}>{children}</div>
    </div>
  );
}

function Sheet({ open, onClose, children, title }) {
  if (!open) return null;
  return (
    <div className="af-sheet-backdrop" onClick={onClose}>
      <div className="af-sheet" onClick={e => e.stopPropagation()}>
        <div className="af-sheet-handle"/>
        {title && (
          <div style={{ display: 'flex', justifyContent: 'space-between',
            alignItems: 'center', marginBottom: 12 }}>
            <div className="af-h2">{title}</div>
            <div onClick={onClose} style={{ cursor: 'pointer', color: 'var(--fg-muted)',
              padding: 4 }}>
              <Icon name="close" size={18}/>
            </div>
          </div>
        )}
        {children}
      </div>
    </div>
  );
}

// Ring gauge with semantic color
function Ring({ value, size = 88, stroke = 6, label, sub }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const off = c * (1 - value / 100);
  const color = value >= 70 ? 'var(--ready-high)'
    : value >= 45 ? 'var(--ready-mod)' : 'var(--ready-low)';
  return (
    <div style={{ position: 'relative', width: size, height: size, flexShrink: 0 }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size/2} cy={size/2} r={r} stroke="var(--border)"
          strokeWidth={stroke} fill="none"/>
        <circle cx={size/2} cy={size/2} r={r} stroke={color}
          strokeWidth={stroke} fill="none"
          strokeDasharray={c} strokeDashoffset={off} strokeLinecap="round"/>
      </svg>
      <div style={{ position: 'absolute', inset: 0, display: 'flex',
        alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>
        <div className="af-mono" style={{ fontSize: size * 0.32, fontWeight: 600,
          lineHeight: 1, letterSpacing: '-0.02em' }}>{value}</div>
        {label && <div className="af-label" style={{ fontSize: 8, marginTop: 2 }}>{label}</div>}
      </div>
    </div>
  );
}

function TabBar({ active = 0, onChange }) {
  const items = [
    { name: 'Home', icon: 'home' },
    { name: 'Workouts', icon: 'grid' },
    { name: 'Coach', icon: 'chatSpark' },
    { name: 'Library', icon: 'bookmark' },
    { name: 'History', icon: 'clock' },
    { name: 'Profile', icon: 'user' },
  ];
  return (
    <div className="af-tabbar af-tabbar-6">
      {items.map((it, i) => (
        <div key={it.name} className="af-tab" data-active={i === active}
          onClick={() => onChange && onChange(i)}>
          <div className="af-tab-pill">
            <Icon name={it.icon} size={18}/>
          </div>
          <span>{it.name}</span>
        </div>
      ))}
    </div>
  );
}

function TopBar({ title, left, right, onLeft, onRight, sub }) {
  return (
    <div style={{ padding: '8px 20px 14px', flexShrink: 0 }}>
      <div style={{ display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', minHeight: 32 }}>
        <div onClick={onLeft} style={{ cursor: onLeft ? 'pointer' : 'default',
          color: 'var(--fg-muted)', display: 'flex', alignItems: 'center', gap: 4,
          fontSize: 13, fontWeight: 500 }}>
          {typeof left === 'string' && left.startsWith('<') ? <Icon name="chevL" size={18}/> : null}
          {typeof left === 'string' ? left.replace(/^</, '') : left}
        </div>
        <div onClick={onRight} style={{ cursor: onRight ? 'pointer' : 'default',
          color: 'var(--fg-muted)', fontSize: 13, fontWeight: 500 }}>
          {right}
        </div>
      </div>
      {title && <div className="af-h1" style={{ marginTop: 8 }}>{title}</div>}
      {sub && <div className="af-muted" style={{ fontSize: 12, marginTop: 2 }}>{sub}</div>}
    </div>
  );
}

// Sparkline
function Spark({ points, w = 100, h = 28, color = 'var(--fg)' }) {
  const min = Math.min(...points), max = Math.max(...points);
  const range = max - min || 1;
  const step = w / (points.length - 1);
  const d = points.map((v, i) => {
    const x = i * step;
    const y = h - ((v - min) / range) * h;
    return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
  }).join(' ');
  return (
    <svg width={w} height={h} style={{ display: 'block' }}>
      <path d={d} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  );
}

// Bars
function Bars({ values, h = 48, accent = -1, w = 100 }) {
  const max = Math.max(...values);
  const bw = (w - (values.length - 1) * 2) / values.length;
  return (
    <svg width={w} height={h} style={{ display: 'block' }}>
      {values.map((v, i) => {
        const bh = (v / max) * h;
        return (
          <rect key={i} x={i * (bw + 2)} y={h - bh} width={bw} height={bh}
            fill={i === accent ? 'var(--ready-high)' : 'var(--fg)'}
            opacity={i === accent ? 1 : 0.85}/>
        );
      })}
    </svg>
  );
}

Object.assign(window, {
  Icon, Btn, Chip, Card, Phone, Desk, Sheet, Ring, TabBar, TopBar, Spark, Bars,
});
