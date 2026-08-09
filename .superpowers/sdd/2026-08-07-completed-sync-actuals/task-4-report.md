# AMA-2387 — Task 4 report: Strava/Garmin OAuth scope + stub

**Status: CODE DONE** (compile/test pending sim recovery)

## Built
- `ActualsCopy.oauthScopes` — upload struck-through NOT REQUESTED (never `activity:write`)
- `ActualsProviderAuthProviding` + `StubActualsProviderAuth` + `MockActualsProviderAuth`
- `ActualsProviderAuthAction` — success → markConnected; cancelled → nothing linked
- `ActualsOAuthScopeView` — host chrome + scope card + Authorize/Cancel
- Connect Sources Garmin/Strava → OAuth scope screen
- Tests: `ActualsProviderAuthTests`

Nothing committed yet.
