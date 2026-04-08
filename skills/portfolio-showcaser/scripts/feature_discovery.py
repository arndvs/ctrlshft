"""
feature_discovery.py — Enumerate showcasable features from a codebase.

Scans routes, pages, API endpoints, components, and user flows to produce
a flat list of features that the exploration engine can visit.

Usage:
    from scripts.feature_discovery import discover_features
    from scripts.code_analyzer import analyze_repo

    analysis = analyze_repo("/path/to/project")
    features = discover_features("/path/to/project", analysis)
"""

import re
from pathlib import Path


def discover_features(repo_path: str, analysis: dict) -> list[dict]:
    """
    Return a list of features discovered by static analysis.
    Each feature: {name, type, path, description, metadata}
    """
    repo = Path(repo_path)
    framework = analysis.get("framework", "unknown")

    features: list[dict] = []

    features.extend(_discover_pages(repo, framework))
    features.extend(_discover_api_endpoints(repo, framework))
    features.extend(_discover_components(repo))
    features.extend(_discover_flows(repo, analysis))
    features.extend(_discover_integration_features(analysis))

    features = _deduplicate(features)

    return features


def _discover_pages(repo: Path, framework: str) -> list[dict]:
    """Discover navigable pages/routes based on framework conventions."""
    pages: list[dict] = []

    if framework == "next":
        pages.extend(_discover_next_pages(repo))
    elif framework in ("vite_react", "cra"):
        pages.extend(_discover_react_router_pages(repo))
    elif framework == "nuxt":
        pages.extend(_discover_nuxt_pages(repo))
    elif framework == "svelte":
        pages.extend(_discover_svelte_pages(repo))
    elif framework == "html":
        pages.extend(_discover_html_pages(repo))
    elif framework == "astro":
        pages.extend(_discover_astro_pages(repo))

    return pages


def _discover_next_pages(repo: Path) -> list[dict]:
    pages = []

    app_dir = repo / "app"
    if app_dir.is_dir():
        for page_file in app_dir.rglob("page.*"):
            if page_file.suffix not in (".ts", ".tsx", ".js", ".jsx"):
                continue
            rel = page_file.parent.relative_to(app_dir)
            route = "/" + str(rel).replace("\\", "/")
            if route == "/.":
                route = "/"

            route = re.sub(r"\([^)]+\)/", "", route)

            if route.startswith("//"):
                route = route[1:]

            is_dynamic = "[" in route
            name = _route_to_name(route)

            pages.append({
                "name": name,
                "type": "page",
                "path": str(page_file.relative_to(repo)),
                "route": route,
                "description": f"{'Dynamic' if is_dynamic else 'Static'} page at {route}",
                "metadata": {"dynamic": is_dynamic, "framework_feature": "app_router"},
            })

    pages_dir = repo / "pages"
    if pages_dir.is_dir():
        for page_file in pages_dir.rglob("*"):
            if page_file.suffix not in (".ts", ".tsx", ".js", ".jsx"):
                continue
            if page_file.stem.startswith("_"):
                continue
            if page_file.parent.name == "api":
                continue

            rel = page_file.relative_to(pages_dir)
            route = "/" + str(rel.with_suffix("")).replace("\\", "/")
            if route.endswith("/index"):
                route = route[:-6] or "/"

            name = _route_to_name(route)
            pages.append({
                "name": name,
                "type": "page",
                "path": str(page_file.relative_to(repo)),
                "route": route,
                "description": f"Page at {route}",
                "metadata": {"dynamic": "[" in route, "framework_feature": "pages_router"},
            })

    return pages


def _discover_react_router_pages(repo: Path) -> list[dict]:
    """Scan for React Router route definitions in common locations."""
    pages = []
    route_files = []

    for candidate in ["src/App.tsx", "src/App.jsx", "src/routes.tsx", "src/routes.jsx",
                       "src/router.tsx", "src/router.jsx", "src/main.tsx", "src/main.jsx"]:
        path = repo / candidate
        if path.exists():
            route_files.append(path)

    for rf in route_files:
        try:
            content = rf.read_text(encoding="utf-8", errors="replace")
            route_matches = re.findall(r'path\s*[=:]\s*["\']([^"\']+)["\']', content)
            for route in route_matches:
                name = _route_to_name(route)
                pages.append({
                    "name": name,
                    "type": "page",
                    "path": str(rf.relative_to(repo)),
                    "route": route,
                    "description": f"React Router page at {route}",
                    "metadata": {"dynamic": ":" in route, "framework_feature": "react_router"},
                })
        except OSError:
            pass

    return pages


