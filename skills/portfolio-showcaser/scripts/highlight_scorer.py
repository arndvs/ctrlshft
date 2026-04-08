"""
highlight_scorer.py — Score discovered features for portfolio impact.

Uses a 4-axis rubric: Visual, Technical, Uniqueness, Demonstrability.
Each axis 1-5, with bonuses for flows and sibling files (loading/error).

Usage:
    from scripts.highlight_scorer import score_features

    scored = score_features(features, analysis, max_features=15)
"""

from __future__ import annotations

import re
from pathlib import Path

AXIS_WEIGHTS = {
    "visual": 1.0,
    "technical": 1.2,
    "uniqueness": 1.5,
    "demonstrability": 1.3,
}

FLOW_BONUS = 3.0
SIBLING_BONUS = 1.5
DYNAMIC_ROUTE_BONUS = 1.0
MULTI_METHOD_API_BONUS = 1.0

SCAFFOLD_PENALTY = -2.0
SCAFFOLD_NAMES = {"about", "contact", "404", "privacy", "terms", "page"}


def score_features(
    features: list[dict],
    analysis: dict,
    max_features: int = 15,
) -> list[dict]:
    """
    Score each feature on the 4-axis rubric, apply bonuses/penalties,
    sort by portfolio_score descending, and return top N.
    """
    scored = []
    for feature in features:
        scores = _score_feature(feature, analysis)
        feature["scores"] = scores
        feature["portfolio_score"] = _compute_total(scores)
        scored.append(feature)

    scored.sort(key=lambda f: f["portfolio_score"], reverse=True)

    return scored[:max_features]


def _score_feature(feature: dict, analysis: dict) -> dict:
    """Compute raw axis scores + bonuses for a single feature."""
    f_type = feature.get("type", "")
    meta = feature.get("metadata", {})
    name = feature.get("name", "").lower()
    integrations = {i["type"] for i in analysis.get("integrations", [])}
    patterns = {p["name"] for p in analysis.get("patterns", [])}

    visual = _score_visual(f_type, meta, name, integrations)
    technical = _score_technical(f_type, meta, name, integrations, patterns)
    uniqueness = _score_uniqueness(f_type, meta, name, integrations)
    demonstrability = _score_demonstrability(f_type, meta, name)

    bonus = 0.0
    if f_type == "flow":
        bonus += FLOW_BONUS
    if meta.get("has_loading_sibling") or meta.get("has_error_sibling"):
        bonus += SIBLING_BONUS
    if meta.get("dynamic"):
        bonus += DYNAMIC_ROUTE_BONUS
    if f_type == "api_endpoint" and len(meta.get("methods", [])) > 1:
        bonus += MULTI_METHOD_API_BONUS

    penalty = 0.0
    name_stem = name.split()[-1].lower() if name.split() else ""
    if name_stem in SCAFFOLD_NAMES:
        penalty += SCAFFOLD_PENALTY

    return {
        "visual": visual,
        "technical": technical,
        "uniqueness": uniqueness,
        "demonstrability": demonstrability,
        "bonus": bonus,
        "penalty": penalty,
    }


def _score_visual(f_type: str, meta: dict, name: str, integrations: set) -> int:
    """How visually interesting is this feature?"""
    score = 2

    if f_type == "flow":
        score += 2
    elif f_type == "page":
        score += 1

    visual_keywords = ["dashboard", "chart", "graph", "visualization", "animation",
                       "gallery", "portfolio", "hero", "landing"]
    if any(kw in name for kw in visual_keywords):
        score += 1

    if "animation" in integrations or "visualization" in integrations:
        score += 1

    return min(score, 5)


def _score_technical(f_type: str, meta: dict, name: str, integrations: set, patterns: set) -> int:
    """How technically impressive is this feature?"""
    score = 2

    if f_type == "api_endpoint":
        score += 1
    if f_type == "flow":
        score += 1

    tech_keywords = ["api", "webhook", "cron", "middleware", "auth", "real-time",
                     "websocket", "stream", "search", "upload"]
    if any(kw in name for kw in tech_keywords):
        score += 1

    tech_integrations = {"ai", "realtime", "search", "database", "payments"}
    if integrations & tech_integrations:
        score += 1

    advanced_patterns = {"Server Actions", "Parallel Routes", "Intercepting Routes",
                         "Streaming/Suspense Boundaries", "Custom Middleware"}
    if patterns & advanced_patterns:
        score += 1

    return min(score, 5)


def _score_uniqueness(f_type: str, meta: dict, name: str, integrations: set) -> int:
    """How unusual/non-boilerplate is this feature?"""
    score = 2

    generic = {"home", "about", "contact", "login", "signup", "register", "settings", "profile"}
    name_words = set(name.lower().split())
    if name_words & generic:
        score -= 1

    unique_keywords = ["ai", "stripe", "realtime", "webhook", "embed", "studio",
                       "builder", "editor", "playground", "sandbox"]
    if any(kw in name for kw in unique_keywords):
        score += 2

    unique_integrations = {"ai", "realtime", "search", "visualization"}
    if integrations & unique_integrations:
        score += 1

    if meta.get("flow_type") in ("checkout", "onboarding"):
        score += 1

    return max(min(score, 5), 1)


def _score_demonstrability(f_type: str, meta: dict, name: str) -> int:
    """Can this feature be meaningfully demoed in screenshots?"""
    score = 3

    if f_type == "page":
        score += 1
    elif f_type == "flow":
        score += 1
    elif f_type == "api_endpoint":
        score -= 1
    elif f_type == "integration":
        score -= 1

    interactive_keywords = ["form", "search", "filter", "sort", "checkout",
                            "cart", "editor", "builder", "wizard"]
    if any(kw in name for kw in interactive_keywords):
        score += 1

    if meta.get("dynamic"):
        score += 0

    return max(min(score, 5), 1)


def _compute_total(scores: dict) -> float:
    """Weighted sum of all axes plus bonuses minus penalties."""
    total = 0.0
    for axis, weight in AXIS_WEIGHTS.items():
        total += scores.get(axis, 0) * weight

    total += scores.get("bonus", 0)
    total += scores.get("penalty", 0)

    return round(total, 2)


def enrich_with_siblings(features: list[dict], repo_path: str) -> list[dict]:
    """
    Post-process features to check for loading.tsx / error.tsx siblings.
    Must run before scoring to get SIBLING_BONUS.
    """
    repo = Path(repo_path)

    for feature in features:
        if feature.get("type") != "page":
            continue
        path = feature.get("path", "")
        if not path:
            continue

        page_dir = (repo / path).parent
        has_loading = any(
            (page_dir / f"loading{ext}").exists()
            for ext in [".tsx", ".jsx", ".ts", ".js"]
        )
        has_error = any(
            (page_dir / f"error{ext}").exists()
            for ext in [".tsx", ".jsx", ".ts", ".js"]
        )

        feature.setdefault("metadata", {})["has_loading_sibling"] = has_loading
        feature.setdefault("metadata", {})["has_error_sibling"] = has_error

    return features
