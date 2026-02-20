import pytest
import numpy as np
import pandas as pd
from pathlib import Path
from data_prep import load_strengthsense_wrist, load_recgym_squat

# StrengthSense has columns like LF_acc_x, LF_acc_y, LF_acc_z, LF_gyr_x, LF_gyr_y, LF_gyr_z
# RecGym has numeric columns; squat files contain "Squat" or "squat" in filename

def make_strengthsense_csv(tmp_path: Path, filename: str, n_rows: int = 50) -> Path:
    """Create a tiny synthetic StrengthSense-format CSV."""
    df = pd.DataFrame({
        "LF_acc_x": np.random.randn(n_rows).astype(np.float32),
        "LF_acc_y": np.random.randn(n_rows).astype(np.float32),
        "LF_acc_z": np.random.randn(n_rows).astype(np.float32),
        "LF_gyr_x": np.random.randn(n_rows).astype(np.float32),
        "LF_gyr_y": np.random.randn(n_rows).astype(np.float32),
        "LF_gyr_z": np.random.randn(n_rows).astype(np.float32),
        "extra_col": np.ones(n_rows),  # extra column should be ignored
    })
    path = tmp_path / filename
    df.to_csv(path, index=False)
    return path

def make_recgym_csv(tmp_path: Path, filename: str, n_rows: int = 50) -> Path:
    """Create a tiny synthetic RecGym-format CSV with 6 numeric columns."""
    df = pd.DataFrame(np.random.randn(n_rows, 8).astype(np.float32),
                      columns=[f"col{i}" for i in range(8)])
    path = tmp_path / filename
    df.to_csv(path, index=False)
    return path

def test_load_strengthsense_wrist_returns_correct_shape(tmp_path):
    make_strengthsense_csv(tmp_path, "squat_p01.csv", n_rows=50)
    samples, labels = load_strengthsense_wrist(str(tmp_path))
    assert samples.ndim == 2
    assert samples.shape[1] == 6
    assert len(labels) == len(samples)
    assert len(samples) == 50

def test_load_strengthsense_normalises_to_minus1_1(tmp_path):
    make_strengthsense_csv(tmp_path, "squat_p01.csv", n_rows=50)
    samples, _ = load_strengthsense_wrist(str(tmp_path))
    assert samples.min() >= -1.0 - 1e-5
    assert samples.max() <= 1.0 + 1e-5

def test_load_strengthsense_labels_from_filename(tmp_path):
    make_strengthsense_csv(tmp_path, "squat_p01.csv", n_rows=10)
    make_strengthsense_csv(tmp_path, "deadlift_p01.csv", n_rows=10)
    _, labels = load_strengthsense_wrist(str(tmp_path))
    assert "squat" in labels
    assert "deadlift" in labels

def test_load_strengthsense_skips_csvs_missing_wrist_columns(tmp_path):
    # CSV without LF_ columns — should be skipped
    df = pd.DataFrame({"other_col": np.ones(10)})
    (tmp_path / "bench_p01.csv").write_text(df.to_csv(index=False))
    make_strengthsense_csv(tmp_path, "squat_p01.csv", n_rows=10)
    samples, labels = load_strengthsense_wrist(str(tmp_path))
    assert len(samples) == 10  # only squat loaded

def test_load_recgym_squat_returns_squat_only(tmp_path):
    make_recgym_csv(tmp_path, "Squat_session1.csv", n_rows=30)
    make_recgym_csv(tmp_path, "BenchPress_session1.csv", n_rows=30)
    samples, labels = load_recgym_squat(str(tmp_path))
    assert len(samples) == 30
    assert all(l == "squat" for l in labels)

def test_load_recgym_normalises(tmp_path):
    make_recgym_csv(tmp_path, "Squat_session1.csv", n_rows=30)
    samples, _ = load_recgym_squat(str(tmp_path))
    assert samples.min() >= -1.0 - 1e-5
    assert samples.max() <= 1.0 + 1e-5
