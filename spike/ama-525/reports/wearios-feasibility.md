# Wear OS LiteRT Feasibility — AMA-525 Spike

## Verdict

✅ Feasible — A quantised 1D-CNN at ~4,900 INT8 parameters (~10 KB weight file) is well within
LiteRT's demonstrated capabilities on Wear OS hardware. Inference latency for a model this size
is estimated at under 5 ms on the CPU delegate alone, making per-rep inference trivially fast.
The primary engineering risk is battery life under continuous 200 Hz sensor sampling, not compute.

---

## LiteRT on Wear OS

### Framework
LiteRT (formerly TensorFlow Lite, rebranded late 2024) is Google's on-device inference framework
for Android and edge platforms. It ships as a standard Android AAR dependency and is fully
compatible with the Wear OS subset of the Android SDK — no special Wear OS variant is required.

### API and Minimum Requirements
- **Minimum Wear OS version**: Wear OS 2.0 (API level 26). LiteRT's core Interpreter API targets
  Android API 21+. The recommended `CompiledModel` API (LiteRT 1.x) requires API 24+.
- **Recommended target**: Wear OS 4 / API 33+ to access NNAPI delegate on Snapdragon W5 Gen 1
  and Exynos W930 devices (Galaxy Watch 6/7, Pixel Watch 2/3).
- **High sampling rate permission**: `android.permission.HIGH_SAMPLING_RATE_SENSORS` must be
  declared in the manifest for sensors above 200 Hz (required for Android API 31+ targets).
- LiteRT's `CompiledModel` API (GA in 2025) provides a unified accelerator path across CPU, GPU,
  and NPU and is the preferred API for new implementations.

### Hardware Acceleration
| Chipset               | Devices                          | Accelerator path       |
|-----------------------|----------------------------------|------------------------|
| Snapdragon W5 Gen 1   | Pixel Watch 2, Pixel Watch 3     | NNAPI / Qualcomm NPU   |
| Exynos W930           | Galaxy Watch 6 / 7               | NNAPI / Samsung NPU    |
| Exynos W1000          | Galaxy Watch Ultra, Galaxy Watch 7 Ultra | Arm Cortex-A78 + NPU |
| Snapdragon W5+        | Pixel Watch 2 (Pro)              | NNAPI + Hexagon DSP    |
| Older / budget        | Fossil, Mobvoi older devices     | CPU only               |

Google internal benchmarks cite NPUs delivering up to **25x** faster inference than CPU at
**1/5** the power draw. For a ~10 KB INT8 model the absolute CPU latency is already low enough
that NPU offload is a latency optimisation, not a necessity.

---

## Sensor Capabilities

### SensorManager on Wear OS
Wear OS exposes the standard Android `SensorManager` API. No proprietary wearable sensor HAL is
required. Key facts:

- **Accelerometer**: `TYPE_ACCELEROMETER` — available on all Wear OS devices.
- **Gyroscope**: `TYPE_GYROSCOPE` — available on Galaxy Watch 4+, Pixel Watch, most post-2021
  devices. Absent on ultra-budget wearables (e.g., some Fossil Gen 5 variants).
- **200 Hz**: Achievable via `registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)`
  or specifying `samplingPeriodUs = 5000` (5 ms = 200 Hz). Requires
  `HIGH_SAMPLING_RATE_SENSORS` permission on API 31+.
- **Realistic sustained rate**: Research indicates 200 Hz is sufficient for running biomechanics
  and strength training rep detection. Studies show accelerometer accuracy above 100 Hz does not
  improve (and may degrade) for walking/running gait analysis; 100–200 Hz is the practical sweet
  spot for high-speed cyclic movements.
- **Background delivery**: Wear OS foreground services with `FOREGROUND_SERVICE_TYPE_HEALTH`
  (API 34+) allow sustained sensor delivery during workout tracking without the OS batching or
  throttling samples.

---

## Latency Estimate

### Model Characteristics (AMA-525 spike model)
- Architecture: 1D-CNN
- Parameters: ~4,900
- Weight format: INT8 quantised
- Estimated weight file: ~10 KB

