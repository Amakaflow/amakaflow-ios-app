import numpy as np
import torch
import pytest
from train import FormClassifierCNN, train_model, evaluate_model, CLASSES

def test_model_output_shape():
    """Model should output (batch, n_classes) logits."""
    model = FormClassifierCNN(n_channels=6, n_classes=4)
    x = torch.randn(8, 6, 200)
    out = model(x)
    assert out.shape == (8, 4)

def test_model_size_under_200kb():
    """Trained model must be deployable on Apple Watch — <200KB."""
    model = FormClassifierCNN(n_channels=6, n_classes=4)
    n_params = sum(p.numel() for p in model.parameters())
    # 200KB / 4 bytes per float32 = 51200 params max
    assert n_params < 51200, f"Too many params: {n_params}"

def test_model_accepts_variable_batch_sizes():
    model = FormClassifierCNN(n_channels=6, n_classes=4)
    for batch_size in [1, 4, 16]:
        x = torch.randn(batch_size, 6, 200)
        out = model(x)
        assert out.shape == (batch_size, 4)

def test_evaluate_returns_accuracy_dict():
    model = FormClassifierCNN(n_channels=6, n_classes=4)
    X = np.random.randn(20, 6, 200).astype(np.float32)
    y = np.random.randint(0, 4, 20)
    metrics = evaluate_model(model, X, y)
    assert "accuracy" in metrics
    assert 0.0 <= metrics["accuracy"] <= 1.0

def test_train_model_improves_over_random_baseline():
    """After training, accuracy should beat random chance (>25%) on training data."""
    # Small dataset for fast test
    n = 200
    X = np.random.randn(n, 6, 200).astype(np.float32)
    y = np.repeat(np.arange(4), n // 4)  # balanced labels

    model = train_model(X, y, epochs=5, lr=1e-3)
    metrics = evaluate_model(model, X, y)
    # After even 5 epochs on training data, should beat random (0.25)
    assert metrics["accuracy"] > 0.25, f"Accuracy too low: {metrics['accuracy']}"

def test_classes_constant_has_4_entries():
    assert len(CLASSES) == 4
    assert "good" in CLASSES
    assert "insufficient_depth" in CLASSES

def test_model_is_in_eval_mode_after_train():
    X = np.random.randn(40, 6, 200).astype(np.float32)
    y = np.repeat(np.arange(4), 10)
    model = train_model(X, y, epochs=2)
    assert not model.training  # train_model should leave model in eval mode