def _discover_nuxt_pages(repo: Path) -> list[dict]:
    pages = []
    pages_dir = repo / "pages"
    if not pages_dir.is_dir():
        return pages

    for page_file in pages_dir.rglob("*.vue"):
        rel = page_file.relative_to(pages_dir)
        route = "/" + str(rel.with_suffix("")).replace("\\", "/")
        if route.endswith("/index"):
            route = route[:-6] or "/"
        name = _route_to_name(route)
        pages.append({
            "name": name,
            "type": "page",
            "path": str(page_file.relative_to(repo)),
            "route": route,
            "description": f"Nuxt page at {route}",
            "metadata": {"dynamic": "[" in route, "framework_feature": "nuxt_pages"},
        })

    return pages


def _discover_svelte_pages(repo: Path) -> list[dict]:
    pages = []
    for routes_dir in [repo / "src" / "routes", repo / "routes"]:
        if not routes_dir.is_dir():
            continue
        for page_file in routes_dir.rglob("+page.svelte"):
            rel = page_file.parent.relative_to(routes_dir)
            route = "/" + str(rel).replace("\\", "/")
            if route == "/.":
                route = "/"
            name = _route_to_name(route)
            pages.append({
                "name": name,
                "type": "page",
                "path": str(page_file.relative_to(repo)),
                "route": route,
                "description": f"SvelteKit page at {route}",
                "metadata": {"dynamic": "[" in route, "framework_feature": "sveltekit"},
            })

    return pages


def _discover_astro_pages(repo: Path) -> list[dict]:
    pages = []
    pages_dir = repo / "src" / "pages"
    if not pages_dir.is_dir():
        return pages

    for page_file in pages_dir.rglob("*"):
        if page_file.suffix not in (".astro", ".md", ".mdx"):
            continue
        rel = page_file.relative_to(pages_dir)
        route = "/" + str(rel.with_suffix("")).replace("\\", "/")
        if route.endswith("/index"):
            route = route[:-6] or "/"
        name = _route_to_name(route)
        pages.append({
            "name": name,
            "type": "page",
            "path": str(page_file.relative_to(repo)),
            "route": route,
            "description": f"Astro page at {route}",
            "metadata": {"dynamic": "[" in route, "framework_feature": "astro"},
        })

    return pages


def _discover_html_pages(repo: Path) -> list[dict]:
    pages = []
    for html_file in repo.glob("*.html"):
        route = "/" if html_file.stem == "index" else f"/{html_file.name}"
        pages.append({
            "name": _route_to_name(route),
            "type": "page",
            "path": str(html_file.relative_to(repo)),
            "route": route,
            "description": f"HTML page at {route}",
            "metadata": {"dynamic": False, "framework_feature": "static_html"},
        })

    return pages


def _discover_api_endpoints(repo: Path, framework: str) -> list[dict]:
    """Discover API routes to potentially demo via curl/fetch."""
    endpoints = []

    if framework == "next":
        for api_dir in [repo / "app" / "api", repo / "pages" / "api"]:
            if not api_dir.is_dir():
                continue
            for route_file in api_dir.rglob("route.*"):
                if route_file.suffix not in (".ts", ".js"):
                    continue
                route = "/api/" + str(route_file.parent.relative_to(api_dir)).replace("\\", "/")
                if route.endswith("/."):
                    route = "/api"

                methods = _detect_http_methods(route_file)
                endpoints.append({
                    "name": f"API: {route}",
                    "type": "api_endpoint",
                    "path": str(route_file.relative_to(repo)),
                    "route": route,
                    "description": f"API endpoint {', '.join(methods)} {route}",
                    "metadata": {"methods": methods, "framework_feature": "api_routes"},
                })

    return endpoints


def _detect_http_methods(file_path: Path) -> list[str]:
    """Read a route file and detect exported HTTP method handlers."""
    methods = []
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
        for method in ["GET", "POST", "PUT", "PATCH", "DELETE"]:
            if re.search(rf"export\s+(async\s+)?function\s+{method}\b", content):
                methods.append(method)
    except OSError:
        pass
    return methods or ["GET"]


