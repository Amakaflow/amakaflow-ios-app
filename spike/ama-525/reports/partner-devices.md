# Partner Device Ecosystem — AMA-525 Spike

## Summary

The bar-mounted sensor space is dominated by a small number of mature players (GymAware, Output Sports,
RepOne) alongside several legacy or discontinued products (PUSH Band, Beast Sensor). Of the active
vendors, GymAware has the most clearly documented, publicly accessible REST API — gated behind a
Cloud Pro license — making it the lowest-friction first integration target. Output Sports exposes an
open API for AMS data push/pull but targets enterprise coaches rather than mobile SDK consumers,
while RepOne is actively building out its Connected ecosystem but its developer-facing SDK is not yet
publicly documented as of early 2026.

---

## Device Comparison

| Device | Technology | API Available | Data Quality | Integration Complexity | Recommendation |
|---|---|---|---|---|---|
| **GymAware FLEX** | Laser optic array + cloud sync via FLEX Bridge | Yes — REST API included with Cloud Pro license ($995/yr). Newline-delimited JSON stream. Batch pull (no real-time push). | Gold standard. Mean velocity, peak velocity, peak/avg power, ROM, bar path coordinates, rep distance, set averages, predictive 1RM. ~20 ms sample resolution on peak velocity. | Medium. Requires Cloud Pro license + FLEX Bridge hardware dongle for cloud sync. API is well-documented (Zendesk + integration guide). Auth via Account ID + token. | **Priority 1** |
| **Output Sports V2** | 9-axis IMU (1000 Hz). Clips to barbell or worn on body. | Yes — "open API" for AMS integrations documented at outputsports.com/performance/api-integrations. Targets data warehouse / AMS pull, not real-time streaming. | High. 180+ tests: mean/peak velocity (VBT), CMJ height, takeoff velocity, contact time, RSI, drop jump, power output. Claims 99% accuracy vs force plate. | Medium-High. API targets B2B enterprise (Kinduct, TeambuildR integrations cited). No public SDK; developer access likely requires direct vendor engagement and an enterprise subscription. | Priority 2 |
| **RepOne (Tether)** | Linear encoder (cable-pull). BLE. Originated as open-source OpenBarbell. | Partial. RepOne Connected exposes APIs/SDKs for equipment manufacturers. Public developer documentation not yet available (as of Q1 2026). | High for encoder-based velocity. Barbell velocity, ROM, rep time. Batch export supported. | High for now. SDK described as "in development / modular" for OEM partners. Not a self-serve integration path at present. | Watch — revisit in 6 months |
| **PUSH Band 2.0** | IMU wrist-worn / bar-clipped accelerometer | No longer viable. Acquired by WHOOP in Sept 2021; product discontinued. | Moderate (validation studies showed reliability but limited validity vs laser). | N/A — discontinued | Do not pursue |
| **Beast Sensor** | IMU (magnetic, bar-mounted). Italian product. | Not available. App last updated 2018 (Android); iOS app removed. Company appears defunct. | Low (poor validation findings in literature). | N/A — discontinued | Do not pursue |
| **Vmaxpro / Enode** | Accelerometer, bar-clipped. German product. | Partial. Subscription tier for raw data export (marketed toward researchers). No documented public REST API or SDK. | Moderate. Velocity and power output. Bar path analysis available in-app. | High — no self-serve developer path identified. | Low priority |
| **Stryd (running pod)** | Foot-pod IMU, running power. Included here as a partnership model analogy. | Limited. ANT+ protocol is private; no public SDK. Native integrations with Garmin and Apple only. Third-party data field workarounds exist on Garmin Connect IQ. | High for running (power, cadence, ground contact). Not applicable to barbell. | Very High for barbell use case. Wrong domain. | Analogy only — not a target device |

---

## Recommended First Integration

**GymAware FLEX** is the recommended first integration partner for AMA-525.

Reasons:

1. **Documented API with known data contract.** The GymAware Cloud REST API is publicly documented
   (Zendesk articles + dedicated integration guide). The JSON schema for the `/summaries` endpoint is
   stable and used by existing AMS integrations in the wild. This minimises discovery risk.

