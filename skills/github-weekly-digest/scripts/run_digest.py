"""
run_digest.py — Main orchestrator for the GitHub Digest pipeline.

Supports three cadences:
  weekly  — full "what I shipped this week" post (default)
  daily   — brief "what I pushed today" dev log entry
  rollup  — weekly post synthesized from saved daily JSON files (no GitHub API)

Usage:
    python -m scripts.run_digest --config config.json
    python -m scripts.run_digest --config config.json --cadence daily
    python -m scripts.run_digest --config config.json --cadence rollup
    python -m scripts.run_digest --config config.json --cadence rollup --fill-gaps
    python -m scripts.run_digest --config config.json --dry-run
    python -m scripts.run_digest --config config.json --since 2025-01-06 --until 2025-01-12
    python -m scripts.run_digest --config config.json --repo my-project
    python -m scripts.run_digest --config config.json --reuse-analysis
    python -m scripts.run_digest --config config.json --force
"""

import argparse
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from scripts.shared_utils import (
    load_config, get_date_window, get_logger,
    ensure_output_dir, save_json, save_analyses, load_analyses,
    merge_daily_analyses, cleanup_old_outputs,
    iso_date, week_label, day_label, monday_of_week,
)
from scripts.github_fetcher import GitHubFetcher
from scripts.commit_analyzer import CommitAnalyzer
from scripts.narrative_writer import NarrativeWriter
from scripts.sanity_publisher import SanityPublisher

log = get_logger("digest")


def run_digest(
    config_path: str,
    cadence: str = "weekly",
    since_str: str = None,
    until_str: str = None,
    dry_run: bool = False,
    force: bool = False,
    single_repo: str = None,
    reuse_analysis: bool = False,
    fill_gaps: bool = False,
) -> None:
    config = load_config(config_path)
    since, until = get_date_window(config, since_str, until_str, cadence)
    out_dir = ensure_output_dir(config)
    date_prefix = iso_date(since)
    model = config.get("ai_model", "claude-sonnet-4-6")

    log.info("=" * 60)
    log.info(f"GitHub Digest  |  cadence={cadence}  |  "
             f"{'DRY RUN  |  ' if dry_run else ''}"
             f"{iso_date(since)} → {iso_date(until)}")
    log.info("=" * 60)

    # ── ROLLUP PATH ───────────────────────────────────────────────────────────
    if cadence == "rollup":
        _run_rollup(
            config, since, until, out_dir, date_prefix,
            model, dry_run, force, fill_gaps,
        )
        return

    # ── DAILY / WEEKLY PATH ───────────────────────────────────────────────────

    # Phase 1: Fetch
    log.info("\n[Phase 1] Fetching GitHub activity...")
    fetcher = GitHubFetcher(config)
    activities = fetcher.fetch(since, until)

    if single_repo:
        activities = [a for a in activities if a.repo_name == single_repo]
        if not activities:
            log.error(f"No activity found for repo '{single_repo}' in this window.")
            sys.exit(1)

    if not activities:
        log.warning("No commits found in this window. Nothing to publish.")
        sys.exit(0)

    log.info(f"Found activity in {len(activities)} repo(s)")

    # Phase 2: Analyze (or reload from cache)
    analysis_path = out_dir / f"{date_prefix}_analysis.json"

    if reuse_analysis and analysis_path.exists():
        log.info("\n[Phase 2] Loading cached analysis (--reuse-analysis)...")
        analyses = load_analyses(analysis_path)
        log.info(f"  Loaded {len(analyses)} analyses from {analysis_path}")
    else:
        log.info("\n[Phase 2] Analyzing commits with AI...")
        analyzer = CommitAnalyzer(config)
        analyses = analyzer.analyze_all(activities)

        if not analyses:
            log.error("AI analysis returned no results. Check API key and model.")
            sys.exit(1)

        save_analyses(analysis_path, analyses)
        log.info(f"  Analysis saved: {analysis_path}")
        log.info(f"  AI usage: {analyzer.token_usage.summary(model)}")

    interesting_count = sum(1 for a in analyses if a.interesting)
    log.info(f"  {interesting_count} featured / {len(analyses) - interesting_count} background")

    # Phase 3: Write narrative
    log.info(f"\n[Phase 3] Writing {cadence} narrative...")
    writer = NarrativeWriter(config)
    post = writer.write(
        analyses, since, until,
        cadence=cadence,
        out_dir=out_dir,
        date_prefix=date_prefix,
    )
    log.info(f"  Title: {post.title}")
    log.info(f"  Tags:  {post.tags}")
    log.info(f"  Stats: {post.stats}")
    log.info(f"  AI usage: {writer.token_usage.summary(model)}")

    # Save outputs
    _save_outputs(post, out_dir, date_prefix, since, until, analyses, model)

    # Phase 4: Publish
    if dry_run:
        log.info("\n[Phase 4] DRY RUN — skipping Sanity publish.")
        log.info(f"  Output dir: {out_dir}")
    else:
        log.info("\n[Phase 4] Publishing draft to Sanity CMS...")
        publisher = SanityPublisher(config)
        doc_id = publisher.publish(post, force=force)
        log.info(f"  Document ID: {doc_id}")
        log.info("  Status: DRAFT — review in Sanity Studio before publishing")

    # Cleanup old outputs
    retain_days = config.get("output", {}).get("retain_days", 0)
    if retain_days > 0:
        cleanup_old_outputs(out_dir, retain_days)

    log.info("\n✓ Digest complete.")


