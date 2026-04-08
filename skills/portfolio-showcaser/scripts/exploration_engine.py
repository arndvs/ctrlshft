"""
exploration_engine.py — Agent-guided browser exploration of running app.

The VS Code agent reads method docstrings (prefixed with 'Agent:') to know
what browser actions to perform for each exploration step. This module
orchestrates the sequence; the agent provides the eyes and hands.

Focus modes:
- core: Landing page, primary navigation, key pages
- interactions: Forms, modals, hover effects, transitions
- responsive: Same pages at mobile, tablet, desktop viewports
- edge_cases: Loading states, error states, empty states, 404
- performance: Lighthouse-style observations, LCP, layout shifts
- freestyle: Agent explores freely, captures anything interesting

Usage:
    from scripts.exploration_engine import ExplorationEngine

    engine = ExplorationEngine(config, state_store, screenshot_mgr, session_log)
    engine.explore_feature(feature, focus="core")
    engine.freestyle_explore(base_url)
"""

from __future__ import annotations


class ExplorationEngine:
    """
    Agent: This engine tells you which features to explore and how.
    For each method call, read the docstring carefully — it contains
    your browser action instructions. After performing each action,
    call the screenshot_manager to capture evidence.
    """

    def __init__(self, config: dict, state_store, screenshot_mgr, session_log):
        self.config = config
        self.state = state_store
        self.screenshots = screenshot_mgr
        self.log = session_log
        self.base_url = f"http://localhost:{config.get('exploration', {}).get('port', 3000)}"
        self.viewports = config.get("exploration", {}).get("viewports", {})

    def explore_feature(self, feature: dict, focus: str = "core") -> dict:
        """
        Agent: Explore a single feature. Steps depend on focus mode.
        Returns a dict of screenshots taken and observations.

        1. Navigate to the feature's route (if it has one)
        2. Read the focus handler's docstring for specific browser actions
        3. Use screenshot_mgr.screenshot_path(feature_name, step_name) for paths
        4. Use screenshot_mgr.annotate(screenshot_path, annotation) to add context
        5. Update state_store with screenshots and status
        6. After all features, optionally call engine.freestyle_explore(base_url)

        The focus handlers return empty dicts — YOU fill them with actual data
        from your browser observations.
        """
        name = feature.get("name", "unknown")
        route = feature.get("route", "/")
        f_type = feature.get("type", "page")
        url = f"{self.base_url}{route}" if route else self.base_url

        self.log.log_event("explore_start", feature=name, data={"focus": focus, "url": url})
        self.state.set_status(name, "in_progress")

        result = {"feature": name, "focus": focus, "screenshots": [], "observations": []}

        handler = getattr(self, f"_focus_{focus}", self._focus_core)
        focus_result = handler(feature, url)
        result["screenshots"].extend(focus_result.get("screenshots", []))
        result["observations"].extend(focus_result.get("observations", []))

        self.state.set_status(name, "screenshotted")
        self.log.log_event("explore_complete", feature=name, data={"screenshot_count": len(result["screenshots"])})

        return result

    def _focus_core(self, feature: dict, url: str) -> dict:
        """
        Agent: CORE EXPLORATION — Capture the feature's primary visual state.

        1. Navigate to {url}
        2. Wait for page to fully load (network idle)
        3. Screenshot the full page → step_name: 'overview'
        4. If there's a hero section or prominent header, screenshot it → 'hero_section'
        5. Identify and screenshot the main navigation → 'navigation'
        6. If the page has distinct sections, screenshot the most interesting one → 'feature_detail'
        7. Note any loading spinners, skeleton screens, or progressive content
        8. Record observations about visual design quality, layout, typography
        """
        return {"screenshots": [], "observations": []}

    def _focus_interactions(self, feature: dict, url: str) -> dict:
        """
        Agent: INTERACTION EXPLORATION — Trigger and capture interactive elements.

        1. Navigate to {url}
        2. Look for forms — fill them with test data, screenshot before/after → 'form_interaction'
        3. Submit a form with invalid data to trigger validation → 'form_validation'
        4. Click buttons that open modals, drawers, or dropdowns → 'modal_or_drawer'
        5. Hover over interactive elements (cards, buttons, links) → 'hover_effect'
        6. Look for animations or transitions, capture mid-animation → 'animation'
        7. Try keyboard navigation (Tab through form fields)
        8. Note any micro-interactions, transitions, or feedback patterns
        """
        return {"screenshots": [], "observations": []}

    def _focus_responsive(self, feature: dict, url: str) -> dict:
        """
        Agent: RESPONSIVE EXPLORATION — Test the same page at multiple viewports.

        1. Navigate to {url}
        2. Set viewport to MOBILE (375x812) → screenshot → 'responsive_mobile'
        3. Set viewport to TABLET (768x1024) → screenshot → 'responsive_tablet'
        4. Set viewport to DESKTOP (1440x900) → screenshot → 'responsive_desktop'
        5. At mobile: check hamburger menu opens/closes → screenshot if present
        6. At mobile: verify no horizontal scroll
        7. Note layout changes, hidden elements, reflow quality
        8. Compare navigation patterns across breakpoints
        """
        return {"screenshots": [], "observations": []}

    def _focus_edge_cases(self, feature: dict, url: str) -> dict:
        """
        Agent: EDGE CASE EXPLORATION — Capture non-happy-path states.

        1. Navigate to {url}
        2. If the page loads data, capture the loading state → 'loading_state'
        3. If possible, trigger an empty/no-data state → 'empty_state'
        4. Navigate to a non-existent route to see 404 handling → 'error_state'
        5. If there are forms, submit empty to see validation errors
        6. Disable JavaScript if possible and see SSR fallback
        7. Try rapid navigation / back-forward to check state persistence
        8. Note error messages, fallback UIs, graceful degradation
        """
        return {"screenshots": [], "observations": []}

    def _focus_performance(self, feature: dict, url: str) -> dict:
        """
        Agent: PERFORMANCE EXPLORATION — Observe loading behavior.

        1. Navigate to {url} with network throttling if possible
        2. Note the largest contentful paint — what loads first?
        3. Watch for layout shifts as content loads → screenshot if visible
        4. Check if images are lazy-loaded (scroll down and observe)
        5. Note whether fonts cause FOUT/FOIT
        6. Check bundle size in network tab if accessible
        7. Try navigating between pages — note client-side transition speed
        8. Record observations about perceived performance
        """
        return {"screenshots": [], "observations": []}

    def _focus_freestyle(self, feature: dict, url: str) -> dict:
        """
        Agent: FREESTYLE EXPLORATION — You have creative freedom.

        1. Navigate to {url}
        2. Explore the feature as a real user would
        3. Look for anything visually impressive or technically interesting
        4. Try unexpected interactions (right-click menus, drag-and-drop, gestures)
        5. Check for dark mode toggle
        6. Look for search functionality and try it
        7. Check data tables for sorting/filtering
        8. Capture anything that would impress in a portfolio → 'misc'
        9. Take at most 3 screenshots of your best finds
        """
        return {"screenshots": [], "observations": []}

    def freestyle_explore(self, base_url: str) -> dict:
        """
        Agent: OPEN-ENDED EXPLORATION — No specific feature target.

        Starting from {base_url}, freely explore the application:
        1. Navigate the full site map
        2. Find pages or features that weren't in the discovery list
        3. Look for easter eggs, particularly polished interactions, or unique UX
        4. Capture anything portfolio-worthy with descriptive annotations
        5. Budget: up to 5 screenshots
        6. Report back what you found as observations

        Return your findings so they can be added to the report.
        """
        self.log.log_event("freestyle_start", feature="freestyle", data={"url": base_url})

        return {"screenshots": [], "observations": [], "discovered_features": []}

    def get_exploration_plan(self, features: list[dict], focus: str = "core") -> list[dict]:
        """
        Build an ordered exploration plan from scored features.
        Returns steps the orchestrator will execute sequentially.
        """
        plan = []
        for i, feature in enumerate(features):
            plan.append({
                "step": i + 1,
                "feature": feature["name"],
                "type": feature.get("type", "page"),
                "route": feature.get("route", ""),
                "focus": focus,
                "score": feature.get("portfolio_score", 0),
            })

        return plan
