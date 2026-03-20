import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/core/session/user_session.dart';

/// 🔔 Servicio de notificaciones push (FCM + local)
/// Maneja tokens de dispositivo, notificaciones en foreground/background
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'doa_orders',
    'Órdenes Doa Repartos',
    description: 'Notificaciones de órdenes en tiempo real',
    importance: Importance.max,
    playSound: true,
  );

  bool _initialized = false;
  StreamSubscription<UserSession>? _sessionSubscription;

  /// Inicializar el servicio de notificaciones push
  static Future<void> init() async {
    await PushNotificationService()._initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    debugPrint('🔔 [PUSH] Inicializando PushNotificationService...');

    // Web: firebase_messaging se maneja via service worker, solo registrar token
    if (kIsWeb) {
      await _initWeb();
      _initialized = true;
      _listenSessionChanges();
      return;
    }

    // Android / iOS
    await _requestPermission();
    await _initLocalNotifications();
    await _createAndroidChannel();
    await _getAndSaveToken();

    // Foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Tap en notificación cuando app está en background (no killed)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Token refresh
    _fcm.onTokenRefresh.listen((token) {
      debugPrint('🔄 [PUSH] Token refreshed');
      _saveToken(token);
    });

    _initialized = true;
    _listenSessionChanges();
    debugPrint('✅ [PUSH] PushNotificationService inicializado');
  }

  /// Escucha cambios de sesión para registrar el token al hacer login
  void _listenSessionChanges() {
    _sessionSubscription?.cancel();
    _sessionSubscription = SessionManager.instance.sessionStream.listen((session) {
      if (session.isValid) {
        debugPrint('🔔 [PUSH] Sesión activa detectada — re-registrando FCM token');
        if (kIsWeb) {
          _initWeb();
        } else {
          _getAndSaveToken();
        }
      }
    });
  }

  Future<void> _initWeb() async {
    try {
      // Pedir permiso en web
      final settings = await _fcm.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await _fcm.getToken(
          vapidKey: 'BDlAkMvK8949P0Hzf2pmgEvEOE0rwzWoYJXM7X0q411wTKylIbAgs8trdUU6k1i_kWZoK9hj6lJ_v26OXhyarvA',
        );
        if (token != null) await _saveToken(token);
      }
    } catch (e) {
      debugPrint('⚠️ [PUSH] Web init error: $e');
    }
  }

  Future<void> _requestPermission() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 [PUSH] Permission: ${settings.authorizationStatus}');
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (details) {
        debugPrint('🔔 [PUSH] Notification tapped: ${details.payload}');
      },
    );
  }

  Future<void> _createAndroidChannel() async {
    if (!Platform.isAndroid) return;
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channel);
  }

  Future<void> _getAndSaveToken() async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('📱 [PUSH] FCM Token obtenido');
        await _saveToken(token);
      }
    } catch (e) {
      debugPrint('⚠️ [PUSH] No se pudo obtener FCM token: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final user = SupabaseConfig.auth.currentUser;
      if (user == null) return;

      String platform = 'android';
      if (kIsWeb) {
        platform = 'web';
      } else if (Platform.isIOS) {
        platform = 'ios';
      }

      // Obtener el rol del usuario desde metadata
      final userMeta = user.userMetadata;
      final role = userMeta?['role'] as String?;

      await SupabaseConfig.client.rpc('upsert_device_token', params: {
        'p_token': token,
        'p_platform': platform,
        'p_role': role,
      });
      debugPrint('✅ [PUSH] Token guardado en DB');
    } catch (e) {
      debugPrint('⚠️ [PUSH] Error guardando token: $e');
    }
  }

  /// Llamar al cerrar sesión para eliminar el token del dispositivo
  static Future<void> deleteToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await SupabaseConfig.client.rpc('delete_device_token', params: {
          'p_token': token,
        });
        debugPrint('✅ [PUSH] Token eliminado de DB');
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('⚠️ [PUSH] Error eliminando token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 [PUSH] Foreground message: ${message.notification?.title}');
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && !kIsWeb) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: message.data['order_id'],
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('🔔 [PUSH] Notification tapped (background): ${message.data}');
    // Navegación a la orden puede agregarse aquí via NavigationService
  }
}
