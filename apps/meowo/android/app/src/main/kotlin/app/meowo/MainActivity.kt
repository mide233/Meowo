package app.meowo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meowo/pdf")
            .setMethodCallHandler { call, result ->
                if (call.method != "render") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val outputDir = call.argument<String>("outputDir")
                if (path.isNullOrBlank() || outputDir.isNullOrBlank()) {
                    result.error("bad_args", "缺少 PDF 路径或输出目录", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val pages = renderPdf(File(path), File(outputDir))
                        runOnUiThread { result.success(pages) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error(
                                "pdf_render_failed",
                                error.message ?: error.javaClass.simpleName,
                                null,
                            )
                        }
                    }
                }.start()
            }
    }

    private fun renderPdf(file: File, outputDir: File): List<Map<String, Any>> {
        if (!file.exists()) throw IllegalArgumentException("PDF 文件不存在")
        outputDir.mkdirs()
        val descriptor = ParcelFileDescriptor.open(
            file,
            ParcelFileDescriptor.MODE_READ_ONLY,
        )
        try {
            val renderer = PdfRenderer(descriptor)
            try {
                if (renderer.pageCount > 500) {
                    throw IllegalArgumentException("首版单次最多导入 500 页 PDF")
                }
                val pages = mutableListOf<Map<String, Any>>()
                val scale = 120.0f / 72.0f
                for (index in 0 until renderer.pageCount) {
                    val page = renderer.openPage(index)
                    try {
                        val width = (page.width * scale).roundToInt().coerceAtLeast(1)
                        val height = (page.height * scale).roundToInt().coerceAtLeast(1)
                        val bitmap = Bitmap.createBitmap(
                            width,
                            height,
                            Bitmap.Config.ARGB_8888,
                        )
                        try {
                            Canvas(bitmap).drawColor(Color.WHITE)
                            page.render(
                                bitmap,
                                null,
                                null,
                                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
                            )
                            val target = File(outputDir, "page-${index + 1}.png")
                            FileOutputStream(target).use { stream ->
                                bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            }
                            pages.add(
                                mapOf(
                                    "path" to target.absolutePath,
                                    "width" to page.width,
                                    "height" to page.height,
                                ),
                            )
                        } finally {
                            bitmap.recycle()
                        }
                    } finally {
                        page.close()
                    }
                }
                return pages
            } finally {
                renderer.close()
            }
        } finally {
            descriptor.close()
        }
    }
}
