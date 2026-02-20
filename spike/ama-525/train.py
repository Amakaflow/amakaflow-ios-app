import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from sklearn.model_selection import train_test_split
from typing import Dict

CLASSES = ["good", "insufficient_depth", "knee_cave", "forward_lean"]


class FormClassifierCNN(nn.Module):
    """Lightweight 1D-CNN for squat form classification.

    Input: (batch, 6, window_size) — 6 IMU channels over time window
    Output: (batch, n_classes) — class logits
    Target: <200KB when exported (FLOAT16 quantised to Core ML)
    """
    def __init__(self, n_channels: int = 6, n_classes: int = 4):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv1d(n_channels, 16, kernel_size=7, padding=3),
            nn.ReLU(),
            nn.MaxPool1d(4),
            nn.Conv1d(16, 32, kernel_size=5, padding=2),
            nn.ReLU(),
            nn.MaxPool1d(4),
            nn.Conv1d(32, 16, kernel_size=3, padding=1),
            nn.ReLU(),
            nn.AdaptiveAvgPool1d(1),
        )
        self.classifier = nn.Linear(16, n_classes)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        features = self.conv(x).squeeze(-1)
        return self.classifier(features)


def train_model(
    X: np.ndarray,
    y: np.ndarray,
    epochs: int = 30,
    lr: float = 1e-3,
) -> "FormClassifierCNN":
    """Train the CNN on windowed IMU data.

    Args:
        X: (n_samples, n_channels, window_size) float32
        y: (n_samples,) int class indices
        epochs: training epochs
        lr: learning rate

    Returns:
        Trained model in eval() mode.
    """
    X_train, X_val, y_train, y_val = train_test_split(
        X, y, test_size=0.2, stratify=y, random_state=42
    )

    train_ds = TensorDataset(torch.FloatTensor(X_train), torch.LongTensor(y_train))
    val_ds = TensorDataset(torch.FloatTensor(X_val), torch.LongTensor(y_val))
    train_dl = DataLoader(train_ds, batch_size=32, shuffle=True)
    val_dl = DataLoader(val_ds, batch_size=32)

    model = FormClassifierCNN()
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.CrossEntropyLoss()

    for epoch in range(epochs):
        model.train()
        for xb, yb in train_dl:
            opt.zero_grad()
            loss_fn(model(xb), yb).backward()
            opt.step()

        if (epoch + 1) % 10 == 0:
            metrics = evaluate_model(model, X_val, y_val)
            print(f"Epoch {epoch+1}/{epochs} — val acc: {metrics['accuracy']:.3f}")

    model.eval()
    return model


def evaluate_model(
    model: "FormClassifierCNN",
    X: np.ndarray,
    y: np.ndarray,
) -> Dict[str, float]:
    """Evaluate model accuracy on a dataset."""
    model.eval()
    with torch.no_grad():
        logits = model(torch.FloatTensor(X))
        preds = logits.argmax(dim=1).numpy()
    accuracy = float((preds == y).mean())
    return {"accuracy": accuracy}