def _run_rollup(
    config: dict,
    since: datetime,
    until: datetime,
    out_dir: Path,
    date_prefix: str,
    model: str,
    dry_run: bool,
    force: bool,
    fill_gaps: bool,
) -> None:
    """
    Rollup: synthesize weekly post from saved daily JSON files.
    No GitHub API calls unless --fill-gaps is set and a day is missing.
    """
    log.info("\n[Rollup] Collecting daily analysis files...")
    monday = monday_of_week(since)

    daily_analyses_list = []
    daily_doc_ids = []
    missing_days = []

    for day_offset in range(7):
        day = monday + timedelta(days=day_offset)
        if day > until:
            break
        day_str = iso_date(day)
        daily_path = out_dir / f"{day_str}_analysis.json"

        if daily_path.exists():
            day_analyses = load_analyses(daily_path)
            daily_analyses_list.append(day_analyses)
            daily_doc_ids.append(f"drafts.dailyDigest-{day_str}")
            log.info(f"  ✓ {day_str}: loaded {len(day_analyses)} analyses")
        else:
            missing_days.append((day_str, day))
            log.warning(f"  ✗ {day_str}: no daily analysis found")

    if missing_days and fill_gaps:
        log.info(f"\n[Rollup] Filling {len(missing_days)} gap(s) from GitHub...")
        fetcher = GitHubFetcher(config)
        analyzer = CommitAnalyzer(config)

        for day_str, day in missing_days:
            gap_since = day.replace(hour=0, minute=0, second=0, microsecond=0, tzinfo=timezone.utc)
            gap_until = day.replace(hour=23, minute=59, second=59, microsecond=0, tzinfo=timezone.utc)
            activities = fetcher.fetch(gap_since, gap_until)
            if activities:
                gap_analyses = analyzer.analyze_all(activities)
                save_analyses(out_dir / f"{day_str}_analysis.json", gap_analyses)
                daily_analyses_list.append(gap_analyses)
                daily_doc_ids.append(f"drafts.dailyDigest-{day_str}")
                log.info(f"  ✓ {day_str}: filled ({len(gap_analyses)} repos)")
            else:
                log.info(f"  — {day_str}: no commits found (gap stays empty)")

    elif missing_days:
        log.warning(
            f"\n  {len(missing_days)} day(s) missing from rollup. "
            f"Use --fill-gaps to fetch them from GitHub."
        )

    if not daily_analyses_list:
        log.warning("No daily analyses found for this week. Nothing to roll up.")
        sys.exit(0)

    # Merge all days
    merged = merge_daily_analyses(daily_analyses_list)
    log.info(f"\n[Rollup] Merged: {len(merged)} repos across {len(daily_analyses_list)} day(s)")

    # Write weekly narrative from merged data
    log.info("\n[Phase 3] Writing weekly rollup narrative...")
    writer = NarrativeWriter(config)
    post = writer.write(
        merged, since, until,
        cadence="rollup",
        daily_refs=daily_doc_ids,
        out_dir=out_dir,
        date_prefix=date_prefix,
    )
    log.info(f"  Title: {post.title}")
    log.info(f"  AI usage: {writer.token_usage.summary(model)}")

    _save_outputs(post, out_dir, date_prefix, since, until, merged, model)

    if dry_run:
        log.info("\n[Phase 4] DRY RUN — skipping Sanity publish.")
    else:
        log.info("\n[Phase 4] Publishing weekly rollup draft to Sanity...")
        publisher = SanityPublisher(config)
        doc_id = publisher.publish(post, force=force)
        log.info(f"  Document ID: {doc_id}")
        if daily_doc_ids:
            log.info(f"  Linked daily digests: {daily_doc_ids}")

    retain_days = config.get("output", {}).get("retain_days", 0)
    if retain_days > 0:
        cleanup_old_outputs(out_dir, retain_days)

    log.info("\n✓ Rollup complete.")


