"""
state_store.py — JSON-backed persistent state for portfolio showcaser.

Atomic-write JSON file that tracks project metadata, discovered features,
code highlights, and run history. Crash-safe via tmpfile + rename.

Usage:
    from scripts.state_store import JsonStateStore

    store = JsonStateStore("./state.json")
    store.set_project_meta({"name": "my-app", "framework": "next"})
    store.add_feature({"id": "dashboard", "name": "Dashboard", "route": "/dashboard", ...})
    store.update_feature("dashboard", {"status": "documented", "portfolio_score": 18})
    pending = store.get_pending_features(focus="core")
"""

import json
import os
import tempfile
from datetime import datetime
from pathlib import Path

STATUS_CODES = {
    "discovered", "scored", "in_progress",
    "screenshotted", "documented", "skipped",
}

SKIP_ON_STARTUP = {"documented", "skipped"}

_EMPTY_STATE = {
    "project": {},
    "runs": [],
    "features": {},
    "code_highlights": [],
}


class JsonStateStore:
    def __init__(self, state_path: str):
        self.state_path = Path(state_path)
        if self.state_path.exists():
            with open(self.state_path, encoding="utf-8") as f:
                self._data = json.load(f)
        else:
            self._data = json.loads(json.dumps(_EMPTY_STATE))

    @property
    def data(self) -> dict:
        return self._data

    def save(self) -> None:
        """Atomic write: write to .tmp then rename."""
        fd, tmp_path = tempfile.mkstemp(
            dir=self.state_path.parent,
            suffix=".tmp",
        )
        try:
            os.write(fd, json.dumps(self._data, indent=2, default=str).encode("utf-8"))
            os.close(fd)
            fd = -1
            Path(tmp_path).replace(self.state_path)
        except Exception:
            if fd >= 0:
                os.close(fd)
            Path(tmp_path).unlink(missing_ok=True)
            raise

    def get_project_meta(self) -> dict:
        return self._data.get("project", {})

    def set_project_meta(self, meta: dict) -> None:
        self._data["project"] = meta
        self.save()

    def get_all_features(self) -> list[dict]:
        """Return all features as a list of dicts."""
        return list(self._data.get("features", {}).values())

    def get_feature(self, feature_id: str) -> dict | None:
        return self._data.get("features", {}).get(feature_id)

    def add_feature(self, name: str, data: dict) -> None:
        """Add a new feature keyed by name."""
        if name in self._data.get("features", {}):
            return
        self._data.setdefault("features", {})[name] = {"name": name, **data}
        self.save()

    def update_feature(self, feature_id: str, updates: dict) -> None:
        """Partial update of a feature's fields."""
        feat = self._data.get("features", {}).get(feature_id)
        if not feat:
            raise KeyError(f"Feature not found: {feature_id}")
        feat.update(updates)
        self.save()

    def set_status(self, feature_id: str, status: str, notes: str = None) -> None:
        """Validated status change."""
        if status not in STATUS_CODES:
            raise ValueError(f"Invalid status '{status}'. Valid: {sorted(STATUS_CODES)}")
        updates = {"status": status}
        if notes is not None:
            updates["notes"] = notes[:500]
        self.update_feature(feature_id, updates)

    def get_pending_features(self, focus: str = "core") -> list[dict]:
        """
        Return features that need processing, filtered by focus mode and
        sorted by portfolio_score descending.
        """
        all_features = self.get_all_features()
        pending = [f for f in all_features if f.get("status") not in SKIP_ON_STARTUP]

        if focus == "responsive":
            pending = [f for f in pending if f.get("status") in ("screenshotted", "scored", "discovered")]
        elif focus == "edge-cases":
            pending = [f for f in pending if f.get("exploration_priority") in ("must", "should")]
        elif focus == "freestyle":
            pass

        def score_key(f: dict) -> int:
            try:
                return int(f.get("portfolio_score") or 0)
            except (ValueError, TypeError):
                return 0

        pending.sort(key=score_key, reverse=True)
        return pending

    def record_run(self, run_id: str, data: dict) -> None:
        self._data.setdefault("runs", []).append({
            "id": run_id,
            **data,
            "date": datetime.now().isoformat(),
        })
        self.save()

    def add_code_highlight(self, highlight: dict) -> None:
        """Add an architecture/pattern highlight from static analysis."""
        self._data.setdefault("code_highlights", []).append(highlight)
        self.save()

    def get_code_highlights(self) -> list[dict]:
        return self._data.get("code_highlights", [])

    def add_screenshot_to_feature(self, feature_id: str, screenshot: dict) -> None:
        """Append a screenshot record to a feature's screenshots list."""
        feat = self._data.get("features", {}).get(feature_id)
        if not feat:
            raise KeyError(f"Feature not found: {feature_id}")
        feat.setdefault("screenshots", []).append(screenshot)
        self.save()

    def write_summary(self) -> dict:
        """Generate and return summary statistics."""
        features = self.get_all_features()
        status_counts: dict[str, int] = {}
        for f in features:
            s = f.get("status", "discovered")
            status_counts[s] = status_counts.get(s, 0) + 1

        total = len(features)
        documented = status_counts.get("documented", 0)
        screenshot_count = sum(
            len(f.get("screenshots", [])) for f in features
        )

        summary = {
            "total_features": total,
            "documented": documented,
            "screenshotted": status_counts.get("screenshotted", 0),
            "pending": total - documented - status_counts.get("skipped", 0),
            "total_screenshots": screenshot_count,
            "total_runs": len(self._data.get("runs", [])),
            "code_highlights": len(self._data.get("code_highlights", [])),
            "last_updated": datetime.now().isoformat(),
        }

        self._data["summary"] = summary
        self.save()
        return summary
