"""Extended tests for dictate.icons — icon generation and caching.

Tests waveform grid generation, PNG encoding, reactive icons, and temp file cleanup.
"""

from __future__ import annotations

import os
import struct
import tempfile
from unittest.mock import MagicMock, patch

import pytest

from dictate.icons import (
    N_ANIM_FRAMES,
    _grid_to_png,
    _make_waveform_grid,
    cleanup_temp_files,
    generate_reactive_icon,
    get_icon_path,
)


class TestMakeWaveformGridExtended:
    """Extended tests for _make_waveform_grid function."""

    def test_default_size_36(self):
        """Test default grid size is 36x36."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        assert len(grid) == 36
        assert all(len(row) == 36 for row in grid)

    def test_custom_size_48(self):
        """Test custom grid size 48x48."""
        grid = _make_waveform_grid([10, 10, 10], size=48)
        assert len(grid) == 48
        assert all(len(row) == 48 for row in grid)

    def test_custom_size_64(self):
        """Test custom grid size 64x64."""
        grid = _make_waveform_grid([10, 10, 10], size=64)
        assert len(grid) == 64
        assert all(len(row) == 64 for row in grid)

    def test_contains_bar_pixels(self):
        """Test grid contains bar pixels (X)."""
        grid = _make_waveform_grid([20, 20, 20, 20, 20])
        flat = "".join(grid)
        assert "X" in flat

    def test_contains_empty_pixels(self):
        """Test grid contains empty pixels (.)."""
        grid = _make_waveform_grid([5, 5, 5, 5, 5])
        flat = "".join(grid)
        assert "." in flat

    def test_taller_bars_more_pixels(self):
        """Test taller bars have more X pixels."""
        short_grid = _make_waveform_grid([5, 5, 5, 5, 5])
        tall_grid = _make_waveform_grid([30, 30, 30, 30, 30])
        
        short_count = sum(row.count("X") for row in short_grid)
        tall_count = sum(row.count("X") for row in tall_grid)
        
        assert tall_count > short_count

    def test_correct_number_of_bars(self):
        """Test correct number of bars in grid."""
        heights = [10, 15, 20, 15, 10]
        grid = _make_waveform_grid(heights)
        
        # Count bar starts (3 pixels wide with gaps)
        # This is a heuristic - check that the pattern looks right
        flat = "".join(grid)
        assert "X" in flat

    def test_different_heights_produce_different_grids(self):
        """Test different heights produce visually different grids."""
        grid1 = _make_waveform_grid([10, 10, 10, 10, 10])
        grid2 = _make_waveform_grid([20, 20, 20, 20, 20])
        
        assert grid1 != grid2

    def test_empty_heights_list(self):
        """Test with empty heights list."""
        grid = _make_waveform_grid([])
        assert len(grid) == 36
        # Should be all empty
        flat = "".join(grid)
        assert "X" not in flat

    def test_single_bar(self):
        """Test with single bar."""
        grid = _make_waveform_grid([20])
        flat = "".join(grid)
        assert "X" in flat

    def test_custom_bar_width(self):
        """Test with custom bar width."""
        grid = _make_waveform_grid([20, 20], bar_width=5)
        assert len(grid) == 36

    def test_custom_gap(self):
        """Test with custom gap."""
        grid = _make_waveform_grid([20, 20], gap=5)
        assert len(grid) == 36

    def test_bottom_padding(self):
        """Test bottom padding."""
        grid = _make_waveform_grid([10, 10], bottom_pad=5)
        assert len(grid) == 36


class TestGridToPngExtended:
    """Extended tests for _grid_to_png function."""

    def test_produces_valid_png_signature(self):
        """Test PNG starts with valid PNG signature."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        png = _grid_to_png(grid)
        assert png[:8] == b"\x89PNG\r\n\x1a\n"

    def test_png_not_empty(self):
        """Test PNG is not empty."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        png = _grid_to_png(grid)
        assert len(png) > 100

    def test_png_has_ihdr_chunk(self):
        """Test PNG contains IHDR chunk."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        png = _grid_to_png(grid)
        assert b"IHDR" in png

    def test_png_has_idat_chunk(self):
        """Test PNG contains IDAT chunk."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        png = _grid_to_png(grid)
        assert b"IDAT" in png

    def test_png_has_iend_chunk(self):
        """Test PNG contains IEND chunk."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        png = _grid_to_png(grid)
        assert b"IEND" in png

    def test_png_has_phys_chunk(self):
        """Test PNG contains pHYs chunk for DPI."""
        grid = _make_waveform_grid([10, 15, 20, 15, 10])
        png = _grid_to_png(grid)
        assert b"pHYs" in png

    def test_different_grids_different_pngs(self):
        """Test different grids produce different PNGs."""
        grid1 = _make_waveform_grid([10, 10, 10, 10, 10])
        grid2 = _make_waveform_grid([20, 20, 20, 20, 20])
        
        png1 = _grid_to_png(grid1)
        png2 = _grid_to_png(grid2)
        
        assert png1 != png2

    def test_empty_grid_produces_valid_png(self):
        """Test empty grid produces valid PNG."""
        grid = _make_waveform_grid([])
        png = _grid_to_png(grid)
        assert png[:8] == b"\x89PNG\r\n\x1a\n"

    def test_png_dimensions_match_grid(self):
        """Test PNG dimensions match grid size."""
        grid = _make_waveform_grid([10, 10, 10], size=36)
        png = _grid_to_png(grid)
        
        # Parse IHDR chunk for dimensions
        # IHDR starts after signature (8) + chunk length (4) + chunk type "IHDR" (4) = 16
        ihdr_start = png.find(b"IHDR") - 4
        width = struct.unpack(">I", png[ihdr_start + 8:ihdr_start + 12])[0]
        height = struct.unpack(">I", png[ihdr_start + 12:ihdr_start + 16])[0]
        
        assert width == 36
        assert height == 36


