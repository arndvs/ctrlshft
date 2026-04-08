"""
report_generator.py — Generate portfolio showcase report.

Produces a Markdown report with 6 sections and a companion JSON data file
from analysis results, scored features, screenshots, and observations.

Usage:
    from scripts.report_generator import generate_report

    generate_report(config, analysis, features, state_store, screenshot_mgr)
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


def generate_report(
    config: dict,
    analysis: dict,
    features: list[dict],
    state_store,
    screenshot_mgr,
) -> dict:
    """
    Generate both markdown report and portfolio-data.json.
    Returns paths to generated files.
    """
    output_dir = Path(config.get("output_dir", "./output"))
    output_dir.mkdir(parents=True, exist_ok=True)

    report_path = output_dir / config.get("report_filename", "portfolio-report.md")
    data_path = output_dir / "portfolio-data.json"

    md = _build_markdown(config, analysis, features, state_store, screenshot_mgr)
    report_path.write_text(md, encoding="utf-8")

    data = _build_json(config, analysis, features, state_store)
    data_path.write_text(json.dumps(data, indent=2, default=str), encoding="utf-8")

    return {"report": str(report_path), "data": str(data_path)}


def _build_markdown(
    config: dict,
    analysis: dict,
    features: list[dict],
    state_store,
    screenshot_mgr,
) -> str:
    sections = []

    sections.append(_section_header(config, analysis))
    sections.append(_section_tech_stack(analysis))
    sections.append(_section_architecture(analysis))
    sections.append(_section_features(features, screenshot_mgr))
    sections.append(_section_code_highlights(state_store))
    sections.append(_section_quality(analysis))

    return "\n\n---\n\n".join(sections)


def _section_header(config: dict, analysis: dict) -> str:
    repo_name = Path(config["repo_path"]).name
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    framework = analysis.get("framework", "unknown")
    language = analysis.get("language", "unknown")

    return f"""# Portfolio Showcase: {repo_name}

> Generated on {now} | {framework} · {language}

## Overview

