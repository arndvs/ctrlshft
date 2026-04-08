"""
code_analyzer.py — Static codebase analysis for portfolio showcaser.

Reads a project directory without running it. Detects framework, tech stack,
integrations, architecture patterns, and quality signals.

Usage:
    from scripts.code_analyzer import analyze_repo

    analysis = analyze_repo("/path/to/project")
    print(analysis["framework"], analysis["integrations"])
"""

import json
import os
import re
from pathlib import Path

from scripts.shared_utils import detect_package_manager as _detect_package_manager_shared

FRAMEWORK_SIGNATURES = {
    "next": {
        "files": ["next.config.js", "next.config.mjs", "next.config.ts"],
        "deps": ["next"],
    },
    "nuxt": {
        "files": ["nuxt.config.js", "nuxt.config.ts"],
        "deps": ["nuxt"],
    },
    "svelte": {
        "files": ["svelte.config.js", "svelte.config.ts"],
        "deps": ["svelte", "@sveltejs/kit"],
    },
    "vite_react": {
        "files": ["vite.config.js", "vite.config.ts", "vite.config.mjs"],
        "deps": ["vite"],
        "also_requires": ["react"],
    },
    "vite_vue": {
        "files": ["vite.config.js", "vite.config.ts", "vite.config.mjs"],
        "deps": ["vite"],
        "also_requires": ["vue"],
    },
    "cra": {
        "deps": ["react-scripts"],
    },
    "angular": {
        "files": ["angular.json"],
        "deps": ["@angular/core"],
    },
    "remix": {
        "files": ["remix.config.js", "remix.config.ts"],
        "deps": ["@remix-run/react"],
    },
    "astro": {
        "files": ["astro.config.mjs", "astro.config.ts"],
        "deps": ["astro"],
    },
    "gatsby": {
        "files": ["gatsby-config.js", "gatsby-config.ts"],
        "deps": ["gatsby"],
    },
    "django": {
        "files": ["manage.py"],
        "deps": ["django", "Django"],
    },
    "flask": {
        "deps": ["flask", "Flask"],
    },
    "rails": {
        "files": ["Gemfile", "Rakefile"],
    },
    "laravel": {
        "files": ["artisan"],
        "deps": ["laravel/framework"],
    },
    "spring": {
        "files": ["pom.xml", "build.gradle"],
    },
}

