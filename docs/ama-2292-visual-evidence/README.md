# AMA-2292 visual evidence

**What we're testing:** After UITEST auth + onboarding skip, root nav shows exactly Today · Library · Profile — not the old 6-tab bar, and not Clerk/onboarding.

| File | Meaning |
| --- | --- |
| `00-cold-launch-unsigned.png` | AMA-1854 crash-gate only (no sign-in). Expect Clerk/onboarding. **Not** tab proof. |
| `01-today-root.png` | Authenticated Today diary + 3-tab bar |
| `02-library-fab.png` | Library + FAB (`af_library_fab`) |
| `03-profile-hub.png` | Profile hub (Coach / History / Settings rows) |

## Auth path used

`UITEST_CLERK_TEST_SESSION` (AMA-1843 UI mock) + `UITEST_SKIP_ONBOARDING=true`.

`UITEST_CLERK_PASSWORD` was **not** available in this environment (Infisical: no valid login session; GitHub Actions secrets are write-only). Real Clerk JWT path remains the preferred CI gate once the secret is injectable.

## Re-run

```bash
maestro --device <SIM_UDID> test e2e/maestro/ama-2292-visual-tab-shell.yaml
```
