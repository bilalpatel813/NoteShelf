#!/usr/bin/env bash
# Generate Android and Windows runners and apply NoteShelf customisations.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android,windows --project-name booknotes --org com.booknotes .

# Install NoteShelf SAF plugin.
KT_DIR=android/app/src/main/kotlin/com/booknotes/booknotes
mkdir -p "$KT_DIR"
cp android_native/SafPlugin.kt "$KT_DIR/SafPlugin.kt"

cat > "$KT_DIR/MainActivity.kt" <<'KT'
package com.booknotes.booknotes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SafPlugin())
    }
}
KT

# Configure Android compile SDK and release signing.
python3 - <<'PY'
from pathlib import Path
import re

gradle = next(
    (p for p in (
        Path("android/app/build.gradle.kts"),
        Path("android/app/build.gradle"),
    ) if p.exists()),
    None,
)

if gradle is None:
    raise SystemExit("Android Gradle file not found")

kts = gradle.suffix == ".kts"
s = gradle.read_text()

# Require Android API 36.
if kts:
    pattern = r"(?m)^(\s*)compileSdk(?:Version)?\s*=.*$"
    replacement = r"\g<1>compileSdk = 36"
else:
    pattern = r"(?m)^(\s*)compileSdk(?:Version)?\s+.*$"
    replacement = r"\g<1>compileSdkVersion 36"

s, count = re.subn(pattern, replacement, s, count=1)

if count != 1:
    raise SystemExit("Could not update compileSdk declaration")

# Add signing configuration only once.
if "NOTE_SHELF_SIGNING_CONFIG" not in s:
    if kts:
        imports = """import java.util.Properties
import java.io.FileInputStream

"""
        if "import java.util.Properties" not in s:
            s = imports + s

        config = """// NOTE_SHELF_SIGNING_CONFIG
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

"""
        s = s.replace("android {", config + "android {", 1)

        signing = """signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }
    """

        s = s.replace("buildTypes {", signing + "buildTypes {", 1)

        s = s.replace(
            'signingConfig = signingConfigs.getByName("debug")',
            'signingConfig = if (keystoreProps.isNotEmpty()) '
            'signingConfigs.getByName("release") '
            'else signingConfigs.getByName("debug")'
        )
    else:
        config = """// NOTE_SHELF_SIGNING_CONFIG
def keystoreProps = new Properties()
def keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProps.load(new FileInputStream(keystoreFile))
}

"""
        s = s.replace("android {", config + "android {", 1)

        signing = """signingConfigs {
        release {
            if (!keystoreProps.isEmpty()) {
                keyAlias keystoreProps["keyAlias"]
                keyPassword keystoreProps["keyPassword"]
                storeFile file(keystoreProps["storeFile"])
                storePassword keystoreProps["storePassword"]
            }
        }
    }
    """

        s = s.replace("buildTypes {", signing + "buildTypes {", 1)

        s = re.sub(
            r"signingConfig\s+signingConfigs\.debug",
            'signingConfig keystoreProps.isEmpty() '
            '? signingConfigs.debug : signingConfigs.release',
            s,
        )

gradle.write_text(s)
print(f"Configured {gradle}: compileSdk 36 and signing")
PY

# Configure release signing only when all secrets are provided.
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
    : "${ANDROID_KEYSTORE_PASSWORD:?Missing keystore password}"
    : "${ANDROID_KEY_ALIAS:?Missing key alias}"
    : "${ANDROID_KEY_PASSWORD:?Missing key password}"

    echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/release.jks

    cat > android/key.properties <<PROPS
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=release.jks
PROPS
fi

echo "Platforms ready."