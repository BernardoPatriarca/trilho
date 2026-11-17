// Canal nativo (MainActivity.kt) para o que o plugin de notificações não
// cobre: otimização de bateria e fabricante do aparelho.
import 'package:flutter/services.dart';

class SystemSettings {
  const SystemSettings();
  static const _channel = MethodChannel('trilho/sistema');

  /// true = o app está fora da otimização de bateria (bom para lembretes).
  Future<bool> ignoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('ignorandoOtimizacaoBateria') ?? false;
    } on Object {
      return false;
    }
  }

  /// Pede ao sistema para tirar o app da otimização de bateria.
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('pedirSemOtimizacaoBateria');
    } on Object {
      await openBatterySettings();
    }
  }

  Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('abrirConfigBateria');
    } on Object {
      return;
    }
  }

  /// Fabricante em minúsculas ("xiaomi", "samsung", "motorola"...).
  Future<String> manufacturer() async {
    try {
      return (await _channel.invokeMethod<String>('fabricante') ?? '').toLowerCase();
    } on Object {
      return '';
    }
  }
}

/// Dicas curtas por fabricante (economia de bateria agressiva).
const batteryTips = {
  'xiaomi':
      'Xiaomi/Redmi/POCO: Configurações › Apps › Trilho › Economia de bateria › "Sem restrições" '
      'e ative "Início automático".',
  'samsung':
      'Samsung: Configurações › Bateria › Limites de uso em segundo plano › tire o Trilho de '
      '"Apps em suspensão" e adicione em "Apps que nunca são suspensos".',
  'motorola':
      'Motorola: Configurações › Apps › Trilho › Bateria › "Sem restrições" (ou "Otimização" › '
      '"Não otimizar").',
};
