package com.snapandgo.shadowwrestling

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.common.collect.ImmutableList
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.snapandgo.shadowwrestling/watermark"
    private val TAG = "WatermarkExport"
    private var activeTransformer: Transformer? = null

    @OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "addWatermark") {
                val inputPath = call.argument<String>("videoPath")
                val assetPath = call.argument<String>("watermarkAsset")

                if (inputPath == null || assetPath == null) {
                    result.error("INVALID_ARGS", "Missing arguments", null)
                    return@setMethodCallHandler
                }

                val inputFile = File(inputPath)
                if (!inputFile.exists() || inputFile.length() <= 0) {
                    result.error("INPUT_ERROR", "Video file is missing or empty: $inputPath", null)
                    return@setMethodCallHandler
                }

                val bitmap = loadFlutterAssetBitmap(assetPath)

                // Prevent the Media3 Transformer from starting if the asset failed to load
                if (bitmap == null) {
                    result.error("ASSET_ERROR", "Watermark asset not found: $assetPath", null)
                    return@setMethodCallHandler
                }

                // FIX: Scoped to filesDir to ensure persistent hardware encoder write access
                val outputDir = File(context.filesDir, "branded_videos")
                if (!outputDir.exists()) outputDir.mkdirs()
                val outputPath = File(outputDir, "watermarked_${System.currentTimeMillis()}.mp4").absolutePath

                val scaledBitmap = scaleWatermarkBitmap(bitmap, inputPath)
                val overlay = TimedWatermarkOverlay(scaledBitmap)

                val overlayEffect = OverlayEffect(ImmutableList.of<TextureOverlay>(overlay))
                
                val audioProcessors = mutableListOf<AudioProcessor>()
                val videoEffects = mutableListOf<Effect>(overlayEffect)
                val effects = Effects(audioProcessors, videoEffects)

                startWatermarkExport(
                    inputPath = inputPath,
                    outputPath = outputPath,
                    effects = effects,
                    requestedVideoBitrate = chooseTargetVideoBitrate(inputPath),
                    removeAudio = false,
                    result = result
                )

            } else {
                result.notImplemented()
            }
        }
    }

    private class TimedWatermarkOverlay(
        private val bitmap: Bitmap
    ) : BitmapOverlay() {
        private val visibleSettings = buildOverlaySettings(alphaScale = 0.85f)
        private val hiddenSettings = buildOverlaySettings(alphaScale = 0f)

        override fun getBitmap(presentationTimeUs: Long): Bitmap = bitmap

        override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
            return if (shouldShowWatermark(presentationTimeUs)) {
                visibleSettings
            } else {
                hiddenSettings
            }
        }

        private fun shouldShowWatermark(presentationTimeUs: Long): Boolean {
            return presentationTimeUs in 5_000_000L until 10_000_000L ||
                presentationTimeUs in 20_000_000L until 25_000_000L ||
                presentationTimeUs in 35_000_000L until 40_000_000L ||
                presentationTimeUs in 50_000_000L until 55_000_000L
        }

        private fun buildOverlaySettings(alphaScale: Float): StaticOverlaySettings {
            return StaticOverlaySettings.Builder()
                .setAlphaScale(alphaScale)
                .setOverlayFrameAnchor(1f, 1f)
                .setBackgroundFrameAnchor(0.92f, 0.92f)
                .build()
        }
    }

    @OptIn(UnstableApi::class)
    private fun startWatermarkExport(
        inputPath: String,
        outputPath: String,
        effects: Effects,
        requestedVideoBitrate: Int,
        removeAudio: Boolean,
        result: MethodChannel.Result
    ) {
        val outputFile = File(outputPath)
        if (outputFile.exists()) outputFile.delete()
        val startedAtMs = SystemClock.elapsedRealtime()

        Log.i(
            TAG,
            "Starting export removeAudio=$removeAudio bitrate=$requestedVideoBitrate inputBytes=${File(inputPath).length()}"
        )

        val mediaItem = MediaItem.fromUri(Uri.fromFile(File(inputPath)))
        val editedMediaItem = EditedMediaItem.Builder(mediaItem)
            .setEffects(effects)
            .setRemoveAudio(removeAudio)
            .build()

        val encoderFactory = DefaultEncoderFactory.Builder(applicationContext)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder()
                    .setBitrate(requestedVideoBitrate)
                    .build()
            )
            .build()

        val transformer = Transformer.Builder(applicationContext)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    Handler(Looper.getMainLooper()).post {
                        activeTransformer = null
                        Log.i(
                            TAG,
                            "Export completed removeAudio=$removeAudio elapsedMs=${SystemClock.elapsedRealtime() - startedAtMs} outputBytes=${File(outputPath).length()}"
                        )
                        result.success(outputPath)
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exception: ExportException
                ) {
                    Handler(Looper.getMainLooper()).post {
                        activeTransformer = null
                        Log.e(
                            TAG,
                            "Export failed removeAudio=$removeAudio elapsedMs=${SystemClock.elapsedRealtime() - startedAtMs} code=${exception.errorCode} name=${exception.errorCodeName}",
                            exception
                        )

                        if (!removeAudio) {
                            Log.w(TAG, "Retrying watermark export without audio after failure.")
                            startWatermarkExport(
                                inputPath = inputPath,
                                outputPath = outputPath,
                                effects = effects,
                                requestedVideoBitrate = requestedVideoBitrate,
                                removeAudio = true,
                                result = result
                            )
                            return@post
                        }

                        val errorCode = when (exception.errorCode) {
                            ExportException.ERROR_CODE_IO_UNSPECIFIED -> "IO_LOCK_ERROR"
                            ExportException.ERROR_CODE_DECODING_FAILED -> "CODEC_FAIL"
                            else -> "TRANSFORM_ERROR"
                        }
                        result.error(errorCode, exception.message, null)
                    }
                }
            })
            .build()

        activeTransformer = transformer
        transformer.start(editedMediaItem, outputPath)
    }

    private fun loadFlutterAssetBitmap(assetPath: String): Bitmap? {
        val loader = io.flutter.FlutterInjector.instance().flutterLoader()
        val lookupKey = loader.getLookupKeyForAsset(assetPath)
        val candidates = linkedSetOf(
            lookupKey,
            lookupKey.replace(" ", "%20"),
            assetPath,
            assetPath.replace(" ", "%20"),
            "flutter_assets/$assetPath",
            "flutter_assets/$assetPath".replace(" ", "%20")
        )

        for (candidate in candidates) {
            try {
                context.assets.open(candidate).use { inputStream ->
                    return BitmapFactory.decodeStream(inputStream)
                }
            } catch (e: Exception) {
                // Try the next asset key variant. Flutter URL-encodes spaces in APK assets.
            }
        }

        return null
    }

    private fun scaleWatermarkBitmap(source: Bitmap, videoPath: String): Bitmap {
        val videoWidth = readVideoWidth(videoPath).takeIf { it > 0 } ?: 720
        val targetWidth = (videoWidth * 0.18f).toInt().coerceAtLeast(96)
        val targetHeight = (targetWidth * (source.height.toFloat() / source.width)).toInt().coerceAtLeast(1)

        return Bitmap.createScaledBitmap(source, targetWidth, targetHeight, true)
    }

    private fun chooseTargetVideoBitrate(videoPath: String): Int {
        val sourceBitrate = readVideoBitrate(videoPath)
        val videoWidth = readVideoWidth(videoPath)
        val estimatedBitrate = when {
            videoWidth >= 1440 -> 20_000_000
            videoWidth >= 1080 -> 14_000_000
            videoWidth >= 720 -> 8_000_000
            else -> 5_000_000
        }

        if (sourceBitrate <= 0) return estimatedBitrate

        val maxBitrate = when {
            videoWidth >= 1440 -> 28_000_000
            videoWidth >= 1080 -> 20_000_000
            videoWidth >= 720 -> 12_000_000
            else -> 8_000_000
        }

        return sourceBitrate
            .coerceAtLeast(estimatedBitrate)
            .coerceAtMost(maxBitrate)
    }

    private fun readVideoBitrate(videoPath: String): Int {
        val retriever = MediaMetadataRetriever()

        return try {
            retriever.setDataSource(videoPath)
            retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toIntOrNull() ?: 0
        } catch (e: Exception) {
            0
        } finally {
            retriever.release()
        }
    }

    private fun readVideoWidth(videoPath: String): Int {
        val retriever = MediaMetadataRetriever()

        return try {
            retriever.setDataSource(videoPath)

            val width = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            val height = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            val rotation = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                ?.toIntOrNull() ?: 0

            if (rotation == 90 || rotation == 270) height else width
        } catch (e: Exception) {
            0
        } finally {
            retriever.release()
        }
    }
}