INTEGRATION_MAP = {
    "stripe": {"type": "payments", "portfolio_angle": "Handles real payment transactions"},
    "@stripe/stripe-js": {"type": "payments", "portfolio_angle": "Client-side Stripe checkout integration"},
    "next-auth": {"type": "auth", "portfolio_angle": "Production authentication with NextAuth.js"},
    "@auth/core": {"type": "auth", "portfolio_angle": "Auth.js authentication framework"},
    "@clerk/nextjs": {"type": "auth", "portfolio_angle": "Clerk authentication with session management"},
    "sanity": {"type": "cms", "portfolio_angle": "Headless CMS with structured content"},
    "next-sanity": {"type": "cms", "portfolio_angle": "Sanity integration with visual editing"},
    "@sanity/client": {"type": "cms", "portfolio_angle": "Sanity API client for content delivery"},
    "contentful": {"type": "cms", "portfolio_angle": "Contentful headless CMS integration"},
    "prisma": {"type": "database", "portfolio_angle": "Type-safe database ORM with Prisma"},
    "@prisma/client": {"type": "database", "portfolio_angle": "Type-safe database access layer"},
    "drizzle-orm": {"type": "database", "portfolio_angle": "Drizzle ORM with type-safe SQL"},
    "resend": {"type": "email", "portfolio_angle": "Transactional email delivery with Resend"},
    "@sendgrid/mail": {"type": "email", "portfolio_angle": "SendGrid email integration"},
    "openai": {"type": "ai", "portfolio_angle": "AI-powered features with OpenAI"},
    "@anthropic-ai/sdk": {"type": "ai", "portfolio_angle": "Claude AI integration"},
    "ai": {"type": "ai", "portfolio_angle": "Vercel AI SDK for streaming responses"},
    "pusher": {"type": "realtime", "portfolio_angle": "Real-time updates with Pusher"},
    "socket.io": {"type": "realtime", "portfolio_angle": "WebSocket-based real-time communication"},
    "socket.io-client": {"type": "realtime", "portfolio_angle": "Real-time client communication"},
    "@algolia/client-search": {"type": "search", "portfolio_angle": "Full-text search with Algolia"},
    "meilisearch": {"type": "search", "portfolio_angle": "Fast search with MeiliSearch"},
    "@sentry/nextjs": {"type": "monitoring", "portfolio_angle": "Production error monitoring with Sentry"},
    "@vercel/analytics": {"type": "analytics", "portfolio_angle": "Vercel web analytics"},
    "zod": {"type": "validation", "portfolio_angle": "Runtime type validation with Zod"},
    "react-hook-form": {"type": "forms", "portfolio_angle": "Performant form handling"},
    "framer-motion": {"type": "animation", "portfolio_angle": "Polished animations with Framer Motion"},
    "react-spring": {"type": "animation", "portfolio_angle": "Physics-based animation library"},
    "recharts": {"type": "visualization", "portfolio_angle": "Data visualization with Recharts"},
    "d3": {"type": "visualization", "portfolio_angle": "Custom data visualizations with D3"},
    "chart.js": {"type": "visualization", "portfolio_angle": "Interactive charts with Chart.js"},
    "@tanstack/react-query": {"type": "data-fetching", "portfolio_angle": "Server state management with TanStack Query"},
    "@tanstack/react-table": {"type": "data-display", "portfolio_angle": "Complex data table handling"},
    "tailwindcss": {"type": "styling", "portfolio_angle": "Utility-first CSS with Tailwind"},
    "@radix-ui/react-dialog": {"type": "ui-library", "portfolio_angle": "Accessible UI primitives with Radix"},
    "lucide-react": {"type": "icons", "portfolio_angle": "Consistent iconography with Lucide"},
    "uploadthing": {"type": "file-upload", "portfolio_angle": "File upload handling"},
    "@upstash/redis": {"type": "cache", "portfolio_angle": "Redis caching with Upstash"},
}

STYLING_SIGNATURES = {
    "tailwindcss": "tailwind",
    "styled-components": "styled_components",
    "@emotion/react": "emotion",
    "sass": "sass",
    "@vanilla-extract/css": "vanilla_extract",
}


def analyze_repo(repo_path: str) -> dict:
    """
    Perform full static analysis of a project directory.
    Returns structured analysis dict with framework, deps, integrations, patterns, quality.
    """
    repo = Path(repo_path)

    pkg_json = _load_package_json(repo)
    all_deps = _extract_all_deps(pkg_json)

    framework = _detect_framework(repo, all_deps)
    language = _detect_language(repo, pkg_json)
    package_manager = _detect_package_manager(repo)
    start_command = _detect_start_command(repo, pkg_json, framework, package_manager)
    dev_port = _detect_port(repo, framework)
    styling = _detect_styling(all_deps, repo)
    integrations = _detect_integrations(all_deps)
    patterns = _detect_patterns(repo, framework, all_deps)
    quality = _detect_quality(repo, pkg_json, all_deps)
    file_stats = _compute_file_stats(repo)

    return {
        "framework": framework,
        "language": language,
        "package_manager": package_manager,
        "start_command": start_command,
        "dev_port": dev_port,
        "styling": styling,
        "dependencies": dict(all_deps),
        "integrations": integrations,
        "patterns": patterns,
        "quality_signals": quality,
        "file_stats": file_stats,
    }


