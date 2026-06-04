/**
 * Paywall + Landing — mobile and desktop variants.
 */


// ----------------------------------------------------------- Paywall Mobile
function PaywallMobile({ nav }) {
  const [plan, setPlan] = React.useState('annual');
  return (
    <>
      <div style={{ padding: '14px 20px 0', display: 'flex', justifyContent: 'space-between' }}>
        <div onClick={() => nav('home')} style={{ color: 'var(--fg-muted)', cursor: 'pointer' }}>
          <Icon name="close" size={20}/>
        </div>
        <span className="af-label">RESTORE</span>
      </div>
      <div className="af-scroll" style={{ flex: 1, overflowY: 'auto', padding: '14px 24px 20px' }}>
        <div className="af-eyebrow" style={{ color: 'var(--fg)' }}>AMAKAFLOW PRO</div>
        <div className="af-h1" style={{ fontSize: 26, marginTop: 8, letterSpacing: '-0.015em',
          lineHeight: 1.2 }}>
          Adaptive coaching,<br/>built for hybrid days.
        </div>
        <div className="af-muted" style={{ fontSize: 13, marginTop: 10, lineHeight: 1.55 }}>
          Your plan reshapes every morning based on HRV, sleep, and yesterday's load — so you train when you're ready and recover when you're not.
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 0,
          margin: '24px 0', borderTop: '1px solid var(--border)' }}>
          {[
            ['Daily adaptive plan', 'Re-optimizes every 6am from biometrics'],
            ['Garmin + Apple Watch sync', 'Live HR, pace, zones during workouts'],
            ['Injury-aware swaps', 'Coach adjusts when you flag soreness'],
            ['Block periodization', 'Multi-month plans for races and events'],
            ['Readiness insights', 'HRV, sleep, load trends explained'],
          ].map(([t, s]) => (
            <div key={t} style={{ padding: '14px 0',
              borderBottom: '1px solid var(--border)',
              display: 'flex', gap: 12, alignItems: 'flex-start' }}>
              <Icon name="check" size={16} style={{ color: 'var(--ready-high)',
                marginTop: 2, flexShrink: 0 }}/>
              <div>
                <div style={{ fontSize: 13, fontWeight: 500 }}>{t}</div>
                <div className="af-muted" style={{ fontSize: 11, marginTop: 2 }}>{s}</div>
              </div>
            </div>
          ))}
        </div>

        <div className="af-label" style={{ marginBottom: 8 }}>CHOOSE PLAN</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginBottom: 14 }}>
          <div onClick={() => setPlan('annual')}
            style={{ padding: '14px 16px', borderRadius: 10,
              border: `1px solid ${plan === 'annual' ? 'var(--fg)' : 'var(--border)'}`,
              background: plan === 'annual' ? 'var(--accent-bg)' : 'var(--bg-elev)',
              display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }}>
            <div style={{ width: 18, height: 18, borderRadius: 999,
              border: `1.5px solid ${plan === 'annual' ? 'var(--fg)' : 'var(--border-str)'}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {plan === 'annual' && <div style={{ width: 8, height: 8, borderRadius: 999,
                background: 'var(--fg)' }}/>}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 14, fontWeight: 500 }}>Annual</span>
                <Chip style={{ background: 'var(--fg)', color: 'var(--bg)', fontSize: 9 }}>
                  SAVE 42%
                </Chip>
              </div>
              <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>
                $89.99/yr · $7.50/mo
              </div>
            </div>
            <div className="af-mono" style={{ fontSize: 15, fontWeight: 500 }}>$89.99</div>
          </div>
          <div onClick={() => setPlan('monthly')}
            style={{ padding: '14px 16px', borderRadius: 10,
              border: `1px solid ${plan === 'monthly' ? 'var(--fg)' : 'var(--border)'}`,
              background: plan === 'monthly' ? 'var(--accent-bg)' : 'var(--bg-elev)',
              display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer' }}>
            <div style={{ width: 18, height: 18, borderRadius: 999,
              border: `1.5px solid ${plan === 'monthly' ? 'var(--fg)' : 'var(--border-str)'}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {plan === 'monthly' && <div style={{ width: 8, height: 8, borderRadius: 999,
                background: 'var(--fg)' }}/>}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14, fontWeight: 500 }}>Monthly</div>
              <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 2 }}>
                $12.99/mo · 7-day trial
              </div>
            </div>
            <div className="af-mono" style={{ fontSize: 15, fontWeight: 500 }}>$12.99</div>
          </div>
        </div>
      </div>
      <div style={{ padding: '12px 20px 18px', borderTop: '1px solid var(--border)',
        background: 'var(--bg-elev)' }}>
        <Btn wide size="lg" onClick={() => nav('home')}>
          Start 7-day free trial
        </Btn>
        <div className="af-muted af-mono" style={{ fontSize: 10, textAlign: 'center',
          marginTop: 8 }}>
          CANCEL ANYTIME · NO CHARGE TODAY
        </div>
      </div>
    </>
  );
}