2. **Rich, validated bar data.** FLEX provides mean velocity, peak velocity, peak and average power,
   ROM, bar path (x/y coordinates), rep distance, and set-level aggregates. This is the superset of
   what AmakaFlow needs to pair with wrist IMU data for lift quality scoring.

3. **Clear licensing path.** API access is bundled into the $995/yr Cloud Pro license with no
   separate developer program to apply for. This means we can prototype immediately against a real
   account without a vendor negotiation cycle.

4. **Established in high-performance sport.** GymAware is widely cited in peer-reviewed VBT
   literature as a criterion device. Coaches already trust it, which reduces user on-boarding friction
   if we support it as an optional data source.

The main tradeoff is that the API is **batch/pull only** — data is accessible after a set is uploaded
to the GymAware Cloud (via the FLEX Bridge dongle), not as a real-time BLE stream during a rep.
AmakaFlow's integration architecture must therefore treat GymAware data as a post-session enrichment
layer rather than an in-rep feedback signal. This is acceptable for the AMA-525 scope.

Output Sports V2 is the recommended **second integration** once the GymAware path is proven, given
its breadth of tests (including jump testing and force-plate-grade CMJ metrics that AmakaFlow does not
currently cover with wrist IMU alone).

---

## Integration Model

```
Athlete lifts
     |
     v
GymAware FLEX sensor  ----BLE---->  FLEX iOS/Android app
     |                                      |
     |                              (FLEX Bridge dongle
     |                               syncs to GymAware Cloud)
     |                                      |
     v                                      v
GymAware Cloud  <---REST poll---  AmakaFlow backend (scheduled job
(summaries endpoint)              or on-demand after session end)
     |
     v
AmakaFlow session record:
  wrist IMU data (Apple Watch)  +  GymAware bar data (velocity, power, bar path)
  fused into unified lift model
     |
     v
AmakaFlow lift quality score, coaching cues, trend analytics
```

**Key design decisions for the integration layer:**

- **Polling cadence.** The GymAware `/summaries` endpoint supports `start`/`end` UTC epoch params
  (max 1-month window) and `modifiedSince` for incremental sync. AmakaFlow should store a
  `lastSyncedAt` timestamp per athlete and use `modifiedSince` to pull only new sets.

- **Identity mapping.** AmakaFlow athlete IDs must be mapped to GymAware athlete IDs at account-link
  time (OAuth or token-paste flow). GymAware does not expose OAuth; token + Account ID must be stored
  securely in AmakaFlow's backend secrets store.

- **Data model.** Each GymAware set record maps to an AmakaFlow `Set` entity. Rep-level velocity
  arrays and bar path coordinates should be stored in a separate `GymAwareRepData` table linked to
  the `Set` foreign key, rather than embedded in the core lift record, to avoid schema coupling.

- **Offline / no-FLEX fallback.** AmakaFlow must degrade gracefully when no GymAware data is
  available for a session. Wrist IMU alone remains the primary signal; GymAware data enriches it
  where present.

- **Real-time limitation acknowledgement.** Because GymAware data arrives post-session, any
  in-workout rep-by-rep feedback in AmakaFlow continues to rely solely on the Apple Watch wrist IMU.
  GymAware data feeds post-session analytics and retrospective coaching summaries.

---

## Open Questions

1. **FLEX Bridge availability and latency.** How quickly after a set does data appear in the
   GymAware Cloud? Is the Bridge required, or does the FLEX app sync over WiFi natively? Needs
   confirmation from GymAware support or a hands-on test unit.

2. **GymAware API rate limits and pagination.** The public documentation describes a newline-
   delimited JSON stream but does not specify rate limits, max records per response, or retry
   semantics. Need to review the full API integration guide
   (gymaware.com/gymaware-cloud-api-integration-guide/) and test with a real Cloud Pro account.

3. **Bar path coordinate system.** The FLEX tracks bar path (x/y), but the documentation does not
   specify the coordinate frame (is x lateral drift? is y vertical displacement?), units (mm? cm?),
   or frame rate. This affects how AmakaFlow visualises path data.

4. **Output Sports API access tier.** Does Output Sports require an enterprise contract to access
   the API, or is it available on any paid plan? Need to contact their sales team to determine
   whether a startup / indie developer tier exists.

