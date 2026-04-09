"""
screenshot_manager.py — Evidence capture and organization for portfolio showcaser.

Saves timestamped screenshots per feature in a structured archive under
{evidence_root}/{feature_id}/NN_stepname_WxH_HHMMSS.png with optional
.txt sidecar annotation files.

Usage:
    from scripts.screenshot_manager import ScreenshotManager

    sm = ScreenshotManager("./evidence/")
    path = sm.screenshot_path("dashboard", "feature_detail", viewport="1440x900")
    sm.annotate("./evidence/dashboard/04_feature_detail_143022.png", "Real-time analytics with live WebSocket feeds")
    paths = sm.get_evidence_paths("dashboard")
"""

import re
from datetime import datetime
from pathlib import Path


class ScreenshotManager:
    STEP_ORDER = [
        "overview",
        "hero_section",
        "navigation",
        "feature_detail",
        "form_interaction",
        "form_validation",
        "modal_or_drawer",
        "loading_state",
        "empty_state",
        "error_state",
        "responsive_mobile",
        "responsive_tablet",
        "responsive_desktop",
        "animation",
        "hover_effect",
        "dark_mode",
        "search",
        "data_table",
        "chart_or_visualization",
        "auth_flow",
        "checkout_flow",
        "misc",
    ]

    def __init__(self, evidence_root: str, session_id: str = ""):
        root = Path(evidence_root)
        self.evidence_root = root / session_id if session_id else root
        self.evidence_root.mkdir(parents=True, exist_ok=True)

    def feature_dir(self, feature_id: str) -> Path:
        """Get (or create) the evidence directory for a feature."""
        safe = re.sub(r"[^\w\-.]", "_", feature_id)
        d = self.evidence_root / safe
        d.mkdir(parents=True, exist_ok=True)
        return d

    def screenshot_path(self, feature_id: str, step: str, viewport: str = "") -> str:
        """
        Return the full path for a screenshot file.
        Files are named: NN_stepname[_WxH]_HHMMSS.png where NN is the step order number.
        Unknown steps get prefix 99.
        """
        step_num = (self.STEP_ORDER.index(step) + 1) if step in self.STEP_ORDER else 99
        timestamp = datetime.now().strftime("%H%M%S")
        viewport_part = f"_{viewport}" if viewport else ""
        filename = f"{step_num:02d}_{step}{viewport_part}_{timestamp}.png"
        return str(self.feature_dir(feature_id) / filename)

    def capture(self, browser, feature_id: str, step: str, viewport: str = "") -> tuple[str, bool]:
        """
        Capture a screenshot via the browser object and save to the evidence archive.
        Returns (path, success). Path is always set (useful for logging even on failure).
        """
        path = self.screenshot_path(feature_id, step, viewport)
        try:
            screenshot_bytes = browser.screenshot()
            Path(path).write_bytes(screenshot_bytes)
            print(f"  📷 {step}: {path}")
            return path, True
        except Exception as e:
            print(f"  ⚠  Screenshot failed ({step}): {e}")
            return path, False

    def annotate(self, screenshot_path: str, annotation: str) -> str:
        """
        Write a .txt sidecar annotation file next to a screenshot.
        Returns the annotation file path.
        """
        txt_path = Path(screenshot_path).with_suffix(".txt")
        txt_path.write_text(annotation, encoding="utf-8")
        return str(txt_path)

    def get_evidence_paths(self, feature_id: str) -> list[str]:
        """List all screenshots for a feature, sorted by filename."""
        return sorted(str(p) for p in self.feature_dir(feature_id).glob("*.png"))

    def get_annotations(self, feature_id: str) -> dict[str, str]:
        """Return {screenshot_path: annotation_text} for all annotated screenshots."""
        result = {}
        for txt in self.feature_dir(feature_id).glob("*.txt"):
            png_path = str(txt.with_suffix(".png"))
            result[png_path] = txt.read_text(encoding="utf-8")
        return result
