package dev.mauznemo.crypthora_chat_wrapper

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "dev.mauznemo.crypthora_chat_wrapper/shortcuts"

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
                call,
                result ->
            if (call.method == "pushShortcut") {
                val shortcutId = call.argument<String>("shortcutId")
                val shortLabel = call.argument<String>("shortLabel")
                val imageBytes = call.argument<ByteArray>("imageBytes")

                if (shortcutId != null && shortLabel != null && imageBytes != null) {
                    pushShortcut(shortcutId, shortLabel, imageBytes)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun pushShortcut(shortcutId: String, shortLabel: String, imageBytes: ByteArray) {
        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
        val icon =
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    val scaledSize = (bitmap.width * 0.68).toInt()
                    val scaledBitmap =
                            Bitmap.createScaledBitmap(bitmap, scaledSize, scaledSize, true)

                    val paddedBitmap =
                            Bitmap.createBitmap(
                                    bitmap.width,
                                    bitmap.height,
                                    Bitmap.Config.ARGB_8888
                            )
                    val canvas = android.graphics.Canvas(paddedBitmap)
                    val left = (bitmap.width - scaledSize) / 2f
                    val top = (bitmap.height - scaledSize) / 2f
                    canvas.drawBitmap(scaledBitmap, left, top, null)

                    IconCompat.createWithAdaptiveBitmap(paddedBitmap)
                } else {
                    IconCompat.createWithBitmap(bitmap)
                }

        val person = androidx.core.app.Person.Builder().setName(shortLabel).setIcon(icon).build()

        val intent =
                Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    // Add extras to open the specific chat, e.g., putExtra("chatId", shortcutId)
                }

        val shortcut =
                ShortcutInfoCompat.Builder(this, shortcutId)
                        .setShortLabel(shortLabel)
                        .setLongLived(true)
                        .setIntent(intent)
                        .setPerson(person)
                        .setIcon(icon)
                        .build()

        ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)
    }
}
