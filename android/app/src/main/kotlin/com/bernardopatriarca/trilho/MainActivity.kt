package com.bernardopatriarca.trilho

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Canal para o que o plugin de notificações não cobre: otimização de
    // bateria e fabricante (para as dicas de Xiaomi, Samsung e Motorola).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "trilho/sistema").setMethodCallHandler { call, result ->
            when (call.method) {
                "ignorandoOtimizacaoBateria" -> {
                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                    result.success(pm.isIgnoringBatteryOptimizations(packageName))
                }
                "pedirSemOtimizacaoBateria" -> {
                    abrir(pedirSemOtimizacao())
                    result.success(null)
                }
                "abrirConfigBateria" -> {
                    abrir(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                "fabricante" -> result.success(Build.MANUFACTURER ?: "")
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("BatteryLife")
    private fun pedirSemOtimizacao(): Intent =
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).setData(Uri.parse("package:$packageName"))

    private fun abrir(intent: Intent) {
        try {
            startActivity(intent)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).setData(Uri.parse("package:$packageName")))
        }
    }
}