### Inference Latency Estimate
LiteRT benchmarks on comparable tiny INT8 models (sub-100 KB, conv1d + dense layers):

| Hardware path              | Estimated latency  | Basis                                      |
|----------------------------|--------------------|---------------------------------------------|
| CPU (Exynos W930 / W1000)  | 1–5 ms             | Extrapolated from MLPerf mobile INT8 results|
| CPU (Snapdragon W5 Gen 1)  | 2–8 ms             | Comparable Snapdragon 660-class CPU perf    |
| NNAPI / NPU delegate       | < 1 ms             | NPU 25x CPU speedup applied to CPU baseline |

At a rep cadence of 0.5–2 Hz (one rep every 500–2000 ms), even a worst-case 8 ms CPU inference
latency represents less than 2% of a rep period — effectively zero scheduling overhead.

For inference triggered once per rep (post-peak-detection), a foreground thread with a 50 ms
budget is ample. Continuous per-sample inference (200 samples/s × ~5 ms = ~100% CPU) would be
inadvisable; this is not required for the use case.

---

## Battery Impact

### Sensor Sampling
Continuous high-frequency sensor sampling is the primary battery cost, not inference:
- 200 Hz accelerometer + gyroscope in a foreground service: estimated **5–15 mW** additional
  draw on modern Wear OS hardware (Samsung developer data for Galaxy Watch).
- Wear OS power guidance recommends batched sensor delivery for background use; for active
  workout tracking the foreground service approach is expected and acceptable.

### LiteRT Inference (per-rep)
- At 2 reps/minute and ~5 ms CPU inference per rep: average additional CPU active time
  ~0.17 ms/s, negligible in power terms.
- At 1 inference per 200 Hz sample (continuous, inadvisable): ~100% CPU core, ~100–300 mW — not
  recommended.

### Recommended duty cycle
Trigger inference once per detected rep (post peak-detection gate) rather than per sample.
This decouples sensor sampling rate from inference rate. Battery impact from inference alone
will be unmeasurable in normal workout sessions (< 60 min).

### Practical Wear OS Battery Guidance
- Use `SENSOR_DELAY_GAME` (50 Hz) as a fallback for devices that throttle `FASTEST` in
  background.
- Register/unregister sensors in `onResume`/`onPause` of the workout tile or foreground service.
- Do not hold a `WakeLock` for sensor delivery in foreground services; the OS manages this.

---

## Comparison to Apple Watch

| Dimension               | Wear OS (LiteRT)                          | Apple Watch (Core ML / ANE)                    |
|-------------------------|-------------------------------------------|------------------------------------------------|
| Inference framework     | LiteRT (TFLite successor), NNAPI delegate | Core ML, delegating to ANE or GPU              |
| Hardware accelerator    | Qualcomm Hexagon DSP / Samsung NPU        | Apple Neural Engine (4-core, S9/S10 SiP)      |
| ANE introduction        | N/A — NPU available on W5+ / Exynos W930  | watchOS 6 + S4 SiP (2-core ANE, 2019)         |
| ANE throughput (S9)     | N/A                                       | ~15 TOPS (estimated, not disclosed by Apple)   |
| Tiny model latency      | 1–8 ms CPU; < 1 ms NPU (estimated)        | < 1 ms ANE (measured by community benchmarks)  |
| Sensor API              | Android SensorManager, standard           | CMMotionManager, up to 100 Hz acc / 100 Hz gyro|
| Max accelerometer rate  | 200 Hz (with permission)                  | 100 Hz (CMMotionManager hard cap on watchOS)   |
| ML model format         | `.tflite` / LiteRT FlatBuffer             | `.mlpackage` / `.mlmodel` (CoreML format)      |
| On-device training      | LiteRT on-device training (experimental)  | Create ML on-device (watchOS 8+, limited)      |
| Developer friction      | Maven dependency, standard Android        | Xcode-integrated, first-class tooling          |