def _discover_components(repo: Path) -> list[dict]:
    """Discover standalone UI components worth showcasing."""
    components = []
    seen_names: set[str] = set()

    for comp_dir in ["src/components", "components", "app/components"]:
        path = repo / comp_dir
        if not path.is_dir():
            continue

        for subdir in sorted(path.iterdir()):
            if not subdir.is_dir() or subdir.name.startswith(".") or subdir.name == "ui":
                continue

            comp_files = list(subdir.glob("*.tsx")) + list(subdir.glob("*.jsx")) + list(subdir.glob("*.vue"))
            if not comp_files:
                continue

            name = subdir.name
            if name in seen_names:
                continue
            seen_names.add(name)

            complexity = sum(1 for _ in subdir.rglob("*") if _.is_file())
            if complexity < 2:
                continue

            components.append({
                "name": _prettify_component(name),
                "type": "component",
                "path": str(subdir.relative_to(repo)),
                "description": f"UI component: {_prettify_component(name)} ({complexity} files)",
                "metadata": {"file_count": complexity},
            })

    return components


def _discover_flows(repo: Path, analysis: dict) -> list[dict]:
    """Detect multi-step user flows (auth, checkout, onboarding, etc.)."""
    flows = []
    integrations = {i["type"] for i in analysis.get("integrations", [])}

    flow_signals = {
        "auth": {
            "dirs": ["app/(auth)", "app/auth", "pages/auth", "src/pages/auth", "app/login", "app/sign-in"],
            "integration": "auth",
            "description": "Authentication flow (sign-up, login, session management)",
        },
        "checkout": {
            "dirs": ["app/checkout", "pages/checkout", "src/pages/checkout", "app/(checkout)"],
            "integration": "payments",
            "description": "Checkout / payment flow with Stripe integration",
        },
        "onboarding": {
            "dirs": ["app/onboarding", "app/welcome", "app/setup", "pages/onboarding"],
            "integration": None,
            "description": "User onboarding / setup wizard",
        },
        "dashboard": {
            "dirs": ["app/dashboard", "app/(dashboard)", "pages/dashboard", "src/pages/dashboard"],
            "integration": None,
            "description": "Data dashboard with charts/tables",
        },
        "settings": {
            "dirs": ["app/settings", "app/(settings)", "pages/settings"],
            "integration": None,
            "description": "User settings / profile management",
        },
        "admin": {
            "dirs": ["app/admin", "app/(admin)", "pages/admin"],
            "integration": None,
            "description": "Admin panel / back-office interface",
        },
    }

    for flow_name, config in flow_signals.items():
        found = False
        flow_path = ""

        for d in config["dirs"]:
            if (repo / d).is_dir():
                found = True
                flow_path = d
                break

        if not found and config["integration"] and config["integration"] in integrations:
            found = True
            flow_path = f"detected via {config['integration']} integration"

        if found:
            flows.append({
                "name": f"{flow_name.title()} Flow",
                "type": "flow",
                "path": flow_path,
                "description": config["description"],
                "metadata": {"flow_type": flow_name},
            })

    return flows


def _discover_integration_features(analysis: dict) -> list[dict]:
    """Turn detected integrations into showcasable features."""
    features = []
    for integration in analysis.get("integrations", []):
        if integration["type"] in ("styling", "icons", "validation"):
            continue
        features.append({
            "name": f"{integration['name']} Integration",
            "type": "integration",
            "path": "",
            "description": integration["portfolio_angle"],
            "metadata": {"integration_type": integration["type"]},
        })

    return features


def _route_to_name(route: str) -> str:
    """Convert a route path to a human-readable name."""
    if route == "/":
        return "Home Page"

    parts = route.strip("/").split("/")
    cleaned = []
    for p in parts:
        p = re.sub(r"[\[\]()]", "", p)
        p = re.sub(r"[_-]", " ", p)
        if p and not p.startswith("."):
            cleaned.append(p.title())

    return " ".join(cleaned) if cleaned else "Page"


def _prettify_component(name: str) -> str:
    """Convert a directory name to a pretty component name."""
    name = re.sub(r"[-_]", " ", name)
    return name.title()


def _deduplicate(features: list[dict]) -> list[dict]:
    """Remove duplicate features by name, preferring pages > flows > components."""
    type_priority = {"flow": 0, "page": 1, "api_endpoint": 2, "component": 3, "integration": 4}
    seen: dict[str, dict] = {}

    for f in features:
        key = f["name"].lower()
        if key not in seen:
            seen[key] = f
        else:
            existing = seen[key]
            if type_priority.get(f["type"], 99) < type_priority.get(existing["type"], 99):
                seen[key] = f

    return list(seen.values())
