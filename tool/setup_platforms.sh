#!/usr/bin/env bash
# Generates the android/ and windows/ runners (missing from the repo) and
# applies NoteShelf's native customisations. Idempotent; never touches lib/ or test/.
# Needs Flutter on PATH. Signing secrets come from env vars only:
#   ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android,windows --project-name booknotes --org com.booknotes .

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

# Release signing: only when the secrets are present; otherwise the build falls
# back to the debug key (fine for CI smoke builds, NOT for distribution).
if [[ -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/release.jks
  cat > android/key.properties <<PROPS
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=release.jks
PROPS
fi

python3 - <<'PY'
import os, re
gradle = next((p for p in ("android/app/build.gradle.kts", "android/app/build.gradle") if os.path.exists(p)), None)
s = open(gradle).read()
if "key.properties" in s:
    raise SystemExit(0)
if gradle.endswith(".kts"):
    s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s
    s = s.replace("android {", """val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {""", 1)
    s = s.replace("buildTypes {", """signingConfigs {
        create("release") {
            if (keystoreProps.isNotEmpty()) {
                keyAlias = keystoreProps["keyAlias"] as String
                keyPassword = keystoreProps["keyPassword"] as String
                storeFile = file(keystoreProps["storeFile"] as String)
                storePassword = keystoreProps["storePassword"] as String
            }
        }
    }
    buildTypes {""", 1)
    s = re.sub(r'signingConfig = signingConfigs\.getByName\("debug"\)',
               'signingConfig = if (keystoreProps.isNotEmpty()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', s)
else:
    raise SystemExit("Groovy build.gradle: add the signingConfig manually (see docs/RELEASE.md)")
open(gradle, "w").write(s)
PY
echo "Platforms ready."
