#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


API = "https://api.github.com"


def request(method: str, url: str, token: str) -> tuple[int, object | None]:
    req = urllib.request.Request(
        url,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read()
            if not body:
                return response.status, None
            return response.status, json.loads(body.decode("utf-8"))
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"GitHub API {method} {url} failed: {error.code} {details}") from error


def parse_image(image: str) -> tuple[str, str, str]:
    if ":" not in image:
        raise SystemExit(f"Image must include a tag: {image}")

    repository, tag = image.rsplit(":", 1)
    parts = repository.split("/")
    if len(parts) != 3 or parts[0] != "ghcr.io":
        raise SystemExit(f"Expected ghcr.io/<org>/<package>:latest, got: {image}")

    return parts[1], parts[2], tag


def list_versions(org: str, package: str, token: str) -> list[dict]:
    encoded_package = urllib.parse.quote(package, safe="")
    versions: list[dict] = []
    page = 1

    while True:
        url = f"{API}/orgs/{org}/packages/container/{encoded_package}/versions?per_page=100&page={page}"
        _, data = request("GET", url, token)
        page_items = data or []
        if not isinstance(page_items, list):
            raise SystemExit(f"Unexpected GitHub API response for {package}: {page_items}")
        versions.extend(page_items)
        if len(page_items) < 100:
            return versions
        page += 1


def version_tags(version: dict) -> set[str]:
    metadata = version.get("metadata") or {}
    container = metadata.get("container") or {}
    return set(container.get("tags") or [])


def delete_version(org: str, package: str, version_id: int, token: str) -> None:
    encoded_package = urllib.parse.quote(package, safe="")
    url = f"{API}/orgs/{org}/packages/container/{encoded_package}/versions/{version_id}"
    request("DELETE", url, token)


def main() -> None:
    parser = argparse.ArgumentParser(description="Delete old GHCR package versions after publishing a fresh image.")
    parser.add_argument("--image", required=True, help="Pushed image, e.g. ghcr.io/org/edtcli:latest.")
    parser.add_argument("--keep-tag", action="append", default=[], help="Additional tag to preserve. Can be repeated.")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN"))
    args = parser.parse_args()

    if not args.token:
        raise SystemExit("GITHUB_TOKEN is required.")

    org, package, current_tag = parse_image(args.image)
    if current_tag != "latest":
        raise SystemExit("Cleanup is intentionally limited to latest-tag images.")

    keep_tags = {current_tag, *args.keep_tag}

    versions = list_versions(org, package, args.token)
    to_delete: list[tuple[int, set[str]]] = []

    for version in versions:
        tags = version_tags(version)
        if tags & keep_tags:
            continue
        to_delete.append((int(version["id"]), tags))

    for version_id, tags in to_delete:
        label = ",".join(sorted(tags)) if tags else "<untagged>"
        action = "would delete" if args.dry_run else "delete"
        print(f"{action} {org}/{package} version {version_id} tags={label}", flush=True)
        if not args.dry_run:
            delete_version(org, package, version_id, args.token)
            time.sleep(0.25)

    print(f"kept tags: {', '.join(sorted(keep_tags))}", flush=True)
    print(f"deleted versions: {len(to_delete)}", flush=True)


if __name__ == "__main__":
    main()
