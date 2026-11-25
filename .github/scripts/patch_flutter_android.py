#!/usr/bin/env python3
"""Apply the release-required Android settings to Flutter's generated wrapper."""

from __future__ import annotations

import argparse
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
ANDROID_NAME = f"{{{ANDROID_NS}}}name"
ANDROID_LABEL = f"{{{ANDROID_NS}}}label"
ANDROID_SCHEME = f"{{{ANDROID_NS}}}scheme"
REQUIRED_PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
)
VIEW_ACTION = "android.intent.action.VIEW"
MAPS_PACKAGE = "com.google.android.apps.maps"
APP_LABEL = "بازاڕی یوسف"

ET.register_namespace("android", ANDROID_NS)


def _parse_manifest(path: Path) -> tuple[ET.ElementTree, ET.Element]:
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
    tree = ET.parse(path, parser=parser)
    root = tree.getroot()
    if root.tag != "manifest":
        raise ValueError(f"Expected <manifest> root in {path}")
    return tree, root


def _queries_intent_exists(queries: ET.Element, scheme: str) -> bool:
    for intent in queries.findall("intent"):
        action = intent.find("action")
        if action is None or action.get(ANDROID_NAME) != VIEW_ACTION:
            continue
        if any(data.get(ANDROID_SCHEME) == scheme for data in intent.findall("data")):
            return True
    return False


def patch_manifest(path: Path) -> None:
    tree, root = _parse_manifest(path)
    application = root.find("application")
    if application is None:
        raise ValueError(f"Expected <application> in {path}")

    # Keep manifest declarations in the conventional order: permissions, queries,
    # then application. Preserve any generated or plugin-provided declarations.
    queries = root.find("queries")
    if queries is None:
        queries = ET.Element("queries")
        root.insert(list(root).index(application), queries)
    elif list(root).index(queries) > list(root).index(application):
        root.remove(queries)
        root.insert(list(root).index(application), queries)

    insert_at = list(root).index(queries)
    existing_permissions = {
        element.get(ANDROID_NAME)
        for element in root.findall("uses-permission")
    }
    for permission in REQUIRED_PERMISSIONS:
        if permission in existing_permissions:
            continue
        root.insert(
            insert_at,
            ET.Element("uses-permission", {ANDROID_NAME: permission}),
        )
        insert_at += 1

    for scheme in ("https", "tel", "geo"):
        if _queries_intent_exists(queries, scheme):
            continue
        intent = ET.SubElement(queries, "intent")
        ET.SubElement(intent, "action", {ANDROID_NAME: VIEW_ACTION})
        ET.SubElement(intent, "data", {ANDROID_SCHEME: scheme})

    if not any(package.get(ANDROID_NAME) == MAPS_PACKAGE for package in queries.findall("package")):
        ET.SubElement(queries, "package", {ANDROID_NAME: MAPS_PACKAGE})

    application.set(ANDROID_LABEL, APP_LABEL)
    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)

    # Validate the emitted XML and required contract before Gradle starts.
    _, updated = _parse_manifest(path)
    updated_application = updated.find("application")
    updated_queries = updated.find("queries")
    permissions = {
        element.get(ANDROID_NAME)
        for element in updated.findall("uses-permission")
    }
    if not set(REQUIRED_PERMISSIONS).issubset(permissions):
        raise ValueError(f"Required Android permissions are missing from {path}")
    if updated_application is None or updated_application.get(ANDROID_LABEL) != APP_LABEL:
        raise ValueError(f"Kurdish application label was not applied in {path}")
    if updated_queries is None:
        raise ValueError(f"<queries> was not applied in {path}")
    if not all(_queries_intent_exists(updated_queries, scheme) for scheme in ("https", "tel", "geo")):
        raise ValueError(f"Required URL query intents are missing from {path}")
    if not any(package.get(ANDROID_NAME) == MAPS_PACKAGE for package in updated_queries.findall("package")):
        raise ValueError(f"Google Maps package query is missing from {path}")


def _sdk_pattern(setting: str) -> re.Pattern[str]:
    return re.compile(
        rf"(?m)^(?P<indent>[ \t]*)(?:{setting})(?P<separator>[ \t]*=[ \t]*|[ \t]+)(?P<value>[^\r\n]+)$"
    )


def _expression_meets_floor(expression: str, floor: int) -> bool:
    value = expression.strip()
    if value.isdigit():
        return int(value) >= floor
    maximum = re.fullmatch(r"(?:maxOf|Math\.max)\(.*,[ \t]*(\d+)[ \t]*\)", value)
    return maximum is not None and int(maximum.group(1)) >= floor


def patch_gradle(path: Path) -> None:
    is_kotlin = path.suffix == ".kts"
    source = path.read_text(encoding="utf-8")
    settings = (
        ("minSdk(?:Version)?", "minSdk" if is_kotlin else "minSdkVersion", 24),
        ("compileSdk(?:Version)?", "compileSdk" if is_kotlin else "compileSdkVersion", 35),
    )

    for pattern_name, output_name, floor in settings:
        pattern = _sdk_pattern(pattern_name)
        replacement_count = 0

        def replace(match: re.Match[str]) -> str:
            nonlocal replacement_count
            replacement_count += 1
            current = match.group("value").strip()
            if _expression_meets_floor(current, floor):
                expression = current
            else:
                function = "maxOf" if is_kotlin else "Math.max"
                expression = f"{function}({current}, {floor})"
            separator = " = " if is_kotlin else " "
            return f"{match.group('indent')}{output_name}{separator}{expression}"

        source = pattern.sub(replace, source)
        if replacement_count != 1:
            raise ValueError(
                f"Expected exactly one {pattern_name} declaration in {path}; found {replacement_count}"
            )

    path.write_text(source, encoding="utf-8")

    updated = path.read_text(encoding="utf-8")
    for pattern_name, _, floor in settings:
        declarations = list(_sdk_pattern(pattern_name).finditer(updated))
        if len(declarations) != 1 or not _expression_meets_floor(declarations[0].group("value"), floor):
            raise ValueError(f"SDK floor for {pattern_name} was not applied to {path}")

def patch_android_project(android_dir: Path) -> None:
    manifest = android_dir / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        raise FileNotFoundError(f"Generated Android manifest not found: {manifest}")

    gradle_files = [
        candidate
        for candidate in (
            android_dir / "app" / "build.gradle.kts",
            android_dir / "app" / "build.gradle",
        )
        if candidate.is_file()
    ]
    if len(gradle_files) != 1:
        raise FileNotFoundError(
            f"Expected one generated app Gradle file under {android_dir / 'app'}; found {len(gradle_files)}"
        )

    patch_manifest(manifest)
    patch_gradle(gradle_files[0])
    print(f"Patched Android manifest and SDK settings: {android_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--android-dir",
        type=Path,
        default=Path("flutter_app/android"),
        help="Path to the generated Android platform directory",
    )
    args = parser.parse_args()
    try:
        patch_android_project(args.android_dir)
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"Android CI patch failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