def _save_outputs(
    post, out_dir: Path, date_prefix: str,
    since, until, analyses, model: str,
) -> None:
    """Save markdown preview and full digest JSON."""
    md_path = out_dir / f"{date_prefix}_post.md"
    md_path.write_text(
        f"# {post.title}\n\n"
        f"*{post.period_label}*\n\n"
        f"**Excerpt:** {post.excerpt}\n\n"
        f"**Tags:** {', '.join(post.tags)}\n\n"
        f"---\n\n"
        f"{post.body_markdown}"
    )
    log.info(f"  Post markdown: {md_path}")

    digest_data = {
        "title": post.title,
        "slug": post.slug,
        "cadence": post.cadence,
        "period_label": post.period_label,
        "week_of": post.week_of,
        "date": post.date,
        "since": iso_date(since),
        "until": iso_date(until),
        "excerpt": post.excerpt,
        "tags": post.tags,
        "stats": post.stats,
        "projects": post.projects,
        "body_markdown": post.body_markdown,
        "daily_refs": post.daily_refs,
    }
    digest_path = out_dir / f"{date_prefix}_digest.json"
    save_json(digest_path, digest_data)
    log.info(f"  Digest JSON:    {digest_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="GitHub Digest — automated commit-to-blog pipeline"
    )
    parser.add_argument("--config", default="config.json")
    parser.add_argument(
        "--cadence", choices=["daily", "weekly", "rollup"], default="weekly",
        help="daily=today's log, weekly=full week post, rollup=synthesize from daily files"
    )
    parser.add_argument("--since", help="Start date YYYY-MM-DD")
    parser.add_argument("--until", help="End date YYYY-MM-DD")
    parser.add_argument("--dry-run", action="store_true",
                        help="Analyze but don't publish to Sanity")
    parser.add_argument("--force", action="store_true",
                        help="Overwrite existing Sanity draft (default: skip if exists)")
    parser.add_argument("--repo", help="Process only this repo name")
    parser.add_argument("--reuse-analysis", action="store_true",
                        help="Load saved analysis JSON instead of calling AI again")
    parser.add_argument("--fill-gaps", action="store_true",
                        help="[rollup] Fetch missing days from GitHub")
    args = parser.parse_args()

    run_digest(
        config_path=args.config,
        cadence=args.cadence,
        since_str=args.since,
        until_str=args.until,
        dry_run=args.dry_run,
        force=args.force,
        single_repo=args.repo,
        reuse_analysis=args.reuse_analysis,
        fill_gaps=args.fill_gaps,
    )
