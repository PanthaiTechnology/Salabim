package com.salabim.salabim

import android.app.Activity
import com.acrcloud.rec.ACRCloudClient
import com.acrcloud.rec.ACRCloudConfig
import com.acrcloud.rec.ACRCloudResult
import com.acrcloud.rec.IACRCloudListener
import com.acrcloud.rec.IACRCloudPartnerDeviceInfo
import io.flutter.plugin.common.EventChannel
import org.json.JSONObject

/// Ponte pro SDK on-device do ACRCloud — branch de teste (ver
/// ARCHITECTURE.md §4.3/4.4: velocidade — fingerprint calculado no
/// aparelho, sem upload do áudio inteiro — e prioridade de captura do
/// microfone, que aqui pedimos nós mesmos, não fica presa ao
/// comportamento fixo do pacote `record`).
///
/// Encapsula ACRCloudClient/IACRCloudListener. `startRecognize` do SDK é
/// uma chamada "tudo incluso" (grava, calcula fingerprint, consulta o
/// servidor, chama `onResult` quando termina) — diferente do nosso
/// pipeline REST atual, que controlamos ponto a ponto (múltiplas
/// tentativas, concordância). Aqui é só um caminho paralelo mais simples,
/// pra testar se o SDK sozinho já resolve.
class AcrCloudBridge(private val activity: Activity) : IACRCloudListener {
    private var client: ACRCloudClient? = null
    private var initialized = false
    private var pendingResult: ((Map<String, Any?>) -> Unit)? = null
    private var volumeSink: EventChannel.EventSink? = null

    fun setVolumeSink(sink: EventChannel.EventSink?) {
        volumeSink = sink
    }

    /// Inicializa (ou reinicializa) o cliente do ACRCloud com as
    /// credenciais do projeto. Retorna se a inicialização deu certo.
    fun init(host: String, accessKey: String, accessSecret: String): Boolean {
        release() // sessão anterior, se houver, libera antes de reiniciar

        val config = ACRCloudConfig()
        config.acrcloudListener = this
        config.context = activity
        config.host = host
        config.accessKey = accessKey
        config.accessSecret = accessSecret
        config.recorderConfig.isVolumeCallback = true
        // "Info do dispositivo parceiro" — pensado pra rádio FM/GPS, não é
        // o nosso caso de uso, mas a interface precisa ser implementada
        // mesmo assim (o demo oficial deles faz o mesmo, tudo nulo/vazio).
        config.acrcloudPartnerDeviceInfo = object : IACRCloudPartnerDeviceInfo {
            override fun getGPS(): String? = null
            override fun getRadioFrequency(): String? = null
            override fun getDeviceId(): String = ""
            override fun getDeviceModel(): String? = null
        }

        val newClient = ACRCloudClient()
        initialized = newClient.initWithConfig(config)
        client = newClient
        return initialized
    }

    /// Dispara o reconhecimento (grava + calcula fingerprint + consulta,
    /// tudo dentro do SDK). [onResult] é chamado uma única vez, quando o
    /// resultado (achou ou não) chegar — ver `onResult` abaixo. Retorna se
    /// conseguiu MEÇAR (não é o resultado em si).
    fun startRecognize(onResult: (Map<String, Any?>) -> Unit): Boolean {
        if (!initialized) return false
        pendingResult = onResult
        val started = client?.startRecognize() ?: false
        if (!started) pendingResult = null
        return started
    }

    fun cancel() {
        client?.cancel()
        pendingResult = null
    }

    fun release() {
        client?.release()
        client = null
        initialized = false
        pendingResult = null
    }

    override fun onResult(results: ACRCloudResult?) {
        val callback = pendingResult
        pendingResult = null
        val parsed = parseResult(results?.result)
        activity.runOnUiThread {
            callback?.invoke(parsed)
        }
    }

    override fun onVolumeChanged(volume: Double) {
        activity.runOnUiThread {
            volumeSink?.success(volume)
        }
    }

    /// Converte o JSON bruto do ACRCloud (status.code == 0 = sucesso,
    /// metadata.music[] com título/artistas/álbum/isrc/score — mesmo
    /// formato que já processamos em Python no backend, ver
    /// acrcloud_fingerprint_client.py) num Map simples pro lado Dart, sem
    /// precisar reimplementar o parsing de JSON lá.
    private fun parseResult(raw: String?): Map<String, Any?> {
        if (raw == null) return mapOf("found" to false)
        return try {
            val json = JSONObject(raw)
            val statusCode = json.optJSONObject("status")?.optInt("code", -1) ?: -1
            if (statusCode != 0) return mapOf("found" to false)

            val musicArray = json.optJSONObject("metadata")?.optJSONArray("music")
            if (musicArray == null || musicArray.length() == 0) return mapOf("found" to false)

            val music = musicArray.getJSONObject(0)
            val artists = music.optJSONArray("artists")
            val artistNames = mutableListOf<String>()
            if (artists != null) {
                for (i in 0 until artists.length()) {
                    artistNames.add(artists.getJSONObject(i).optString("name"))
                }
            }
            val album = music.optJSONObject("album")?.optString("name")
            val isrc = music.optJSONObject("external_ids")?.optString("isrc")
            val score = music.optDouble("score", 0.0)

            mapOf(
                "found" to true,
                "title" to music.optString("title", "Desconhecido"),
                "artist" to if (artistNames.isNotEmpty()) artistNames.joinToString(", ") else "Desconhecido",
                "album" to album,
                "isrc" to isrc,
                "score" to score,
            )
        } catch (e: Exception) {
            mapOf("found" to false, "error" to e.message)
        }
    }
}