This report highlights the most portfolio-worthy aspects of **{repo_name}**,
including technical architecture, standout features, and code quality signals."""


def _section_tech_stack(analysis: dict) -> str:
    lines = ["## Tech Stack\n"]

    lines.append(f"- **Framework:** {analysis.get('framework', 'unknown')}")
    lines.append(f"- **Language:** {analysis.get('language', 'unknown')}")
    lines.append(f"- **Package Manager:** {analysis.get('package_manager', 'unknown')}")
    lines.append(f"- **Styling:** {analysis.get('styling', 'css')}")

    integrations = analysis.get("integrations", [])
    if integrations:
        lines.append("\n### Integrations\n")
        for i in integrations:
            lines.append(f"- **{i['name']}** ({i['type']}) — {i['portfolio_angle']}")

    stats = analysis.get("file_stats", {})
    if stats:
        lines.append("\n### File Statistics\n")
        lines.append(f"| Metric | Count |")
        lines.append(f"|--------|-------|")
        for key, val in stats.items():
            label = key.replace("_", " ").title()
            lines.append(f"| {label} | {val} |")

    return "\n".join(lines)


def _section_architecture(analysis: dict) -> str:
    lines = ["## Architecture Patterns\n"]

    patterns = analysis.get("patterns", [])
    if not patterns:
        lines.append("No notable architecture patterns detected.")
        return "\n".join(lines)

    patterns_sorted = sorted(patterns, key=lambda p: p.get("score", 0), reverse=True)
    for p in patterns_sorted:
        score_stars = "⭐" * min(p.get("score", 0), 5)
        lines.append(f"### {p['name']} {score_stars}\n")
        files = p.get("files", [])
        if files:
            for f in files[:5]:
                lines.append(f"- `{f}`")
        lines.append("")

    return "\n".join(lines)


def _section_features(features: list[dict], screenshot_mgr) -> str:
    lines = ["## Standout Features\n"]
    lines.append("Ranked by portfolio impact score (Visual × Technical × Uniqueness × Demonstrability).\n")

    for i, feature in enumerate(features, 1):
        score = feature.get("portfolio_score", 0)
        f_type = feature.get("type", "unknown")
        desc = feature.get("description", "")
        scores = feature.get("scores", {})

        lines.append(f"### {i}. {feature['name']} (Score: {score})\n")
        lines.append(f"**Type:** {f_type} | **Route:** `{feature.get('route', 'N/A')}`\n")
        lines.append(f"{desc}\n")

        if scores:
            lines.append(f"| Axis | Score |")
            lines.append(f"|------|-------|")
            for axis in ["visual", "technical", "uniqueness", "demonstrability"]:
                val = scores.get(axis, 0)
                bar = "█" * val + "░" * (5 - val)
                lines.append(f"| {axis.title()} | {bar} {val}/5 |")
            if scores.get("bonus", 0) > 0:
                lines.append(f"| Bonus | +{scores['bonus']} |")
            if scores.get("penalty", 0) < 0:
                lines.append(f"| Penalty | {scores['penalty']} |")

        annotations = screenshot_mgr.get_annotations() if screenshot_mgr else {}
        feature_screenshots = {k: v for k, v in annotations.items() if feature["name"].lower().replace(" ", "_") in k.lower()}
        if feature_screenshots:
            lines.append("\n**Screenshots:**\n")
            for path, annotation in feature_screenshots.items():
                fname = Path(path).name
                lines.append(f"- `{fname}`: {annotation}")

        lines.append("")

    return "\n".join(lines)


def _section_code_highlights(state_store) -> str:
    lines = ["## Code Highlights\n"]
    lines.append("Notable code patterns and implementations worth discussing in interviews.\n")

    highlights = state_store.get_code_highlights() if state_store else []
    if not highlights:
        lines.append("No code highlights recorded. Run exploration with `--focus interactions` to capture more.")
        return "\n".join(lines)

    for h in highlights:
        lines.append(f"### {h.get('title', 'Highlight')}\n")
        if h.get("file"):
            lines.append(f"**File:** `{h['file']}`\n")
        if h.get("description"):
            lines.append(f"{h['description']}\n")
        if h.get("code_snippet"):
            lang = h.get("language", "")
            lines.append(f"```{lang}")
            lines.append(h["code_snippet"])
            lines.append("```\n")

    return "\n".join(lines)


def _section_quality(analysis: dict) -> str:
    lines = ["## Code Quality Signals\n"]

    quality = analysis.get("quality_signals", {})
    if not quality:
        lines.append("No quality signals detected.")
        return "\n".join(lines)

    indicators = [
        ("TypeScript Strict Mode", quality.get("typescript_strict", False)),
        ("ESLint Configuration", quality.get("has_eslint", False)),
        ("Prettier Formatting", quality.get("has_prettier", False)),
        ("Runtime Validation (Zod)", quality.get("has_zod", False)),
        ("Environment Validation", quality.get("has_env_validation", False)),
        ("CI/CD Pipeline", quality.get("has_ci", False)),
    ]

    lines.append("| Signal | Status |")
    lines.append("|--------|--------|")
    for label, present in indicators:
        status = "✅ Yes" if present else "❌ No"
        lines.append(f"| {label} | {status} |")

    test_count = quality.get("test_file_count", 0)
    lines.append(f"\n**Test Files:** {test_count}")

    if test_count > 20:
        lines.append("\n> 🏆 Strong testing culture — this project has a comprehensive test suite.")
    elif test_count > 5:
        lines.append("\n> ✅ Good test coverage with meaningful test files.")
    elif test_count > 0:
        lines.append("\n> ⚠️ Some tests exist but coverage could be improved.")

    return "\n".join(lines)


def _build_json(
    config: dict,
    analysis: dict,
    features: list[dict],
    state_store,
) -> dict:
    """Build structured JSON for programmatic consumption."""
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "repo": Path(config["repo_path"]).name,
        "repo_path": config["repo_path"],
        "analysis": {
            "framework": analysis.get("framework"),
            "language": analysis.get("language"),
            "package_manager": analysis.get("package_manager"),
            "styling": analysis.get("styling"),
            "dev_port": analysis.get("dev_port"),
            "integrations": analysis.get("integrations", []),
            "patterns": analysis.get("patterns", []),
            "quality_signals": analysis.get("quality_signals", {}),
            "file_stats": analysis.get("file_stats", {}),
        },
        "features": [
            {
                "name": f["name"],
                "type": f.get("type"),
                "route": f.get("route"),
                "score": f.get("portfolio_score", 0),
                "scores": f.get("scores", {}),
                "description": f.get("description"),
            }
            for f in features
        ],
        "code_highlights": state_store.get_code_highlights() if state_store else [],
        "run_history": state_store.data.get("runs", []) if state_store else [],
    }
