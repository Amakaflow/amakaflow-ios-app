import numpy as np
from typing import List, Tuple


def augment_insufficient_depth(rep: np.ndarray, depth_factor: float = 0.6) -> np.ndarray:
    """Simulate not reaching squat depth by scaling down descent-phase vertical accel.

    Modifies the Y axis (index 1) of the first half of the rep window.
    Does not mutate input.
    """
    result = rep.copy()
    descent_end = len(rep) // 2
    result[:descent_end, 1] = result[:descent_end, 1] * depth_factor
    return result


def augment_knee_cave(rep: np.ndarray, cave_magnitude: float = 0.3) -> np.ndarray:
    """Simulate knee cave by introducing sinusoidal lateral asymmetry (X axis, index 0).

    Affects the second half of the rep window. Does not mutate input.
    """
    result = rep.copy()
    mid = len(rep) // 2
    n = len(rep) - mid
    result[mid:, 0] = result[mid:, 0] + cave_magnitude * np.sin(np.linspace(0, np.pi, n))
    return result


def augment_forward_lean(rep: np.ndarray, lean_factor: float = 0.4) -> np.ndarray:
    """Simulate forward lean by amplifying forward accel (Z axis, index 2) in descent phase.

    Does not mutate input.
    """
    result = rep.copy()
    descent_end = len(rep) // 2
    result[:descent_end, 2] = result[:descent_end, 2] * (1.0 + lean_factor)
    return result


def generate_bad_form_dataset(
    n_good: int = 500,
    window_size: int = 200,
    seed: int = 42,
) -> List[Tuple[np.ndarray, str]]:
    """Generate balanced dataset of good and bad-form squat windows.

    For each good rep, creates 3 bad-form variants. Returns list of (window, label) tuples.
    Each window is shape (window_size, 6) — 6 IMU channels.
    Labels: 'good', 'insufficient_depth', 'knee_cave', 'forward_lean'.
    """
    rng = np.random.RandomState(seed)
    t = np.linspace(0, 2 * np.pi, window_size)
    dataset: List[Tuple[np.ndarray, str]] = []

    for _ in range(n_good):
        # Simulate a good rep as smooth sinusoidal IMU signal
        rep = np.column_stack([
            0.1 * rng.randn(window_size),                              # X: lateral (minimal)
            np.sin(t) + 0.05 * rng.randn(window_size),                # Y: vertical (main motion)
            0.3 * np.sin(t / 2) + 0.05 * rng.randn(window_size),     # Z: forward
            0.05 * rng.randn(window_size),                             # Gyr X
            0.05 * rng.randn(window_size),                             # Gyr Y
            0.05 * rng.randn(window_size),                             # Gyr Z
        ]).astype(np.float32)

        dataset.append((rep, "good"))
        dataset.append((augment_insufficient_depth(rep), "insufficient_depth"))
        dataset.append((augment_knee_cave(rep), "knee_cave"))
        dataset.append((augment_forward_lean(rep), "forward_lean"))

    return dataset
