# AMA-525 Spike: Wearable Form Feedback

## Structure
- `data/` — raw datasets (gitignored, too large to commit)
- `models/` — trained Core ML / TFLite models
- `notebooks/` — Jupyter exploration
- `reports/` — spike findings docs
- `requirements.txt` — Python dependencies

## Setup
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Datasets
- StrengthSense (2025): https://arxiv.org/abs/2511.02027
- RecGym (2025): https://archive.ics.uci.edu/dataset/1128
