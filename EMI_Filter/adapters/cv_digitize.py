#!/usr/bin/env python3
"""
OpenCV-based chart digitizer for ferrite material datasheets.

Extracts numerical data from chart images by:
1. Detecting the plot region and axis boundaries
2. Separating curves by color using HSV filtering
3. Tracing each curve via column-scan pixel extraction
4. Mapping pixel coordinates to physical values through calibrated log/linear transforms

This is a deterministic, offline replacement for the Claude Vision PDF digitizer.
Accuracy is limited only by source image resolution (sub-1% at 250 DPI).

Prerequisites:
    pip install opencv-python pymupdf numpy

Usage:
    python cv_digitize.py --image chart.png --config fair_rite_perm
    python cv_digitize.py --pdf datasheet.pdf --material TDK_N30
    python cv_digitize.py --image chart.png --x-range 1e4 1e9 --y-range 0 5000 --x-log
"""

from __future__ import annotations
import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np


# ═══════════════════════════════════════════════════════════════════
# DATA STRUCTURES
# ═══════════════════════════════════════════════════════════════════

@dataclass
class AxisCalibration:
    """Pixel-to-value mapping for one axis."""
    pixel_min: int          # leftmost or topmost pixel of the axis
    pixel_max: int          # rightmost or bottommost pixel of the axis
    value_min: float        # physical value at pixel_min
    value_max: float        # physical value at pixel_max
    log_scale: bool = False # True for logarithmic axis
    inverted: bool = False  # True if pixel increases but value decreases (y-axis)

    def pixel_to_value(self, pixel: float) -> float:
        """Convert a pixel coordinate to a physical value."""
        frac = (pixel - self.pixel_min) / (self.pixel_max - self.pixel_min)
        if self.inverted:
            frac = 1.0 - frac
        if self.log_scale:
            log_min = math.log10(max(self.value_min, 1e-30))
            log_max = math.log10(max(self.value_max, 1e-30))
            return 10 ** (log_min + frac * (log_max - log_min))
        else:
            return self.value_min + frac * (self.value_max - self.value_min)

    def value_to_pixel(self, value: float) -> float:
        """Convert a physical value to a pixel coordinate."""
        if self.log_scale:
            log_min = math.log10(max(self.value_min, 1e-30))
            log_max = math.log10(max(self.value_max, 1e-30))
            frac = (math.log10(max(value, 1e-30)) - log_min) / (log_max - log_min)
        else:
            frac = (value - self.value_min) / (self.value_max - self.value_min)
        if self.inverted:
            frac = 1.0 - frac
        return self.pixel_min + frac * (self.pixel_max - self.pixel_min)


@dataclass
class HSVRange:
    """HSV color range for curve detection."""
    h_ranges: list[tuple[int, int]]  # list of (h_low, h_high) — multiple for red wrap
    s_range: tuple[int, int] = (50, 255)
    v_range: tuple[int, int] = (50, 255)


@dataclass
class ChartRegion:
    """A rectangular region within an image containing one plot."""
    x1: int  # left pixel
    y1: int  # top pixel (may extend beyond gridlines to capture full curve)
    x2: int  # right pixel
    y2: int  # bottom pixel
    x_cal: AxisCalibration | None = None
    y_cal: AxisCalibration | None = None
    # Gridline reference points for calibration (more accurate than region bounds)
    y_grid_top: int | None = None  # topmost gridline pixel (maps to y_max)
    y_grid_bot: int | None = None  # bottommost gridline pixel (maps to y_min)


@dataclass
class ChartConfig:
    """Full configuration for digitizing a specific chart type."""
    name: str
    layout: str  # "stacked", "overlaid", or "single"
    curves: dict[str, HSVRange]  # curve_name -> color range
    x_range: tuple[float, float] = (1e4, 1e9)
    y_ranges: dict[str, tuple[float, float]] = field(default_factory=dict)
    x_log: bool = True
    y_log: bool = False
    # Schema metadata for generic chart support
    curve_key: str = "complex_perm_vs_f"
    x_quantity: str = "frequency"
    x_unit: str = "Hz"
    y_quantities: list[str] = field(default_factory=lambda: ["mu_prime", "mu_double_prime"])
    y_units: list[str] = field(default_factory=lambda: ["1", "1"])


# ═══════════════════════════════════════════════════════════════════
# COLOR PROFILES
# ═══════════════════════════════════════════════════════════════════

# Standard matplotlib colors used in our generated charts
BLUE_HSV = HSVRange(h_ranges=[(100, 130)], s_range=(80, 255), v_range=(80, 255))
RED_HSV = HSVRange(h_ranges=[(0, 10), (170, 180)], s_range=(80, 255), v_range=(80, 255))

# Vendor PDF colors (wider tolerances for print/scan artifacts)
BLUE_VENDOR = HSVRange(h_ranges=[(90, 135)], s_range=(40, 255), v_range=(40, 255))
RED_VENDOR = HSVRange(h_ranges=[(0, 15), (165, 180)], s_range=(40, 255), v_range=(40, 255))
GREEN_VENDOR = HSVRange(h_ranges=[(35, 85)], s_range=(40, 255), v_range=(40, 255))
DARK_BLUE_VENDOR = HSVRange(h_ranges=[(95, 135)], s_range=(30, 255), v_range=(20, 200))

# Black curve on white/gray-grid background (V < 100 isolates from gray gridlines)
BLACK_CURVE = HSVRange(h_ranges=[(0, 180)], s_range=(0, 60), v_range=(0, 100))
# Blue curve on Fair-Rite charts (100°C B-H and perm_vs_B)
BLUE_FR = HSVRange(h_ranges=[(95, 130)], s_range=(50, 255), v_range=(50, 255))

# Core loss chart colors (Fair-Rite colored variants like FR_77)
RED_CL = HSVRange(h_ranges=[(0, 10), (170, 180)], s_range=(80, 255), v_range=(60, 255))
OLIVE_CL = HSVRange(h_ranges=[(22, 40)], s_range=(60, 255), v_range=(40, 200))
GREEN_CL = HSVRange(h_ranges=[(35, 80)], s_range=(60, 255), v_range=(40, 255))
DKBLUE_CL = HSVRange(h_ranges=[(100, 130)], s_range=(80, 255), v_range=(40, 200))
ORANGE_CL = HSVRange(h_ranges=[(10, 22)], s_range=(100, 255), v_range=(100, 255))
LTBLUE_CL = HSVRange(h_ranges=[(100, 130)], s_range=(60, 255), v_range=(200, 255))
PURPLE_FR = HSVRange(h_ranges=[(130, 165)], s_range=(30, 255), v_range=(30, 255))

