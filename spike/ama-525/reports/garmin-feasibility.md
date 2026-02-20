# Garmin Connect IQ Feasibility — AMA-525 Spike

## Verdict

⚠️ Feasible with constraints — Classical signal processing (peak detection + rule-based classifier)
is viable. No ML inference runtime exists in Monkey C, so the 1D-CNN model explored in this spike
cannot be ported to Connect IQ. A rule-based form classifier is the only practical path.

---

## Sensor Capabilities

### Accelerometer
- API: `Sensor.registerSensorDataListener()` with an options dictionary
- Maximum sample rate: **100 Hz** (configurable via `:sampleRate` key)
- Typical field usage: 25–50 Hz to stay within memory budgets
- Data arrives in batched arrays per `:period` callback (e.g., 25 samples per 1-second period at 25 Hz)
- Timestamps array available for synchronisation across axes

### Gyroscope
- Accessible via the same `registerSensorDataListener()` call, `Toybox.Sensor.SensorData`
- Maximum sample rate: **100 Hz**
- Not available on all devices — must check device `.xml` capability flags before enabling
- Community reports note that gyroscope support is patchier than accelerometer across older lines

### Magnetometer
- Also available in `SensorData`, but irrelevant to IMU form classification

### Practical Constraint
Raw sensor arrays are delivered to the callback as `Array<Number>`. Each element is a signed 16-bit
integer scaled to milli-g (accelerometer) or milli-deg/s (gyroscope). There is no floating-point
DSP pipeline; all arithmetic is done in Monkey C's dynamically typed runtime where every object
allocation counts against heap.

---

## Compute Constraints

### Memory Budget (Monkey C heap)
Memory limits are defined per device and per app type in the SDK device `.xml` files:

| Device family       | Data Field budget | Activity app budget |
|---------------------|-------------------|---------------------|
| fēnix 6X Pro        | 128 KB            | 131 KB              |
| fēnix 7 / epix Gen 2| 256 KB            | 256 KB              |
| fēnix 8             | **128 KB** (halved vs. 7) | 256 KB      |
| Forerunner 965 / 255| 256 KB            | 256 KB              |
| Older budget devices| 28–64 KB          | 64–92 KB            |

Key points:
- The compiled `.prg` binary + loaded resources + runtime heap all share this budget.
- `registerSensorDataListener()` allocates API callback objects that are charged to the heap.
  Large circular buffers or history windows will exhaust memory quickly.
- Exceeding the budget causes the OS to silently terminate the app and fall back to the default
  watch face — no crash log is surfaced to the user.
- The Connect IQ simulator exposes a "View Memory" tool (File → View Memory) that is the primary
  profiling path.

### No ML Inference Runtime
- Monkey C has no tensor runtime, no matrix multiply primitive, no BLAS, and no NNAPI bridge.
- There is no documented path to load a `.tflite` or CoreML model.
- All computation must be expressed as explicit integer/float Monkey C code.
- A quantised 1D-CNN with 4,900 parameters and INT8 weights is **not portable** to Connect IQ.

### CPU Throughput
- Garmin does not publish clock speeds for individual watch SoCs.
- Community benchmarks show simple per-sample arithmetic (add, compare, running average) at
  25 Hz is well within budget.
- A sliding-window RMS + zero-crossing peak detector running on 50 samples (2 s at 25 Hz) is
  feasible; a full CNN forward pass is not.

---

## Recommended Approach

Given the absence of an ML runtime, a **classical signal processing pipeline** is recommended:

1. **Sampling**: Register accelerometer at 25 Hz (saves memory vs 100 Hz, sufficient for rep
   counting at typical strength-training frequencies 0.5–2 Hz).
2. **Buffering**: Maintain a circular buffer of the last 50–100 samples (~200–400 bytes of
   integer arrays) per axis.
3. **Peak detection**: Compute a running mean and detect positive-to-negative zero-crossings of
   the mean-subtracted signal to identify rep peaks. Simple threshold guards (e.g., amplitude
   must exceed 0.3 g) reject noise.
