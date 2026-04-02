"""
session_logger.py — Structured per-session logging as newline-delimited JSON.

Logs are written to {evidence_path}/session_logs/session_{TIMESTAMP}.jsonl.
Each line is a JSON object with ts, domain, event, and data fields.

Usage:
    from scripts.session_logger import SessionLogger

    logger = SessionLogger(evidence_path="./evidence/")
    logger.log_event("yelp.com", "submitted", {"confirmation_id": "ABC123"})
    logger.log_error("manta.com", error=e, phase=5)
    logger.close()
"""

import json
import traceback
from datetime import datetime
from pathlib import Path


class SessionLogger:
    def __init__(self, evidence_path: str):
        log_dir = Path(evidence_path) / "session_logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.log_path = log_dir / f"session_{self.session_id}.jsonl"
        self._file = open(self.log_path, "a", encoding="utf-8")
        self.log_event("__session__", "started", {"session_id": self.session_id})
        print(f"Session log: {self.log_path}")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    def log_event(self, domain: str, event: str, data: dict = None) -> None:
        """Log a structured event."""
        entry = {
            "ts": datetime.now().isoformat(),
            "domain": domain,
            "event": event,
            "data": data or {},
        }
        self._file.write(json.dumps(entry) + "\n")
        self._file.flush()

    def log_error(self, domain: str, error: Exception, phase: int = None) -> None:
        """Log an error with full traceback."""
        self.log_event(domain, "error", {
            "phase": phase,
            "error_type": type(error).__name__,
            "error_msg": str(error),
            "traceback": traceback.format_exc(),
        })

    def close(self) -> None:
        """Finalize the session log."""
        if self._file.closed:
            return
        self.log_event("__session__", "ended", {"session_id": self.session_id})
        self._file.close()
        print(f"Session log closed: {self.log_path}")

    def __del__(self):
        try:
            if hasattr(self, "_file") and not self._file.closed:
                self._file.close()
        except Exception:
            pass
