import os
import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler

WRIST_CHANNELS = ["LF_acc_x", "LF_acc_y", "LF_acc_z",
                   "LF_gyr_x", "LF_gyr_y", "LF_gyr_z"]

def load_strengthsense_wrist(data_dir: str):
    """Load and normalise wrist-placement channels from StrengthSense dataset.

    Expects CSV files named {activity}_{participant}.csv with columns including
    LF_acc_x/y/z and LF_gyr_x/y/z (left forearm — closest to watch placement).
    Skips files missing these columns.

    Returns (samples, labels) where samples is (N, 6) float32 normalised to [-1, 1].
    """
    frames, labels = [], []
    for fname in os.listdir(data_dir):
        if not fname.endswith(".csv"):
            continue
        df = pd.read_csv(os.path.join(data_dir, fname))
        available = [c for c in WRIST_CHANNELS if c in df.columns]
        if len(available) < 6:
            continue
        frames.append(df[available].values.astype(np.float32))
        activity = fname.split("_")[0]
        labels.extend([activity] * len(df))

    if not frames:
        return np.zeros((0, 6), dtype=np.float32), []

    samples = np.vstack(frames)
    scaler = MinMaxScaler(feature_range=(-1, 1))
    samples = scaler.fit_transform(samples).astype(np.float32)
    return samples, labels


def load_recgym_squat(data_dir: str):
    """Load squat-only samples from RecGym dataset.

    Filters files containing 'squat' or 'Squat' in filename.
    Takes first 6 numeric columns as the IMU channels.

    Returns (samples, labels) where labels are all 'squat'.
    """
    frames, labels = [], []
    for root, _, files in os.walk(data_dir):
        for fname in files:
            if "squat" not in fname.lower():
                continue
            if not fname.endswith(".csv"):
                continue
            df = pd.read_csv(os.path.join(root, fname))
            numeric_cols = df.select_dtypes(include=[np.number]).columns[:6]
            if len(numeric_cols) < 6:
                continue
            frames.append(df[numeric_cols].values.astype(np.float32))
            labels.extend(["squat"] * len(df))

    if not frames:
        return np.zeros((0, 6), dtype=np.float32), []

    samples = np.vstack(frames)
    scaler = MinMaxScaler(feature_range=(-1, 1))
    samples = scaler.fit_transform(samples).astype(np.float32)
    return samples, labels
