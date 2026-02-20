import os
import numpy as np
import torch
from typing import Dict, Any
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

from synthetic import generate_bad_form_dataset
from train import FormClassifierCNN, train_model, evaluate_model, CLASSES


def export_to_coreml(
    output_path: str = "models/FormClassifier.mlmodel",
    n_synthetic: int = 500,
    window_size: int = 200,
    epochs: int = 30,
) -> Dict[str, Any]:
    """Train on synthetic data and export to Core ML.

    Returns a result dict with keys:
    - size_kb: float — file size in KB
    - val_accuracy: float — validation accuracy before export
    - output_path: str
    - skipped: bool (True if coremltools native unavailable)
    - reason: str (if skipped)
    """
    # Build dataset
    le = LabelEncoder().fit(CLASSES)
    dataset = generate_bad_form_dataset(n_good=n_synthetic, window_size=window_size)
    X = np.stack([item[0].T for item in dataset]).astype(np.float32)  # (N, 6, time)
    y = le.transform([item[1] for item in dataset])

    # Train
    _, X_val, _, y_val = train_test_split(X, y, test_size=0.2, stratify=y, random_state=42)
    model = train_model(X, y, epochs=epochs)
    metrics = evaluate_model(model, X_val, y_val)
    val_accuracy = metrics["accuracy"]

    # Export
    try:
        import coremltools as ct

        # Test that native conversion is available
        example_input = torch.zeros(1, 6, window_size)
        traced = torch.jit.trace(model, example_input)

        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="imu_window", shape=(1, 6, window_size))],
            outputs=[ct.TensorType(name="class_logits")],
            minimum_deployment_target=ct.target.watchOS10,
            compute_precision=ct.precision.FLOAT16,
        )
        mlmodel.short_description = "AMA-525 Form Classifier — squat form deviation detection"

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        mlmodel.save(output_path)

        size_kb = os.path.getsize(output_path) / 1024
        print(f"Saved {output_path} ({size_kb:.1f}KB) — val accuracy: {val_accuracy:.3f}")
        return {
            "output_path": output_path,
            "size_kb": size_kb,
            "val_accuracy": val_accuracy,
            "skipped": False,
        }

    except Exception as e:
        reason = f"coremltools conversion unavailable: {e}"
        print(f"WARNING: {reason}")
        print(f"Val accuracy before export: {val_accuracy:.3f}")
        return {
            "skipped": True,
            "reason": reason,
            "val_accuracy": val_accuracy,
        }


if __name__ == "__main__":
    result = export_to_coreml(output_path="models/FormClassifier.mlmodel")
    if result.get("skipped"):
        print(f"SKIPPED: {result['reason']}")
    else:
        print(f"SUCCESS: {result['size_kb']:.1f}KB, accuracy: {result['val_accuracy']:.3f}")