def _load_package_json(repo: Path) -> dict:
    pkg_path = repo / "package.json"
    if not pkg_path.exists():
        return {}
    try:
        with open(pkg_path, encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def _extract_all_deps(pkg: dict) -> dict:
    deps = {}
    deps.update(pkg.get("dependencies", {}))
    deps.update(pkg.get("devDependencies", {}))
    return deps


def _detect_framework(repo: Path, deps: dict) -> str:
    for name, sig in FRAMEWORK_SIGNATURES.items():
        file_match = False
        dep_match = False

        for f in sig.get("files", []):
            if (repo / f).exists():
                file_match = True
                break

        for d in sig.get("deps", []):
            if d in deps:
                dep_match = True
                break

        if file_match or dep_match:
            also = sig.get("also_requires", [])
            if also and not any(d in deps for d in also):
                continue
            return name

    if (repo / "index.html").exists():
        return "html"

    requirements = repo / "requirements.txt"
    if requirements.exists():
        try:
            content = requirements.read_text(encoding="utf-8").lower()
            if "django" in content:
                return "django"
            if "flask" in content:
                return "flask"
        except OSError:
            pass

    return "unknown"


def _detect_language(repo: Path, pkg: dict) -> str:
    if (repo / "tsconfig.json").exists():
        return "typescript"
    if pkg.get("dependencies", {}).get("typescript") or pkg.get("devDependencies", {}).get("typescript"):
        return "typescript"
    if (repo / "package.json").exists():
        return "javascript"
    if (repo / "requirements.txt").exists() or (repo / "pyproject.toml").exists():
        return "python"
    if (repo / "Gemfile").exists():
        return "ruby"
    if (repo / "go.mod").exists():
        return "go"
    if (repo / "Cargo.toml").exists():
        return "rust"
    if (repo / "pom.xml").exists() or (repo / "build.gradle").exists():
        return "java"
    if (repo / "composer.json").exists():
        return "php"
    return "unknown"


def _detect_package_manager(repo: Path) -> str:
    return _detect_package_manager_shared(str(repo))


def _detect_start_command(repo: Path, pkg: dict, framework: str, pm: str) -> str:
    scripts = pkg.get("scripts", {})

    if "dev" in scripts:
        return f"{pm} run dev" if pm in ("npm", "yarn") else f"{pm} dev"
    if "start" in scripts:
        return f"{pm} run start" if pm in ("npm", "yarn") else f"{pm} start"

    framework_defaults = {
        "next": "npx next dev",
        "vite_react": "npx vite",
        "vite_vue": "npx vite",
        "nuxt": "npx nuxi dev",
        "svelte": "npx vite dev",
        "angular": "npx ng serve",
        "django": "python manage.py runserver",
        "flask": "flask run",
    }
    return framework_defaults.get(framework, "")


def _detect_port(repo: Path, framework: str) -> int:
    framework_ports = {
        "next": 3000,
        "cra": 3000,
        "remix": 3000,
        "vite_react": 5173,
        "vite_vue": 5173,
        "nuxt": 3000,
        "svelte": 5173,
        "angular": 4200,
        "django": 8000,
        "flask": 5000,
        "gatsby": 8000,
        "astro": 4321,
        "html": 5500,
    }

    for config_name in ["next.config.js", "next.config.mjs", "next.config.ts",
                         "vite.config.js", "vite.config.ts", "vite.config.mjs"]:
        config_path = repo / config_name
        if config_path.exists():
            try:
                content = config_path.read_text(encoding="utf-8")
                port_match = re.search(r"port\s*[:=]\s*(\d+)", content)
                if port_match:
                    return int(port_match.group(1))
            except OSError:
                pass

    return framework_ports.get(framework, 3000)


def _detect_styling(deps: dict, repo: Path) -> str:
    for dep, name in STYLING_SIGNATURES.items():
        if dep in deps:
            return name

    if (repo / "tailwind.config.js").exists() or (repo / "tailwind.config.ts").exists():
        return "tailwind"

    css_modules = list(repo.rglob("*.module.css")) + list(repo.rglob("*.module.scss"))
    if css_modules:
        return "css_modules"

    return "css"


def _detect_integrations(deps: dict) -> list[dict]:
    found = []
    seen_types: set[str] = set()

    for dep_name, info in INTEGRATION_MAP.items():
        if dep_name in deps:
            if info["type"] not in seen_types:
                found.append({
                    "name": dep_name,
                    "type": info["type"],
                    "portfolio_angle": info["portfolio_angle"],
                    "version": deps.get(dep_name, ""),
                })
                seen_types.add(info["type"])

    return found


def _detect_patterns(repo: Path, framework: str, deps: dict) -> list[dict]:
    patterns = []

    if framework == "next":
        app_dir = repo / "app"
        if app_dir.is_dir():
            patterns.append({"name": "Next.js App Router", "files": ["app/"], "score": 3})

            loading_files = list(app_dir.rglob("loading.tsx")) + list(app_dir.rglob("loading.jsx"))
            if loading_files:
                patterns.append({
                    "name": "Streaming/Suspense Boundaries",
                    "files": [str(f.relative_to(repo)) for f in loading_files[:5]],
                    "score": 4,
                })

            error_files = list(app_dir.rglob("error.tsx")) + list(app_dir.rglob("error.jsx"))
            if error_files:
                patterns.append({
                    "name": "Error Boundaries",
                    "files": [str(f.relative_to(repo)) for f in error_files[:5]],
                    "score": 3,
                })

            not_found = list(app_dir.rglob("not-found.tsx")) + list(app_dir.rglob("not-found.jsx"))
            if not_found:
                patterns.append({
                    "name": "Custom 404 Pages",
                    "files": [str(f.relative_to(repo)) for f in not_found[:3]],
                    "score": 2,
                })

            api_dir = app_dir / "api"
            if api_dir.is_dir():
                route_files = list(api_dir.rglob("route.ts")) + list(api_dir.rglob("route.js"))
                if route_files:
                    patterns.append({
                        "name": "API Route Handlers",
                        "files": [str(f.relative_to(repo)) for f in route_files[:10]],
                        "score": 3,
                    })

            route_groups = [d for d in app_dir.rglob("*") if d.is_dir() and d.name.startswith("(")]
            if route_groups:
                patterns.append({
                    "name": "Route Groups",
                    "files": [str(d.relative_to(repo)) for d in route_groups[:5]],
                    "score": 3,
                })

            parallel = [d for d in app_dir.rglob("*") if d.is_dir() and d.name.startswith("@")]
            if parallel:
                patterns.append({
                    "name": "Parallel Routes",
                    "files": [str(d.relative_to(repo)) for d in parallel[:5]],
                    "score": 5,
                })

            intercepting = [d for d in app_dir.rglob("*") if d.is_dir() and d.name.startswith("(.)")]
            if intercepting:
                patterns.append({
                    "name": "Intercepting Routes",
                    "files": [str(d.relative_to(repo)) for d in intercepting[:5]],
                    "score": 5,
                })

        middleware = repo / "middleware.ts"
        if not middleware.exists():
            middleware = repo / "middleware.js"
        if middleware.exists():
            patterns.append({
                "name": "Custom Middleware",
                "files": [str(middleware.relative_to(repo))],
                "score": 3,
            })

        if (repo / "app").is_dir():
            server_action_files = []
            for ext in ("*.ts", "*.tsx", "*.js", "*.jsx"):
                for f in (repo / "app").rglob(ext):
                    try:
                        content = f.read_text(encoding="utf-8", errors="replace")
                        if "use server" in content[:200]:
                            server_action_files.append(str(f.relative_to(repo)))
                            if len(server_action_files) >= 5:
                                break
                    except OSError:
                        pass
                if len(server_action_files) >= 5:
                    break
            if server_action_files:
                patterns.append({
                    "name": "Server Actions",
                    "files": server_action_files,
                    "score": 4,
                })

    hooks_dir = None
    for candidate in ["src/hooks", "hooks", "lib/hooks", "src/lib/hooks"]:
        if (repo / candidate).is_dir():
            hooks_dir = repo / candidate
            break
    if hooks_dir:
        hook_files = [f for f in hooks_dir.iterdir() if f.is_file() and f.stem.startswith("use")]
        if hook_files:
            patterns.append({
                "name": "Custom React Hooks",
                "files": [str(f.relative_to(repo)) for f in hook_files[:10]],
                "score": 3,
            })

    for components_dir in ["src/components", "components", "app/components"]:
        comp_path = repo / components_dir
        if comp_path.is_dir():
            component_dirs = [d for d in comp_path.iterdir() if d.is_dir() and not d.name.startswith(".")]
            if len(component_dirs) >= 5:
                patterns.append({
                    "name": "Component Library",
                    "files": [str(d.relative_to(repo)) for d in component_dirs[:10]],
                    "score": 3,
                })
            break

    if (repo / "docker-compose.yml").exists() or (repo / "docker-compose.yaml").exists() or (repo / "Dockerfile").exists():
        patterns.append({"name": "Docker Configuration", "files": ["Dockerfile"], "score": 2})

    ci_files = []
    gh_workflows = repo / ".github" / "workflows"
    if gh_workflows.is_dir():
        ci_files = [str(f.relative_to(repo)) for f in gh_workflows.glob("*.yml")]
    if (repo / ".gitlab-ci.yml").exists():
        ci_files.append(".gitlab-ci.yml")
    if ci_files:
        patterns.append({"name": "CI/CD Pipeline", "files": ci_files[:5], "score": 2})

    if (repo / "turbo.json").exists() or (repo / "nx.json").exists():
        patterns.append({"name": "Monorepo Architecture", "files": ["turbo.json"], "score": 4})

    for prisma_path in [repo / "prisma" / "schema.prisma", repo / "prisma" / "schema"]:
        if prisma_path.exists():
            patterns.append({
                "name": "Prisma Database Schema",
                "files": [str(prisma_path.relative_to(repo))],
                "score": 3,
            })
            break

    return patterns


def _detect_quality(repo: Path, pkg: dict, deps: dict) -> dict:
    signals = {}

    tsconfig = repo / "tsconfig.json"
    if tsconfig.exists():
        try:
            content = tsconfig.read_text(encoding="utf-8")
            data = json.loads(re.sub(r"//.*", "", content))
            strict = data.get("compilerOptions", {}).get("strict")
            signals["typescript_strict"] = strict is True
        except (json.JSONDecodeError, OSError):
            signals["typescript_strict"] = False
    else:
        signals["typescript_strict"] = False

    signals["has_eslint"] = (
        (repo / ".eslintrc.json").exists()
        or (repo / ".eslintrc.js").exists()
        or (repo / ".eslintrc.cjs").exists()
        or (repo / "eslint.config.js").exists()
        or (repo / "eslint.config.mjs").exists()
        or "eslint" in deps
    )

    signals["has_prettier"] = (
        (repo / ".prettierrc").exists()
        or (repo / ".prettierrc.json").exists()
        or (repo / "prettier.config.js").exists()
        or (repo / "prettier.config.mjs").exists()
        or "prettier" in deps
    )

    test_extensions = ["*.test.ts", "*.test.tsx", "*.test.js", "*.test.jsx",
                       "*.spec.ts", "*.spec.tsx", "*.spec.js", "*.spec.jsx"]
    test_count = 0
    for pattern in test_extensions:
        test_count += len(list(repo.rglob(pattern)))
    signals["test_file_count"] = test_count

    signals["has_zod"] = "zod" in deps
    signals["has_env_validation"] = any(
        (repo / f).exists() for f in ["env.ts", "env.mjs", "src/env.ts", "src/env.mjs"]
    )

    signals["has_ci"] = (repo / ".github" / "workflows").is_dir() or (repo / ".gitlab-ci.yml").exists()

    return signals


def _compute_file_stats(repo: Path) -> dict:
    stats = {
        "total_files": 0,
        "ts_files": 0,
        "tsx_files": 0,
        "js_files": 0,
        "jsx_files": 0,
        "css_files": 0,
        "py_files": 0,
        "test_files": 0,
    }

    skip_dirs = {"node_modules", ".next", ".git", "dist", "build", ".cache", "__pycache__", ".venv", "venv"}

    for root, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for f in files:
            stats["total_files"] += 1
            ext = Path(f).suffix.lower()
            if ext == ".ts":
                stats["ts_files"] += 1
            elif ext == ".tsx":
                stats["tsx_files"] += 1
            elif ext == ".js":
                stats["js_files"] += 1
            elif ext == ".jsx":
                stats["jsx_files"] += 1
            elif ext in (".css", ".scss", ".sass"):
                stats["css_files"] += 1
            elif ext == ".py":
                stats["py_files"] += 1

            stem = Path(f).stem
            if ".test" in f or ".spec" in f or stem.startswith("test_"):
                stats["test_files"] += 1

    return stats
