import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Servicio centralizado para reproducir alertas de sonido
/// - No toca lógica de negocio
/// - Funciona en web/móvil/desktop usando audioplayers
/// - Implementa antirebote para evitar sonidos repetidos
class AlertSoundService {
  AlertSoundService._internal();
  static final AlertSoundService instance = AlertSoundService._internal();

  final AudioPlayer _player = AudioPlayer()
    ..setVolume(0.9)
    ..setReleaseMode(ReleaseMode.stop);
  double _volume = 0.9;

  // Rol actual (para decidir qué sonar)
  UserRole? _currentRole;

  // Anti-spam por tipo
  final Map<String, DateTime> _lastPlay = {};
  Duration minGap = const Duration(seconds: 2);

  // Para desbloquear audio en web tras warmup
  bool _warmedUp = false;

  // Rutas de assets sugeridas (coherentes con audioplayers en web: usar path relativo al key "assets/")
  // En pubspec.yaml está declarado: assets/audio/ -> por convención usar 'audio/xxx.mp3'
  static const String restaurantAsset = 'audio/restaurant_new_order.mp3';
  static const String deliveryAsset = 'audio/delivery_new_order.mp3';

  // Fallback URLs muy livianas (en caso de que el asset no exista)
  // Nota: es recomendable subir assets locales para mayor confiabilidad
  static const String restaurantFallback =
      'https://assets.mixkit.co/active_storage/sfx/2570/2570-preview.mp3'; // short notification
  static const String deliveryFallback =
      'https://assets.mixkit.co/active_storage/sfx/2573/2573-preview.mp3'; // pop alert

  void setCurrentRole(UserRole? role) => _currentRole = role;

  /// Warmup para web: intenta reproducir de forma silenciosa para desbloquear el contexto de audio
  Future<void> warmup() async {
    if (_warmedUp) return;
    try {
      if (kIsWeb) {
        await _player.setVolume(0);
        // Probar primero la ruta sin prefijo
        try {
          await _player.play(AssetSource(restaurantAsset.replaceFirst('assets/', '')));
        } catch (_) {
          // Intentar con el path completo
          try {
            await _player.play(AssetSource(restaurantAsset));
          } catch (_) {}
        }
        await Future.delayed(const Duration(milliseconds: 150));
        await _player.stop();
        await _player.setVolume(_volume);
      }
      _warmedUp = true;
    } catch (e) {
      debugPrint('⚠️ [ALERT] Warmup fallido (continuará con fallback si es necesario): $e');
    }
  }

  bool _shouldPlay(String key) {
    final now = DateTime.now();
    final last = _lastPlay[key];
    if (last == null || now.difference(last) > minGap) {
      _lastPlay[key] = now;
      return true;
    }
    return false;
  }

  Future<void> _playAssetOrFallback({required String asset, required String fallbackUrl}) async {
    // Asegurar warmup en web
    await warmup();

    // Intentar con dos formatos de ruta de asset (audio/… primero)
    final candidatePaths = <String>[
      asset, // p.ej. audio/xxx.mp3
      'assets/' + asset, // p.ej. assets/audio/xxx.mp3
    ];

    for (final path in candidatePaths) {
      try {
        await _player.stop();
        await _player.play(AssetSource(path));
        return; // Éxito
      } catch (_) {
        // probar siguiente
      }
    }

    // Si todas las rutas fallan, intentar reproducir URL remota como respaldo
    try {
      await _player.stop();
      await _player.play(UrlSource(fallbackUrl));
    } catch (e) {
      debugPrint('❌ [ALERT] Error reproduciendo sonido: $e');
    }
  }

  /// Reproduce sonido para nueva orden de restaurante (rol restaurante)
  Future<void> playRestaurantNewOrder() async {
    if (_currentRole != UserRole.restaurant) return;
    if (!_shouldPlay('restaurant')) return;
    await _playAssetOrFallback(asset: restaurantAsset, fallbackUrl: restaurantFallback);
  }

  /// Reproduce sonido para nueva orden disponible/confirmada para repartidor
  Future<void> playDeliveryNewOrder() async {
    if (_currentRole != UserRole.delivery_agent) return;
    if (!_shouldPlay('delivery')) return;
    await _playAssetOrFallback(asset: deliveryAsset, fallbackUrl: deliveryFallback);
  }
}
