# Android setup for T2 (SAF)

After `flutter create --platforms=windows,android ...`:

1. Copy `SafPlugin.kt` to
   `android/app/src/main/kotlin/com/booknotes/booknotes/SafPlugin.kt`
   (adjust the `package` line if your MainActivity package differs).
2. Register it in `MainActivity.kt`:

```kotlin
package com.booknotes.booknotes

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SafPlugin())
    }
}
```

No manifest permissions are needed: SAF grants are per-folder and come from the
system picker. (Do NOT add MANAGE_EXTERNAL_STORAGE.)
