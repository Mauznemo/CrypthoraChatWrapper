package dev.mauznemo.crypthora_chat_wrapper

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
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

                if (shortcutId != null && shortLabel != null) {
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

    private fun pushShortcut(shortcutId: String, shortLabel: String, imageBytes: ByteArray?) {
        val bitmap =
                if (imageBytes != null) {
                    BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                } else {
                    createLetterBitmap(shortLabel)
                }

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
                    val canvas = Canvas(paddedBitmap)
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

    private fun createLetterBitmap(label: String): Bitmap {
        val size = 192 // Size in pixels
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Background color - you can customize this or generate based on the label
        val backgroundColor = generateColorFromString(label)
        canvas.drawColor(backgroundColor)

        // Draw the first letter
        val letter = label.firstOrNull()?.uppercaseChar()?.toString() ?: "?"
        val paint =
                Paint().apply {
                    color = Color.WHITE
                    textSize = size * 0.5f
                    typeface = Typeface.DEFAULT_BOLD
                    textAlign = Paint.Align.CENTER
                    isAntiAlias = true
                }

        val xPos = size / 2f
        val yPos = (size / 2f) - ((paint.descent() + paint.ascent()) / 2f)
        canvas.drawText(letter, xPos, yPos, paint)

        return bitmap
    }

    private fun generateColorFromString(str: String): Int {
        // Generate a consistent color based on the string
        val hash = str.hashCode()
        val hue = (hash and 0xFF).toFloat() / 255f * 360f
        return Color.HSVToColor(floatArrayOf(hue, 0.6f, 0.7f))
    }
}
