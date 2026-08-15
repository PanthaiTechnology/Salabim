package com.salabim.salabim

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Branch de teste da ponte nativa do SDK do ACRCloud (ver
/// ARCHITECTURE.md §4.3/4.4) — primeiro código nativo custom do projeto
/// (até aqui só plugins do pub.dev registravam canais próprios). Segue o
/// mesmo padrão de embedding v2 que eles já usam.
class MainActivity : FlutterActivity() {
    private val methodChannelName = "salabim/acrcloud"
    private val volumeChannelName = "salabim/acrcloud/volume"

    private lateinit var bridge: AcrCloudBridge
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bridge = AcrCloudBridge(this)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    val host = call.argument<String>("host") ?: ""
                    val accessKey = call.argument<String>("accessKey") ?: ""
                    val accessSecret = call.argument<String>("accessSecret") ?: ""
                    result.success(bridge.init(host, accessKey, accessSecret))
                }
                "startRecognize" -> {
                    // O resultado de verdade não vem na resposta desse
                    // método — ele chega depois, de forma assíncrona, via
                    // uma chamada reversa (nativo -> Dart) "onResult" no
                    // mesmo canal (ver AcrCloudBridge.startRecognize e o
                    // lado Dart em acrcloud_native_service.dart). O que
                    // esse `result.success` devolve é só "conseguiu
                    // COMEÇAR a gravar", não o resultado do reconhecimento.
                    val started = bridge.startRecognize { resultMap ->
                        methodChannel?.invokeMethod("onResult", resultMap)
                    }
                    result.success(started)
                }
                "cancel" -> {
                    bridge.cancel()
                    result.success(null)
                }
                "release" -> {
                    bridge.release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    bridge.setVolumeSink(events)
                }

                override fun onCancel(arguments: Any?) {
                    bridge.setVolumeSink(null)
                }
            })
    }

    override fun onDestroy() {
        if (::bridge.isInitialized) {
            bridge.release()
        }
        super.onDestroy()
    }
}
