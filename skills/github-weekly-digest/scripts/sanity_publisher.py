"""
sanity_publisher.py — Publish digest posts as drafts to Sanity CMS.

Supports both weeklyDigest and dailyDigest document types.
Never auto-publishes — always creates as draft for human review.

Key fixes from audit:
- createIfNotExists by default (won't overwrite manual edits)
- --force flag switches to createOrReplace
- _key() uses full UUID (no truncation, no collision risk)
- dailyDigest support for daily cadence
- weeklyDigest links back to dailyDigest docs via dailyRefs
"""

import uuid
from datetime import datetime, timezone

import requests

from scripts.narrative_writer import DigestPost
from scripts.shared_utils import get_logger

log = get_logger("publisher")


class SanityPublisher:
    def __init__(self, config: dict):
        self.project_id = config["sanity_project_id"]
        self.dataset = config["sanity_dataset"]
        self.token = config["sanity_token"]
        self.api_version = config.get("sanity_api_version", "2024-01-01")
        self._mutate_url = (
            f"https://{self.project_id}.api.sanity.io"
            f"/v{self.api_version}/data/mutate/{self.dataset}"
        )
        self._query_url = (
            f"https://{self.project_id}.api.sanity.io"
            f"/v{self.api_version}/data/query/{self.dataset}"
        )
        self._headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }

    def publish(self, post: DigestPost, force: bool = False) -> str:
        """
        Create a draft document in Sanity.
        Returns the document _id.

        force=False (default): uses createIfNotExists — safe, won't overwrite manual edits.
        force=True: uses createOrReplace — overwrites any existing draft.
        """
        if post.cadence == "daily":
            doc_id = f"drafts.dailyDigest-{post.date}"
            document = self._build_daily_document(post, doc_id)
        else:
            doc_id = f"drafts.weeklyDigest-{post.week_of}"
            document = self._build_weekly_document(post, doc_id)

        if force:
            mutation_type = "createOrReplace"
        else:
            mutation_type = "createIfNotExists"

        mutation = {"mutations": [{mutation_type: document}]}

        log.info(f"Publishing draft to Sanity [{mutation_type}]: {doc_id}")
        response = requests.post(
            self._mutate_url,
            headers=self._headers,
            json=mutation,
            timeout=30,
        )

        if response.status_code not in (200, 201):
            raise RuntimeError(
                f"Sanity publish failed ({response.status_code}): {response.text[:500]}"
            )

        result = response.json()

        # Detect if createIfNotExists was a no-op (doc already existed)
        results = result.get("results", [])
        if results and results[0].get("operation") == "none":
            log.warning(
                f"  Draft already exists: {doc_id}\n"
                f"  No changes made. Use --force to overwrite."
            )
        else:
            log.info(f"  ✓ Draft created: {doc_id}")

        studio_path = "dailyDigest" if post.cadence == "daily" else "weeklyDigest"
        log.info(
            f"  Review: https://{self.project_id}.sanity.studio"
            f"/desk/{studio_path};{doc_id}"
        )
        return doc_id

    def _build_weekly_document(self, post: DigestPost, doc_id: str) -> dict:
        doc = {
            "_id": doc_id,
            "_type": "weeklyDigest",
            "title": post.title,
            "slug": {"_type": "slug", "current": post.slug},
            "weekOf": post.week_of,
            "weekLabel": post.period_label,
            "excerpt": post.excerpt,
            "publishedAt": datetime.now(timezone.utc).isoformat(),
            "tags": post.tags,
            "body": _markdown_to_portable_text(post.body_markdown),
            "stats": post.stats,
            "projects": [
                {
                    "_key": _key(),
                    "repoName": p["repoName"],
                    "projectType": p["projectType"],
                    "summary": p["summary"],
                    "skillsDemonstrated": p["skillsDemonstrated"],
                    "url": p.get("url", ""),
                }
                for p in post.projects
            ],
        }
        # Link back to daily draft documents if this is a rollup
        if post.daily_refs:
            doc["dailyRefs"] = [
                {"_type": "reference", "_ref": ref, "_key": _key()}
                for ref in post.daily_refs
            ]
        return doc

    def _build_daily_document(self, post: DigestPost, doc_id: str) -> dict:
        return {
            "_id": doc_id,
            "_type": "dailyDigest",
            "title": post.title,
            "slug": {"_type": "slug", "current": post.slug},
            "date": post.date,
            "weekOf": post.week_of,
            "excerpt": post.excerpt,
            "publishedAt": datetime.now(timezone.utc).isoformat(),
            "tags": post.tags,
            "body": _markdown_to_portable_text(post.body_markdown),
            "stats": post.stats,
        }

    def test_connection(self) -> bool:
        """Test Sanity API connectivity. Returns True on success."""
        resp = requests.get(
            self._query_url,
            params={"query": '*[_type=="weeklyDigest"][0]._id'},
            headers=self._headers,
            timeout=10,
        )
        return resp.status_code == 200


# ── Portable Text conversion ──────────────────────────────────────────────────

def _markdown_to_portable_text(markdown: str) -> list[dict]:
    """
    Convert markdown to Sanity Portable Text blocks.
    Handles: ##/### headings, paragraphs, bullet/dash lists.
    """
    blocks: list[dict] = []
    lines = markdown.strip().split("\n")
    list_items: list[str] = []

    def flush_list() -> None:
        nonlocal list_items
        for item in list_items:
            blocks.append({
                "_type": "block",
                "_key": _key(),
                "style": "normal",
                "listItem": "bullet",
                "level": 1,
                "markDefs": [],
                "children": [{"_type": "span", "_key": _key(), "text": item, "marks": []}],
            })
        list_items = []

    for line in lines:
        line = line.rstrip()
        if not line:
            flush_list()
        elif line.startswith("### "):
            flush_list()
            blocks.append(_heading_block(line[4:].strip(), "h3"))
        elif line.startswith("## "):
            flush_list()
            blocks.append(_heading_block(line[3:].strip(), "h2"))
        elif line.startswith("# "):
            flush_list()
            blocks.append(_heading_block(line[2:].strip(), "h1"))
        elif line.startswith("- ") or line.startswith("* "):
            list_items.append(line[2:].strip())
        elif line.startswith("---"):
            flush_list()  # HR: skip (no native Sanity equivalent)
        else:
            flush_list()
            if line.strip():
                blocks.append(_paragraph_block(line.strip()))

    flush_list()
    return blocks


def _heading_block(text: str, style: str) -> dict:
    return {
        "_type": "block",
        "_key": _key(),
        "style": style,
        "markDefs": [],
        "children": [{"_type": "span", "_key": _key(), "text": text, "marks": []}],
    }


def _paragraph_block(text: str) -> dict:
    return {
        "_type": "block",
        "_key": _key(),
        "style": "normal",
        "markDefs": [],
        "children": [{"_type": "span", "_key": _key(), "text": text, "marks": []}],
    }


def _key() -> str:
    """Generate a unique key for Sanity block _key fields. Full UUID — no truncation."""
    return str(uuid.uuid4()).replace("-", "")
