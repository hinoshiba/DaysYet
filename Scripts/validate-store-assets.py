#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import struct
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "http_dist"
STORE = ROOT / "AppStore"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: Path) -> str:
    if not path.is_file():
        fail(f"missing file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8").strip()


class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag not in {"a", "link"}:
            return
        for key, value in attrs:
            if key == "href" and value:
                self.links.append(value)


def validate_site() -> None:
    required_pages = [
        "index.html", "en/index.html", "privacy/index.html", "en/privacy/index.html",
        "terms/index.html", "en/terms/index.html", "support/index.html", "en/support/index.html",
        "accessibility/index.html", "en/accessibility/index.html",
    ]
    forbidden = ["PLACEHOLDER", "TODO", "TBD", "Provisional brand", "Terms · Draft", "公開準備中"]
    for relative in required_pages:
        page = SITE / relative
        content = read(page)
        expected_lang = 'lang="en"' if relative.startswith("en/") else 'lang="ja"'
        if expected_lang not in content:
            fail(f"incorrect or missing html language: http_dist/{relative}")
        for marker in forbidden:
            if marker in content:
                fail(f"release placeholder in http_dist/{relative}: {marker}")
        if 'hreflang="ja"' not in content or 'hreflang="en"' not in content:
            fail(f"missing ja/en alternate links: http_dist/{relative}")

        parser = LinkParser()
        parser.feed(content)
        for href in parser.links:
            parts = urlsplit(href)
            if parts.scheme or parts.netloc or href.startswith("#"):
                continue
            path = parts.path
            if not path:
                continue
            target = (page.parent / path).resolve()
            if path.endswith("/"):
                target /= "index.html"
            if SITE.resolve() not in target.parents and target != SITE.resolve():
                fail(f"local link escapes http_dist in {relative}: {href}")
            if not target.exists():
                fail(f"broken local link in {relative}: {href}")


def validate_catalog() -> None:
    path = ROOT / "Shared/Localizable.xcstrings"
    try:
        catalog = json.loads(read(path))
    except json.JSONDecodeError as error:
        fail(f"invalid String Catalog JSON: {error}")
    if catalog.get("sourceLanguage") != "ja":
        fail("Shared/Localizable.xcstrings must use Japanese as sourceLanguage")
    for key, entry in catalog.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        for locale in ("ja", "en"):
            unit = localizations.get(locale, {}).get("stringUnit", {})
            if unit.get("state") != "translated" or not unit.get("value"):
                fail(f"incomplete {locale} translation for String Catalog key: {key}")


def validate_metadata() -> None:
    limits = {
        "name.txt": (30, "characters"),
        "subtitle.txt": (30, "characters"),
        "promotional_text.txt": (170, "characters"),
        "description.txt": (4000, "characters"),
        "keywords.txt": (100, "bytes"),
        "release_notes.txt": (4000, "characters"),
    }
    required = list(limits) + [
        "support_url.txt", "marketing_url.txt", "privacy_url.txt", "accessibility_url.txt"
    ]
    configuration = read(STORE / "configuration.yml")
    initial_release = "initial_release: true" in configuration
    for locale in ("ja", "en-US"):
        directory = STORE / "metadata" / locale
        for filename in required:
            value = read(directory / filename)
            if filename in limits:
                maximum, unit = limits[filename]
                length = len(value.encode("utf-8")) if unit == "bytes" else len(value)
                if length > maximum:
                    fail(f"{locale}/{filename} is {length} {unit}; maximum is {maximum}")
            if filename.endswith("_url.txt") and not value.startswith("https://"):
                fail(f"{locale}/{filename} must use https")
            if filename == "keywords.txt":
                terms = [term.strip() for term in value.split(",")]
                if any(len(term) <= 2 for term in terms):
                    fail(f"{locale}/{filename} contains a keyword shorter than 3 characters")
            if filename == "release_notes.txt" and initial_release and value:
                fail(f"{locale}/{filename} must be empty for the first App Store version")

    for expected in (
        "primary_locale: ja", "bundle_id: com.hinoshiba.daysyet",
        "widget_bundle_id: com.hinoshiba.daysyet.widget",
        "app_group: group.com.hinoshiba.daysyet",
    ):
        if expected not in configuration:
            fail(f"AppStore/configuration.yml is missing: {expected}")


def png_properties(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()
    if len(data) < 26 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        fail(f"not a valid PNG screenshot: {path.relative_to(ROOT)}")
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    return width, height, color_type


def validate_screenshots() -> None:
    accepted = {
        "iphone-6.9": {(1260, 2736), (1290, 2796), (1320, 2868)},
        "ipad-13": {(2064, 2752), (2048, 2732)},
    }
    for locale in ("ja", "en-US"):
        for device, dimensions in accepted.items():
            directory = STORE / "screenshots" / locale / device
            images = sorted(directory.glob("*.png")) if directory.is_dir() else []
            if not 1 <= len(images) <= 10:
                fail(f"{directory.relative_to(ROOT)} must contain 1–10 PNG screenshots")
            for image in images:
                width, height, color_type = png_properties(image)
                if (width, height) not in dimensions:
                    fail(f"unsupported dimensions {width}x{height}: {image.relative_to(ROOT)}")
                if color_type in {4, 6}:
                    fail(f"alpha channel is not allowed: {image.relative_to(ROOT)}")


def validate_public_urls() -> None:
    for locale in ("ja", "en-US"):
        for filename in ("support_url.txt", "marketing_url.txt", "privacy_url.txt", "accessibility_url.txt"):
            url = read(STORE / "metadata" / locale / filename)
            request = Request(url, headers={"User-Agent": "DaysYet-release-validator/1"})
            try:
                with urlopen(request, timeout=15) as response:
                    status = response.status
                    final_url = response.url
            except Exception as error:
                fail(f"public URL is unreachable ({locale}/{filename}): {error}")
            if status != 200:
                fail(f"public URL returned HTTP {status} ({locale}/{filename}): {url}")
            if final_url.rstrip("/") != url.rstrip("/"):
                fail(f"public URL redirects ({locale}/{filename}): {url} -> {final_url}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site-only", action="store_true")
    parser.add_argument("--require-screenshots", action="store_true")
    parser.add_argument("--check-urls", action="store_true")
    args = parser.parse_args()
    validate_site()
    if not args.site_only:
        validate_catalog()
        validate_metadata()
        if args.require_screenshots:
            validate_screenshots()
        if args.check_urls:
            validate_public_urls()
    print("Release asset validation passed.")


if __name__ == "__main__":
    main()
