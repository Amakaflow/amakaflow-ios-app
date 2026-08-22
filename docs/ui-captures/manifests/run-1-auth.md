# Capture manifest — run-1-auth

- build: `f47e38c7` (build the app was compiled from, supplied explicitly)
- device: iPhone 17 Pro Max · iOS-26-1, erased before capture
- artifacts: `docs/ui-captures/f47e38c7/run-1-auth/`
- auth: signed out — simulator erased so no session exists

Captured by hand rather than by probe. The other runs relaunch an app that is
already signed in; this run needs the opposite, a device with no session at
all, which only an erase produces. An erase is destructive and not something a
probe should do on a shared simulator, so these three states were driven
manually and the steps recorded here instead.

No account was signed into. The screens below are what a new install shows
before any credentials exist, so nothing here depends on a real identity.

| Screen | Status | Evidence |
| --- | --- | --- |
| `permission-notifications` | CAPTURED | notification prompt, not-determined state |
| `mental-model-gate` | CAPTURED | "Three places. One coach." onboarding |
| `sign-in` | CAPTURED | Sign in with Apple / Continue with email |

3 of 3 screens captured.

## Superseded, do not act on the defects below

David, 2026-08-22: onboarding still carries the old design and is due to be
redesigned once the full design lands. These captures are therefore a record
of what shipped today, not a defect list. Nothing below should become a
ticket; recapture after the redesign instead.

## Two issues visible in these captures

**Pre-auth screens ignore dark mode.** `BASELINE.md` fixes appearance to Dark,
and every signed-in screen honours it. The mental-model gate and the sign-in
screen render light. `ContentView` sets `.preferredColorScheme(.dark)`, but
these screens sit above it in `unauthenticatedRoot`, so nothing applies it.

**Terms line is truncated.** The sign-in screen reads "you agree to AmakaFlow's
Terms and Privac…". A legal consent line clipped mid-word would normally be worth a ticket;
here it waits for the redesign.

## Not captured

Permission allowed and denied end-states, and the post-sign-in transition.
Both need a real sign-in, which needs credentials this capture deliberately
does not use.
