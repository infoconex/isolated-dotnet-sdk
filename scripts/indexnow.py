#!/usr/bin/env python3
"""Submit published Coding URLs to IndexNow.

Usage:
  python3 scripts/indexnow.py --all
      Submit every URL in the deployed sitemap. Intended for an initial
      backfill or an explicit manual workflow run.

  python3 scripts/indexnow.py
      Submit only URLs affected between BASE_SHA and HEAD_SHA.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import PurePosixPath
from urllib.parse import urljoin, urlparse

INDEXNOW_ENDPOINT = "https://api.indexnow.org/indexnow"
BATCH_SIZE = 10_000
AGGREGATE_URLS = ("/", "/docs/")
SITE_WIDE_PREFIXES = ("_layouts/", "_data/", "assets/")
SITE_WIDE_FILES = {"_config.yml", "search-index.json", "scripts/pages_seo.py"}
IGNORED_PREFIXES = (".github/", "scripts/", "tests/", ".config/")


def run_git(*args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        check=check,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout


def git_file(ref: str, path: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    return result.stdout if result.returncode == 0 else None


def parse_front_matter(text: str | None) -> dict[str, str]:
    if not text or not text.startswith("---"):
        return {}

    match = re.match(r"^---\s*\n(.*?)\n---(?:\s*\n|$)", text, re.DOTALL)
    if not match:
        return {}

    values: dict[str, str] = {}
    for raw_line in match.group(1).splitlines():
        if ":" not in raw_line or raw_line.lstrip().startswith("#"):
            continue
        key, value = raw_line.split(":", 1)
        value = value.strip().strip('"\'')
        values[key.strip()] = value
    return values


def is_published(front_matter: dict[str, str]) -> bool:
    return front_matter.get("published", "true").strip().lower() not in {
        "false",
        "no",
        "0",
    }


def normalize_site_url(site_url: str) -> str:
    return site_url.rstrip("/") + "/"


def absolute_url(site_url: str, path: str) -> str:
    return urljoin(normalize_site_url(site_url), path.lstrip("/"))


def inferred_page_path(repo_path: str, front_matter: dict[str, str]) -> str | None:
    permalink = front_matter.get("permalink")
    if permalink:
        return permalink
    if repo_path == "README.md":
        return "/"
    if repo_path == "CHANGELOG.md":
        return "/CHANGELOG.html"
    if repo_path == "docs/README.md":
        return "/docs/"
    if repo_path.startswith("docs/") and repo_path.endswith("/README.md"):
        return "/" + repo_path[:-len("README.md")]
    if repo_path.startswith("docs/") and repo_path.endswith(".md"):
        return "/" + repo_path[:-3] + ".html"
    return None


def url_for_version(site_url: str, ref: str, repo_path: str) -> tuple[str | None, bool]:
    text = git_file(ref, repo_path)
    if text is None:
        return None, False
    front_matter = parse_front_matter(text)
    page_path = inferred_page_path(repo_path, front_matter)
    return (
        absolute_url(site_url, page_path) if page_path else None,
        is_published(front_matter),
    )


def changed_paths(base_sha: str, head_sha: str) -> list[tuple[str, list[str]]]:
    output = run_git("diff", "--name-status", base_sha, head_sha)
    changes: list[tuple[str, list[str]]] = []
    for line in output.splitlines():
        if not line.strip():
            continue
        fields = line.split("\t")
        status = fields[0]
        paths = fields[1:]
        changes.append((status, paths))
    return changes


def collect_changed_urls(site_url: str, base_sha: str, head_sha: str) -> tuple[set[str], bool]:
    urls: set[str] = set()
    for status, paths in changed_paths(base_sha, head_sha):
        if any(path in SITE_WIDE_FILES or path.startswith(SITE_WIDE_PREFIXES) for path in paths):
            return set(), True
        for repo_path in paths:
            if repo_path.startswith(IGNORED_PREFIXES):
                continue
            current_url, current_published = url_for_version(site_url, head_sha, repo_path)
            previous_url, previous_published = url_for_version(site_url, base_sha, repo_path)
            if current_url and current_published:
                urls.add(current_url)
            if previous_url and previous_published and (previous_url != current_url or not current_published):
                urls.add(previous_url)
    return urls, False


def sitemap_urls(site_url: str) -> set[str]:
    sitemap_url = absolute_url(site_url, "/sitemap.xml")
    request = urllib.request.Request(
        sitemap_url,
        headers={"User-Agent": "isolated-dotnet-sdk-indexnow/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        xml_bytes = response.read()

    root = ET.fromstring(xml_bytes)
    urls = {
        element.text.strip()
        for element in root.findall(".//{*}loc")
        if element.text and element.text.strip()
    }

    site_host = urlparse(site_url).netloc.lower()
    return {
        url
        for url in urls
        if urlparse(url).netloc.lower() == site_host
    }


def submit_urls(site_url: str, key: str, key_location: str, urls: set[str]) -> None:
    ordered_urls = sorted(urls)
    if not ordered_urls:
        print("IndexNow: no page URLs changed; nothing to submit.")
        return

    host = urlparse(site_url).netloc
    total = len(ordered_urls)

    for start in range(0, total, BATCH_SIZE):
        batch = ordered_urls[start : start + BATCH_SIZE]
        payload = json.dumps(
            {
                "host": host,
                "key": key,
                "keyLocation": key_location,
                "urlList": batch,
            }
        ).encode("utf-8")

        request = urllib.request.Request(
            INDEXNOW_ENDPOINT,
            data=payload,
            method="POST",
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "User-Agent": "isolated-dotnet-sdk-indexnow/1.0",
            },
        )

        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                status = response.status
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", "replace")
            print(
                f"IndexNow submission failed: HTTP {error.code}: {body}",
                file=sys.stderr,
            )
            raise

        if status not in {200, 202}:
            raise RuntimeError(f"Unexpected IndexNow response: HTTP {status}")

        print(
            f"IndexNow: submitted {len(batch)} URL(s) "
            f"({start + 1}-{start + len(batch)} of {total}); HTTP {status}."
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--all",
        action="store_true",
        help="Submit all URLs currently present in the deployed sitemap.",
    )
    args = parser.parse_args()

    site_url = os.environ.get("INDEXNOW_SITE_URL", "https://isolated-dotnet-sdk.infoconex.com")
    key = os.environ.get("INDEXNOW_KEY", "").strip()
    key_location = os.environ.get("INDEXNOW_KEY_LOCATION", "").strip()

    if not key:
        raise RuntimeError("INDEXNOW_KEY is required")
    if not key_location:
        key_location = absolute_url(site_url, f"/{key}.txt")

    if args.all:
        urls = sitemap_urls(site_url)
        print(f"IndexNow backfill: sitemap contains {len(urls)} URL(s).")
    else:
        base_sha = os.environ.get("BASE_SHA", "").strip()
        head_sha = os.environ.get("HEAD_SHA", "HEAD").strip()
        if not base_sha or set(base_sha) == {"0"}:
            print("IndexNow: no usable base SHA; using sitemap backfill.")
            urls = sitemap_urls(site_url)
        else:
            urls, site_wide = collect_changed_urls(site_url, base_sha, head_sha)
            if site_wide:
                print("IndexNow: site-wide source changed; submitting deployed sitemap.")
                urls = sitemap_urls(site_url)

    submit_urls(site_url, key, key_location, urls)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
