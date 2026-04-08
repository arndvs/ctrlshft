"""
session_logger.py — Structured per-session logging as newline-delimited JSON.

Logs are written to {evidence_path}/session_logs/session_{TIMESTAMP}.jsonl.
Each line is a JSON object with ts, feature, event, and data fields.

Usage:
    from scripts.session_logger import SessionLogger

    logger = SessionLogger(evidence_path="./evidence/")
    logger.log_event("/dashboard", "screenshotted", {"viewport": "desktop"})
    logger.log_error("/checkout", error=e, phase=5)
    logger.close()
"""

import json
import traceback
from datetime import datetime, timezone
from pathlib import Path


class SessionLogger:
    def __init__(self, evidence_path: str, session_id: str = ""):
        log_dir = Path(evidence_path) / "session_logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        self.session_id = session_id or datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        self.log_path = log_dir / f"session_{self.session_id}.jsonl"
        self._file = open(self.log_path, "a", encoding="utf-8")
        self.log_event("started", feature="__session__", data={"session_id": self.session_id})
        print(f"Session log: {self.log_path}")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    def log_event(self, event: str, feature: str = "", data: dict = None) -> None:
        """Log a structured event."""
        entry = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "event": event,
            "feature": feature,
            "data": data or {},
        }
        self._file.write(json.dumps(entry) + "\n")
        self._file.flush()

    def log_error(self, feature: str, error: Exception, phase: int = None) -> None:
        """Log an error with full traceback."""
        self.log_event(feature, "error", {
            "phase": phase,
            "error_type": type(error).__name__,
            "error_msg": str(error),
            "traceback": traceback.format_exc(),
        })

    def close(self) -> None:
        """Finalize the session log."""
        if self._file.closed:
            return
        self.log_event("ended", feature="__session__", data={"session_id": self.session_id})
        self._file.close()
        print(f"Session log closed: {self.log_path}")

    def __del__(self):
        try:
            if hasattr(self, "_file") and not self._file.closed:
                self._file.close()
        except Exception:
            pass