Key takeaway: For the AMA-525 model size, both platforms can handle inference in well under 10 ms.
Apple Watch has a latency edge from the dedicated ANE, but Wear OS closes the gap with NNAPI /
NPU delegates on modern hardware. Apple Watch is limited to 100 Hz sensor sampling vs. 200 Hz on
Wear OS — an advantage for Wear OS if higher-frequency kinematic features prove beneficial.

---

## Recommended Approach

### Architecture
1. **Sensor collection**: Register `TYPE_ACCELEROMETER` + `TYPE_GYROSCOPE` at 100 Hz
   (conservative, avoids permission complexity; step up to 200 Hz if model accuracy requires it).
2. **Windowing**: Accumulate a 2-second sliding window (200 samples at 100 Hz) of 6-channel
   data (acc x/y/z + gyro x/y/z) in a circular buffer.
3. **Inference trigger**: Run a lightweight peak-detection pass (RMS threshold) to identify rep
   events, then trigger LiteRT inference on the completed rep window.
4. **LiteRT runtime**: Use the `Interpreter` API with `NnApiDelegate` as primary, falling back
   to `XNNPackDelegate` (CPU SIMD) on devices without NNAPI support.
5. **Output**: Emit a form quality score (0–100) to the Wear OS tile / ongoing notification.

### Build Integration
```kotlin
// build.gradle (Wear OS module)
implementation("com.google.ai.edge.litert:litert:1.0.1")
implementation("com.google.ai.edge.litert:litert-gpu:1.0.1")      // optional
implementation("com.google.ai.edge.litert:litert-support:1.0.1")
```

### Model Packaging
- Bundle the `.tflite` file in `assets/` (no Play Models API required for a static model).
- INT8 quantisation confirmed to reduce model to ~10 KB; validate accuracy against float32
  baseline before shipping.

### Minimum SDK targets
```xml
<uses-permission android:name="android.permission.HIGH_SAMPLING_RATE_SENSORS" />
<!-- minSdkVersion 26, targetSdkVersion 34 -->
```

---

## References

- [LiteRT for Android — Google AI Edge](https://ai.google.dev/edge/litert/android)
- [LiteRT: Maximum performance, simplified — Google Developers Blog](https://developers.googleblog.com/litert-maximum-performance-simplified/)
- [Google Enhances LiteRT for Faster On-Device Inference — InfoQ (May 2025)](https://www.infoq.com/news/2025/05/google-litert-on-device-ai/)
- [Unlocking Peak Performance on Qualcomm NPU with LiteRT — Google Developers Blog](https://developers.googleblog.com/unlocking-peak-performance-on-qualcomm-npu-with-litert/)
- [LiteRT Delegates — Google AI Edge](https://ai.google.dev/edge/litert/performance/delegates)
- [Hardware optimization on Android for AI model inference — arXiv 2511.13453](https://arxiv.org/html/2511.13453v1)
- [Motion sensors — Android Developers](https://developer.android.com/develop/sensors-and-location/sensors/sensors_motion)
- [Conserve power and battery — Wear OS Android Developers](https://developer.android.com/training/wearables/apps/power)
- [Wear OS 5.1 — Android Developers](https://developer.android.com/training/wearables/versions/5-1)
- [Understanding and Converting Galaxy Watch Accelerometer Data — Samsung Developer (Apr 2025)](https://developer.samsung.com/sdp/blog/en/2025/04/10/understanding-and-converting-galaxy-watch-accelerometer-data)
- [Influence of Sampling Rate on Wearable IMU Orientation Estimation — PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11991382/)
- [SensorLib: Energy-efficient Sensor-collection for Wear OS — ACM](https://dl.acm.org/doi/fullHtml/10.1145/3651640.3651641)
- [Apple S9 SiP Neural Engine — NotebookCheck](https://www.notebookcheck.net/Apple-S9-SiP-Processor-Benchmarks-and-Specs.780134.0.html)
- [What the Hell is a Neural Engine? — Greg Gant (2024)](https://blog.greggant.com/posts/2024/06/24/what-the-hell-is-an-apple-neural-engine.html)