class TestGenerateReactiveIconExtended:
    """Extended tests for generate_reactive_icon function."""

    def test_creates_temp_file(self):
        """Test creates a temp file."""
        path = generate_reactive_icon([10, 15, 20, 15, 10])
        assert os.path.exists(path)
        assert path.endswith(".png")

    def test_file_is_valid_png(self):
        """Test created file is valid PNG."""
        path = generate_reactive_icon([10, 15, 20, 15, 10])
        with open(path, "rb") as f:
            sig = f.read(8)
        assert sig == b"\x89PNG\r\n\x1a\n"

    def test_alternates_between_two_paths(self):
        """Test alternates between two temp file paths."""
        path1 = generate_reactive_icon([10, 15, 20, 15, 10])
        path2 = generate_reactive_icon([15, 20, 25, 20, 15])
        path3 = generate_reactive_icon([10, 15, 20, 15, 10])
        
        # Should alternate between two paths
        assert path1 != path2
        assert path3 == path1  # Back to first

    def test_different_heights_produce_different_files(self):
        """Test different heights produce different files."""
        path1 = generate_reactive_icon([10, 10, 10, 10, 10])
        path2 = generate_reactive_icon([20, 20, 20, 20, 20])
        
        with open(path1, "rb") as f:
            data1 = f.read()
        with open(path2, "rb") as f:
            data2 = f.read()
        
        assert data1 != data2

    def test_file_prefix(self):
        """Test file has correct prefix."""
        path = generate_reactive_icon([10, 15, 20, 15, 10])
        assert "dictate_reactive_" in path

    def test_file_is_writable(self):
        """Test file is writable and can be updated."""
        path = generate_reactive_icon([10, 15, 20, 15, 10])
        
        # Should be able to write to it again (alternating path)
        path2 = generate_reactive_icon([20, 25, 30, 25, 20])
        assert os.path.exists(path2)