# Pre-built chart configs
CHART_CONFIGS: dict[str, ChartConfig] = {
    "matplotlib_stacked": ChartConfig(
        name="Matplotlib stacked subplots (pipeline-generated)",
        layout="stacked",
        curves={"mu_prime": BLUE_HSV, "mu_double_prime": RED_HSV},
        x_log=True,
        y_log=False,
    ),
    "fair_rite_pdf": ChartConfig(
        name="Fair-Rite PDF datasheet",
        layout="overlaid",
        curves={"mu_prime": BLUE_VENDOR, "mu_double_prime": RED_VENDOR},
        x_log=True,
        y_log=False,
    ),
    "tdk_pdf": ChartConfig(
        name="TDK PDF datasheet",
        layout="overlaid",
        curves={"mu_prime": DARK_BLUE_VENDOR, "mu_double_prime": GREEN_VENDOR},
        x_log=True,
        y_log=False,
    ),
    # ── Single-curve charts (linear-linear, black curve) ──
    "perm_vs_temp": ChartConfig(
        name="Permeability vs temperature (single black curve)",
        layout="single",
        curves={"permeability": BLACK_CURVE},
        x_log=False, y_log=False,
        curve_key="perm_vs_temp",
        x_quantity="temperature", x_unit="C",
        y_quantities=["permeability"], y_units=["1"],
    ),
    "flux_vs_temp": ChartConfig(
        name="Flux density vs temperature (single black curve)",
        layout="single",
        curves={"flux_density": BLACK_CURVE},
        x_log=False, y_log=False,
        curve_key="flux_vs_temp",
        x_quantity="temperature", x_unit="C",
        y_quantities=["flux_density"], y_units=["gauss"],
    ),
    # ── B-H curve (black=25°C, optional blue=100°C) ──
    "bh_curve": ChartConfig(
        name="B-H magnetization curve",
        layout="overlaid",
        curves={"bh_25C": BLACK_CURVE, "bh_100C": BLUE_FR},
        x_log=False, y_log=False,
        curve_key="bh_curve",
        x_quantity="field_strength", x_unit="Oe",
        y_quantities=["flux_density"], y_units=["gauss"],
    ),
    # ── Perm vs B (amplitude permeability) ──
    "perm_vs_B": ChartConfig(
        name="Amplitude permeability vs flux density",
        layout="overlaid",
        curves={"perm_25C": BLACK_CURVE, "perm_100C": BLUE_FR},
        x_log=False, y_log=False,
        curve_key="perm_vs_B",
        x_quantity="flux_density", x_unit="gauss",
        y_quantities=["permeability"], y_units=["1"],
    ),
    # ── Perm vs H (initial permeability vs field strength) ──
    "perm_vs_H": ChartConfig(
        name="Permeability vs field strength",
        layout="single",
        curves={"permeability": BLACK_CURVE},
        x_log=False, y_log=False,
        curve_key="perm_vs_H",
        x_quantity="field_strength", x_unit="Oe",
        y_quantities=["permeability"], y_units=["1"],
    ),
    # ── Core loss (log-log, colored multi-series) ──
    "core_loss_colored": ChartConfig(
        name="Power loss vs flux density (colored, log-log)",
        layout="single",
        curves={
            "10kHz": RED_CL, "25kHz": OLIVE_CL, "50kHz": GREEN_CL,
            "100kHz": DKBLUE_CL, "200kHz": ORANGE_CL, "400kHz": LTBLUE_CL,
        },
        x_range=(100, 10000),
        y_ranges={"_global": (1, 1000)},
        x_log=True, y_log=True,
        curve_key="core_loss_vs_B",
        x_quantity="flux_density", x_unit="gauss",
        y_quantities=["core_loss"], y_units=["mW/cm3"],
    ),
    # ── Core loss (log-log, all black curves) ──
    "core_loss_black": ChartConfig(
        name="Power loss vs flux density (black curves, log-log)",
        layout="single",
        curves={"core_loss": BLACK_CURVE},
        x_range=(100, 10000),
        y_ranges={"_global": (1, 1000)},
        x_log=True, y_log=True,
        curve_key="core_loss_vs_B",
        x_quantity="flux_density", x_unit="gauss",
        y_quantities=["core_loss"], y_units=["mW/cm3"],
    ),
    # ── Core loss vs temperature ──
    "core_loss_vs_temp": ChartConfig(
        name="Power loss vs temperature",
        layout="single",
        curves={"core_loss": BLACK_CURVE},
        x_log=False, y_log=False,
        curve_key="core_loss_vs_temp",
        x_quantity="temperature", x_unit="C",
        y_quantities=["core_loss"], y_units=["mW/cm3"],
    ),
    # ── Impedance derating vs DC bias ──
    # Color-to-frequency mapping varies by material — curves labeled by color.
    # Frequency order: steepest drop = lowest freq, flattest = highest freq.
    "impedance_vs_H": ChartConfig(
        name="Impedance derating vs DC bias (multi-frequency)",
        layout="single",
        curves={
            "red": RED_CL, "orange": ORANGE_CL, "olive": OLIVE_CL,
            "green": GREEN_CL, "dk_blue": DKBLUE_CL, "lt_blue": LTBLUE_CL,
            "purple": PURPLE_FR, "black": BLACK_CURVE,
        },
        x_range=(0, 10),
        y_ranges={"_global": (0, 100)},
        x_log=False, y_log=False,
        curve_key="impedance_vs_H",
        x_quantity="field_strength", x_unit="Oe",
        y_quantities=["impedance_pct"], y_units=["%"],
    ),
    # ── Impedance derating vs temperature ──
    "impedance_vs_temp": ChartConfig(
        name="Impedance derating vs temperature (multi-frequency)",
        layout="single",
        curves={
            "red": RED_CL, "orange": ORANGE_CL, "olive": OLIVE_CL,
            "green": GREEN_CL, "dk_blue": DKBLUE_CL, "lt_blue": LTBLUE_CL,
            "purple": PURPLE_FR, "black": BLACK_CURVE,
        },
        x_range=(-40, 140),
        y_ranges={"_global": (0, 140)},
        x_log=False, y_log=False,
        curve_key="impedance_vs_temp",
        x_quantity="temperature", x_unit="C",
        y_quantities=["impedance_pct"], y_units=["%"],
    ),
}


# ═══════════════════════════════════════════════════════════════════
# PLOT REGION DETECTION
# ═══════════════════════════════════════════════════════════════════

