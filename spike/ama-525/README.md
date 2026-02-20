# AMA-525 Spike: Wearable Form Feedback

## Structure
- `data/` — raw datasets (gitignored, too large to commit)
- `models/` — trained Core ML / TFLite models
- `notebooks/` — Jupyter exploration
- `reports/` — spike findings docs
- `requirements.txt` — Python dependencies

## Setup
```bash
# Requires Python 3.10 or 3.11 (coremltools 7.x does not support 3.12+)
mkdir -p data models notebooks reports
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Datasets
- StrengthSense (2025): https://arxiv.org/abs/2511.02027
- RecGym (2025): https://archive.ics.uci.edu/dataset/1128
