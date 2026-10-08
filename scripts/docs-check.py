#!/usr/bin/env python3
"""Compile every Swift example in the docs against the SDK, as an app would.

The docs are only worth reading if their code compiles: a wiki written beside the
SDK in 2025 documented dozens of APIs that never existed. This builds the
LuxAnalytics module once, then typechecks each ```swift block in README.md and
docs/*.md as its own file that imports LuxAnalytics, so only public API is
visible. Any error fails the check, with the page and line.

A block that isn't app code (a Package.swift manifest, say) opts out with an
explicit ```swift ignore fence.

API listings use a ```swift interface fence. Those aren't compiled; instead every
declaration line in them must appear in the SDK's compiler-emitted public interface
(module qualifiers and attributes aside), so a listed signature can't be invented
or go stale.

Relative links in the docs (and their #anchors, slugged the way GitHub slugs
headings) must resolve too, including the docs URL the SDK prints in its
not-initialized fatalError.

Usage: scripts/docs-check.py            (run from the repo root; needs Xcode)
"""

import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TARGET = "arm64-apple-ios18.0-simulator"
SWIFTC = ["xcrun", "-sdk", "iphonesimulator", "swiftc", "-target", TARGET, "-swift-version", "6"]
HEADER = "import Foundation\nimport SwiftUI\nimport UIKit\nimport LuxAnalytics\n"
FENCE = re.compile(r"^```swift([^\n]*)\n(.*?)^```", re.S | re.M)


def blocks(page: Path, kind: str = "") -> list[tuple[int, str]]:
    """The page's ```swift blocks of one kind: "" (compiled examples) or "interface"."""
    text = page.read_text()
    found = []
    for m in FENCE.finditer(text):
        words = m.group(1).split()
        if "ignore" in words or (kind not in words if kind else "interface" in words):
            continue
        line = text.count("\n", 0, m.start(2)) + 1
        found.append((line, m.group(2)))
    return found


QUALIFIER = re.compile(r"\b(?:Swift|Foundation|_Concurrency|UIKit|LuxAnalytics)\.(?=[A-Za-z_])")


def normalize(decl: str) -> str:
    decl = QUALIFIER.sub("", decl)
    decl = re.sub(r"@[A-Za-z_.]+(\([^)]*\))?\s*", "", decl)
    decl = re.sub(r"\b(final|nonisolated)\s+", "", decl)
    decl = re.sub(r"\s+", " ", decl).strip()
    return decl.removesuffix("{").strip()


def interface_declarations(interface: Path) -> set[str]:
    return {normalize(line) for line in interface.read_text().splitlines() if line.strip()}


def check_interface(page: Path, line: int, code: str, declared: set[str]) -> list[str]:
    errors = []
    for i, raw in enumerate(code.splitlines()):
        decl = normalize(raw.split("//")[0])
        if decl in ("", "}") or decl.startswith("//"):
            continue
        if decl not in declared:
            errors.append(f"{page}:{line + i}: not in the SDK's public interface: {decl}")
    return errors


LINK = re.compile(r"\]\(([^)\s]+)\)")
DOCS_URL = "https://github.com/luxardolabs/luxanalytics-swift/blob/main/"


def slug(heading: str) -> str:
    text = heading.strip().lower().replace("`", "")
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def anchors(page: Path) -> set[str]:
    text = re.sub(r"^```.*?^```", "", page.read_text(), flags=re.S | re.M)
    return {slug(h) for h in re.findall(r"^#{1,6} (.+)$", text, re.M)}


def check_link(source: str, target: str) -> str | None:
    path, _, anchor = target.partition("#")
    page = (Path(source).parent / path).resolve() if path else Path(source).resolve()
    if not page.exists():
        return f"{source}: broken link {target}"
    if anchor and page.suffix == ".md" and anchor not in anchors(page):
        return f"{source}: no heading for #{anchor} in {page.relative_to(Path.cwd())}"
    return None


def check_links(pages: list[Path]) -> list[str]:
    errors = []
    for page in pages:
        for target in LINK.findall(page.read_text()):
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            if (error := check_link(str(page), target)):
                errors.append(error)
    # The URL the SDK's fatalError points developers to.
    for src in Path("Sources/LuxAnalytics").glob("*.swift"):
        for url in re.findall(re.escape(DOCS_URL) + r"([^\s\"]+)", src.read_text()):
            if (error := check_link("README.md", url)):
                errors.append(f"{src} (docs URL): {error}")
    return errors


def build_module(out: Path) -> None:
    """The module examples compile against, built as a SwiftPM adopter builds it (from
    source, no library evolution), and separately the public interface listings are
    checked against. The interface needs library evolution, which also makes the SDK's
    enums non-frozen, so it gets its own build rather than changing what examples see."""
    sources = sorted(str(p) for p in Path("Sources/LuxAnalytics").glob("*.swift"))
    common = SWIFTC + ["-parse-as-library", "-emit-module", "-module-name", "LuxAnalytics"]
    builds = [
        [*common, "-emit-module-path", str(out / "LuxAnalytics.swiftmodule"), *sources],
        [*common, "-enable-library-evolution", "-no-verify-emitted-module-interface",
         "-emit-module-path", str(out / "interface" / "LuxAnalytics.swiftmodule"),
         "-emit-module-interface-path", str(out / "LuxAnalytics.swiftinterface"), *sources],
    ]
    (out / "interface").mkdir()
    for cmd in builds:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(f"docs-check: the SDK itself doesn't build:\n{result.stderr}")


def check(job: tuple[Path, int, str, Path, Path]) -> list[str]:
    page, line, code, work, module = job
    # A block with @main is a library file; anything else may use top-level code.
    name = "Example.swift" if "@main" in code else "main.swift"
    src = work / name
    src.write_text(HEADER + code)
    cmd = SWIFTC + ["-typecheck", "-I", str(module), str(src)]
    if name != "main.swift":
        cmd.insert(-1, "-parse-as-library")
    result = subprocess.run(cmd, capture_output=True, text=True)
    errors = []
    for err in re.findall(rf"{re.escape(name)}:(\d+):\d+: error: (.*)", result.stderr):
        doc_line = line + int(err[0]) - 1 - HEADER.count("\n")
        errors.append(f"{page}:{doc_line}: {err[1]}")
    if result.returncode != 0 and not errors:
        errors.append(f"{page}:{line}: block failed to typecheck:\n{result.stderr.strip()}")
    return errors


def main() -> int:
    pages = [Path("README.md"), *sorted(Path("docs").glob("*.md"))]
    link_pages = [*pages, Path("CHANGELOG.md"), Path("CONTRIBUTING.md")]
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        module = root / "module"
        module.mkdir()
        build_module(module)
        jobs = []
        for page in pages:
            for i, (line, code) in enumerate(blocks(page)):
                work = root / f"{page.stem}-{i}"
                work.mkdir()
                jobs.append((page, line, code, work, module))
        with ThreadPoolExecutor(max_workers=8) as pool:
            errors = [e for result in pool.map(check, jobs) for e in result]
        declared = interface_declarations(module / "LuxAnalytics.swiftinterface")
        listings = 0
        for page in pages:
            for line, code in blocks(page, "interface"):
                listings += 1
                errors += check_interface(page, line, code, declared)
    errors += check_links(link_pages)
    for e in errors:
        print(f"❌ {e}")
    if errors:
        print(f"🔴 docs-check: {len(errors)} error(s) in {len(jobs)} Swift examples and {listings} API listings")
        return 1
    print(f"🟢 docs-check: {len(jobs)} Swift examples compile and {listings} API listings match the SDK"
          f" ({len(pages)} pages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