5. **RepOne Connected SDK ETA.** RepOne describes their SDK as in active development for OEM
   partners. Are they open to a software-only integration partner (i.e., AmakaFlow as an app
   that reads RepOne data), and what is the expected timeline for a public SDK?

6. **Stryd analogy — lessons for partner model.** Stryd's walled-garden approach (private ANT+,
   platform-exclusive integrations) is a cautionary example. AmakaFlow should define clear
   contractual expectations around data portability and API stability before committing engineering
   effort to any sensor vendor.

7. **Multi-device sessions.** If an athlete uses both GymAware (bar) and Apple Watch (wrist), clock
   synchronisation between the two data streams is non-trivial. The GymAware set record includes a
   UTC timestamp; Apple Watch sensor data is timestamped locally. Network Time Protocol drift and
   Bluetooth pairing delays could cause alignment errors of 1–3 seconds. A synchronisation strategy
   (e.g., lift-start event alignment) needs design work before data fusion is reliable.

---

## References

- [GymAware API Integration Guide](https://gymaware.com/gymaware-cloud-api-integration-guide/)
- [GymAware API Integration — Zendesk](https://gymaware.zendesk.com/hc/en-us/articles/360001396875-API-Integration)
- [GymAware FLEX App Data and Implementation](https://gymaware.com/gymaware-flex-app-data-and-implementation/)
- [FLEX Metrics Displayed — GymAware Zendesk](https://gymaware.zendesk.com/hc/en-us/articles/6947872421007-FLEX-Metrics-Displayed)
- [Does FLEX Measure Peak Velocity and Peak Power?](https://gymaware.zendesk.com/hc/en-us/articles/6948063762959-Does-FLEX-measure-Peak-Velocity-and-Peak-Power)
- [GymAware Integration Package](https://gymaware.com/product/integration-package/)
- [GymAware Cloud Pro](https://gymaware.com/product/gymaware-cloud-pro/)
- [FLEX Bridge — GymAware Zendesk](https://gymaware.zendesk.com/hc/en-us/articles/6947902764559-FLEX-Bridge)
- [Output Sports — API Integrations](https://www.outputsports.com/performance/api-integrations)
- [Output Sports — How It Works](https://www.outputsports.com/how-it-works)
- [Output Sports — VBT Device](https://www.outputsports.com/performance/velocity-based-training)
- [Integrating Output Data into Your AMS — Output Sports Blog](https://www.outputsports.com/blog/integrating-output-data-into-your-athlete-management-system-with-nick-mascioli)
- [Output Sports V2 Sensor — Perform Better](https://www.performbetter.com/Output-Sports-V2-Sensor/)
- [RepOne Connected](https://www.reponestrength.com/connected)
- [RepOne Connected — Blog](https://www.reponestrength.com/repone-blog/repone-connected-fitness-reinvented)
- [OpenBarbell — GitHub (Liftology)](https://github.com/Liftology/OpenBarbell)
- [OpenBarbell V3 — GitHub (Squats and Science Labs)](https://github.com/squatsandsciencelabs/OpenBarbell-V3)
- [WHOOP Acquires PUSH — Press Release](https://www.prnewswire.com/news-releases/whoop-acquires-push-the-velocity-based-training-coaching-solution-301368511.html)
- [Vmaxpro / Enode](https://vmaxpro.de/)
- [Beast Sensor](https://thisisbeast.com/)
- [Stryd Dev — GitHub](https://github.com/stryd)
- [Stryd RIVAL Integration — Wahoo](https://support.wahoofitness.com/hc/en-us/articles/4411225067410-RIVAL-Stryd-Integration)
- [GymAware FLEX Review — SimpliFaster](https://simplifaster.com/articles/gymaware-flex-bar-speed-review/)
- [Buyers Guide to VBT Systems — SimpliFaster](https://simplifaster.com/articles/buyers-guide-velocity-based-training-systems/)
- [Best VBT Devices 2025 — VBT Coach](https://www.vbtcoach.com/blog/velocity-based-training-devices-buyers-guide)
- [Concurrent Validity of Smartphone Apps for Barbell Velocity — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11575817/)