// ----------------------------------------------------------- Paywall Desktop
function PaywallDesktop({ nav }) {
  const [plan, setPlan] = React.useState('annual');
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '18px 36px', borderBottom: '1px solid var(--border)',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ width: 26, height: 26, borderRadius: 7, background: 'var(--fg)',
            color: 'var(--bg)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="bolt" size={14}/>
          </div>
          <span style={{ fontSize: 14, fontWeight: 600, letterSpacing: '-0.01em' }}>AmakaFlow</span>
        </div>
        <span className="af-label">UPGRADE TO PRO</span>
      </div>

      <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '1.1fr 1fr',
        overflow: 'hidden' }}>
        <div style={{ padding: '56px 64px', display: 'flex', flexDirection: 'column',
          justifyContent: 'center' }}>
          <div className="af-eyebrow">AMAKAFLOW PRO</div>
          <div style={{ fontSize: 52, fontWeight: 600, letterSpacing: '-0.02em',
            lineHeight: 1.05, marginTop: 16 }}>
            Adaptive coaching,<br/>built for hybrid days.
          </div>
          <div className="af-muted" style={{ fontSize: 15, marginTop: 20, lineHeight: 1.55,
            maxWidth: 460 }}>
            Your plan reshapes every morning based on HRV, sleep, and yesterday's load — so you train when you're ready and recover when you're not.
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '14px 24px',
            marginTop: 36, maxWidth: 520 }}>
            {[
              'Daily adaptive plan',
              'Garmin + Apple Watch sync',
              'Injury-aware swaps',
              'Block periodization',
              'Readiness insights',
              'Unlimited history',
            ].map(f => (
              <div key={f} style={{ display: 'flex', alignItems: 'center', gap: 10,
                fontSize: 14 }}>
                <Icon name="check" size={16} style={{ color: 'var(--ready-high)' }}/>
                {f}
              </div>
            ))}
          </div>
        </div>

        <div style={{ background: 'var(--bg-subtle)', padding: '56px 64px',
          display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
          <div className="af-label" style={{ marginBottom: 14 }}>CHOOSE PLAN</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 20 }}>
            {[
              { v: 'annual', name: 'Annual', price: '$89.99', sub: '$7.50/mo · save 42%', tag: 'BEST VALUE' },
              { v: 'monthly', name: 'Monthly', price: '$12.99', sub: '$12.99/mo · 7-day trial' },
            ].map(o => (
              <div key={o.v} onClick={() => setPlan(o.v)}
                style={{ padding: '18px 20px', borderRadius: 12,
                  border: `1px solid ${plan === o.v ? 'var(--fg)' : 'var(--border)'}`,
                  background: plan === o.v ? 'var(--accent-bg)' : 'var(--bg-elev)',
                  cursor: 'pointer',
                  display: 'flex', alignItems: 'center', gap: 14 }}>
                <div style={{ width: 20, height: 20, borderRadius: 999,
                  border: `1.5px solid ${plan === o.v ? 'var(--fg)' : 'var(--border-str)'}`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {plan === o.v && <div style={{ width: 10, height: 10, borderRadius: 999,
                    background: 'var(--fg)' }}/>}
                </div>
                <div style={{ flex: 1 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{ fontSize: 16, fontWeight: 500 }}>{o.name}</span>
                    {o.tag && <Chip style={{ background: 'var(--fg)', color: 'var(--bg)',
                      fontSize: 9 }}>{o.tag}</Chip>}
                  </div>
                  <div className="af-muted af-mono" style={{ fontSize: 12, marginTop: 4 }}>{o.sub}</div>
                </div>
                <div className="af-mono" style={{ fontSize: 22, fontWeight: 500 }}>{o.price}</div>
              </div>
            ))}
          </div>
          <Btn size="lg" wide onClick={() => nav('home')}>Start 7-day free trial</Btn>
          <div className="af-muted af-mono" style={{ fontSize: 10, textAlign: 'center',
            marginTop: 12 }}>
            CANCEL ANYTIME · NO CHARGE TODAY · RESTORE PURCHASE
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------- Landing Mobile
function LandingMobile({ nav }) {
  const [email, setEmail] = React.useState('');
  const [sent, setSent] = React.useState(false);
  return (
    <div className="af-scroll" style={{ height: '100%', overflowY: 'auto' }}>
      <div style={{ padding: '24px 24px 14px', display: 'flex',
        justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ width: 22, height: 22, borderRadius: 6, background: 'var(--fg)',
            color: 'var(--bg)', display: 'flex', alignItems: 'center',
            justifyContent: 'center' }}>
            <Icon name="bolt" size={12}/>
          </div>
          <span style={{ fontSize: 13, fontWeight: 600, letterSpacing: '-0.01em' }}>AmakaFlow</span>
        </div>
        <Chip outline><span className="af-dot af-dot-high"/> BETA</Chip>
      </div>

      <div style={{ padding: '40px 24px 14px' }}>
        <div className="af-eyebrow">ADAPTIVE COACHING FOR HYBRID ATHLETES</div>
        <div style={{ fontSize: 36, fontWeight: 600, letterSpacing: '-0.02em',
          lineHeight: 1.08, marginTop: 14 }}>
          Train on the<br/>right day.
        </div>
        <div className="af-muted" style={{ fontSize: 14, lineHeight: 1.55, marginTop: 14 }}>
          An AI coach for hybrid athletes. Every 6am, your plan adapts to HRV, sleep, and yesterday's load.
        </div>

        {!sent ? (
          <div style={{ display: 'flex', gap: 8, marginTop: 22 }}>
            <input className="af-input" placeholder="your@email.com"
              value={email} onChange={e => setEmail(e.target.value)}
              style={{ flex: 1 }}/>
            <Btn size="md" onClick={() => email.includes('@') && setSent(true)}>
              Join <Icon name="chevR" size={12}/>
            </Btn>
          </div>
        ) : (
          <div style={{ marginTop: 22, padding: 14, border: '1px solid var(--border)',
            borderRadius: 10, display: 'flex', gap: 10 }}>
            <Icon name="check" size={18} style={{ color: 'var(--ready-high)' }}/>
            <div style={{ fontSize: 13 }}>You're on the list. We'll email when your spot opens.</div>
          </div>
        )}
        <div className="af-muted af-mono" style={{ fontSize: 10, marginTop: 10 }}>
          1,482 ATHLETES ON WAITLIST · NEXT COHORT MAY 15
        </div>
      </div>

      {/* Mock preview */}
      <div style={{ margin: '30px 24px', padding: 20, background: 'var(--bg-subtle)',
        borderRadius: 14, border: '1px solid var(--border)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
          <Ring value={84} size={56} stroke={5}/>
          <div>
            <div className="af-label">READINESS · TODAY</div>
            <div className="af-h3" style={{ marginTop: 4 }}>Ready</div>
          </div>
        </div>
        <div style={{ padding: '12px 14px', background: 'var(--bg-elev)',
          border: '1px solid var(--border)', borderRadius: 8 }}>
          <div className="af-label" style={{ fontSize: 9 }}>THRESHOLD RUN</div>
          <div style={{ fontSize: 14, fontWeight: 500, marginTop: 3 }}>
            4×8 min @ threshold
          </div>
          <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 4 }}>
            64m · Z3–4 · TSS 78
          </div>
        </div>
      </div>

      <div style={{ padding: '0 24px 32px' }}>
        <div className="af-label" style={{ marginBottom: 14 }}>HOW IT WORKS</div>
        {[
          ['01', 'Wear your watch', 'Sync Garmin or Apple Watch. We read HRV, sleep, and training load.'],
          ['02', 'Answer 5 questions', 'Tell us your goal, hours, and modalities. Takes under 2 minutes.'],
          ['03', 'Train on the right day', 'Each morning at 6am, your plan reshapes to match your readiness.'],
        ].map(([n, t, d]) => (
          <div key={n} style={{ padding: '16px 0',
            borderTop: '1px solid var(--border)', display: 'flex', gap: 14 }}>
            <div className="af-mono" style={{ fontSize: 13, color: 'var(--fg-muted)',
              width: 26 }}>{n}</div>
            <div>
              <div style={{ fontSize: 14, fontWeight: 500 }}>{t}</div>
              <div className="af-muted" style={{ fontSize: 12, marginTop: 4, lineHeight: 1.5 }}>{d}</div>
            </div>
          </div>
        ))}
      </div>

      <div style={{ padding: '0 24px 40px' }}>
        <div className="af-label" style={{ marginBottom: 14 }}>HOW AMAKAFLOW WORKS</div>
        {[
          ['TELEGRAM — YOUR COACH, EVERY MORNING',
            "A daily briefing lands in Telegram with today's session and the reason behind it. Reply to swap a workout, scale it back, or adjust around fatigue. Sunday you get a summary of what changed and why."],
          ['THE APP — SETUP AND REVIEW',
            "Answer a few questions about your goal, training time, and what you do. AmakaFlow builds your plan, shows the reasoning behind it, and keeps a record of every adaptation over time. You don't open the app to train — it's for setup and review."],
          ['YOUR WATCH — WHERE TRAINING HAPPENS',
            "Open the day's session and send the workout to your Garmin. Intervals, sets, and reps are structured on the device. Completed training data feeds back into what comes next."],
          ['ONE ADAPTIVE COACH',
            "Most tools handle one part of training well: running plans, strength logs, or spreadsheets. AmakaFlow connects those pieces into one coach that adapts tomorrow based on what happened today. For hybrid athletes training for a HYROX, a half-marathon, or a general fitness PR."],
        ].map(([h, b]) => (
          <div key={h} style={{ padding: '18px 0',
            borderTop: '1px solid var(--border)' }}>
            <div className="af-label" style={{ marginBottom: 8, color: 'var(--fg)' }}>{h}</div>
            <div className="af-muted" style={{ fontSize: 13, lineHeight: 1.6 }}>{b}</div>
          </div>
        ))}
      </div>

      <div style={{ padding: '24px', borderTop: '1px solid var(--border)',
        display: 'flex', justifyContent: 'space-between',
        color: 'var(--fg-muted)', fontSize: 11, fontFamily: 'var(--font-mono)' }}>
        <span>© 2026 AMAKAFLOW</span>
        <span>PRIVACY · TERMS</span>
      </div>
    </div>
  );
}

// ----------------------------------------------------------- Landing Desktop
function LandingDesktop({ nav }) {
  const [email, setEmail] = React.useState('');
  const [sent, setSent] = React.useState(false);
  return (
    <div className="af-scroll" style={{ height: '100%', overflowY: 'auto' }}>
      <div style={{ padding: '20px 56px', borderBottom: '1px solid var(--border)',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 28, height: 28, borderRadius: 7, background: 'var(--fg)',
            color: 'var(--bg)', display: 'flex', alignItems: 'center',
            justifyContent: 'center' }}>
            <Icon name="bolt" size={15}/>
          </div>
          <span style={{ fontSize: 15, fontWeight: 600, letterSpacing: '-0.01em' }}>AmakaFlow</span>
        </div>
        <div style={{ display: 'flex', gap: 26, alignItems: 'center',
          fontSize: 13, color: 'var(--fg-muted)' }}>
          <span style={{ cursor: 'pointer' }}>How it works</span>
          <span style={{ cursor: 'pointer' }}>Science</span>
          <span style={{ cursor: 'pointer' }}>Pricing</span>
          <Btn size="sm" variant="ghost" onClick={() => nav('paywall-d')}>Join waitlist</Btn>
        </div>
      </div>

      <div style={{ padding: '72px 56px 56px', display: 'grid',
        gridTemplateColumns: '1.15fr 1fr', gap: 56, alignItems: 'center' }}>
        <div>
          <Chip outline style={{ marginBottom: 20 }}>
            <span className="af-dot af-dot-high"/> NOW IN BETA · 1,482 ATHLETES
          </Chip>
          <div className="af-eyebrow" style={{ marginBottom: 16 }}>ADAPTIVE COACHING FOR HYBRID ATHLETES</div>
          <div style={{ fontSize: 68, fontWeight: 600, letterSpacing: '-0.025em',
            lineHeight: 1.02 }}>
            Train on the<br/>right day.
          </div>
          <div className="af-muted" style={{ fontSize: 17, lineHeight: 1.55, marginTop: 24,
            maxWidth: 520 }}>
            An AI coach for hybrid athletes. Every morning, your plan adapts to HRV, sleep, and yesterday's training load — so you push when you're ready and recover when you're not.
          </div>

          {!sent ? (
            <div style={{ display: 'flex', gap: 10, marginTop: 32, maxWidth: 480 }}>
              <input className="af-input" placeholder="your@email.com"
                value={email} onChange={e => setEmail(e.target.value)}
                style={{ flex: 1, padding: '14px 16px', fontSize: 14 }}/>
              <Btn size="lg" onClick={() => email.includes('@') && setSent(true)}>
                Join waitlist <Icon name="chevR" size={14}/>
              </Btn>
            </div>
          ) : (
            <div style={{ marginTop: 32, padding: 16, border: '1px solid var(--border)',
              borderRadius: 10, display: 'inline-flex', gap: 10, alignItems: 'center' }}>
              <Icon name="check" size={18} style={{ color: 'var(--ready-high)' }}/>
              <div style={{ fontSize: 14 }}>You're on the list. Next cohort opens May 15.</div>
            </div>
          )}
          <div className="af-muted af-mono" style={{ fontSize: 11, marginTop: 14 }}>
            FREE TRIAL · CANCEL ANYTIME · GARMIN + APPLE WATCH
          </div>
        </div>

        {/* Product preview */}
        <div style={{ background: 'var(--bg-subtle)', padding: 36, borderRadius: 20,
          border: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 18 }}>
            <Ring value={84} size={72} stroke={6}/>
            <div>
              <div className="af-label">READINESS · THU · 6:14 AM</div>
              <div className="af-h2" style={{ marginTop: 4 }}>Ready</div>
              <div className="af-muted" style={{ fontSize: 12, marginTop: 3 }}>
                HRV +8 · Sleep 7h 42m
              </div>
            </div>
          </div>
          <div style={{ padding: '16px 18px', background: 'var(--bg-elev)',
            border: '1px solid var(--border)', borderRadius: 10, marginBottom: 10 }}>
            <div className="af-label" style={{ fontSize: 10 }}>TODAY · THRESHOLD RUN</div>
            <div style={{ fontSize: 18, fontWeight: 500, marginTop: 5,
              letterSpacing: '-0.005em' }}>4×8 min @ threshold</div>
            <div className="af-muted af-mono" style={{ fontSize: 12, marginTop: 5 }}>
              64m · Z3–4 · TSS 78 · IF 0.87
            </div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)',
            gap: 6, marginTop: 14 }}>
            {[1,1,1,0,0,0,0].map((d, i) => (
              <div key={i} style={{ aspectRatio: 1, borderRadius: 6,
                background: d ? 'var(--accent-bg)' : 'transparent',
                border: d ? 'none' : '1px dashed var(--border-str)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: 'var(--fg-muted)', fontSize: 11 }}>
                {d ? <Icon name="check" size={12}/> : ''}
              </div>
            ))}
          </div>
        </div>
      </div>

      <div style={{ padding: '40px 56px', borderTop: '1px solid var(--border)',
        borderBottom: '1px solid var(--border)' }}>
        <div className="af-label" style={{ marginBottom: 20 }}>HOW IT WORKS</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 48 }}>
          {[
            ['01', 'Wear your watch', 'Sync Garmin or Apple Watch. We read HRV, resting HR, sleep, and training load every morning.'],
            ['02', 'Answer 5 questions', 'Goal, hours per week, modalities, experience, injuries. Under two minutes.'],
            ['03', 'Train on the right day', 'At 6am, your plan reshapes. Push when fresh, swap when tired, always progress safely.'],
          ].map(([n, t, d]) => (
            <div key={n}>
              <div className="af-mono" style={{ fontSize: 14, color: 'var(--fg-muted)',
                marginBottom: 10 }}>{n}</div>
              <div style={{ fontSize: 18, fontWeight: 500, letterSpacing: '-0.005em' }}>{t}</div>
              <div className="af-muted" style={{ fontSize: 13, marginTop: 8,
                lineHeight: 1.6 }}>{d}</div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ padding: '56px 56px 64px' }}>
        <div className="af-label" style={{ marginBottom: 22 }}>HOW AMAKAFLOW WORKS</div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)',
          columnGap: 56 }}>
          {[
            ['TELEGRAM — YOUR COACH, EVERY MORNING',
              "A daily briefing lands in Telegram with today's session and the reason behind it. Reply to swap a workout, scale it back, or adjust around fatigue. Sunday you get a summary of what changed and why."],
            ['THE APP — SETUP AND REVIEW',
              "Answer a few questions about your goal, training time, and what you do. AmakaFlow builds your plan, shows the reasoning behind it, and keeps a record of every adaptation over time. You don't open the app to train — it's for setup and review."],
            ['YOUR WATCH — WHERE TRAINING HAPPENS',
              "Open the day's session and send the workout to your Garmin. Intervals, sets, and reps are structured on the device. Completed training data feeds back into what comes next."],
            ['ONE ADAPTIVE COACH',
              "Most tools handle one part of training well: running plans, strength logs, or spreadsheets. AmakaFlow connects those pieces into one coach that adapts tomorrow based on what happened today. For hybrid athletes training for a HYROX, a half-marathon, or a general fitness PR."],
          ].map(([h, b]) => (
            <div key={h} style={{ padding: '24px 0',
              borderTop: '1px solid var(--border)' }}>
              <div className="af-label" style={{ marginBottom: 10, color: 'var(--fg)',
                fontSize: 11 }}>{h}</div>
              <div className="af-muted" style={{ fontSize: 14, lineHeight: 1.65,
                maxWidth: 540 }}>{b}</div>
            </div>
          ))}
        </div>
      </div>

      <div style={{ padding: '24px 56px', borderTop: '1px solid var(--border)',
        display: 'flex', justifyContent: 'space-between', color: 'var(--fg-muted)',
        fontSize: 11, fontFamily: 'var(--font-mono)' }}>
        <span>© 2026 AMAKAFLOW</span>
        <span>PRIVACY · TERMS · SUPPORT</span>
      </div>
    </div>
  );
}

Object.assign(window, { PaywallMobile, PaywallDesktop, LandingMobile, LandingDesktop });
