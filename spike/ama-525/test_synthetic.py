import numpy as np
import pytest
from synthetic import augment_insufficient_depth, augment_knee_cave, augment_forward_lean, generate_bad_form_dataset

def test_depth_augmentation_changes_vertical_channel():
    good_rep = np.random.randn(100, 6).astype(np.float32)
    bad_rep = augment_insufficient_depth(good_rep, depth_factor=0.6)
    assert bad_rep.shape == good_rep.shape
    assert not np.allclose(bad_rep[:, 1], good_rep[:, 1])

def test_depth_augmentation_preserves_other_channels():
    good_rep = np.random.randn(100, 6).astype(np.float32)
    bad_rep = augment_insufficient_depth(good_rep, depth_factor=0.6)
    # Other channels (not Y=index 1) should be unchanged
    np.testing.assert_array_equal(bad_rep[:, 0], good_rep[:, 0])
    np.testing.assert_array_equal(bad_rep[:, 2:], good_rep[:, 2:])

def test_knee_cave_changes_lateral_channel():
    good_rep = np.random.randn(100, 6).astype(np.float32)
    bad_rep = augment_knee_cave(good_rep, cave_magnitude=0.3)
    assert bad_rep.shape == good_rep.shape
    assert not np.allclose(bad_rep[:, 0], good_rep[:, 0])

def test_forward_lean_changes_forward_channel():
    good_rep = np.random.randn(100, 6).astype(np.float32)
    bad_rep = augment_forward_lean(good_rep, lean_factor=0.4)
    assert bad_rep.shape == good_rep.shape
    assert not np.allclose(bad_rep[:, 2], good_rep[:, 2])

def test_augmentation_does_not_modify_input():
    """Augmentations must not mutate the input array."""
    good_rep = np.random.randn(100, 6).astype(np.float32)
    original = good_rep.copy()
    augment_insufficient_depth(good_rep)
    augment_knee_cave(good_rep)
    augment_forward_lean(good_rep)
    np.testing.assert_array_equal(good_rep, original)

def test_generate_bad_form_dataset_has_balanced_labels():
    dataset = generate_bad_form_dataset(n_good=20, window_size=100, seed=42)
    labels = [item[1] for item in dataset]
    from collections import Counter
    counts = Counter(labels)
    assert "good" in counts
    assert "insufficient_depth" in counts
    assert "knee_cave" in counts
    assert "forward_lean" in counts
    # Each class should have exactly n_good samples
    assert counts["good"] == 20
    assert counts["insufficient_depth"] == 20
    assert counts["knee_cave"] == 20
    assert counts["forward_lean"] == 20

def test_generate_bad_form_dataset_window_shape():
    dataset = generate_bad_form_dataset(n_good=5, window_size=100, seed=0)
    for sample, label in dataset:
        assert sample.shape == (100, 6), f"Expected (100, 6) got {sample.shape}"

def test_generate_bad_form_dataset_is_deterministic():
    ds1 = generate_bad_form_dataset(n_good=5, window_size=100, seed=42)
    ds2 = generate_bad_form_dataset(n_good=5, window_size=100, seed=42)
    for (s1, l1), (s2, l2) in zip(ds1, ds2):
        np.testing.assert_array_equal(s1, s2)
        assert l1 == l2
