from __future__ import annotations

import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from patch_flutter_android import (
    ANDROID_LABEL,
    ANDROID_NAME,
    ANDROID_SCHEME,
    APP_LABEL,
    MAPS_PACKAGE,
    REQUIRED_PERMISSIONS,
    patch_android_project,
    patch_gradle,
    patch_manifest,
)


class PatchManifestTests(unittest.TestCase):
    def test_manifest_is_patched_idempotently(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "AndroidManifest.xml"
            manifest.write_text(
                '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="local_marketplace" />
</manifest>
''',
                encoding="utf-8",
            )

            patch_manifest(manifest)
            first_result = manifest.read_text(encoding="utf-8")
            patch_manifest(manifest)
            self.assertEqual(manifest.read_text(encoding="utf-8"), first_result)

            root = ET.parse(manifest).getroot()
            permissions = {item.get(ANDROID_NAME) for item in root.findall("uses-permission")}
            self.assertTrue(set(REQUIRED_PERMISSIONS).issubset(permissions))
            application = root.find("application")
            self.assertIsNotNone(application)
            self.assertEqual(application.get(ANDROID_LABEL), APP_LABEL)

            queries = root.find("queries")
            self.assertIsNotNone(queries)
            schemes = {
                data.get(ANDROID_SCHEME)
                for intent in queries.findall("intent")
                for data in intent.findall("data")
            }
            self.assertTrue({"https", "tel", "geo"}.issubset(schemes))
            self.assertIn(
                MAPS_PACKAGE,
                {package.get(ANDROID_NAME) for package in queries.findall("package")},
            )


class PatchGradleTests(unittest.TestCase):
    def test_kotlin_gradle_sdk_floors_are_applied_idempotently(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            gradle = Path(directory) / "build.gradle.kts"
            gradle.write_text(
                """android {
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        minSdk = flutter.minSdkVersion
    }
}
""",
                encoding="utf-8",
            )
            patch_gradle(gradle)
            first_result = gradle.read_text(encoding="utf-8")
            patch_gradle(gradle)
            self.assertEqual(gradle.read_text(encoding="utf-8"), first_result)
            self.assertIn("compileSdk = maxOf(flutter.compileSdkVersion, 35)", first_result)
            self.assertIn("minSdk = maxOf(flutter.minSdkVersion, 24)", first_result)

    def test_groovy_gradle_sdk_floors_are_applied(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            gradle = Path(directory) / "build.gradle"
            gradle.write_text(
                """android {
    compileSdkVersion flutter.compileSdkVersion
    defaultConfig {
        minSdkVersion flutter.minSdkVersion
    }
}
""",
                encoding="utf-8",
            )
            patch_gradle(gradle)
            result = gradle.read_text(encoding="utf-8")
            self.assertIn("compileSdkVersion Math.max(flutter.compileSdkVersion, 35)", result)
            self.assertIn("minSdkVersion Math.max(flutter.minSdkVersion, 24)", result)

    def test_existing_higher_sdk_values_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            gradle = Path(directory) / "build.gradle.kts"
            gradle.write_text(
                """android {
    compileSdk = 36
    defaultConfig {
        minSdk = 26
    }
}
""",
                encoding="utf-8",
            )
            patch_gradle(gradle)
            result = gradle.read_text(encoding="utf-8")
            self.assertIn("compileSdk = 36", result)
            self.assertIn("minSdk = 26", result)

    def test_full_project_patch_accepts_generated_kotlin_wrapper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            android = Path(directory) / "android"
            app = android / "app"
            manifest = app / "src" / "main" / "AndroidManifest.xml"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(
                '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                '<application android:label="local_marketplace" /></manifest>',
                encoding="utf-8",
            )
            gradle = app / "build.gradle.kts"
            gradle.write_text(
                """android {
    compileSdk = flutter.compileSdkVersion
    defaultConfig {
        minSdk = flutter.minSdkVersion
    }
}
""",
                encoding="utf-8",
            )

            patch_android_project(android)
            self.assertIn("maxOf(flutter.compileSdkVersion, 35)", gradle.read_text(encoding="utf-8"))
            self.assertIn(APP_LABEL, manifest.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
