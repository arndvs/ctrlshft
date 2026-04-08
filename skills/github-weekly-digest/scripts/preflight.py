"""
preflight.py — Validate all config and API connections before running.

Usage:
    python -m scripts.preflight --config config.json
"""

import argparse
import sys
from pathlib import Path

from scripts.shared_utils import load_config, get_logger

log = get_logger("preflight")


def run_preflight(config_path: str) -> bool:
    print("=" * 55)
    print("GitHub Digest — Pre-flight Check")
    print("=" * 55)

    try:
        config = load_config(config_path)
        print("  ✓ config.json valid")
    except (FileNotFoundError, ValueError) as e:
        print(f"  ✗ config.json: {e}")
        return False

    errors = []

    # 1. .gitignore check
    gitignore = Path(".gitignore")
    if not gitignore.exists():
        print("  ⚠  .gitignore missing — copy assets/.gitignore to project root to avoid committing secrets")
    elif "config.json" not in gitignore.read_text():
        print("  ⚠  .gitignore exists but doesn't list config.json — add it to prevent secret leaks")
    else:
        print("  ✓ .gitignore present and covers config.json")

    # 2. GitHub
    try:
        from github import Github
        gh = Github(config["github_token"])
        user = gh.get_user(config["github_username"])
        repo_count = user.public_repos
        print(f"  ✓ GitHub API: @{config['github_username']} ({repo_count} public repos)")
        if config.get("include_orgs"):
            for org_name in config["include_orgs"]:
                try:
                    gh.get_organization(org_name)
                    print(f"  ✓ GitHub org: {org_name}")
                except Exception as e:
                    errors.append(f"GitHub org '{org_name}' not accessible: {e}")
    except ImportError:
        errors.append("PyGithub not installed. Run: pip install PyGithub")
    except Exception as e:
        errors.append(f"GitHub API failed: {e}")

    # 3. Anthropic
    try:
        import anthropic
        anthropic.Anthropic(api_key=config["anthropic_api_key"])
        model = config.get("ai_model", "claude-sonnet-4-6")
        print(f"  ✓ Anthropic API: key configured (model: {model})")
    except ImportError:
        errors.append("anthropic not installed. Run: pip install anthropic")
    except Exception as e:
        errors.append(f"Anthropic config failed: {e}")

    # 4. Sanity
    try:
        from scripts.sanity_publisher import SanityPublisher
        publisher = SanityPublisher(config)
        if publisher.test_connection():
            print(
                f"  ✓ Sanity API: project={config['sanity_project_id']} "
                f"dataset={config['sanity_dataset']}"
            )
        else:
            errors.append(
                "Sanity API returned non-200. Check project_id, dataset, token, "
                "and that the token has Editor permissions."
            )
    except Exception as e:
        errors.append(f"Sanity connection failed: {e}")

    # 5. Prompt templates
    from pathlib import Path as _Path
    pt = _Path("references/prompt_templates.md")
    if pt.exists():
        content = pt.read_text()
        for section in ("WEEKLY_NARRATIVE_PROMPT", "DAILY_NARRATIVE_PROMPT", "REPO_ANALYSIS_PROMPT"):
            if f"<!-- {section}_START -->" in content:
                print(f"  ✓ Prompt: {section}")
            else:
                print(f"  ⚠  Prompt section {section} not found in prompt_templates.md (builtin will be used)")
    else:
        print("  ⚠  references/prompt_templates.md not found (builtin prompts will be used)")

    # 6. Output directory
    try:
        from scripts.shared_utils import ensure_output_dir
        out = ensure_output_dir(config)
        print(f"  ✓ Output directory: {out}")
    except Exception as e:
        errors.append(f"Could not create output directory: {e}")

    # 7. private_repos config
    private_mode = config.get("private_repos", "include")
    valid_modes = ("include", "skip", "summarize_only")
    if private_mode not in valid_modes:
        errors.append(f"private_repos must be one of {valid_modes}, got: '{private_mode}'")
    else:
        print(f"  ✓ Private repos mode: {private_mode}")

    print()
    if errors:
        print("ERRORS — fix before running:")
        for e in errors:
            print(f"  ✗ {e}")
        print()
        print("Pre-flight FAILED.")
        return False

    print("Pre-flight PASSED. Ready to run:")
    print("  python -m scripts.run_digest --config config.json")
    print("  python -m scripts.run_digest --config config.json --cadence daily")
    print("  python -m scripts.run_digest --config config.json --cadence rollup")
    return True


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pre-flight check for GitHub Digest")
    parser.add_argument("--config", default="config.json")
    args = parser.parse_args()
    ok = run_preflight(args.config)
    sys.exit(0 if ok else 1)
