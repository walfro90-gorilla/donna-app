import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/services/polling_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/screens/restaurants/restaurants_screen.dart';
import 'package:doa_repartos/screens/profile/profile_screen.dart';
import 'package:doa_repartos/screens/orders/order_details_screen.dart';
import 'package:doa_repartos/widgets/restaurant_card.dart';
import 'package:doa_repartos/widgets/active_order_tracker.dart';
import 'package:doa_repartos/widgets/multi_order_tracker.dart';
import 'package:doa_repartos/core/theme/app_theme_controller.dart';
import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/core/session/user_session.dart';
import 'package:doa_repartos/services/review_service.dart';
import 'package:doa_repartos/screens/reviews/review_screen.dart';
import 'package:doa_repartos/widgets/welcome_onboarding_card.dart';
import 'package:doa_repartos/core/supabase/supabase_rpc.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<DoaRestaurant> _featuredRestaurants = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _showWelcomeCard = true; // Mostrar card de bienvenida
  bool _isFirstTime = true; // Es primera vez del usuario
  DoaUser? _currentUser; // Usuario actual
  List<DoaOrder> _activeOrders = [];
  DoaOrder? _activeOrder;
  Timer? _orderRefreshTimer;
  Timer? _trackerBackupTimer;
  StreamSubscription<List<DoaOrder>>? _clientActiveOrdersSubscription;
  StreamSubscription<void>? _restaurantsUpdatesSubscription;
  StreamSubscription<void>? _couriersUpdatesSubscription;
  StreamSubscription<void>? _pollingRestaurantsUpdatesSubscription;
  StreamSubscription<void>? _pollingRefreshDataSubscription;
  StreamSubscription<DoaOrder>? _orderUpdatesSubscription;
  StreamSubscription<UserSession>? _sessionSubscription;
  final _reviewService = const ReviewService();
  bool _isShowingReviewSheet = false;
  // Evita mostrar el modal de review más de una vez por pedido en esta sesión
  final Set<String> _reviewPromptedOrderIds = <String>{};
  // Evita condiciones de carrera cuando llegan 2 eventos casi simultáneos
  final Set<String> _reviewPromptInFlight = <String>{};
  bool _hasActiveCouriers =
      true; // Gate: mostrar restaurantes solo si hay repartidores online
  // UI header state
  String? _deliveryAddress;
  double? _deliveryLat;
  double? _deliveryLon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('🚀 [HOME] ===== INICIALIZANDO HOME SCREEN =====');

    // CRÍTICO: Cargar órdenes activas INMEDIATAMENTE como los restaurantes
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        debugPrint(
            '🚀 [HOME] ===== POST FRAME CALLBACK - CARGA INMEDIATA =====');

        final user = SupabaseConfig.client.auth.currentUser;
        if (user?.emailConfirmedAt == null) {
          debugPrint('❌ [HOME] Usuario no autenticado en post frame callback');
          return;
        }

        // Verificar que el widget sigue mounted
        if (!mounted) {
          debugPrint(
              '❌ [HOME] Widget ya no está mounted, cancelando post frame callback');
          return;
        }

        // ✅ PROTECCIÓN CRÍTICA: Verificar que el usuario actual sea un cliente
        debugPrint('🔍 [HOME] ===== VERIFICANDO TIPO DE USUARIO =====');
        debugPrint('👤 [HOME] Usuario ID: ${user!.id}');
        debugPrint('📧 [HOME] Usuario Email: ${user.email}');

        // Verificar rol del usuario en la BD
        final userData = await SupabaseConfig.client
            .from('users')
            .select('role')
            .eq('id', user.id)
            .single();

        final userRole = userData['role'] as String?;
        final normalizedRole =
            (userRole ?? 'cliente').toString().toLowerCase().trim();
        debugPrint(
            '👑 [HOME] Usuario Role: $userRole -> normalizado: $normalizedRole');

        // Aceptar 'cliente' y su variante en inglés 'client'. Si es null, tratamos como cliente.
        final isClient =
            normalizedRole == 'cliente' || normalizedRole == 'client';
        if (!isClient) {
          debugPrint(
              '❌ [HOME] ===== ERROR CRÍTICO: USUARIO NO ES CLIENTE =====');
          debugPrint(
              '❌ [HOME] Usuario role: $userRole, pero dashboard es para cliente');
          debugPrint('❌ [HOME] Evitando carga de datos incorrectos');

          // Mostrar error y redirigir a login - con verificaciones mejoradas
          if (mounted && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Error: Este dashboard es solo para clientes'),
                backgroundColor: Colors.red,
              ),
            );

            // Redirigir al login después de un breve delay - con manejo de errores
            Timer(const Duration(seconds: 2), () {
              if (mounted && context.mounted) {
                try {
                  Navigator.of(context).pushReplacementNamed('/login');
                } catch (e) {
                  debugPrint('❌ [HOME] Error navegando al login: $e');
                }
              } else {
                debugPrint(
                    '⚠️ [HOME] Context ya no válido para navegación al login');
              }
            });
          }
          return;
        }

        debugPrint('✅ [HOME] ===== USUARIO CLIENTE VERIFICADO =====');

        // Verificar nuevamente que el widget siga montado antes de continuar
        if (!mounted) {
          debugPrint(
              '❌ [HOME] Widget ya no mounted después de verificación de rol');
          return;
        }

        final realtimeService = RealtimeNotificationService.forUser(user.id);
        debugPrint(
            '🚀 [HOME] Service para ${user.id} inicializado: ${realtimeService.isInitialized}');

        // Forzar inicialización si no está inicializado
        if (!realtimeService.isInitialized) {
          debugPrint('🚀 [HOME] ===== INICIALIZANDO REALTIME SERVICE =====');
          await realtimeService.initialize();
          debugPrint(
              '🚀 [HOME] Service después de init: ${realtimeService.isInitialized}');
        }

        // Verificar que el widget siga montado antes de refrescar
        if (!mounted) {
          debugPrint('❌ [HOME] Widget ya no mounted antes de refresh');
          return;
        }

        // Refrescar órdenes
        await realtimeService.refreshClientActiveOrders();

        // VERIFICACIÓN MANUAL ADICIONAL - Consulta directa a la BD
        if (mounted) {
          await _manualOrderCheck();
        }

        debugPrint('✅ [HOME] ===== POST FRAME CALLBACK COMPLETADO =====');
      } catch (e) {
        debugPrint('❌ [HOME] CRITICAL ERROR en post frame callback: $e');
        debugPrint('❌ [HOME] Stack trace: ${StackTrace.current}');

        // Manejo de emergencia
        if (mounted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('❌ Error cargando datos. Intenta reiniciar la app.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });

    _loadData(); // Cargar restaurantes
    _loadUserData(); // Cargar datos del usuario
    _setupRealtimeUpdates(); // Configurar tiempo real
    _initializeActiveOrder(); // Verificación adicional
    _startOrderTracking(); // Timer de respaldo
    _checkFirstTimeUser(); // Verificar si es primera vez

    // Escuchar cambios de sesión para actualizar saludo en AppBar
    try {
      _sessionSubscription =
          SessionManager.instance.sessionStream.listen((session) {
        if (!mounted) return;
        if (session.role == UserRole.client) {
          setState(() {
            _currentUser = session.clientData ??
                (session.userData != null
                    ? DoaUser.fromJson(session.userData!)
                    : _currentUser);
          });
        }
      });
    } catch (e) {
      debugPrint('⚠️ [HOME] No se pudo suscribir a SessionManager: $e');
    }
    debugPrint('✅ [HOME] ===== HOME SCREEN INICIALIZADO =====');
  }

  @override
  void dispose() {
    try {
      debugPrint('🗑️ [HOME] ===== DISPOSING HOME SCREEN =====');

      WidgetsBinding.instance.removeObserver(this);

      // Cancelar todos los timers
      _orderRefreshTimer?.cancel();
      _trackerBackupTimer?.cancel();

      // Cancelar todas las subscripciones
      _clientActiveOrdersSubscription?.cancel();
      _restaurantsUpdatesSubscription?.cancel();
      _couriersUpdatesSubscription?.cancel();
      _pollingRestaurantsUpdatesSubscription?.cancel();
      _pollingRefreshDataSubscription?.cancel();
      _orderUpdatesSubscription?.cancel();
      _sessionSubscription?.cancel();

      debugPrint('✅ [HOME] Todos los recursos liberados exitosamente');
    } catch (e) {
      debugPrint('❌ [HOME] Error durante dispose: $e');
    } finally {
      super.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      print(
          '📱 [HOME] ========= APP RESUMED - CHECKING ACTIVE ORDER VIA TIEMPO REAL =========');
      // Verificar pedidos activos cuando la app vuelve al primer plano
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt != null) {
        RealtimeNotificationService.forUser(user!.id)
            .refreshClientActiveOrders();
      }
    }
  }

  /// Cargar datos del usuario actual
  Future<void> _loadUserData() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt != null) {
        // Usar servicio centralizado que ya incluye client_profiles(*)
        final userData = await DoaRepartosService.getUserById(user!.id);

        if (mounted && userData != null) {
          final parsed = DoaUser.fromJson(userData);
          setState(() {
            _currentUser = parsed;
            _deliveryAddress = parsed.formattedAddress ?? parsed.address ?? '';
            _deliveryLat = parsed.latitude;
            _deliveryLon = parsed.longitude;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error cargando datos de usuario: $e');
    }
  }

  Future<void> _openAddressPicker() async {
    try {
      /*
      // ANTERIOR: Modal Bottom Sheet (causaba problemas con el teclado)
      final result = await showModalBottomSheet<AddressPickResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AddressPickerModal(
          initialAddress: _deliveryAddress ?? (_currentUser?.address ?? ''),
        ),
      );
      */
      
      // NUEVO: Full Screen Dialog para evitar traslape de teclado
      final result = await Navigator.of(context).push<AddressPickResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => Scaffold(
            body: AddressPickerModal(
              initialAddress: _deliveryAddress ?? (_currentUser?.address ?? ''),
            ),
          ),
        ),
      );
      if (result != null && mounted) {
        final confirmed = await _showConfirmAddressDialog(result);
        if (confirmed != true) return;
        setState(() {
          _deliveryAddress = result.formattedAddress;
          _deliveryLat = result.lat;
          _deliveryLon = result.lon;
        });
        await _persistAddress(result);
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error abriendo picker de dirección: $e');
    }
  }

  Future<bool?> _showConfirmAddressDialog(AddressPickResult result) {
    final theme = Theme.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Confirmar dirección de entrega'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.formattedAddress, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                  'Lat: ${result.lat.toStringAsFixed(6)}  Lon: ${result.lon.toStringAsFixed(6)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(height: 12),
              Text(
                  '¿Estás seguro de confirmar esta dirección para tus entregas?',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _persistAddress(AddressPickResult result) async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;

      debugPrint('📍 [HOME] Guardando dirección en client_profiles: "${result.formattedAddress}" lat=${result.lat}, lon=${result.lon}');

      // 1) Guardar usando helper (usa RPC update_client_default_address o upsert directo)
      final ok = await DoaRepartosService.updateClientDefaultAddress(
        userId: user.id,
        address: result.formattedAddress,
        lat: result.lat,
        lon: result.lon,
        addressStructured: result.addressStructured,
      );

      // 2) Verificación ligera contra client_profiles
      try {
        final row = await SupabaseConfig.client
            .from('client_profiles')
            .select('address, lat, lon')
            .eq('user_id', user.id)
            .maybeSingle();
        bool approximatelyEqual(double? a, double? b) => a != null && b != null && (a - b).abs() < 1e-6;
        final addr = row?['address']?.toString();
        final latDb = (row?['lat'] as num?)?.toDouble();
        final lonDb = (row?['lon'] as num?)?.toDouble();
        if (ok && addr == result.formattedAddress && approximatelyEqual(latDb, result.lat) && approximatelyEqual(lonDb, result.lon)) {
          debugPrint('✅ [HOME] Dirección persistida correctamente en client_profiles');
        } else {
          debugPrint('⚠️ [HOME] Persistencia no verificada. addr="$addr" lat=$latDb lon=$lonDb');
        }
      } catch (e) {
        debugPrint('ℹ️ [HOME] No se pudo verificar persistencia: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dirección actualizada'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error guardando dirección: $e');
    }
  }

  /// Verificar si es la primera vez del usuario
  Future<void> _checkFirstTimeUser() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        final isFirst =
            await OnboardingNotificationService.isFirstTimeUser(user.id);
        if (mounted) {
          setState(() => _isFirstTime = isFirst);
        }
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error verificando primera vez: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      debugPrint(
          '🔄 [HOME] Cargando restaurantes para dashboard del cliente...');

      // Primero: verificar si hay repartidores activos
      final hasCouriers = await DoaRepartosService.hasActiveCouriers();
      if (mounted) {
        setState(() => _hasActiveCouriers = hasCouriers);
      }

      if (!hasCouriers) {
        debugPrint(
            '⛔ [HOME] No hay repartidores activos. Ocultando restaurantes.');
        if (mounted) {
          setState(() {
            _featuredRestaurants = [];
            _isLoading = false;
          });
        }
        return;
      }

      // CRÍTICO: Obtener solo restaurantes aprobados Y online (TRUE)
      final allRestaurants = await DoaRepartosService.getRestaurants(
          status: 'approved', isOnline: true);

      debugPrint(
          '📊 [HOME] Total restaurantes aprobados y online: ${allRestaurants.length}');

      // Log cada restaurante para debugging
      for (var restaurant in allRestaurants) {
        debugPrint('🏪 [HOME] ${restaurant.name}: ONLINE (aprobado)');
      }

      if (mounted) {
        try {
          setState(() {
            // Todos los restaurantes obtenidos ya están aprobados y online
            _featuredRestaurants = allRestaurants.take(5).toList();
            _isLoading = false;
          });
        } catch (e) {
          debugPrint(
              '❌ [HOME] Error actualizando lista de restaurantes en setState: $e');
        }
      }

      debugPrint(
          '🎯 [HOME] Restaurantes destacados mostrados: ${_featuredRestaurants.length}');

      // También refrescar pedido activo cuando se hace refresh
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt != null) {
        RealtimeNotificationService.forUser(user!.id)
            .refreshClientActiveOrders();
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error cargando restaurantes: $e');
      if (mounted) {
        try {
          setState(() => _isLoading = false);
        } catch (e2) {
          debugPrint('❌ [HOME] Error actualizando _isLoading en catch: $e2');
        }
      }
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    }
  }

  /// Inicializar y cargar pedido activo inmediatamente al iniciar la pantalla
  Future<void> _initializeActiveOrder() async {
    print(
        '🔄 [HOME] ========= INICIALIZANDO PEDIDO ACTIVO VIA TIEMPO REAL =========');
    // Usar el nuevo sistema de tiempo real
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt != null) {
      RealtimeNotificationService.forUser(user!.id).refreshClientActiveOrders();
    }
    print(
        '✅ [HOME] ========= PEDIDO ACTIVO INICIALIZADO VIA TIEMPO REAL =========');
  }

  void _startOrderTracking() {
    // Actualizar cada 10 segundos como respaldo más frecuente
    _orderRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      try {
        // SEGURIDAD: Verificar que el widget siga montado
        if (!mounted) {
          debugPrint(
              '⚠️ [HOME] Order refresh timer ejecutándose pero widget ya no mounted');
          _orderRefreshTimer?.cancel();
          return;
        }

        print(
            '⏰ [HOME] ========= TIMER PERIODIC CHECK VIA TIEMPO REAL =========');
        // Usar el nuevo sistema de tiempo real
        final user = SupabaseConfig.client.auth.currentUser;
        if (user?.emailConfirmedAt != null) {
          RealtimeNotificationService.forUser(user!.id)
              .refreshClientActiveOrders();
        }
      } catch (e) {
        debugPrint('❌ [HOME] Error en order refresh timer: $e');
      }
    });
  }

  /// Configurar actualizaciones en tiempo real usando el nuevo sistema de órdenes
  void _setupRealtimeUpdates() {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) {
      debugPrint('❌ [HOME] Usuario no autenticado en setup realtime updates');
      return;
    }

    final realtimeService = RealtimeNotificationService.forUser(user!.id);

    debugPrint('🎯 [HOME] ===== CONFIGURANDO ESCUCHA DE TIEMPO REAL =====');
    debugPrint(
        '🎯 [HOME] Service inicializado: ${realtimeService.isInitialized}');

    // 🎯 NUEVO SISTEMA: Escuchar directamente las órdenes activas del cliente
    try {
      _clientActiveOrdersSubscription =
          realtimeService.clientActiveOrders.listen((orders) {
        debugPrint(
            '🎯 [HOME] ===== ÓRDENES ACTIVAS RECIBIDAS EN TIEMPO REAL =====');
        debugPrint('📊 [HOME] Cantidad de órdenes activas: ${orders.length}');
        debugPrint(
            '🔗 [HOME] Stream subscription activa: ${_clientActiveOrdersSubscription != null}');
        debugPrint('🏠 [HOME] Widget mounted: $mounted');
        debugPrint('🕰 [HOME] Timestamp: ${DateTime.now()}');

        if (orders.isNotEmpty) {
          // Tomar la orden más reciente
          final mostRecentOrder = orders.first;
          debugPrint('📱 [HOME] ===== ORDEN ENCONTRADA =====');
          debugPrint('📱 [HOME] Order ID: ${mostRecentOrder.id}');
          debugPrint('📱 [HOME] Order Status: ${mostRecentOrder.status}');
          debugPrint(
              '📱 [HOME] Order Restaurant: ${mostRecentOrder.restaurant?.name}');
          debugPrint('📱 [HOME] Order User ID: ${mostRecentOrder.userId}');
          debugPrint(
              '📱 [HOME] Order Created At: ${mostRecentOrder.createdAt}');
          debugPrint('🚚 [HOME] Delivery Agent ID: ${mostRecentOrder.deliveryAgentId}');
          debugPrint('👤 [HOME] Delivery Agent Name: ${mostRecentOrder.deliveryAgent?.name}');

          if (mounted) {
            try {
              debugPrint('🔄 [HOME] ===== ANTES DE setState =====');
              debugPrint('🔄 [HOME] _activeOrders.length ANTES: ${_activeOrders.length}');
              debugPrint('🔄 [HOME] _activeOrder ANTES: ${_activeOrder?.id}');
              if (_activeOrders.isNotEmpty) {
                debugPrint('🔄 [HOME] Status orden ANTES: ${_activeOrders.first.status}');
                debugPrint('🔄 [HOME] Delivery ANTES: ${_activeOrders.first.deliveryAgent?.name}');
              }
              
              setState(() {
                _activeOrders = orders;
                _activeOrder = mostRecentOrder;
              });
              
              debugPrint('✅ [HOME] ===== DESPUÉS DE setState =====');
              debugPrint('✅ [HOME] _activeOrders.length DESPUÉS: ${_activeOrders.length}');
              debugPrint('✅ [HOME] _activeOrder DESPUÉS: ${_activeOrder?.id}');
              if (_activeOrders.isNotEmpty) {
                debugPrint('✅ [HOME] Status orden DESPUÉS: ${_activeOrders.first.status}');
                debugPrint('✅ [HOME] Delivery DESPUÉS: ${_activeOrders.first.deliveryAgent?.name}');
              }
              debugPrint('🔍 [HOME] ¿Tracker debe mostrarse? ${_activeOrder != null}');
            } catch (e) {
              debugPrint(
                  '❌ [HOME] Error actualizando _activeOrder en setState: $e');
            }
          } else {
            debugPrint(
                '❌ [HOME] Widget no está mounted, no se puede actualizar estado');
          }
        } else {
          debugPrint('❌ [HOME] ===== NO HAY ÓRDENES ACTIVAS =====');
          debugPrint('❌ [HOME] Ocultando tracker');
          if (mounted) {
            try {
              setState(() {
                _activeOrders = [];
                _activeOrder = null;
              });
            } catch (e) {
              debugPrint('❌ [HOME] Error ocultando tracker en setState: $e');
            }
          }
        }

        // Log final del estado
        debugPrint(
            '🏁 [HOME] Estado final - _activeOrder: ${_activeOrder?.id ?? 'NULL'}');
      }, onError: (error) {
        debugPrint(
            '❌ [HOME] CRÍTICO: Error en stream de órdenes activas: $error');
      }, onDone: () {
        debugPrint('⚠️ [HOME] ADVERTENCIA: Stream de órdenes activas se cerró');
      });

      debugPrint('✅ [HOME] Suscripción al stream configurada exitosamente');
    } catch (e) {
      debugPrint('❌ [HOME] ERROR CONFIGURANDO STREAM: $e');
    }

    // Escuchar actualizaciones de restaurantes (online/offline)
    _restaurantsUpdatesSubscription =
        realtimeService.restaurantsUpdated.listen((_) {
      debugPrint(
          '🔔 [HOME] Actualización de restaurantes recibida en tiempo real');

      // Recargar la lista de restaurantes cuando hay cambios
      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🍴 ¡Restaurantes actualizados!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // Escuchar cambios de repartidores (online/offline)
    _couriersUpdatesSubscription = realtimeService.couriersUpdated.listen((_) {
      debugPrint('🔔 [HOME] Cambio en repartidores detectado (realtime)');
      _loadData(); // Reevalúa hasActiveCouriers + refresca lista

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚚 ¡Disponibilidad de repartidores actualizada!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // Escuchar cambios de órdenes para detectar entregas y solicitar reseña
    _orderUpdatesSubscription = realtimeService.orderUpdates.listen((order) {
      final current = SupabaseConfig.client.auth.currentUser;
      if (current?.emailConfirmedAt != null &&
          order.status == OrderStatus.delivered &&
          order.userId == current!.id) {
        _maybePromptReview(order.id);
      }
    });

    // Inicializar polling como respaldo adicional
    _initializePollingBackup();

    // Timer de backup para forzar verificación de tracker cada 15 segundos
    _trackerBackupTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        // SEGURIDAD: Verificar que el widget siga montado
        if (!mounted) {
          debugPrint(
              '⚠️ [HOME] Timer backup ejecutándose pero widget ya no mounted');
          _trackerBackupTimer?.cancel();
          return;
        }

        debugPrint('⏰ [HOME] ===== TIMER BACKUP: VERIFICANDO TRACKER =====');
        debugPrint(
            '⏰ [HOME] _activeOrder actual: ${_activeOrder?.id ?? 'NULL'}');

        // Solo actualizar si no hay orden activa mostrada
        if (_activeOrder == null) {
          debugPrint(
              '⏰ [HOME] No hay tracker visible, forzando verificación...');
          final user = SupabaseConfig.client.auth.currentUser;
          if (user?.emailConfirmedAt != null) {
            RealtimeNotificationService.forUser(user!.id)
                .refreshClientActiveOrders();
          }
        } else {
          debugPrint('⏰ [HOME] Tracker ya visible: ${_activeOrder!.id}');
        }
      } catch (e) {
        debugPrint('❌ [HOME] Error en backup timer periódico: $e');
      }
    });

    // Forzar carga inicial de órdenes activas
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('🗤️ [HOME] ===== POST FRAME CALLBACK INICIADO =====');
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt != null) {
        RealtimeNotificationService.forUser(user!.id)
            .refreshClientActiveOrders();
      }

      // También hacer verificación manual como backup
      _manualOrderCheck();

      // Backup final con delay - PROTEGIDO
      Timer(const Duration(seconds: 3), () {
        try {
          // SEGURIDAD: Verificar que el widget siga montado
          if (!mounted) {
            debugPrint(
                '⚠️ [HOME] Timer ejecutándose pero widget ya no mounted, cancelando');
            return;
          }

          debugPrint('⛱️ [HOME] ===== BACKUP FINAL VERIFICACIÓN =====');
          debugPrint(
              '⛱️ [HOME] _activeOrder después de 3s: ${_activeOrder?.id ?? 'NULL'}');

          if (_activeOrder == null) {
            debugPrint('🚨 [HOME] TRACKER SIGUE NULL DESPUÉS DE 3 SEGUNDOS!');
            final user = SupabaseConfig.client.auth.currentUser;
            if (user?.emailConfirmedAt != null && mounted) {
              RealtimeNotificationService.forUser(user!.id)
                  .refreshClientActiveOrders();
            }
            if (mounted) {
              _manualOrderCheck();
            }
          }
        } catch (e) {
          debugPrint('❌ [HOME] Error en backup timer: $e');
        }
      });

      debugPrint('✅ [HOME] ===== POST FRAME CALLBACK COMPLETADO =====');
    });
  }

  Future<void> _maybePromptReview(String orderId) async {
    // Evitar modales concurrentes y re-prompts del mismo pedido
    if (_isShowingReviewSheet) return;
    if (_reviewPromptedOrderIds.contains(orderId)) {
      debugPrint('ℹ️ [HOME] Review ya fue solicitada para $orderId en esta sesión.');
      return;
    }

    // Evitar condiciones de carrera: si ya hay un prompt en vuelo para esta orden, salimos
    if (_reviewPromptInFlight.contains(orderId)) {
      debugPrint('⏳ [HOME] Review para $orderId ya en vuelo, evitando duplicado');
      return;
    }
    _reviewPromptInFlight.add(orderId);
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) return;
    // Evitar doble invocación si ya tiene alguna reseña para esta orden
    final already = await _reviewService.hasAnyReviewByAuthorForOrder(
        orderId: orderId, authorId: user!.id);
    if (already) {
      _reviewPromptInFlight.remove(orderId);
      return;
    }
    // Marcar este pedido como ya solicitado para no volver a abrirlo
    _reviewPromptedOrderIds.add(orderId);
    _isShowingReviewSheet = true;
    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.3,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (_, __) => ReviewScreen(orderId: orderId),
        ),
      );
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Gracias por calificar!')));

        // Notificar a otras pantallas (p. ej., OrderDetails) para que deshabiliten el botón
        // y actualicen su estado de reseña sin necesidad de recargar manualmente.
        // Publicar evento usando EventBus
        // Se hace import explícito arriba del archivo
        EventBus.instance.publish<DataUpdatedEvent>(
          DataUpdatedEvent(
            dataType: 'review_submitted',
            data: {
              'order_id': orderId,
              'author_id': user.id,
            },
            timestamp: DateTime.now(),
            userId: user.id,
          ),
        );
      }
    } finally {
      _isShowingReviewSheet = false;
      _reviewPromptInFlight.remove(orderId);
    }
  }

  /// Inicializar servicio de polling como respaldo adicional
  Future<void> _initializePollingBackup() async {
    try {
      final user = DoaRepartosService.getCurrentUser();
      if (user != null) {
        debugPrint(
            '🔄 [HOME] Inicializando polling backup para restaurantes...');

        final pollingService = PollingService();
        await pollingService.initialize(user.id, user.role);

        // Escuchar actualizaciones del polling service para restaurantes Y órdenes
        _pollingRestaurantsUpdatesSubscription =
            pollingService.restaurantsUpdated.listen((_) {
          debugPrint(
              '🔔 [HOME] Actualización de restaurantes recibida via POLLING');
          _loadData();
        });

        // CRÍTICO: También escuchar datos generales via polling
        _pollingRefreshDataSubscription =
            pollingService.refreshData.listen((_) {
          try {
            // SEGURIDAD: Verificar que el widget siga montado
            if (!mounted) {
              debugPrint(
                  '⚠️ [HOME] Polling refresh ejecutándose pero widget ya no mounted');
              _pollingRefreshDataSubscription?.cancel();
              return;
            }

            debugPrint(
                '🔔 [HOME] Actualización general de datos recibida via POLLING');
            // Usar el nuevo sistema de tiempo real en lugar de _checkForActiveOrder
            final user = SupabaseConfig.client.auth.currentUser;
            if (user?.emailConfirmedAt != null) {
              RealtimeNotificationService.forUser(user!.id)
                  .refreshClientActiveOrders();
            }
          } catch (e) {
            debugPrint('❌ [HOME] Error en polling refresh subscription: $e');
          }
        });

        debugPrint('✅ [HOME] Polling backup inicializado correctamente');
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error inicializando polling backup: $e');
    }
  }

  /// Verificación manual directa a la base de datos para debugging
  Future<void> _manualOrderCheck() async {
    try {
      debugPrint('🔍 [HOME] ===== VERIFICACIÓN MANUAL DE ÓRDENES =====');

      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [HOME] Usuario no autenticado para verificación manual');
        return;
      }

      debugPrint('👤 [HOME] Usuario manual check: ${user!.id}');

      // Consulta directa sin el servicio de tiempo real - CON RELACIONES ESPECÍFICAS
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            user:users!orders_user_id_fkey(*),
            restaurant:restaurants(*),
            delivery_agent:users!orders_delivery_agent_id_fkey(*),
            order_items(
              *,
              product:products(*)
            )
          ''')
          .eq('user_id', user.id)
          .inFilter('status', [
            'pending',
            'confirmed',
            'in_preparation',
            'ready_for_pickup',
            'assigned',
            'on_the_way'
          ])
          .order('created_at', ascending: false);

      debugPrint('🗃️ [HOME] ===== RESPUESTA MANUAL =====');
      debugPrint('📊 [HOME] Raw response: $response');
      debugPrint('📊 [HOME] Response length: ${(response as List).length}');

      if ((response).isNotEmpty) {
        final orders =
            (response).map((json) => DoaOrder.fromJson(json)).toList();
        debugPrint('✅ [HOME] ===== ÓRDENES ENCONTRADAS MANUALMENTE =====');
        debugPrint('📊 [HOME] Total órdenes: ${orders.length}');

        for (var order in orders) {
          debugPrint(
              '📋 [HOME] Order: ${order.id} | Status: ${order.status} | Restaurant: ${order.restaurant?.name}');
        }

        // Si encontramos órdenes pero el tracker no aparece, hay un problema en el stream
        if (orders.isNotEmpty && _activeOrder == null) {
          debugPrint('🚨 [HOME] ===== INCONSISTENCIA CRÍTICA DETECTADA =====');
          debugPrint(
              '🚨 [HOME] BD tiene órdenes activas pero _activeOrder es null');
          debugPrint('🚨 [HOME] Esto indica que el stream NO está funcionando');
          debugPrint('🚨 [HOME] FORZANDO UPDATE MANUAL DEL ESTADO');

          final orderToShow = orders.first;
          debugPrint(
              '🔧 [HOME] Forzando orden: ${orderToShow.id} | Status: ${orderToShow.status}');

          // Forzar actualización del estado como último recurso
          if (mounted) {
            try {
              setState(() {
                _activeOrders = orders;
                _activeOrder = orderToShow;
              });
              debugPrint(
                  '✅ [HOME] ✅ ESTADO FORZADO EXITOSAMENTE - TRACKER DEBE APARECER AHORA');
              debugPrint('✅ [HOME] _activeOrder es ahora: ${_activeOrder?.id}');
            } catch (e) {
              debugPrint(
                  '❌ [HOME] Error forzando _activeOrder en setState: $e');
            }
          } else {
            debugPrint('❌ [HOME] Widget no mounted, no se puede forzar estado');
          }
        } else if (_activeOrder != null) {
          debugPrint(
              '✅ [HOME] _activeOrder ya está configurado: ${_activeOrder!.id}');
        }
      } else {
        debugPrint('❌ [HOME] ===== NO HAY ÓRDENES ACTIVAS EN BD =====');
      }
    } catch (e) {
      debugPrint('❌ [HOME] Error en verificación manual: $e');
    }
  }

  /// DEPRECATED - Solo mantener como respaldo de emergencia
  /// El sistema principal ahora usa RealtimeNotificationService.clientActiveOrders
  Future<void> _checkForActiveOrder() async {
    debugPrint(
        '⚠️ [HOME] MÉTODO LEGACY: _checkForActiveOrder llamado (usar tiempo real)');
    // Solo redirigir al sistema de tiempo real
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt != null) {
      RealtimeNotificationService.forUser(user!.id).refreshClientActiveOrders();
    }
  }

  /// Verifica si un estado de orden es considerado "activo" para mostrar en el tracker
  bool _isActiveStatus(OrderStatus status) {
    final activeStatuses = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.inPreparation,
      OrderStatus.readyForPickup,
      OrderStatus.assigned,
      OrderStatus.onTheWay,
    ];
    final isActive = activeStatuses.contains(status);
    print('🔍 [HOME] _isActiveStatus(${status}) = $isActive');
    return isActive;
  }

  void _showOrderStatusNotification(DoaOrder order) {
    final statusMessages = {
      'pending': 'Tu pedido está esperando confirmación del restaurante 🕒',
      'confirmed': 'Tu pedido fue confirmado, se está preparando 👨‍🍳',
      'in_preparation': 'Tu comida se está preparando con cariño 🍳',
      'ready_for_pickup': 'Tu pedido está listo, esperando repartidor 📦',
      'in_delivery': 'Tu pedido está en camino hacia tu dirección 🚗',
      'completed': '¡Tu pedido ha sido entregado! Disfruta tu comida 🎉',
    };

    final statusKey = order.status.toString().split('.').last.toLowerCase();
    final message =
        statusMessages[statusKey] ?? 'Estado del pedido actualizado';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Ver',
            textColor: Colors.white,
            onPressed: () => _showOrderDetails(order),
          ),
        ),
      );
    }
  }

  void _showOrderDetails(DoaOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OrderDetailsScreen(order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Log crítico para debugging del build (comentado)
    // debugPrint('🏠 [HOME] ===== BUILD EJECUTÁNDOSE =====');
    // debugPrint('🏠 [HOME] _activeOrder estado: ${_activeOrder?.id ?? 'NULL'}');
    // debugPrint('🏠 [HOME] ¿Tracker debe renderizarse? ${_activeOrder != null}');

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final greetName = (_currentUser?.name != null &&
                    _currentUser!.name!.trim().isNotEmpty)
                ? _currentUser!.name!.trim()
                : 'cliente';

            // Responsive: si hay poco espacio, acortar el saludo
            final width = MediaQuery.of(context).size.width;
            final salutation =
                width < 360 ? 'Hola, $greetName' : 'Hey, $greetName 👋';

            return Text(
              salutation,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            );
          },
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                  color: Theme.of(context).colorScheme.onSurface),
              tooltip: isDark ? 'Modo claro' : 'Modo oscuro',
              onPressed: () => AppThemeController.toggle()),
          IconButton(
              icon: Icon(Icons.person_outline,
                  color: Theme.of(context).colorScheme.onSurface),
              onPressed: () {
                Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()));
              })
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                print('🔄 [HOME] ========= REFRESH MANUAL TRIGGERED =========');
                await _loadData();
                await _checkForActiveOrder(); // CRÍTICO: También verificar pedidos activos
                print('✅ [HOME] ========= REFRESH MANUAL COMPLETADO =========');
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Deliver to + greeting + search
                    _ClientHeader(
                      address: _deliveryAddress,
                      userName: _currentUser?.name,
                      onTapAddress: _openAddressPicker,
                      onSearchChanged: (value) {
                        if (mounted) setState(() => _searchQuery = value);
                      },
                    ),

                    const SizedBox(height: 16),

                    // Categorías rápidas
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Categorías',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RestaurantsScreen(),
                            ),
                          ),
                          child: const Text('Ver todas'),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),

                    _CategoryChips(canExplore: _hasActiveCouriers),

                    const SizedBox(height: 16),

                    // Card de bienvenida para clientes nuevos
                    if (_currentUser != null &&
                        _showWelcomeCard &&
                        _isFirstTime) ...[
                      Builder(
                        builder: (context) {
                          final onboardingStatus = OnboardingNotificationService
                              .calculateClientOnboarding(_currentUser!);
                          final welcomeMessage =
                              OnboardingNotificationService.getWelcomeMessage(
                                  UserRole.client, onboardingStatus);

                          return WelcomeOnboardingCard(
                            welcomeMessage: welcomeMessage,
                            onboardingStatus: onboardingStatus,
                            onActionPressed: () {
                              // Redirigir a restaurantes
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RestaurantsScreen(),
                                ),
                              );
                            },
                            onDismiss: () {
                              setState(() => _showWelcomeCard = false);
                              // Marcar como visto
                              final user =
                                  SupabaseConfig.client.auth.currentUser;
                              if (user != null) {
                                OnboardingNotificationService
                                    .markOnboardingSeen(user.id);
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],

                    // DEBUGGING CRÍTICO DEL TRACKER (comentado)
                    // Builder(
                    //   builder: (context) {
                    //     debugPrint(
                    //         '🎯 [HOME] ===== BUILD METHOD - VERIFICANDO TRACKER =====');
                    //     debugPrint(
                    //         '🎯 [HOME] _activeOrder: ${_activeOrder?.id ?? 'NULL'}');
                    //     debugPrint(
                    //         '🎯 [HOME] _activeOrder != null: ${_activeOrder != null}');
                    //     debugPrint('🎯 [HOME] Widget mounted: $mounted');
                    //     debugPrint('🎯 [HOME] _isLoading: $_isLoading');
                    //     return const SizedBox.shrink();
                    //   },
                    // ),

                    // Módulo de seguimiento de pedido activo
                    if (_activeOrders.isNotEmpty) ...[
                      Text(
                        _activeOrders.length > 1
                            ? 'Tus Pedidos Activos'
                            : 'Tu Pedido Activo',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      MultiOrderTracker(
                        // CRÍTICO: Key único basado en contenido para forzar rebuild cuando cambian datos
                        key: ValueKey('tracker_${_activeOrders.map((o) => '${o.id}_${o.deliveryAgent?.name ?? "null"}_${o.status}').join('_')}'),
                        orders: _activeOrders,
                        onOrderSelected: (order) {
                          if (mounted) {
                            setState(() => _activeOrder = order);
                          }
                        },
                        onTapOrder: (order) => _showOrderDetails(order),
                      ),
                      const SizedBox(height: 32),
                    ] else ...[
                      // Debug cuando no hay tracker
                      Builder(
                        builder: (context) {
                          debugPrint(
                              '❌ [HOME] ===== NO HAY TRACKER ACTIVO =====');
                          debugPrint('❌ [HOME] _activeOrder es null');
                          debugPrint(
                              '❌ [HOME] Esto significa que no hay órdenes activas en el stream');
                          return const SizedBox.shrink();
                        },
                      ),
                    ],

                    // Promociones
                    SizedBox(
                      height: 160,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _PromoCard(
                            title: '¡50% OFF!',
                            subtitle: 'En combos de hamburguesa',
                            emoji: '🍔',
                            onTap: () {
                              if (!_hasActiveCouriers) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'No hay repartidores activos. Intenta más tarde.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RestaurantsScreen(),
                                ),
                              );
                            },
                          ),
                          _PromoCard(
                            title: 'Pizza Delight!',
                            subtitle: 'Compra 2, ¡lleva 1 gratis!',
                            emoji: '🍕',
                            gradientSecondary: true,
                            onTap: () {
                              if (!_hasActiveCouriers) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'No hay repartidores activos. Intenta más tarde.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RestaurantsScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Restaurantes destacados
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Restaurantes Destacados',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (!_hasActiveCouriers) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'No hay repartidores activos. Intenta más tarde.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RestaurantsScreen(),
                              ),
                            );
                          },
                          child: const Text('Ver todos'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (!_hasActiveCouriers)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Por ahora no hay repartidores activos',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Cuando haya al menos 1 repartidor disponible, los restaurantes aparecerán aquí para que puedas pedir con confianza.',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_featuredRestaurants.isEmpty)
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.restaurant,
                              size: 64,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No hay restaurantes disponibles',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                            ),
                          ],
                        ),
                      )
                    else
                      Column(
                        children: _featuredRestaurants
                            .map((restaurant) => Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: RestaurantCard(restaurant: restaurant),
                                ))
                            .toList(),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ClientHeader extends StatelessWidget {
  final String? address;
  final String? userName;
  final VoidCallback onTapAddress;
  final ValueChanged<String> onSearchChanged;

  const _ClientHeader({
    required this.address,
    required this.userName,
    required this.onTapAddress,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.10),
            theme.colorScheme.secondary.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Deliver to row
          InkWell(
            onTap: onTapAddress,
            borderRadius: BorderRadius.circular(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.place, color: Colors.orange, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Entregar en',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    address?.isNotEmpty == true
                        ? address!
                        : 'Selecciona tu dirección...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Greeting moved to AppBar. Keep spacing minimal before search.
          const SizedBox(height: 4),

          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.15)),
            ),
            child: TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar comida',
                prefixIcon: Icon(Icons.search,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
      constraints: BoxConstraints(),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  final bool canExplore;

  const _CategoryChips({this.canExplore = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <_ChipData>[
      _ChipData('Rolls', Icons.ramen_dining),
      _ChipData('Burger', Icons.lunch_dining),
      _ChipData('Pizza', Icons.local_pizza),
      _ChipData('Dessert', Icons.icecream),
      _ChipData('Fries', Icons.fastfood),
      _ChipData('Tacos', Icons.set_meal),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: chips.map((c) {
          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: false,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(c.label),
                ],
              ),
              shape: StadiumBorder(
                  side: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2))),
              backgroundColor: theme.colorScheme.surface,
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              onSelected: (_) {
                if (!canExplore) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'No hay repartidores activos. Intenta más tarde.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                // Potentially navigate to category filtered list
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RestaurantsScreen()),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChipData {
  final String label;
  final IconData icon;
  const _ChipData(this.label, this.icon);
}

class _PromoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final bool gradientSecondary;
  final VoidCallback onTap;

  const _PromoCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.onTap,
    this.gradientSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = gradientSecondary
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    final end = gradientSecondary
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [start, end]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: 16,
              top: 12,
              child: Text(emoji, style: const TextStyle(fontSize: 40)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Pedir Ahora'),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