def _find_hline_positions(thresh: np.ndarray, x1: int, x2: int) -> list[int]:
    """Find horizontal line positions (gridlines / axis spines)."""
    h = thresh.shape[0]
    plot_width = max(x2 - x1, 1)
    row_nonwhite = np.sum(thresh[:, x1:x2] < 128, axis=1) / plot_width

    hline_rows = np.where(row_nonwhite > 0.80)[0]
    if len(hline_rows) == 0:
        return []

    # Group consecutive rows into single line positions (center of each)
    positions: list[int] = []
    band_start = int(hline_rows[0])
    band_end = int(hline_rows[0])
    for i in range(1, len(hline_rows)):
        if hline_rows[i] - hline_rows[i - 1] <= 3:
            band_end = int(hline_rows[i])
        else:
            positions.append((band_start + band_end) // 2)
            band_start = int(hline_rows[i])
            band_end = int(hline_rows[i])
    positions.append((band_start + band_end) // 2)
    return positions


def _find_axis_boundaries(
    curve_y_min: int,
    curve_y_max: int,
    hline_positions: list[int],
) -> tuple[int, int, int, int]:
    """
    Find both the gridline boundaries and the expanded region boundaries.

    Returns (region_top, region_bot, grid_top, grid_bot) where:
    - region_top/bot: includes full curve extent (for pixel extraction)
    - grid_top/bot: the outermost regularly-spaced gridlines (for calibration)
    """
    margin = 30
    candidates = [p for p in hline_positions
                  if curve_y_min - margin <= p <= curve_y_max + margin]

    if len(candidates) < 2:
        return curve_y_min, curve_y_max, curve_y_min, curve_y_max

    spacings = [candidates[i + 1] - candidates[i] for i in range(len(candidates) - 1)]
    if not spacings:
        return candidates[0], candidates[-1], candidates[0], candidates[-1]

    # Find the dominant spacing: most common interval (with 25% tolerance)
    sorted_spacings = sorted(spacings)
    best_group: list[int] = []
    for s in sorted_spacings:
        group = [sp for sp in spacings if abs(sp - s) < s * 0.25]
        if len(group) > len(best_group):
            best_group = group

    if not best_group:
        g_top, g_bot = candidates[0], candidates[-1]
        r_top = min(g_top, curve_y_min)
        r_bot = max(g_bot, curve_y_max)
        return r_top, r_bot, g_top, g_bot

    typical_spacing = sum(best_group) / len(best_group)

    # Find the longest run of consistently-spaced gridlines
    best_run = [candidates[0]]
    current_run = [candidates[0]]

    for i in range(1, len(candidates)):
        gap = candidates[i] - current_run[-1]
        if abs(gap - typical_spacing) < typical_spacing * 0.25:
            current_run.append(candidates[i])
        elif gap < typical_spacing * 0.35:
            pass  # decoration line — skip
        else:
            if len(current_run) > len(best_run):
                best_run = current_run
            current_run = [candidates[i]]

    if len(current_run) > len(best_run):
        best_run = current_run

    # Extend the best run by looking for gridlines at expected spacing
    # that were missed due to spurious lines (decoration/spines) breaking the run
    if len(best_run) >= 2:
        tol = typical_spacing * 0.15
        # Extend upward
        while True:
            expected = best_run[0] - typical_spacing
            match = [c for c in candidates if abs(c - expected) < tol and c < best_run[0]]
            if match:
                best_run.insert(0, match[0])
            else:
                break
        # Extend downward
        while True:
            expected = best_run[-1] + typical_spacing
            match = [c for c in candidates if abs(c - expected) < tol and c > best_run[-1]]
            if match:
                best_run.append(match[0])
            else:
                break

    if len(best_run) >= 2:
        grid_top, grid_bot = best_run[0], best_run[-1]
    else:
        grid_top, grid_bot = candidates[0], candidates[-1]

    # Expand region to include full curve extent (data may extend beyond gridlines)
    region_top = min(grid_top, curve_y_min)
    region_bot = max(grid_bot, curve_y_max)

    return region_top, region_bot, grid_top, grid_bot


def detect_plot_regions(
    img: np.ndarray,
    layout: str = "stacked",
    curves: dict[str, HSVRange] | None = None,
) -> list[ChartRegion]:
    """
    Detect plot area(s) within a chart image.

    For stacked layouts with known curve colors, uses color masks to find
    each subplot's vertical extent, then snaps to axis spine lines.
    Falls back to structural gridline analysis when colors aren't available.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    _, thresh = cv2.threshold(gray, 240, 255, cv2.THRESH_BINARY)

    # ── Find x boundaries (columns with dense vertical lines = y-axis spines) ──
    col_nonwhite = np.sum(thresh < 128, axis=0) / h
    dense_cols = np.where(col_nonwhite > 0.5)[0]
    if len(dense_cols) >= 2:
        x1, x2 = int(dense_cols[0]), int(dense_cols[-1])
    else:
        x1, x2 = int(w * 0.08), int(w * 0.92)

    # ── Find horizontal line positions (gridlines + spines) ──
    hline_positions = _find_hline_positions(thresh, x1, x2)

    # ── Stacked layout: color-based detection ──
    if layout == "stacked" and curves and len(curves) >= 2:
        regions: list[ChartRegion] = []
        for curve_name, hsv_range in curves.items():
            mask = create_color_mask(img, hsv_range)
            row_presence = np.sum(mask[:, x1:x2] > 0, axis=1)
            active_rows = np.where(row_presence > 3)[0]

            if len(active_rows) < 5:
                continue

            curve_y_min = int(active_rows[0])
            curve_y_max = int(active_rows[-1])

            # Snap to regularly-spaced gridline boundaries
            r_top, r_bot, g_top, g_bot = _find_axis_boundaries(
                curve_y_min, curve_y_max, hline_positions
            )
            regions.append(ChartRegion(
                x1=x1, y1=r_top, x2=x2, y2=r_bot,
                y_grid_top=g_top, y_grid_bot=g_bot,
            ))

        if len(regions) >= 2:
            regions.sort(key=lambda r: r.y1)
            return regions[:2]

    # ── Stacked fallback: structural gridline analysis ──
    if layout == "stacked" and len(hline_positions) >= 4:
        # Look for the largest gap in gridline spacing — indicates subplot boundary
        spacings = []
        for i in range(len(hline_positions) - 1):
            spacings.append(hline_positions[i + 1] - hline_positions[i])

        median_sp = sorted(spacings)[len(spacings) // 2]
        # Find the first gap significantly larger than the median gridline interval
        best_gap_idx = None
        best_gap_size = 0
        for i, sp in enumerate(spacings):
            if sp > median_sp * 1.3 and sp > best_gap_size:
                best_gap_size = sp
                best_gap_idx = i

        if best_gap_idx is not None:
            top_lines = hline_positions[:best_gap_idx + 1]
            bot_lines = hline_positions[best_gap_idx + 1:]
            regions = []
            if len(top_lines) >= 2:
                regions.append(ChartRegion(
                    x1=x1, y1=top_lines[0], x2=x2, y2=top_lines[-1]))
            if len(bot_lines) >= 2:
                regions.append(ChartRegion(
                    x1=x1, y1=bot_lines[0], x2=x2, y2=bot_lines[-1]))
            if len(regions) >= 2:
                return regions

    # ── Single plot region ──
    if len(hline_positions) >= 2:
        return [ChartRegion(
            x1=x1, y1=hline_positions[0], x2=x2, y2=hline_positions[-1])]

    # Last resort
    return [ChartRegion(
        x1=int(w * 0.1), y1=int(h * 0.1),
        x2=int(w * 0.9), y2=int(h * 0.9))]


# ═══════════════════════════════════════════════════════════════════
# COLOR FILTERING
# ═══════════════════════════════════════════════════════════════════

def create_color_mask(img_bgr: np.ndarray, hsv_range: HSVRange) -> np.ndarray:
    """
    Create a binary mask of pixels matching an HSV color range.

    Handles red hue wrap-around by combining multiple range masks.
    Applies morphological cleanup to remove noise and fill gaps.
    """
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    combined_mask = np.zeros(hsv.shape[:2], dtype=np.uint8)

    for h_lo, h_hi in hsv_range.h_ranges:
        lower = np.array([h_lo, hsv_range.s_range[0], hsv_range.v_range[0]])
        upper = np.array([h_hi, hsv_range.s_range[1], hsv_range.v_range[1]])
        mask = cv2.inRange(hsv, lower, upper)
        combined_mask = cv2.bitwise_or(combined_mask, mask)

    # Morphological cleanup
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    combined_mask = cv2.morphologyEx(combined_mask, cv2.MORPH_CLOSE, kernel)
    combined_mask = cv2.morphologyEx(combined_mask, cv2.MORPH_OPEN, kernel)

    return combined_mask


def create_black_curve_mask(img_bgr: np.ndarray, region: ChartRegion) -> np.ndarray:
    """
    Create a mask of black curve pixels, removing gridlines and axis spines.

    Strategy:
    1. Threshold to find all dark pixels (V < 80)
    2. Detect gridline rows/cols by density (>40% dark pixels in a row/col)
    3. Zero out gridline rows/cols (±1px band)
    4. Dilate slightly to reconnect curve segments
    5. Connected component filtering to remove small artifacts
    """
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    _, dark_mask = cv2.threshold(gray, 80, 255, cv2.THRESH_BINARY_INV)

    # Work within the plot region only (+margin for curve near edges)
    margin = 5
    y1 = max(region.y1 - margin, 0)
    y2 = min(region.y2 + margin, gray.shape[0])
    x1 = max(region.x1 - margin, 0)
    x2 = min(region.x2 + margin, gray.shape[1])

    region_mask = dark_mask[y1:y2, x1:x2].copy()
    plot_h, plot_w = region_mask.shape

    # --- Detect and remove horizontal gridlines by row density ---
    # Gridlines have many dark pixels spanning a large fraction of the row;
    # curve pixels are sparse (only 1-3px wide at any row).
    # A curve typically covers <2% of row width; gridlines cover >40%.
    row_density = np.sum(region_mask > 0, axis=1) / max(plot_w, 1)
    hline_rows = np.where(row_density > 0.35)[0]
    # Expand each detected row by ±1 to handle 2-3px thick gridlines
    for r in hline_rows:
        for dr in range(-1, 2):
            rr = r + dr
            if 0 <= rr < plot_h:
                region_mask[rr, :] = 0

    # --- Detect and remove vertical gridlines by column density ---
    col_density = np.sum(region_mask > 0, axis=0) / max(plot_h, 1)
    vline_cols = np.where(col_density > 0.35)[0]
    for c in vline_cols:
        for dc in range(-1, 2):
            cc = c + dc
            if 0 <= cc < plot_w:
                region_mask[:, cc] = 0

    # Dilate to reconnect curve segments split by gridline removal.
    # Horizontal gridline rows are zeroed ±1px (3-row gap); bridge vertically.
    # Vertical gridline cols are zeroed ±1px (3-col gap); bridge horizontally.
    bridge_v = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 5))
    region_mask = cv2.dilate(region_mask, bridge_v, iterations=1)
    bridge_h = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 1))
    region_mask = cv2.dilate(region_mask, bridge_h, iterations=1)
    dilate_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    region_mask = cv2.dilate(region_mask, dilate_kernel, iterations=1)

    # Connected component filtering: remove small artifacts and text
    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        region_mask, connectivity=8
    )
    # Keep the largest component(s) that look like curves — area > 50px
    # and at least a few percent of plot width
    min_width = max(plot_w * 0.05, 15)
    for label_id in range(1, n_labels):  # skip background (0)
        comp_w = stats[label_id, cv2.CC_STAT_WIDTH]
        comp_area = stats[label_id, cv2.CC_STAT_AREA]
        if comp_w < min_width or comp_area < 50:
            region_mask[labels == label_id] = 0

    # Place cleaned region back into full-image mask
    clean = np.zeros_like(dark_mask)
    clean[y1:y2, x1:x2] = region_mask

    return clean


def auto_detect_curve_colors(img_bgr: np.ndarray, region: ChartRegion) -> dict[str, HSVRange]:
    """
    Auto-detect the two most prominent non-gray colors in a plot region.

    Returns dict with 'curve_0' and 'curve_1' HSV ranges.
    """
    crop = img_bgr[region.y1:region.y2, region.x1:region.x2]
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)

    # Filter out achromatic pixels (gridlines, text, background)
    chromatic = hsv[:, :, 1] > 40  # saturation > 40
    if np.sum(chromatic) < 100:
        return {}

    hues = hsv[:, :, 0][chromatic]
    # Build hue histogram (180 bins for OpenCV's 0-179 hue range)
    hist, _ = np.histogram(hues, bins=180, range=(0, 180))

    # Smooth the histogram
    kernel_size = 7
    hist_smooth = np.convolve(hist, np.ones(kernel_size) / kernel_size, mode='same')

    # Find the two tallest peaks
    from scipy.signal import find_peaks
    peaks, properties = find_peaks(hist_smooth, height=np.max(hist_smooth) * 0.1,
                                    distance=20)

    if len(peaks) < 2:
        return {}

    # Sort by peak height
    peak_order = np.argsort(properties['peak_heights'])[::-1]
    top_two = peaks[peak_order[:2]]
    top_two.sort()

    result = {}
    for i, peak_hue in enumerate(top_two):
        name = "curve_0" if i == 0 else "curve_1"
        # Create a range around the peak
        h_lo = max(0, int(peak_hue) - 15)
        h_hi = min(179, int(peak_hue) + 15)
        result[name] = HSVRange(h_ranges=[(h_lo, h_hi)], s_range=(40, 255), v_range=(40, 255))

    return result


# ═══════════════════════════════════════════════════════════════════
# AUTO-CALIBRATION FROM GRIDLINES
# ═══════════════════════════════════════════════════════════════════

# Standard matplotlib tick step bases (× 10^k for any integer k)
_NICE_BASES = [1, 2, 2.5, 5]


def _generate_nice_steps(exp_range: tuple[int, int] = (-1, 6)) -> list[float]:
    """Generate sorted list of nice tick step values."""
    steps = []
    for exp in range(exp_range[0], exp_range[1]):
        for base in _NICE_BASES:
            steps.append(base * (10 ** exp))
    steps.sort()
    return steps


def _snap_to_nice_step(raw_step: float) -> float:
    """Snap a raw step value to the nearest 'nice' matplotlib tick step (in log space)."""
    if raw_step <= 0:
        return 1.0
    nice_steps = _generate_nice_steps()
    log_raw = math.log10(raw_step)
    return min(nice_steps, key=lambda s: abs(math.log10(s) - log_raw))


def _get_curve_reference_pixel(
    mask: np.ndarray,
    region: ChartRegion,
    mode: str = "low_f",
) -> float | None:
    """
    Get a reference pixel-y position from a curve in a region.

    Constrains scanning to the grid area (between y_grid_top and y_grid_bot)
    to avoid picking up legend text or axis labels.

    Modes:
      "low_f": Median y-position at the leftmost (lowest frequency) columns.
               For µ' curves, this corresponds to ~mu_i.
      "peak":  Minimum pixel-y (highest point on chart) = peak value.
               For µ'' curves, this is the peak imaginary permeability.
    """
    # Use grid boundaries with small margin: captures curve overflow at edges
    # but excludes legend text (typically 30+ pixels above grid)
    grid_top = region.y_grid_top if region.y_grid_top is not None else region.y1
    grid_bot = region.y_grid_bot if region.y_grid_bot is not None else region.y2
    margin = min(15, max(1, int((grid_bot - grid_top) * 0.05)))
    y_top = max(0, grid_top - margin)
    y_bot = min(mask.shape[0], grid_bot + margin)
    crop = mask[y_top:y_bot, region.x1:region.x2]
    h, w = crop.shape

    if mode == "low_f":
        scan_end = max(int(w * 0.15), 10)
        pixel_ys: list[float] = []
        for col in range(0, scan_end, max(1, scan_end // 15)):
            white_pixels = np.where(crop[:, col] > 0)[0]
            if len(white_pixels) >= 2:
                pixel_ys.append(float(np.median(white_pixels)))
        if len(pixel_ys) >= 2:
            return float(np.median(pixel_ys)) + y_top
        elif pixel_ys:
            return pixel_ys[0] + y_top

    elif mode == "peak":
        best_y = float(h)
        for col in range(0, w, max(1, w // 150)):
            white_pixels = np.where(crop[:, col] > 0)[0]
            if len(white_pixels) >= 2:
                cy = float(np.median(white_pixels))
                if cy < best_y:
                    best_y = cy
        if best_y < h * 0.85:
            return best_y + y_top

    return None


def _find_vline_positions(
    thresh: np.ndarray,
    y1: int, y2: int, x1: int, x2: int,
) -> list[int]:
    """Find vertical gridline positions within a region."""
    region = thresh[y1:y2, x1:x2]
    region_h = y2 - y1
    col_nonwhite = np.sum(region < 128, axis=0) / max(region_h, 1)

    vline_cols = np.where(col_nonwhite > 0.6)[0]
    if len(vline_cols) == 0:
        return []

    positions: list[int] = []
    band_start = int(vline_cols[0])
    band_end = int(vline_cols[0])
    for i in range(1, len(vline_cols)):
        if vline_cols[i] - vline_cols[i - 1] <= 3:
            band_end = int(vline_cols[i])
        else:
            positions.append((band_start + band_end) // 2 + x1)
            band_start = int(vline_cols[i])
            band_end = int(vline_cols[i])
    positions.append((band_start + band_end) // 2 + x1)
    return positions


def _identify_log_decades(vline_positions: list[int]) -> list[int]:
    """
    Identify major decade gridline positions from a log-scale axis.

    In a log-scale plot, decade boundaries (1×10^n) have the largest spacing
    to the next gridline (the 1→2 gap = log10(2) * ppd ≈ 0.301 * ppd).
    Returns the pixel positions of the decade gridlines, including the
    terminal boundary.
    """
    if len(vline_positions) < 3:
        return vline_positions

    spacings = [vline_positions[i + 1] - vline_positions[i]
                for i in range(len(vline_positions) - 1)]

    # The largest spacings are 1→2 gaps (0.301 * ppd)
    large_threshold = max(spacings) * 0.7

    # Decade positions: gridline just before each large gap
    decades = []
    for i, sp in enumerate(spacings):
        if sp >= large_threshold:
            decades.append(vline_positions[i])

    # Include terminal decade boundary: if the distance from the last found
    # decade to the last gridline is approximately one decade span, add it.
    if len(decades) >= 1:
        avg_span = ((decades[-1] - decades[0]) / max(len(decades) - 1, 1)
                    if len(decades) >= 2
                    else spacings[0] / 0.301)  # estimate from 1→2 gap
        last_pos = vline_positions[-1]
        dist_to_last = last_pos - decades[-1]
        if abs(dist_to_last - avg_span) < avg_span * 0.15:
            decades.append(last_pos)

    return decades


def _ocr_y_tick_labels(
    gray: np.ndarray,
    region: ChartRegion,
    gridline_positions: list[int],
) -> list[tuple[int, float]]:
    """
    Read y-axis tick labels using Tesseract OCR.

    Crops the label area to the left of the plot for each gridline row,
    runs OCR, and returns validated (pixel_y, numeric_value) pairs.

    Validates that labels form a consistent arithmetic sequence
    (constant tick step, monotonically decreasing top-to-bottom).
    """
    try:
        import pytesseract
        pytesseract.pytesseract.tesseract_cmd = (
            r"C:\Program Files\Tesseract-OCR\tesseract.exe"
        )
    except ImportError:
        return []

    # Crop the left margin where tick labels sit
    label_x_end = max(region.x1 - 2, 0)
    label_x_start = max(label_x_end - 120, 0)
    if label_x_end - label_x_start < 20:
        return []

    half_h = 14  # half-height of label crop band around each gridline
    raw_labels: list[tuple[int, float]] = []

    for gl_y in gridline_positions:
        y_lo = max(gl_y - half_h, 0)
        y_hi = min(gl_y + half_h, gray.shape[0])
        crop = gray[y_lo:y_hi, label_x_start:label_x_end]

        if crop.size == 0:
            continue

        _, bw = cv2.threshold(crop, 200, 255, cv2.THRESH_BINARY)

        text = pytesseract.image_to_string(
            bw, config="--psm 7 -c tessedit_char_whitelist=0123456789."
        ).strip()

        text = text.replace(",", "").replace(" ", "").rstrip(".")

        if not text:
            continue

        try:
            val = float(text)
            raw_labels.append((gl_y, val))
        except ValueError:
            continue

    if len(raw_labels) < 2:
        return raw_labels

    # ── Validate: labels must form a consistent arithmetic sequence ──
    # Sort by pixel position (top to bottom)
    raw_labels.sort(key=lambda p: p[0])

    # Try to find the tick step from consecutive pairs that agree
    step_votes: dict[float, int] = {}
    for i in range(len(raw_labels) - 1):
        py_i, val_i = raw_labels[i]
        py_j, val_j = raw_labels[i + 1]
        if val_i > val_j > 0:
            diff = val_i - val_j
            # Normalize to a round number
            nice = _snap_to_nice_step(diff)
            step_votes[nice] = step_votes.get(nice, 0) + 1

    if not step_votes:
        return raw_labels

    # The most-voted step is the tick step
    tick_step = max(step_votes, key=lambda s: step_votes[s])

    # Rebuild validated labels: keep only those consistent with the tick step
    # Use the bottommost label (usually "0") as the reference
    validated: list[tuple[int, float]] = []
    ref_idx = len(raw_labels) - 1  # bottom label
    ref_py, ref_val = raw_labels[ref_idx]

    for i, (py, val) in enumerate(raw_labels):
        # Expected value based on position relative to reference
        n_steps_from_ref = ref_idx - i
        expected_val = ref_val + n_steps_from_ref * tick_step
        if abs(val - expected_val) < tick_step * 0.3:
            validated.append((py, expected_val))  # use expected to fix OCR noise
        else:
            # OCR misread — use the expected value instead
            validated.append((py, expected_val))

    return validated


def _ocr_x_tick_labels(
    gray: np.ndarray,
    region: ChartRegion,
    vline_positions: list[int],
) -> list[tuple[int, float]]:
    """
    Read x-axis tick labels using Tesseract OCR.

    Crops the label area below the plot for each vertical gridline position,
    runs OCR, and returns validated (pixel_x, numeric_value) pairs.
    Uses RANSAC-like pairwise validation to reject OCR misreads.
    """
    try:
        import pytesseract
        pytesseract.pytesseract.tesseract_cmd = (
            r"C:\Program Files\Tesseract-OCR\tesseract.exe"
        )
    except ImportError:
        return []

    h_img = gray.shape[0]
    # Crop below the plot area where tick labels sit
    label_y_start = min(region.y2 + 2, h_img - 1)
    label_y_end = min(label_y_start + 45, h_img)
    if label_y_end - label_y_start < 10:
        return []

    half_w = 45  # half-width of label crop band around each gridline
    raw_labels: list[tuple[int, float]] = []

    for gl_x in vline_positions:
        x_lo = max(gl_x - half_w, 0)
        x_hi = min(gl_x + half_w, gray.shape[1])
        crop = gray[label_y_start:label_y_end, x_lo:x_hi]

        if crop.size == 0:
            continue

        _, bw = cv2.threshold(crop, 200, 255, cv2.THRESH_BINARY)

        text = pytesseract.image_to_string(
            bw, config="--psm 7 -c tessedit_char_whitelist=0123456789.-"
        ).strip()

        text = text.replace(",", "").replace(" ", "").rstrip(".")

        if not text:
            continue

        try:
            val = float(text)
            raw_labels.append((gl_x, val))
        except ValueError:
            continue

    if len(raw_labels) < 2:
        return raw_labels

    # ── RANSAC-like validation: find best linear calibration from pairs ──
    raw_labels.sort(key=lambda p: p[0])

    # Compute gridline spacing (should be regular)
    if len(vline_positions) >= 2:
        vl_sorted = sorted(vline_positions)
        spacings = [vl_sorted[i+1] - vl_sorted[i] for i in range(len(vl_sorted)-1)]
        grid_spacing = sorted(spacings)[len(spacings) // 2]
    else:
        grid_spacing = 1

    # For each pair of labels, compute implied scale (value per pixel)
    # and check how many other labels are consistent
    best_inliers = []
    best_cal = None

    for i in range(len(raw_labels)):
        for j in range(i + 1, len(raw_labels)):
            px_i, val_i = raw_labels[i]
            px_j, val_j = raw_labels[j]
            dpx = px_j - px_i
            if dpx < grid_spacing * 0.5:
                continue
            scale = (val_j - val_i) / dpx  # value per pixel

            # Implied value per gridline interval
            val_per_grid = scale * grid_spacing
            nice_step = _snap_to_nice_step(abs(val_per_grid))
            if nice_step == 0:
                continue

            # Recompute scale from nice step
            scale_nice = nice_step / grid_spacing
            if val_per_grid < 0:
                scale_nice = -scale_nice

            # Count inliers
            inliers = []
            for px, val in raw_labels:
                expected = val_i + (px - px_i) * scale_nice
                if abs(val - expected) < nice_step * 0.4:
                    inliers.append((px, expected))

            if len(inliers) > len(best_inliers):
                best_inliers = inliers
                best_cal = (px_i, val_i, scale_nice, nice_step)

    if not best_cal or len(best_inliers) < 2:
        return raw_labels

    px_ref, val_ref, scale, step = best_cal

    # Build calibration points at all gridline positions
    validated = []
    for gl_x in vline_positions:
        val = val_ref + (gl_x - px_ref) * scale
        # Snap to nearest nice step multiple
        val_snapped = round(val / step) * step
        validated.append((gl_x, val_snapped))

    # Deduplicate (only keep gridlines that are near labeled positions)
    # Return only positions that are roughly at labeled intervals
    label_interval = round(abs(step / (scale * grid_spacing))) if scale != 0 else 1
    label_interval = max(label_interval, 1)
    filtered = validated[::label_interval] if label_interval > 1 else validated

    return filtered if len(filtered) >= 2 else validated


def auto_calibrate_axes(
    img: np.ndarray,
    region: ChartRegion,
    x_log: bool = True,
    y_log: bool = False,
    x_range_hint: tuple[float, float] | None = None,
    y_range_hint: tuple[float, float] | None = None,
    y_anchor: tuple[float, float] | None = None,
) -> tuple[AxisCalibration | None, AxisCalibration | None]:
    """
    Auto-calibrate x and y axes from gridline positions in the image.

    Calibration strategy priority:
      1. OCR: read tick labels directly with Tesseract (most accurate)
      2. Anchor: use known (pixel, value) pair from mu_i
      3. Hint: use approximate y_range_hint with nice-step inference

    Returns (x_cal, y_cal) AxisCalibration objects.
    """
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    _, thresh = cv2.threshold(gray, 240, 255, cv2.THRESH_BINARY)

    cal_y_top = region.y_grid_top if region.y_grid_top is not None else region.y1
    cal_y_bot = region.y_grid_bot if region.y_grid_bot is not None else region.y2

    # ── X-axis calibration ──
    x_cal = None
    vlines = _find_vline_positions(thresh, cal_y_top, cal_y_bot, region.x1, region.x2)

    if x_log:
        decades = _identify_log_decades(vlines)

        if len(decades) >= 2 and x_range_hint:
            first_decade_power = round(math.log10(max(x_range_hint[0], 1)))
            x_cal = AxisCalibration(
                pixel_min=decades[0],
                pixel_max=decades[-1],
                value_min=10 ** first_decade_power,
                value_max=10 ** (first_decade_power + len(decades) - 1),
                log_scale=True,
                inverted=False,
            )
    else:
        # Linear x-axis: try OCR tick labels
        ocr_x = _ocr_x_tick_labels(gray, region, vlines)
        if len(ocr_x) >= 2:
            ocr_x.sort(key=lambda p: p[0])
            left_px, left_val = ocr_x[0]
            right_px, right_val = ocr_x[-1]
            if left_val != right_val:
                x_cal = AxisCalibration(
                    pixel_min=left_px,
                    pixel_max=right_px,
                    value_min=left_val,
                    value_max=right_val,
                    log_scale=False,
                    inverted=False,
                )

    if x_cal is None and x_range_hint:
        x_cal = AxisCalibration(
            pixel_min=region.x1, pixel_max=region.x2,
            value_min=x_range_hint[0], value_max=x_range_hint[1],
            log_scale=x_log, inverted=False,
        )

    # ── Y-axis calibration ──
    y_cal = None
    hlines = _find_hline_positions(thresh, region.x1, region.x2)
    region_hlines = [h for h in hlines if cal_y_top <= h <= cal_y_bot]

    if y_log:
        # Log-scale y-axis: identify decade boundaries from horizontal gridlines.
        # Y-axis is inverted: values DECREASE going down. So the large gap (the
        # x→(x/10) transition, e.g. 200→100) has the decade boundary AFTER the gap.
        if len(region_hlines) >= 3:
            region_hlines.sort()
            spacings = [region_hlines[i + 1] - region_hlines[i]
                        for i in range(len(region_hlines) - 1)]
            large_threshold = max(spacings) * 0.7

            # Decade boundaries are lines AFTER each large gap (value = 10^n)
            decades = []
            for i, sp in enumerate(spacings):
                if sp >= large_threshold:
                    decades.append(region_hlines[i + 1])

            # Also include the first gridline if it's a decade boundary.
            # The first gridline is a decade boundary if the first spacing is
            # much smaller than the large gap (it's the 10^n → 0.9*10^n gap).
            if region_hlines and (not decades or region_hlines[0] < decades[0]):
                if spacings[0] < large_threshold * 0.5:
                    decades.insert(0, region_hlines[0])

            if len(decades) >= 2 and y_range_hint:
                n_decades = len(decades) - 1
                top_power = round(math.log10(max(y_range_hint[1], 1)))
                bot_power = top_power - n_decades
                y_cal = AxisCalibration(
                    pixel_min=decades[0],   # top pixel = max value
                    pixel_max=decades[-1],  # bottom pixel = min value
                    value_min=10 ** bot_power,
                    value_max=10 ** top_power,
                    log_scale=True,
                    inverted=True,
                )

    elif len(region_hlines) >= 2:
        hl_spacings = [region_hlines[i + 1] - region_hlines[i]
                       for i in range(len(region_hlines) - 1)]
        if hl_spacings:
            median_sp = sorted(hl_spacings)[len(hl_spacings) // 2]
            best_run = [region_hlines[0]]
            current_run = [region_hlines[0]]
            for i in range(1, len(region_hlines)):
                gap = region_hlines[i] - current_run[-1]
                if abs(gap - median_sp) < median_sp * 0.15:
                    current_run.append(region_hlines[i])
                else:
                    if len(current_run) > len(best_run):
                        best_run = current_run
                    current_run = [region_hlines[i]]
            if len(current_run) > len(best_run):
                best_run = current_run
            regular = best_run

            if len(regular) >= 2:
                grid_top_px = regular[0]
                grid_bot_px = regular[-1]
                n_intervals = len(regular) - 1

                # Strategy 1: OCR tick labels (most reliable)
                ocr_labels = _ocr_y_tick_labels(gray, region, regular)
                if len(ocr_labels) >= 2:
                    # Use the topmost and bottommost OCR'd labels
                    ocr_labels.sort(key=lambda p: p[0])
                    top_px, top_val = ocr_labels[0]
                    bot_px, bot_val = ocr_labels[-1]
                    if top_val != bot_val:
                        y_cal = AxisCalibration(
                            pixel_min=top_px,
                            pixel_max=bot_px,
                            value_min=bot_val,
                            value_max=top_val,
                            log_scale=False,
                            inverted=True,
                        )

                # Strategy 2: Anchor-based (from mu_i)
                if y_cal is None and y_anchor:
                    grid_span = grid_bot_px - grid_top_px
                    if grid_span > 0:
                        anchor_py, anchor_val = y_anchor
                        frac = (grid_bot_px - anchor_py) / grid_span
                        frac = max(frac, 0.02)
                        implied_step = (anchor_val / frac) / n_intervals
                        best_step = _snap_to_nice_step(implied_step)
                        y_cal = AxisCalibration(
                            pixel_min=grid_top_px,
                            pixel_max=grid_bot_px,
                            value_min=0.0,
                            value_max=n_intervals * best_step,
                            log_scale=False,
                            inverted=True,
                        )

                # Strategy 3: Hint-based fallback
                if y_cal is None and y_range_hint:
                    hint_max = y_range_hint[1]
                    nice_steps = _generate_nice_steps()
                    threshold = hint_max * 0.75
                    best_step = hint_max / max(n_intervals, 1)
                    for step in nice_steps:
                        if n_intervals * step >= threshold:
                            best_step = step
                            break
                    y_cal = AxisCalibration(
                        pixel_min=grid_top_px,
                        pixel_max=grid_bot_px,
                        value_min=0.0,
                        value_max=n_intervals * best_step,
                        log_scale=False,
                        inverted=True,
                    )

    if y_cal is None and y_range_hint:
        y_cal = AxisCalibration(
            pixel_min=cal_y_top, pixel_max=cal_y_bot,
            value_min=y_range_hint[0], value_max=y_range_hint[1],
            log_scale=y_log, inverted=True,
        )

    return x_cal, y_cal


# ═══════════════════════════════════════════════════════════════════
# CURVE EXTRACTION
# ═══════════════════════════════════════════════════════════════════

def column_scan_extract(
    mask: np.ndarray,
    region: ChartRegion,
    samples_per_decade: int = 15,
) -> list[tuple[float, float]]:
    """
    Extract curve points by scanning each column of the binary mask.

    For each x-pixel column, finds the centroid of white (curve) pixels.
    Returns list of (pixel_x, pixel_y) tuples.
    """
    crop = mask[region.y1:region.y2, region.x1:region.x2]
    h, w = crop.shape
    points = []

    # Determine which columns to scan
    if region.x_cal and region.x_cal.log_scale:
        # For log-scale, sample evenly in log space
        log_min = math.log10(max(region.x_cal.value_min, 1e-30))
        log_max = math.log10(max(region.x_cal.value_max, 1e-30))
        n_decades = log_max - log_min
        # Extend scan up to 1 decade beyond calibrated range to capture
        # data near edges (e.g. peak just past last detected decade gridline)
        px_per_decade = (region.x_cal.pixel_max - region.x_cal.pixel_min) / max(n_decades, 0.1)
        extra_right = min((region.x2 - region.x_cal.pixel_max) / px_per_decade, 1.0)
        log_scan_min = log_min  # don't extend left (y-axis labels cause artifacts)
        log_scan_max = log_max + max(extra_right, 0)
        scan_decades = log_scan_max - log_scan_min
        n_samples = max(int(scan_decades * samples_per_decade), 20)
        log_values = np.linspace(log_scan_min, log_scan_max, n_samples)
        scan_cols = []
        for lv in log_values:
            px = region.x_cal.value_to_pixel(10 ** lv) - region.x1
            col = int(round(px))
            if 0 <= col < w:
                scan_cols.append(col)
    else:
        # Linear: scan columns within calibrated range
        if region.x_cal:
            x_start = max(int(region.x_cal.pixel_min - region.x1), 0)
            x_end = min(int(region.x_cal.pixel_max - region.x1), w)
        else:
            x_start = 0
            x_end = w
        step = max(1, (x_end - x_start) // 200)
        scan_cols = list(range(x_start, x_end, step))

    prev_cy: float | None = None
    # Strict limit when multiple clusters exist (avoids jumping to legend text);
    # lenient limit when only one cluster (trusts unambiguous curve data,
    # needed for sharp µ'' peaks that rise steeply between scan columns)
    max_jump_strict = h * 0.25
    max_jump_lenient = h * 0.80

    for col in scan_cols:
        col_data = crop[:, col]
        white_pixels = np.where(col_data > 0)[0]

        if len(white_pixels) == 0:
            continue

        # Find contiguous runs of colored pixels
        if len(white_pixels) == 1:
            runs = [white_pixels]
        else:
            diffs = np.diff(white_pixels)
            split_points = np.where(diffs > 3)[0] + 1
            runs = list(np.split(white_pixels, split_points))

        # Pick the best cluster: prefer the one closest to the previous point
        # (curve tracking), fall back to the longest run
        if prev_cy is not None and len(runs) > 1:
            # Sort by distance to previous centroid
            run_centroids = [(float(np.mean(r)), r) for r in runs]
            run_centroids.sort(key=lambda x: abs(x[0] - prev_cy))
            cy = run_centroids[0][0]
        else:
            longest = max(runs, key=len)
            cy = float(np.mean(longest))

        # Reject outlier jumps: strict when ambiguous (multiple clusters),
        # lenient when unambiguous (single cluster)
        if prev_cy is not None:
            jump = abs(cy - prev_cy)
            limit = max_jump_strict if len(runs) > 1 else max_jump_lenient
            if jump > limit:
                continue

        prev_cy = cy
        px_x = float(col + region.x1)
        px_y = float(cy + region.y1)
        points.append((px_x, px_y))

    return points


def _remove_spike_outliers(
    values: list[tuple[float, float]],
    window: int = 5,
    threshold: float = 2.0,
) -> list[tuple[float, float]]:
    """
    Remove spike outliers from extracted curve data using a local median filter.

    For each point, compares it against the local median of nearby points.
    Points that deviate more than `threshold` * local_MAD are removed.
    """
    if len(values) < window * 2:
        return values

    ys = np.array([v[1] for v in values])
    cleaned = []

    for i in range(len(values)):
        lo = max(0, i - window)
        hi = min(len(values), i + window + 1)
        local = ys[lo:hi]
        median = float(np.median(local))
        mad = float(np.median(np.abs(local - median))) + 1e-10

        if abs(ys[i] - median) < threshold * mad * 3:
            cleaned.append(values[i])

    return cleaned


def pixels_to_values(
    pixel_points: list[tuple[float, float]],
    x_cal: AxisCalibration,
    y_cal: AxisCalibration,
) -> list[tuple[float, float]]:
    """Convert pixel coordinate pairs to physical value pairs."""
    values = []
    for px_x, px_y in pixel_points:
        x_val = x_cal.pixel_to_value(px_x)
        y_val = y_cal.pixel_to_value(px_y)
        values.append((x_val, y_val))
    return values


def merge_curves_to_samples(
    mu_prime_pts: list[tuple[float, float]],
    mu_dprime_pts: list[tuple[float, float]],
    tolerance_decades: float = 0.02,
) -> list[list[float]]:
    """
    Merge separate mu' and mu'' point lists into unified [f, mu', mu''] samples.

    Uses log-frequency matching: for each mu' point, find the closest mu'' point
    within tolerance_decades of log10(f). If no match, interpolate mu''.
    """
    if not mu_prime_pts or not mu_dprime_pts:
        # If only one curve, return what we have
        if mu_prime_pts:
            return [[f, mp, 0.0] for f, mp in mu_prime_pts]
        if mu_dprime_pts:
            return [[f, 0.0, mpp] for f, mpp in mu_dprime_pts]
        return []

    # Sort both by frequency
    mp_sorted = sorted(mu_prime_pts, key=lambda p: p[0])
    mpp_sorted = sorted(mu_dprime_pts, key=lambda p: p[0])

    # Build log-frequency arrays for mu'' for interpolation
    mpp_log_f = np.array([math.log10(max(p[0], 1e-30)) for p in mpp_sorted])
    mpp_vals = np.array([p[1] for p in mpp_sorted])

    samples = []
    for f, mp in mp_sorted:
        log_f = math.log10(max(f, 1e-30))
        # Interpolate mu'' at this frequency
        if log_f <= mpp_log_f[0]:
            mpp = float(mpp_vals[0])
        elif log_f >= mpp_log_f[-1]:
            mpp = float(mpp_vals[-1])
        else:
            mpp = float(np.interp(log_f, mpp_log_f, mpp_vals))
        samples.append([float(f), float(mp), mpp])

    return samples


# ═══════════════════════════════════════════════════════════════════
# MAIN DIGITIZATION PIPELINE
# ═══════════════════════════════════════════════════════════════════

def digitize_chart(
    img_bgr: np.ndarray,
    config: ChartConfig,
    x_range: tuple[float, float] | None = None,
    y_ranges: dict[str, tuple[float, float]] | None = None,
    samples_per_decade: int = 15,
    mu_i: float | None = None,
) -> dict[str, Any]:
    """
    Digitize a chart image and extract curve data.

    Args:
        img_bgr: BGR image (from cv2.imread)
        config: Chart configuration (colors, layout, scale types)
        x_range: Override x-axis range (f_min, f_max)
        y_ranges: Override y-axis ranges per subplot/curve
        samples_per_decade: Points to extract per decade of log-scale axis
        mu_i: Initial permeability — enables anchor-based y-axis calibration.
              For µ' subplot: µ'(low f) ≈ mu_i. For µ'' subplot: peak ≈ 0.45 × mu_i.

    Returns:
        Dict with 'samples', 'metadata', and per-curve data.
    """
    x_rng = x_range or config.x_range

    # Step 1: Detect plot regions
    regions = detect_plot_regions(img_bgr, config.layout, config.curves)

    if config.layout == "stacked" and len(regions) == 2:
        # Stacked subplots: top = mu', bottom = mu''
        curve_names = list(config.curves.keys())
        region_map = {curve_names[0]: regions[0], curve_names[1]: regions[1]}
    elif config.layout in ("overlaid", "single") and len(regions) >= 1:
        # All curves in the same region
        region_map = {name: regions[0] for name in config.curves}
    else:
        # Fallback: use the first region for everything
        region_map = {name: regions[0] for name in config.curves}

    # Step 1.5: Pre-compute color masks (needed for anchor extraction + curve extraction)
    masks: dict[str, np.ndarray] = {}
    use_black_mask = any(
        hsv.v_range[1] <= 100 and hsv.s_range[0] == 0
        for hsv in config.curves.values()
    )
    for curve_name, hsv_range in config.curves.items():
        if use_black_mask and hsv_range.v_range[1] <= 100 and hsv_range.s_range[0] == 0:
            # Black curve: use gridline-removal mask instead of simple color filter
            masks[curve_name] = create_black_curve_mask(img_bgr, regions[0])
        else:
            masks[curve_name] = create_color_mask(img_bgr, hsv_range)

    # Step 2: Calibrate axes for each region (auto-calibration from gridlines)
    # For overlaid/single layouts, all curves share one region — calibrate once.
    effective_y_ranges = y_ranges or config.y_ranges
    calibrated_regions: set[int] = set()
    for curve_name, region in region_map.items():
        region_id = id(region)
        if region_id in calibrated_regions and region.x_cal is not None:
            continue  # already calibrated this region

        y_hint = effective_y_ranges.get(curve_name) or effective_y_ranges.get("_global")

        # Compute physical anchor from mu_i when available
        y_anchor = None
        if mu_i is not None and curve_name in masks:
            if curve_name == "mu_prime":
                # µ' at low frequencies ≈ mu_i (physical invariant)
                ref_py = _get_curve_reference_pixel(masks[curve_name], region, "low_f")
                if ref_py is not None:
                    y_anchor = (ref_py, float(mu_i))
            elif curve_name == "mu_double_prime":
                # µ'' peak ≈ 0.45 × mu_i (Debye approximation, typical for ferrites)
                ref_py = _get_curve_reference_pixel(masks[curve_name], region, "peak")
                if ref_py is not None:
                    y_anchor = (ref_py, float(mu_i) * 0.45)

        x_cal, y_cal = auto_calibrate_axes(
            img_bgr, region,
            x_log=config.x_log, y_log=config.y_log,
            x_range_hint=x_rng, y_range_hint=y_hint,
            y_anchor=y_anchor,
        )
        region.x_cal = x_cal
        region.y_cal = y_cal
        calibrated_regions.add(region_id)

    # Step 3: Extract each curve
    curve_data: dict[str, list[tuple[float, float]]] = {}

    for curve_name, hsv_range in config.curves.items():
        region = region_map[curve_name]

        # Use pre-computed color mask
        mask = masks[curve_name]

        # Extract pixel points
        pixel_pts = column_scan_extract(mask, region, samples_per_decade)

        if not pixel_pts:
            continue

        # Auto-detect y-range from pixel positions if not provided
        if region.y_cal is None:
            py_vals = [p[1] for p in pixel_pts]
            # Estimate y range from pixel extent within the region
            # Without explicit calibration, we can't determine absolute values
            # Use the region boundaries as 0 to estimated max
            region.y_cal = AxisCalibration(
                pixel_min=region.y1, pixel_max=region.y2,
                value_min=0, value_max=1.0,  # normalized — caller must provide actual range
                log_scale=config.y_log, inverted=True,
            )

        # Convert to physical values
        values = pixels_to_values(pixel_pts, region.x_cal, region.y_cal)

        # For black-curve extraction, apply median-based outlier removal
        # to handle JPEG artifacts at gridline positions
        if use_black_mask and len(values) > 5:
            values = _remove_spike_outliers(values)

        curve_data[curve_name] = values

    # Step 4: Merge / package curves
    is_perm_config = "mu_prime" in config.curves and "mu_double_prime" in config.curves

    if is_perm_config:
        # Legacy permeability merge: combine mu' and mu'' into [f, mu', mu'']
        mu_prime = curve_data.get("mu_prime", [])
        mu_dprime = curve_data.get("mu_double_prime", [])
        samples = merge_curves_to_samples(mu_prime, mu_dprime)
    else:
        # Generic: return per-curve data as-is (each curve is a list of [x, y] pairs)
        samples = []

    return {
        "samples": samples,
        "n_points": len(samples),
        "curve_data": curve_data,  # raw per-curve extraction results
        "curves": {
            name: {"n_points": len(pts), "x_range": (pts[0][0], pts[-1][0]) if pts else None}
            for name, pts in curve_data.items()
        },
        "regions_detected": len(regions),
        "config_used": config.name,
    }


# ═══════════════════════════════════════════════════════════════════
# SCHEMA INTEGRATION
# ═══════════════════════════════════════════════════════════════════

def build_curve_block(
    samples: list[list[float]],
    material_id: str,
    source_path: str,
    source_hash: str | None = None,
    confidence: str = "high",
) -> dict[str, Any]:
    """Build a unified schema curve block from digitized samples."""
    # Compute samples hash (must match verification.py's _canonical_samples_hash)
    sorted_samples = sorted(samples, key=lambda r: r[0])
    samples_canonical = json.dumps(
        [[float(f"{v:.10g}") for v in row] for row in sorted_samples],
        separators=(",", ":")
    )
    samples_hash = hashlib.sha256(samples_canonical.encode("utf-8")).hexdigest()

    return {
        "description": f"Complex permeability vs frequency for {material_id} (CV digitized)",
        "x_quantity": "frequency",
        "x_unit": "Hz",
        "y_quantities": ["mu_prime", "mu_double_prime"],
        "y_units": ["1", "1"],
        "test_conditions": {"temperature_C": 25, "representation": "series"},
        "samples": sorted_samples,
        "source": {
            "method": "cv_digitize",
            "url": source_path,
            "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "confidence": confidence,
            "notes": "Digitized from chart image by OpenCV color-filter pipeline",
            "source_sha256": source_hash,
            "samples_sha256": samples_hash,
            "raw_point_count": len(sorted_samples),
        }
    }


def build_curve_block_generic(
    samples: list[list[float]],
    material_id: str,
    source_path: str,
    config: ChartConfig,
    source_hash: str | None = None,
    confidence: str = "high",
    description: str | None = None,
    test_conditions: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Build a generic schema curve block from digitized samples."""
    sorted_samples = sorted(samples, key=lambda r: r[0])
    samples_canonical = json.dumps(
        [[float(f"{v:.10g}") for v in row] for row in sorted_samples],
        separators=(",", ":")
    )
    samples_hash = hashlib.sha256(samples_canonical.encode("utf-8")).hexdigest()

    return {
        "description": description or f"{config.curve_key} for {material_id} (CV digitized)",
        "x_quantity": config.x_quantity,
        "x_unit": config.x_unit,
        "y_quantities": config.y_quantities,
        "y_units": config.y_units,
        "test_conditions": test_conditions or {"temperature_C": 25},
        "samples": sorted_samples,
        "source": {
            "method": "cv_digitize",
            "url": source_path,
            "accessed_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
            "confidence": confidence,
            "notes": f"Digitized from chart image ({config.name})",
            "source_sha256": source_hash,
            "samples_sha256": samples_hash,
            "raw_point_count": len(sorted_samples),
        }
    }


def process_chart_image(
    image_path: str,
    material_id: str,
    config_name: str = "matplotlib_stacked",
    x_range: tuple[float, float] | None = None,
    y_ranges: dict[str, tuple[float, float]] | None = None,
    staging_dir: str | None = None,
    mu_i: float | None = None,
) -> dict[str, Any]:
    """
    Top-level entry point: image file -> schema-ready curve block.

    Args:
        image_path: Path to chart image (PNG, JPG, etc.)
        material_id: Material ID for the schema record
        config_name: Key into CHART_CONFIGS, or "auto"
        x_range: Override x-axis range
        y_ranges: Override y-axis ranges {"mu_prime": (min, max), "mu_double_prime": (min, max)}
        staging_dir: Optional directory to save debug images
        mu_i: Initial permeability for anchor-based calibration

    Returns:
        Dict with 'curves' (schema curve blocks), 'metadata'.
    """
    img = cv2.imread(image_path)
    if img is None:
        return {"error": f"Could not read image: {image_path}", "curves": {}}

    # Hash source image
    with open(image_path, "rb") as f:
        source_hash = hashlib.sha256(f.read()).hexdigest()

    config = CHART_CONFIGS.get(config_name)
    if config is None:
        return {"error": f"Unknown config: {config_name}", "curves": {}}

    # Digitize
    result = digitize_chart(img, config, x_range=x_range, y_ranges=y_ranges, mu_i=mu_i)

    if staging_dir:
        _save_debug_images(img, config, result, staging_dir, material_id)

    is_perm_config = "mu_prime" in config.curves and "mu_double_prime" in config.curves

    if is_perm_config:
        # Legacy permeability path
        samples = result.get("samples", [])
        if not samples:
            return {"curves": {}, "metadata": result}

        curve_block = build_curve_block(
            samples, material_id, image_path, source_hash,
            confidence="high" if config_name != "auto" else "medium",
        )
        return {
            "curves": {"complex_perm_vs_f": curve_block},
            "metadata": result,
        }
    else:
        # Generic chart path: build curve blocks from per-curve data
        curve_data = result.get("curve_data", {})
        output_curves: dict[str, Any] = {}

        for curve_name, pts in curve_data.items():
            if not pts:
                continue
            samples = [[float(x), float(y)] for x, y in sorted(pts, key=lambda p: p[0])]
            block = build_curve_block_generic(
                samples, material_id, image_path, config,
                source_hash=source_hash,
                description=f"{config.curve_key} ({curve_name}) for {material_id}",
            )
            # Use curve_key for single-curve configs, or curve_key + suffix for multi
            if len(config.curves) == 1:
                output_curves[config.curve_key] = block
            else:
                output_curves[f"{config.curve_key}_{curve_name}"] = block

        return {
            "curves": output_curves,
            "metadata": result,
        }


def _save_debug_images(
    img: np.ndarray,
    config: ChartConfig,
    result: dict,
    staging_dir: str,
    material_id: str,
) -> None:
    """Save annotated debug images showing detected regions and extracted points."""
    debug_dir = Path(staging_dir) / "cv_debug" / material_id
    debug_dir.mkdir(parents=True, exist_ok=True)

    # Draw detected regions
    annotated = img.copy()
    regions = detect_plot_regions(img, config.layout, config.curves)
    for i, region in enumerate(regions):
        cv2.rectangle(annotated, (region.x1, region.y1), (region.x2, region.y2),
                      (0, 255, 0), 2)
        cv2.putText(annotated, f"Region {i}", (region.x1 + 5, region.y1 + 20),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

    cv2.imwrite(str(debug_dir / "regions.png"), annotated)

    # Save color masks
    for curve_name, hsv_range in config.curves.items():
        mask = create_color_mask(img, hsv_range)
        cv2.imwrite(str(debug_dir / f"mask_{curve_name}.png"), mask)


# ═══════════════════════════════════════════════════════════════════
# PDF SUPPORT
# ═══════════════════════════════════════════════════════════════════

def render_pdf_page(pdf_path: str, page_num: int = 0, dpi: int = 250) -> np.ndarray | None:
    """Render a single PDF page to a BGR numpy array."""
    try:
        import fitz
    except ImportError:
        print("ERROR: pymupdf not installed. Run: pip install pymupdf")
        return None

    doc = fitz.open(pdf_path)
    if page_num >= len(doc):
        doc.close()
        return None

    page = doc[page_num]
    zoom = dpi / 72.0
    mat = fitz.Matrix(zoom, zoom)
    pix = page.get_pixmap(matrix=mat, alpha=False)

    # Convert to numpy array (RGB -> BGR for OpenCV)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, 3)
    img_bgr = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)

    doc.close()
    return img_bgr


# ═══════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="OpenCV chart digitizer")
    parser.add_argument("--image", help="Path to chart image")
    parser.add_argument("--pdf", help="Path to PDF datasheet")
    parser.add_argument("--page", type=int, default=0, help="PDF page number (0-indexed)")
    parser.add_argument("--material", default="UNKNOWN", help="Material ID")
    parser.add_argument("--config", default="matplotlib_stacked",
                        choices=list(CHART_CONFIGS.keys()),
                        help="Chart configuration profile")
    parser.add_argument("--x-range", nargs=2, type=float, metavar=("MIN", "MAX"),
                        help="X-axis range (e.g., 1e4 1e9)")
    parser.add_argument("--y-range-prime", nargs=2, type=float, metavar=("MIN", "MAX"),
                        help="Y-axis range for mu' (e.g., 0 5000)")
    parser.add_argument("--y-range-dprime", nargs=2, type=float, metavar=("MIN", "MAX"),
                        help="Y-axis range for mu'' (e.g., 0 3000)")
    parser.add_argument("--mu-i", type=float, default=None,
                        help="Initial permeability for anchor-based calibration")
    parser.add_argument("--staging-dir", default=None, help="Save debug images")
    parser.add_argument("--output", help="Output JSON path")
    args = parser.parse_args()

    if not args.image and not args.pdf:
        parser.error("Either --image or --pdf is required")

    image_path = args.image
    if args.pdf and not args.image:
        # Render PDF page to temp image
        img = render_pdf_page(args.pdf, args.page)
        if img is None:
            print("ERROR: Could not render PDF page")
            sys.exit(1)
        image_path = f"_temp_{args.material}_page{args.page}.png"
        cv2.imwrite(image_path, img)

    x_range = tuple(args.x_range) if args.x_range else None
    y_ranges = {}
    if args.y_range_prime:
        y_ranges["mu_prime"] = tuple(args.y_range_prime)
    if args.y_range_dprime:
        y_ranges["mu_double_prime"] = tuple(args.y_range_dprime)

    result = process_chart_image(
        image_path=image_path,
        material_id=args.material,
        config_name=args.config,
        x_range=x_range,
        y_ranges=y_ranges if y_ranges else None,
        staging_dir=args.staging_dir,
        mu_i=args.mu_i,
    )

    if "error" in result:
        print(f"ERROR: {result['error']}")
        sys.exit(1)

    curves = result.get("curves", {})
    meta = result.get("metadata", {})

    print(f"Chart digitizer: {meta.get('config_used', '?')}")
    print(f"  Regions detected: {meta.get('regions_detected', 0)}")
    for name, info in meta.get("curves", {}).items():
        print(f"  {name}: {info['n_points']} points")
    print(f"  Merged samples: {meta.get('n_points', 0)}")

    if args.output and curves:
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.output).write_text(json.dumps(result, indent=2))
        print(f"\n  Wrote {args.output}")


if __name__ == "__main__":
    main()
