"""
run_showcase.py — Main orchestrator for portfolio showcaser.

8-phase pipeline: preflight → analyze → discover → score → install →
start server → explore → report. Supports resume, focus modes, and
single-feature targeting via CLI flags.

Usage (by agent):
    python -m scripts.run_showcase --config config.json
    python -m scripts.run_showcase --config config.json --focus interactions
    python -m scripts.run_showcase --config config.json --feature "Home Page"
    python -m scripts.run_showcase --config config.json --skip-server --dry-run

Agent: Read each phase method's docstring for what browser actions are needed.
Only phases 6 (explore) and the freestyle sub-step require browser interaction.
All other phases are fully automated.
"""

from __future__ import annotations

import argparse
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

from scripts.shared_utils import load_config, CircuitBreaker
from scripts.session_logger import SessionLogger
from scripts.screenshot_manager import ScreenshotManager
from scripts.state_store import JsonStateStore
from scripts.code_analyzer import analyze_repo
from scripts.feature_discovery import discover_features
from scripts.highlight_scorer import score_features, enrich_with_siblings
from scripts.app_runner import AppRunner
from scripts.exploration_engine import ExplorationEngine
from scripts.report_generator import generate_report
from scripts.preflight import run_preflight, print_preflight_results


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    config = load_config(args.config)

    if args.focus:
        config["_focus"] = args.focus
    if args.feature:
        config["_target_feature"] = args.feature
    config["_dry_run"] = args.dry_run
    config["_skip_server"] = args.skip_server

    session_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_dir = Path(config.get("output_dir", "./output"))
    log_dir.mkdir(parents=True, exist_ok=True)

    logger = SessionLogger(str(log_dir), session_id)
    logger.log_event("session_start", feature="orchestrator", data={"config": args.config, "focus": args.focus})

    try:
        return _run_pipeline(config, logger, session_id)
    except KeyboardInterrupt:
        logger.log_event("session_interrupted", feature="orchestrator")
        print("\n⚠️  Interrupted by user.")
        return 130
    except Exception as e:
        logger.log_error("orchestrator", e)
        print(f"\n❌ Fatal error: {e}")
        traceback.print_exc()
        return 1
    finally:
        logger.log_event("session_end", feature="orchestrator")
        logger.close()