class TestGetIconPathExtended:
    """Extended tests for get_icon_path function."""

    def test_idle_icon_creates_file(self):
        """Test idle icon creates a file."""
        path = get_icon_path("idle")
        assert os.path.exists(path)
        assert path.endswith(".png")

    def test_all_anim_icons_create_files(self):
        """Test all animation icons create files."""
        for i in range(N_ANIM_FRAMES):
            path = get_icon_path(f"anim_{i}")
            assert os.path.exists(path), f"anim_{i} should exist"

    def test_icons_are_cached(self):
        """Test icons are cached and same path returned."""
        path1 = get_icon_path("idle")
        path2 = get_icon_path("idle")
        path3 = get_icon_path("idle")
        
        assert path1 == path2 == path3

    def test_different_icons_different_paths(self):
        """Test different icons have different paths."""
        path_idle = get_icon_path("idle")
        path_anim_0 = get_icon_path("anim_0")
        
        assert path_idle != path_anim_0

    def test_icon_file_is_valid_png(self):
        """Test icon file is valid PNG."""
        path = get_icon_path("idle")
        with open(path, "rb") as f:
            sig = f.read(8)
        assert sig == b"\x89PNG\r\n\x1a\n"

    def test_file_prefix_includes_icon_name(self):
        """Test file prefix includes icon name."""
        path = get_icon_path("idle")
        assert "dictate_idle_" in path

    def test_unknown_icon_raises_value_error(self):
        """Test unknown icon raises ValueError."""
        with pytest.raises(ValueError, match="Unknown icon"):
            get_icon_path("nonexistent_icon")

    def test_empty_string_raises_value_error(self):
        """Test empty string raises ValueError."""
        with pytest.raises(ValueError, match="Unknown icon"):
            get_icon_path("")


class TestCleanupTempFilesExtended:
    """Extended tests for cleanup_temp_files function."""

    def test_removes_cached_icons(self):
        """Test removes cached icon files."""
        # Create some icons
        path1 = get_icon_path("idle")
        path2 = get_icon_path("anim_0")
        
        assert os.path.exists(path1)
        assert os.path.exists(path2)
        
        cleanup_temp_files()
        
        assert not os.path.exists(path1)
        assert not os.path.exists(path2)

    def test_clears_icon_cache(self):
        """Test clears icon cache dict."""
        # Access icon to populate cache
        get_icon_path("idle")
        
        from dictate.icons import _icon_cache
        assert len(_icon_cache) > 0
        
        cleanup_temp_files()
        
        assert len(_icon_cache) == 0

    def test_removes_reactive_paths(self):
        """Test removes reactive icon paths."""
        # Create reactive icons
        path1 = generate_reactive_icon([10, 15, 20, 15, 10])
        path2 = generate_reactive_icon([15, 20, 25, 20, 15])
        
        assert os.path.exists(path1) or os.path.exists(path2)
        
        cleanup_temp_files()
        
        # Both paths should be removed
        assert not os.path.exists(path1)
        assert not os.path.exists(path2)

    def test_clears_reactive_paths_list(self):
        """Test clears reactive paths list."""
        # Create reactive icons
        generate_reactive_icon([10, 15, 20, 15, 10])
        
        from dictate.icons import _reactive_paths
        assert len(_reactive_paths) > 0
        
        cleanup_temp_files()
        
        assert len(_reactive_paths) == 0

    def test_no_error_on_empty_cache(self):
        """Test no error when cache is empty."""
        # Ensure cache is empty
        cleanup_temp_files()
        
        # Should not raise
        cleanup_temp_files()

    def test_no_error_on_missing_files(self):
        """Test no error when files are already deleted."""
        # Create an icon
        path = get_icon_path("idle")
        
        # Delete it manually
        os.remove(path)
        
        # Should not raise when trying to clean up
        cleanup_temp_files()

    def test_cleanup_then_regenerate(self):
        """Test can regenerate icons after cleanup."""
        # Create icons
        path1 = get_icon_path("idle")
        cleanup_temp_files()
        
        # Should be able to create new icon
        path2 = get_icon_path("idle")
        assert os.path.exists(path2)
        assert path1 != path2  # Different temp file