4. **Form heuristics**: Derive per-rep scalar features from the buffer:
   - Concentric vs. eccentric duration ratio (time above vs. below mid-point)
   - Peak-to-peak amplitude symmetry across left/right axes
   - Jerk proxy (first difference of acceleration vector magnitude)
   Compare against per-exercise thresholds stored as constants.
5. **Output**: Emit a single form-quality integer (0–100) as a data field value each rep.

This pipeline requires ~2–4 KB of working heap and runs comfortably within 28 KB (worst-case
budget device), making it broadly compatible.

---

## Device Coverage

`Sensor.registerSensorDataListener()` is available from **Connect IQ API level 3.1+**.

Devices confirmed to support accelerometer + gyroscope data fields:

- **fēnix series**: fēnix 5 Plus and later; fēnix 6 / 6S / 6X all variants; fēnix 7 / 7S / 7X;
  fēnix 8 (all sizes)
- **epix series**: epix Gen 2, epix Pro
- **Forerunner series**: FR245, FR255, FR265, FR745, FR945, FR955, FR965
- **quatix / tactix**: quatix 7, tactix 7
- **Instinct series**: Instinct 2 / 2X Solar (accelerometer only; gyroscope availability varies)
- **Venu / vivoactive**: Venu 3 / Sq 2 have accelerometer; gyroscope not guaranteed

Devices running **CIQ < 3.1** or low-end fitness trackers (Vivosmart, Vivofit) do **not** have
`registerSensorDataListener()` and must be excluded from the target device list.

SDK 7.4.3+ is required for System 8 devices (fēnix 8, 2025 Q2 QMR and later). The Connect IQ
store mandates SDK 8.1 minimum for uploads as of mid-2025.

---

## Open Questions

1. **Gyroscope on Instinct / Venu**: Needs direct test — community reports conflict on whether
   the gyroscope `:enabled` flag silently no-ops on these devices.
2. **fēnix 8 memory halving**: The halved data field budget (128 KB vs. 256 KB on fēnix 7) is
   unexplained in official docs. Garmin engineering should be asked whether this is a hardware
   constraint or a CIQ system policy.
3. **Callback timing jitter**: At 100 Hz the callback is guaranteed to fire within the `:period`
   window, but inter-sample jitter within the delivered array is unstated. For phase-sensitive
   gyroscope integration this matters.
4. **Background sensor access**: Garmin's Background Service API does not grant access to
   `registerSensorDataListener()`. Rep counting is only feasible as an active foreground data
   field or activity app.
5. **Distribution model**: Garmin Connect IQ Store approval timelines are known to be slow (weeks).
   Confirm AmakaFlow release cadence is compatible before committing.

---

## References

- [Toybox.Sensor API docs — Garmin Developer](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor.html)
- [Toybox.Sensor.AccelerometerData](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor/AccelerometerData.html)
- [Toybox.Sensor.SensorData](https://developer.garmin.com/connect-iq/api-docs/Toybox/Sensor/SensorData.html)
- [Core Topics: Sensors — Garmin Developer](https://developer.garmin.com/connect-iq/core-topics/sensors/)
- [Monkey C Objects and Memory — Garmin Developer](https://developer.garmin.com/connect-iq/monkey-c/objects-and-memory/)
- [Understanding Connect IQ device memory limits — Garmin Forums](https://forums.garmin.com/developer/connect-iq/f/discussion/4060/understanding-connect-iq-device-memory-limits)
- [Fenix 8 data field memory — Garmin Forums](https://forums.garmin.com/developer/connect-iq/f/discussion/382120/fenix-8-data-field)
- [Connect IQ SDK 6.3.0 Release Notes — Garmin Forums](https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/connect-iq-6-3-0-sdk-release)
- [Compatible Devices — Garmin Developer](https://developer.garmin.com/connect-iq/compatible-devices/)
- [How to improve Connect IQ app performance — Garmin Blog](https://www.garmin.com/en-US/blog/developer/improve-your-app-performance/)