def _run_pipeline(config: dict, logger: SessionLogger, session_id: str) -> int:
    """
    Agent: This is the 8-phase pipeline. You will be called to act during
    phase 6 (explore). All other phases run automatically.
    """

    # ── Phase 1: Preflight ───────────────────────────────────────────
    print("━" * 60)
    print("Phase 1/8: Preflight checks")
    print("━" * 60)

    ok, checks = run_preflight(config)
    print_preflight_results(checks)

    if not ok:
        print("\n❌ Preflight failed. Fix the errors above and retry.")
        return 1

    print("✅ Preflight passed.\n")
    logger.log_event("preflight_passed", feature="orchestrator")

    # ── Phase 2: Analyze codebase ────────────────────────────────────
    print("━" * 60)
    print("Phase 2/8: Analyzing codebase")
    print("━" * 60)

    analysis = analyze_repo(config["repo_path"])
    print(f"  Framework: {analysis['framework']}")
    print(f"  Language:  {analysis['language']}")
    print(f"  Pkg Mgr:   {analysis['package_manager']}")
    print(f"  Styling:   {analysis['styling']}")
    print(f"  Port:      {analysis['dev_port']}")
    print(f"  Integrations: {len(analysis['integrations'])}")
    print(f"  Patterns:  {len(analysis['patterns'])}")
    print(f"  Files:     {analysis['file_stats']['total_files']}")
    logger.log_event("analysis_complete", feature="orchestrator", data={"framework": analysis["framework"]})

    # ── Phase 3: Discover features ───────────────────────────────────
    print(f"\n{'━' * 60}")
    print("Phase 3/8: Discovering features")
    print("━" * 60)

    features = discover_features(config["repo_path"], analysis)
    features = enrich_with_siblings(features, config["repo_path"])
    print(f"  Discovered {len(features)} features")

    for f in features[:10]:
        print(f"    • {f['name']} ({f['type']})")
    if len(features) > 10:
        print(f"    ... and {len(features) - 10} more")

    logger.log_event("discovery_complete", feature="orchestrator", data={"count": len(features)})

    # ── Phase 4: Score and rank ──────────────────────────────────────
    print(f"\n{'━' * 60}")
    print("Phase 4/8: Scoring features")
    print("━" * 60)

    max_features = config.get("exploration", {}).get("max_features", 15)
    scored = score_features(features, analysis, max_features=max_features)
    print(f"  Top {len(scored)} features by portfolio score:")

    for i, f in enumerate(scored, 1):
        print(f"    {i:2d}. {f['name']:30s} score={f['portfolio_score']:.1f}  ({f['type']})")

    logger.log_event("scoring_complete", feature="orchestrator", data={"top_count": len(scored)})

    # ── Phase 5: Initialize state & output ───────────────────────────
    print(f"\n{'━' * 60}")
    print("Phase 5/8: Setting up state and output")
    print("━" * 60)

    output_dir = Path(config.get("output_dir", "./output"))
    state_path = config.get("state_file", str(output_dir / "state.json"))
    screenshots_dir = Path(config.get("screenshots_dir", str(output_dir / "screenshots")))

    state = JsonStateStore(state_path)
    state.set_project_meta({
        "repo_path": config["repo_path"],
        "framework": analysis["framework"],
        "language": analysis["language"],
        "session_id": session_id,
    })

    for f in scored:
        existing = state.get_feature(f["name"])
        if not existing:
            state.add_feature(f["name"], {
                "type": f.get("type"),
                "route": f.get("route"),
                "score": f.get("portfolio_score"),
                "description": f.get("description"),
            })

    screenshot_mgr = ScreenshotManager(str(screenshots_dir), session_id)

    print(f"  State: {state_path}")
    print(f"  Screenshots: {screenshots_dir}")
    logger.log_event("state_initialized", feature="orchestrator")

    if config.get("_dry_run"):
        print("\n🏁 Dry run complete. No server started, no exploration performed.")
        _generate_report(config, analysis, scored, state, screenshot_mgr, logger)
        return 0

    # ── Phase 6: Install deps & start server ─────────────────────────
    runner = None
    if not config.get("_skip_server"):
        print(f"\n{'━' * 60}")
        print("Phase 6/8: Starting dev server")
        print("━" * 60)

        runner = AppRunner(config, analysis)

        print(f"  Installing dependencies ({analysis['package_manager']})...")
        try:
            runner.install_deps()
            print("  ✅ Dependencies installed")
        except RuntimeError as e:
            print(f"  ⚠️  Install failed: {e}")
            logger.log_error("orchestrator", e)

        print(f"  Starting server: {analysis['start_command']}")
        try:
            url = runner.start()
            print(f"  ✅ Server ready at {url}")
            logger.log_event("server_started", feature="orchestrator", data={"url": url})
        except RuntimeError as e:
            print(f"  ❌ Server failed to start: {e}")
            logger.log_error("orchestrator", e)
            print("  Continuing without server. Use --skip-server to skip this phase.")
            runner = None
    else:
        print(f"\n{'━' * 60}")
        print("Phase 6/8: Skipping server (--skip-server)")
        print("━" * 60)

    # ── Phase 7: Explore features ────────────────────────────────────
    print(f"\n{'━' * 60}")
    print("Phase 7/8: Exploring features")
    print("━" * 60)

    engine = ExplorationEngine(config, state, screenshot_mgr, logger)
    focus = config.get("_focus", "core")
    target_feature = config.get("_target_feature")
    breaker = CircuitBreaker(
        threshold=config.get("session", {}).get("circuit_breaker_threshold", 5)
    )

    explore_list = scored
    if target_feature:
        explore_list = [f for f in scored if f["name"].lower() == target_feature.lower()]
        if not explore_list:
            print(f"  ⚠️  Feature '{target_feature}' not found. Available:")
            for f in scored:
                print(f"    • {f['name']}")
            return 1

    print(f"  Focus: {focus}")
    print(f"  Features to explore: {len(explore_list)}")

    explored = 0
    for feature in explore_list:
        if breaker.tripped:
            print(f"  🔴 Circuit breaker tripped after {breaker.threshold} consecutive failures")
            logger.log_event("circuit_breaker_tripped", feature="orchestrator")
            break

        print(f"\n  → Exploring: {feature['name']} (score={feature.get('portfolio_score', 0):.1f})")

        try:
            result = engine.explore_feature(feature, focus=focus)
            breaker.record_success()
            explored += 1

            screenshots_taken = len(result.get("screenshots", []))
            observations = len(result.get("observations", []))
            print(f"    📸 {screenshots_taken} screenshots, 💬 {observations} observations")

        except Exception as e:
            breaker.record_failure()
            logger.log_error(feature["name"], e)
            print(f"    ❌ Error: {e}")
            state.set_status(feature["name"], "skipped")

    print(f"\n  Explored {explored}/{len(explore_list)} features")
    logger.log_event("exploration_complete", feature="orchestrator", data={"explored": explored})

    # ── Phase 8: Generate report ─────────────────────────────────────
    _generate_report(config, analysis, scored, state, screenshot_mgr, logger)

    state.record_run(session_id, {
        "focus": focus,
        "features_explored": explored,
        "features_total": len(scored),
    })

    if runner:
        print("\nStopping dev server...")
        runner.stop()
        print("✅ Server stopped.")

    return 0


def _generate_report(config, analysis, scored, state, screenshot_mgr, logger):
    print(f"\n{'━' * 60}")
    print("Phase 8/8: Generating report")
    print("━" * 60)

    paths = generate_report(config, analysis, scored, state, screenshot_mgr)
    print(f"  📄 Report: {paths['report']}")
    print(f"  📊 Data:   {paths['data']}")
    logger.log_event("report_generated", feature="orchestrator", data=paths)
    print("\n🏁 Done!")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Portfolio Showcaser — Discover and showcase your best work",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--config", default="config.json",
        help="Path to config.json (default: config.json)",
    )
    parser.add_argument(
        "--focus", choices=["core", "interactions", "responsive", "edge_cases", "performance", "freestyle"],
        default=None,
        help="Exploration focus mode (default: core)",
    )
    parser.add_argument(
        "--feature", default=None,
        help="Explore a single feature by name",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Run analysis and scoring only, skip server and exploration",
    )
    parser.add_argument(
        "--skip-server", action="store_true",
        help="Skip dependency install and server startup",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    sys.exit(main())
