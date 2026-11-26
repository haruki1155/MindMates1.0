package ph.edu.ucu.mindmates

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class PhotoExpressionEngine(private val context: Context) : AutoCloseable {

    private val labels = listOf(
        "Neutral",
        "Happy",
        "Surprise",
        "Sad",
        "Angry",
        "Disgust",
        "Fear",
        "Contempt"
    )

    private val environment = OrtEnvironment.getEnvironment()

    private var faceLandmarker: FaceLandmarker? = null
    private var session: OrtSession? = null

    private fun getLandmarker(): FaceLandmarker {
        faceLandmarker?.let { return it }

        val baseOptions = BaseOptions.builder()
            .setModelAssetPath("mediapipe/face_landmarker.task")
            .build()

        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(2)
            .setMinFaceDetectionConfidence(0.5f)
            .setMinFacePresenceConfidence(0.5f)
            .build()

        return FaceLandmarker.createFromOptions(context, options)
            .also { faceLandmarker = it }
    }

    private fun getSession(): OrtSession {
        session?.let { return it }

        val modelBytes = context.assets
            .open("mediapipe/emotion-ferplus-8.onnx")
            .use { it.readBytes() }

        return OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(2)
            environment.createSession(modelBytes, options)
        }.also { session = it }
    }

    private fun loadPhoto(path: String): Bitmap {
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }

        BitmapFactory.decodeFile(path, bounds)

        require(bounds.outWidth > 0 && bounds.outHeight > 0) {
            "Unable to read the captured photo."
        }

        var sample = 1

        while (max(bounds.outWidth, bounds.outHeight) / sample > 1600) {
            sample *= 2
        }

        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        val bitmap = BitmapFactory.decodeFile(path, options)
            ?: error("Unable to open the captured photo.")

        val orientation = ExifInterface(path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )

        val matrix = Matrix()

        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL ->
                matrix.setScale(-1f, 1f)

            ExifInterface.ORIENTATION_ROTATE_180 ->
                matrix.setRotate(180f)

            ExifInterface.ORIENTATION_FLIP_VERTICAL ->
                matrix.setScale(1f, -1f)

            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }

            ExifInterface.ORIENTATION_ROTATE_90 ->
                matrix.setRotate(90f)

            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }

            ExifInterface.ORIENTATION_ROTATE_270 ->
                matrix.setRotate(270f)
        }

        if (matrix.isIdentity) return bitmap

        val rotated = Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true
        )

        if (rotated !== bitmap) bitmap.recycle()

        return rotated
    }

    @Synchronized
    fun analyze(path: String): Map<String, Any> {
        val bitmap = loadPhoto(path)

        try {
            val image = BitmapImageBuilder(
                bitmap.copy(Bitmap.Config.ARGB_8888, false)
                    ?: error("Unable to copy photo bitmap")
            ).build()

            val detection = try {
                getLandmarker().detect(image)
            } finally {
                image.close()
            }

            val faces = detection.faceLandmarks()

            if (faces.isEmpty()) {
                return mapOf(
                    "status" to "no_face",
                    "message" to "No face detected. Please retake your photo."
                )
            }

            if (faces.size > 1) {
                return mapOf(
                    "status" to "multiple_faces",
                    "message" to "Please take a photo with only one face."
                )
            }

            val face = faces.first()

            val minX = face.minOf { it.x() } * bitmap.width
            val maxX = face.maxOf { it.x() } * bitmap.width
            val minY = face.minOf { it.y() } * bitmap.height
            val maxY = face.maxOf { it.y() } * bitmap.height

            val centerX = (minX + maxX) / 2f
            val centerY = (minY + maxY) / 2f

            val size = max(maxX - minX, maxY - minY) * 1.20f

            val left = max(0, (centerX - size / 2f).roundToInt())
            val top = max(0, (centerY - size / 2f).roundToInt())

            val right = min(
                bitmap.width,
                (centerX + size / 2f).roundToInt()
            )

            val bottom = min(
                bitmap.height,
                (centerY + size / 2f).roundToInt()
            )

            if (right - left < 32 || bottom - top < 32) {
                return mapOf(
                    "status" to "face_too_small",
                    "message" to "Move closer to the camera and retake your photo."
                )
            }

            val crop = Bitmap.createBitmap(
                bitmap,
                left,
                top,
                right - left,
                bottom - top
            )

            val resized = Bitmap.createScaledBitmap(crop, 64, 64, true)

            val pixels = IntArray(64 * 64)

            resized.getPixels(
                pixels,
                0,
                64,
                0,
                0,
                64,
                64
            )

            val input = FloatArray(64 * 64)

            for (i in pixels.indices) {
                val pixel = pixels[i]

                input[i] =
                    0.299f * Color.red(pixel) +
                    0.587f * Color.green(pixel) +
                    0.114f * Color.blue(pixel)
            }

            if (resized !== crop && resized !== bitmap) {
                resized.recycle()
            }

            if (crop !== bitmap) {
                crop.recycle()
            }

            val model = getSession()
            val inputName = model.inputNames.first()

            val scores = OnnxTensor.createTensor(
                environment,
                FloatBuffer.wrap(input),
                longArrayOf(1, 1, 64, 64)
            ).use { tensor ->
                model.run(mapOf(inputName to tensor)).use { result ->
                    val output = result[0].value as Array<*>
                    (output.first() as FloatArray).copyOf()
                }
            }

            require(scores.size == labels.size) {
                "Unexpected emotion model output."
            }

            require(scores.all { it.isFinite() }) {
                "Invalid emotion model output."
            }

            val index = scores.indices.maxByOrNull { scores[it] }
                ?: error("No expression result.")

            val label = labels[index]

            if (label == "Contempt") {
                return mapOf(
                    "status" to "unclear",
                    "label" to "Expression unclear",
                    "modelVersion" to "ferplus_onnx_v1"
                )
            }

            return mapOf(
                "status" to "success",
                "label" to label,
                "modelVersion" to "ferplus_onnx_v1"
            )

        } finally {
            bitmap.recycle()
        }
    }

    @Synchronized
    override fun close() {
        faceLandmarker?.close()
        faceLandmarker = null

        session?.close()
        session = null
    }
}
