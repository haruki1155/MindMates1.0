package ph.edu.ucu.mindmates

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val channelName = "mindmate/photo_expression"

    private val executor = Executors.newSingleThreadExecutor()

    private var expressionEngine: PhotoExpressionEngine? = null

    private var expressionChannel: MethodChannel? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        expressionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        expressionChannel?.setMethodCallHandler { call, result ->

            when (call.method) {

                "analyzePhoto" -> {
                    val path = call.argument<String>("path")

                    if (path.isNullOrBlank()) {
                        result.error(
                            "INVALID_PHOTO",
                            "Photo path is missing.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            val engine = expressionEngine
                                ?: PhotoExpressionEngine(
                                    applicationContext
                                ).also {
                                    expressionEngine = it
                                }

                            val response = engine.analyze(path)

                            runOnUiThread {
                                result.success(response)
                            }

                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error(
                                    "EXPRESSION_ERROR",
                                    e.message ?: "Photo analysis failed.",
                                    null
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        expressionChannel?.setMethodCallHandler(null)
        expressionChannel = null

        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        executor.execute {
            expressionEngine?.close()
            expressionEngine = null
        }

        executor.shutdown()

        super.onDestroy()
    }
}
