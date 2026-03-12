import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'package:doa_repartos/screens/delivery/unified_orders_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_balance_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_earnings_screen.dart';
import 'package:doa_repartos/screens/profile/profile_screen.dart';
import 'package:doa_repartos/screens/delivery/settlement_screen.dart';
import 'package:doa_repartos/screens/reviews/review_screen.dart';
import 'package:doa_repartos/services/review_service.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:doa_repartos/widgets/welcome_onboarding_card.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';
import 'package:doa_repartos/screens/delivery/delivery_onboarding_dashboard.dart';
import 'package:doa_repartos/widgets/delivery_profile_progress_card.dart';
import 'package:doa_repartos/core/theme/app_theme_controller.dart';

/// Periodo de cálculo para la "Tasa de éxito"
enum SuccessPeriod { today, week }

/// Dashboard principal con navbar para repartidores
class DeliveryMainDashboard extends StatefulWidget {
  const DeliveryMainDashboard({super.key});

  @override
  State<DeliveryMainDashboard> createState() => _DeliveryMainDashboardState();
}

class _DeliveryMainDashboardState extends State<DeliveryMainDashboard> {
  int _selectedIndex = 0;
  late PageController _pageController;
  
  bool isDeliveryAgentOnline = false; // Estado online del repartidor
  DoaUser? _deliveryAgent;
  final bool _showWelcomeCard = true; // Mostrar card de bienvenida
  bool _isFirstTime = true; // Es primera vez del usuario
  bool _hasShownWelcomeModal = false; // Evitar mostrar modal más de una vez
  // Selector de periodo para "Tasa de éxito"
  SuccessPeriod _successPeriod = SuccessPeriod.today;
  Map<String, num> deliveryStats = {
    // Contadores principales
    'assignedOrders': 0,
    'activeDeliveries': 0,
    'completedToday': 0,
    // KPIs adicionales
    'totalDeliveredAllTime': 0,
    'canceledLast30': 0,
    'successRateLast30': 0.0,
    'avgEarningPerDeliveryLast30': 0.0,
    'todayEarnings': 0.0,
    // Nuevos KPIs por periodo
    'successRateToday': 0.0,
    'successRateWeek': 0.0,
  };
  bool isLoadingStats = true;
  Timer? _refreshTimer;
  RealtimeNotificationService? _realtimeService;
  StreamSubscription<List<DoaOrder>>? _ordersSubscription;
  bool _isServiceInitialized = false;
  StreamSubscription? _authStateSubscription;
  String? _initialUserId;
  StreamSubscription<DoaOrder>? _orderUpdatesSubscription;
  final _reviewService = const ReviewService();
  bool _isShowingReviewSheet = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🔥*-*-*-*-*-*-*-*-START DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-*-*🔥');
    debugPrint('🚚 [DELIVERY] ===== INICIALIZANDO DELIVERY DASHBOARD =====');
    
    final currentUser = SupabaseConfig.client.auth.currentUser;
    debugPrint('🔥 [DELIVERY-INIT] Usuario en initState: ${currentUser?.email} (${currentUser?.id})');
    
    // Inicializar PageController siempre (necesario para el UI)
    _pageController = PageController();
    
    // Guardar ID del usuario inicial para detectar cambios
    _initialUserId = currentUser?.id;
    debugPrint('🔥 [DELIVERY-INIT] ID inicial guardado: $_initialUserId');
    
    // Escuchar cambios de sesión
    _setupAuthListener();
    
    // ✅ PROTECCIÓN CRÍTICA: Verificar rol del usuario ANTES de inicializar servicios de datos
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldContinue = await _verifyUserRole();
      if (shouldContinue) {
        debugPrint('✅ [DELIVERY] Usuario verificado, iniciando servicios...');
        await _initializeRealtimeService();
        await _loadDeliveryAgentData();
        await _checkFirstTimeUser();
        _startAutoRefresh();
      } else {
        debugPrint('❌ [DELIVERY] Usuario NO verificado, NO iniciando servicios');
        debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      }
    });
  }

  Future<void> _confirmAndSetAvailability(bool value) async {
    if (_deliveryAgent == null) return;
    // Debe estar aprobado y con onboarding completo
    final onboarding = OnboardingNotificationService.calculateDeliveryOnboarding(_deliveryAgent!);
    // accountState is an enum (DeliveryAccountState); compare correctly
    final isApproved = _deliveryAgent!.accountState == DeliveryAccountState.approved;
    if (!isApproved || !onboarding.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa registro y espera aprobación para activarte'), backgroundColor: Colors.orange),
      );
      if (!onboarding.isComplete) {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()));
      }
      return;
    }

    final action = value ? 'conectarte' : 'desconectarte';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(value ? Icons.wifi : Icons.wifi_off, color: value ? Colors.green : Colors.red), const SizedBox(width: 8), Text(value ? 'Conectarte' : 'Desconectarte')]),
        content: Text('¿Quieres ${action} para recibir pedidos?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirm == true) {
      await _setDeliveryAvailability(value);
    }
  }

  /// Cambiar disponibilidad del repartidor (persistir en BD si es posible)
  Future<void> _setDeliveryAvailability(bool value) async {
    if (_deliveryAgent == null) return;

    // Debe estar aprobado y con onboarding completo
    final onboarding = OnboardingNotificationService.calculateDeliveryOnboarding(_deliveryAgent!);
    final isApproved = _deliveryAgent!.accountState == DeliveryAccountState.approved;
    if (!isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pendiente de aprobación del administrador'), backgroundColor: Colors.orange),
      );
      return;
    }
    if (!onboarding.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa tu registro y documentos primero'), backgroundColor: Colors.orange),
      );
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()));
      return;
    }

    setState(() => isDeliveryAgentOnline = value);

    try {
      // Actualizar el campo 'status' en delivery_agent_profiles (online/offline)
      final statusValue = value ? 'online' : 'offline';
      debugPrint('🔘 [TOGGLE] Persisting status=$statusValue for user=${_deliveryAgent!.id}');
      await SupabaseConfig.client
          .from('delivery_agent_profiles')
          .update({'status': statusValue, 'updated_at': DateTime.now().toIso8601String()})
          .eq('user_id', _deliveryAgent!.id);
      
      debugPrint('✅ [DELIVERY] Estado del repartidor actualizado a: $statusValue');
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error actualizando estado: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al actualizar disponibilidad: $e'), backgroundColor: Colors.red),
      );
    }
  }
  
  /// Verificar que el usuario actual sea un repartidor
  Future<bool> _verifyUserRole() async {
    try {
      debugPrint('🔍 [DELIVERY] ===== VERIFICANDO TIPO DE USUARIO =====');
      
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [DELIVERY] Usuario no autenticado');
        debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
        return false;
      }
      
      debugPrint('👤 [DELIVERY] Usuario ID: ${user!.id}');
      debugPrint('📧 [DELIVERY] Usuario Email: ${user.email}');
      
      // Verificar rol del usuario en la BD
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();
          
      final userRole = userData['role'] as String?;
      final enumRole = UserRole.fromString(userRole ?? '');
      debugPrint('👑 [DELIVERY] Usuario Role: $userRole -> enum=${enumRole.name}');
      
      if (enumRole != UserRole.delivery_agent) {
        debugPrint('❌ [DELIVERY] ===== ERROR CRÍTICO: USUARIO NO ES REPARTIDOR =====');
        debugPrint('❌ [DELIVERY] Usuario role(raw): $userRole, role(normalizado): ${enumRole.name}, pero dashboard es para repartidor');
        debugPrint('❌ [DELIVERY] ⚠️ CANCELANDO TODA INICIALIZACIÓN DE DASHBOARD ⚠️');
        debugPrint('❌ [DELIVERY] NO se ejecutarán timers, servicios ni cargas de datos');
        
        // Mostrar error al usuario
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: Dashboard incorrecto para tu rol: ${userRole ?? 'desconocido'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
        return false;
      }
      
      debugPrint('✅ [DELIVERY] ===== USUARIO REPARTIDOR VERIFICADO =====');
      debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      return true;
      
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error verificando rol de usuario: $e');
      debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      return false;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _authStateSubscription?.cancel();
    _authStateSubscription = null;

    _orderUpdatesSubscription?.cancel();
    _orderUpdatesSubscription = null;
    
    _cleanupRealtimeService();
    _pageController.dispose();
    
    debugPrint('✅ [DELIVERY] Dashboard del repartidor limpiado exitosamente');
    debugPrint('🔥*-*-*-*-*-*-END DELIVERY DISPOSE*-*-*-*-*-*-🔥');
    super.dispose();
  }
  
  /// Inicializar servicio de tiempo real por usuario
  Future<void> _initializeRealtimeService() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        debugPrint('❌ [DELIVERY REALTIME] Usuario no autenticado');
        return;
      }
      
      debugPrint('🎯 [DELIVERY REALTIME] ===== INICIALIZANDO SERVICIO TIEMPO REAL =====');
      debugPrint('👤 [DELIVERY REALTIME] Usuario: ${user.email} (${user.id})');
      
      // Crear instancia del servicio por usuario
      _realtimeService = RealtimeNotificationService.forUser(user.id);
      
      // Inicializar el servicio
      await _realtimeService!.initialize();
      _isServiceInitialized = true;

      // Escuchar cambios de órdenes para detectar entregas y solicitar reseña al repartidor
      final current = SupabaseConfig.client.auth.currentUser;
      if (current?.emailConfirmedAt != null) {
        _orderUpdatesSubscription = _realtimeService!.orderUpdates.listen((order) {
          if (order.status == OrderStatus.delivered && order.deliveryAgentId == current!.id) {
            _maybePromptReview(order.id);
          }
        });
      }
      
      debugPrint('✅ [DELIVERY REALTIME] Servicio inicializado exitosamente');
      
    } catch (e) {
      debugPrint('❌ [DELIVERY REALTIME] Error inicializando servicio: $e');
    }
  }
  
  Future<void> _maybePromptReview(String orderId) async {
    if (_isShowingReviewSheet) return;
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) return;
    final already = await _reviewService.hasAnyReviewByAuthorForOrder(orderId: orderId, authorId: user!.id);
    if (already) return;
    _isShowingReviewSheet = true;
    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.3,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (_, __) => ReviewScreen(orderId: orderId),
        ),
      );
      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Gracias por calificar!')));
      }
    } finally {
      _isShowingReviewSheet = false;
    }
  }
  
  /// Limpiar servicio de tiempo real
  Future<void> _cleanupRealtimeService() async {
    try {
      debugPrint('🧹 [DELIVERY REALTIME] ===== LIMPIANDO SERVICIO =====');
      
      await _ordersSubscription?.cancel();
      _ordersSubscription = null;
      
      if (_realtimeService != null) {
        await _realtimeService!.dispose();
        _realtimeService = null;
      }
      
      _isServiceInitialized = false;
      debugPrint('✅ [DELIVERY REALTIME] Servicio limpiado exitosamente');
      
    } catch (e) {
      debugPrint('❌ [DELIVERY REALTIME] Error limpiando servicio: $e');
    }
  }

  /// Iniciar polling cada 10 segundos para dashboard principal
  void _startAutoRefresh() {
    // 60s: el realtime WebSocket cubre urgencias; el rol no cambia durante la sesión
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_selectedIndex != 0) return;
      // Verificar sesión en memoria (sin query a BD)
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser == null) { timer.cancel(); return; }
      _loadDeliveryAgentData(showLoading: false);
    });
  }

  /// Verificar si es la primera vez del usuario (delivery-specific)
  Future<void> _checkFirstTimeUser() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        // Asegurar que exista registro en user_preferences (idempotente)
        try {
          await SupabaseConfig.client.from('user_preferences').upsert({
            'user_id': user.id,
          });
        } catch (e) {
          debugPrint('⚠️ [DELIVERY] No se pudo upsert user_preferences (no-fatal): $e');
        }

        final isFirst = await OnboardingNotificationService.isFirstTimeDelivery(user.id);
        if (mounted) {
          setState(() => _isFirstTime = isFirst);
        }

        // Mostrar modal de bienvenida la primera vez (solo una vez)
        if (mounted && isFirst && !_hasShownWelcomeModal && _deliveryAgent != null) {
          _hasShownWelcomeModal = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDeliveryWelcomeModal();
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error verificando primera vez: $e');
    }
  }

  /// Modal de bienvenida con checklist para repartidor (primera vez)
  void _showDeliveryWelcomeModal() {
    if (!mounted || _deliveryAgent == null) return;
    final onboardingStatus = OnboardingNotificationService.calculateDeliveryOnboarding(_deliveryAgent!);
    final welcomeMessage = OnboardingNotificationService.getWelcomeMessage(UserRole.delivery_agent, onboardingStatus);
    final user = SupabaseConfig.client.auth.currentUser;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reutilizamos el mismo contenido visual del card dentro del modal
                  WelcomeOnboardingCard(
                    welcomeMessage: welcomeMessage,
                    onboardingStatus: onboardingStatus,
                    onActionPressed: () {
                      Navigator.of(ctx).pop();
                      if (user != null) {
                        OnboardingNotificationService.markDeliveryWelcomeSeen(user.id);
                      }
                      if (mounted) {
                        setState(() => _isFirstTime = false);
                      }
                      // Ir al dashboard de onboarding/documentos
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()),
                      );
                    },
                    onDismiss: () {
                      Navigator.of(ctx).pop();
                      if (user != null) {
                        OnboardingNotificationService.markDeliveryWelcomeSeen(user.id);
                      }
                      if (mounted) {
                        setState(() => _isFirstTime = false);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  // Botones explícitos (en caso de que el usuario quiera cerrar)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          if (user != null) {
                            OnboardingNotificationService.markDeliveryWelcomeSeen(user.id);
                          }
                          if (mounted) {
                            setState(() => _isFirstTime = false);
                          }
                        },
                        child: const Text('Más tarde'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          if (user != null) {
                            OnboardingNotificationService.markDeliveryWelcomeSeen(user.id);
                          }
                          if (mounted) {
                            setState(() => _isFirstTime = false);
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()),
                          );
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        icon: const Icon(Icons.assignment),
                        label: const Text('Completar registro'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  /// Cargar datos del repartidor y estadísticas
  Future<void> _loadDeliveryAgentData({bool showLoading = true}) async {
    debugPrint('🔥*-*-*-*-*-*-*-*-START LOAD DELIVERY DATA*-*-*-*-*-*-*-*🔥');
    
    if (showLoading && mounted) setState(() => isLoadingStats = true);
    
    try {
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ [LOAD] No hay usuario logueado');
        debugPrint('🔥*-*-*-*-*-*-END LOAD DELIVERY DATA*-*-*-*-*-*-🔥');
        return;
      }
      
      debugPrint('🔄 [LOAD] Loading delivery agent for user: ${currentUser.id}');
      debugPrint('🔄 [LOAD] User email: ${currentUser.email}');
      
      // ✅ PROTECCIÓN ADICIONAL: Verificar rol ANTES de cualquier operación de BD
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', currentUser.id)
          .single();
          
      final userRole = userData['role'] as String?;
      final enumRole = UserRole.fromString(userRole ?? '');
      debugPrint('🔍 [LOAD] Verificación previa - Usuario role: $userRole -> enum=${enumRole.name}');
      
      if (enumRole != UserRole.delivery_agent) {
        debugPrint('❌ [LOAD] ===== CARGA CANCELADA: USUARIO NO ES REPARTIDOR =====');
        debugPrint('❌ [LOAD] Usuario role(raw): $userRole, role(normalizado): ${enumRole.name}, cancelando carga de datos de repartidor');
        debugPrint('🔥*-*-*-*-*-*-END LOAD DELIVERY DATA*-*-*-*-*-*-🔥');
        return;
      }
      
      debugPrint('✅ [LOAD] Usuario verificado como repartidor, continuando carga...');

      // Obtener información del usuario repartidor + su perfil de documentos
      final userRow = await SupabaseConfig.client
          .from('users')
          .select()
          .eq('id', currentUser.id)
          .single();

      Map<String, dynamic>? profileRow;
      try {
        profileRow = await SupabaseConfig.client
            .from('delivery_agent_profiles')
            .select()
            .eq('user_id', currentUser.id)
            .maybeSingle();
      } catch (e) {
        debugPrint('ℹ️ [LOAD] No delivery_agent_profiles row yet: $e');
      }

      // Intentar también la vista consolidada como apoyo
      Map<String, dynamic>? viewRow;
      try {
        viewRow = await SupabaseConfig.client
            .from('delivery_agents_view')
            .select('*')
            .or('id.eq.${currentUser.id},user_id.eq.${currentUser.id}')
            .maybeSingle();
      } catch (e) {
        debugPrint('ℹ️ [LOAD] delivery_agents_view not available: $e');
      }

      final merged = <String, dynamic>{
        if (userRow != null) ...userRow,
        if (profileRow != null) ...profileRow,
        if (viewRow != null) ...viewRow,
      };

      debugPrint('🔄 [LOAD] Merged delivery profile keys: ${merged.keys.toList()}');
      
      if (merged.isNotEmpty) {
        _deliveryAgent = DoaUser.fromJson(merged);
        debugPrint('✅ [LOAD] Delivery agent data loaded: ${_deliveryAgent?.name}');
        // Correct source of online flag: delivery_agent_profiles.status -> UserStatus enum
        bool onlineFromDb = _deliveryAgent?.status == UserStatus.online;
        // Fallback: leer user_preferences si existe bandera
        try {
          final prefs = await SupabaseConfig.client
              .from('user_preferences')
              .select('is_delivery_online')
              .eq('user_id', currentUser.id)
              .maybeSingle();
          if (prefs != null && prefs['is_delivery_online'] != null) {
            onlineFromDb = prefs['is_delivery_online'] == true;
          }
        } catch (e) {
          debugPrint('ℹ️ [LOAD] No user_preferences.is_delivery_online: $e');
        }
        setState(() {
          // Nunca permitir "online" si no está aprobado (verificar account_state)
          final approved = _deliveryAgent?.accountState == DeliveryAccountState.approved;
          isDeliveryAgentOnline = approved ? onlineFromDb : false;
        });
        debugPrint('📶 [LOAD] account_state=${_deliveryAgent?.accountState?.name}, status=${_deliveryAgent?.status.name}, toggle=$isDeliveryAgentOnline');
        
        await _loadDeliveryStats();
        
        // Mostrar mensaje informativo si no tiene nombre
        if (_deliveryAgent?.name == null || _deliveryAgent!.name!.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('🚚 Actualiza tu información en "Perfil" para completar tu registro'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'IR A PERFIL',
                  textColor: Colors.white,
                  onPressed: () => _onItemTapped(3), // Ir a página de perfil
                ),
              ),
            );
          }
        }
      }
      
    } catch (e) {
      debugPrint('❌ [DELIVERY MAIN] Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error cargando datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (showLoading && mounted) setState(() => isLoadingStats = false);
      debugPrint('🔥*-*-*-*-*-*-END LOAD DELIVERY DATA*-*-*-*-*-*-🔥');
    }
  }

  /// Cargar estadísticas de entregas
  Future<void> _loadDeliveryStats() async {
    if (_deliveryAgent == null) return;
    
    try {
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) return;
      
      // Rango de fechas útiles
      final now = DateTime.now();
      final todayStartDt = DateTime(now.year, now.month, now.day);
      final todayEndDt = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final last30StartDt = now.subtract(const Duration(days: 30));
      final last7StartDt = now.subtract(const Duration(days: 6));
      final todayStart = todayStartDt.toIso8601String();
      final todayEnd = todayEndDt.toIso8601String();
      final last30Start = last30StartDt.toIso8601String();
      final last7Start = DateTime(last7StartDt.year, last7StartDt.month, last7StartDt.day).toIso8601String();

      // 1) Pedidos asignados (assigned, ready_for_pickup)
      final assignedOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .inFilter('status', ['assigned', 'ready_for_pickup']);

      // 2) Entregas activas (on_the_way)
      final activeDeliveriesResponse = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'on_the_way');

      // 3) Entregas completadas HOY (usar delivery_time en lugar de created_at)
      final completedTodayResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, delivery_time, delivery_fee')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'delivered')
          .gte('delivery_time', todayStart)
          .lte('delivery_time', todayEnd);

      // 4) Total entregas completadas (all time)
      final totalDeliveredResponse = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'delivered');

      // 5) Canceladas últimos 30 días (aprox. por updated_at)
      final canceledLast30Response = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'canceled')
          .gte('updated_at', last30Start);

      // 6) Entregas últimos 7 días para gráfica (usar delivery_time)
      final last7Delivered = await SupabaseConfig.client
          .from('orders')
          .select('id, delivery_time')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'delivered')
          .gte('delivery_time', last7Start);

      // 7) Canceladas HOY (para tasa de éxito hoy)
      final canceledTodayResponse = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'canceled')
          .gte('updated_at', todayStart)
          .lte('updated_at', todayEnd);

      // 8) Entregas completadas últimos 7 días (conteo) para tasa semanal
      final deliveredWeekResponse = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'delivered')
          .gte('delivery_time', last7Start);

      // 9) Canceladas últimos 7 días (aprox. por updated_at) para tasa semanal
      final canceledWeekResponse = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'canceled')
          .gte('updated_at', last7Start);

      // Cálculos adicionales
      final completedTodayList = List<Map<String, dynamic>>.from(completedTodayResponse as List? ?? []);
      final todayEarnings = completedTodayList.fold<double>(0.0, (sum, row) {
        final fee = (row['delivery_fee'] ?? 0) as num;
        return sum + fee.toDouble();
      });

      final totalDelivered = (totalDeliveredResponse as List?)?.length ?? 0;
      final canceledLast30 = (canceledLast30Response as List?)?.length ?? 0;
      // Éxito HOY: delivered_today / (delivered_today + canceled_today)
      final canceledToday = (canceledTodayResponse as List?)?.length ?? 0;
      final deliveredWeek = (deliveredWeekResponse as List?)?.length ?? 0;
      final canceledWeek = (canceledWeekResponse as List?)?.length ?? 0;
      final successToday = (completedTodayList.length + canceledToday) > 0
          ? (completedTodayList.length / (completedTodayList.length + canceledToday)) * 100.0
          : 0.0;
      // Éxito SEMANA: delivered_week / (delivered_week + canceled_week)
      final successWeek = (deliveredWeek + canceledWeek) > 0
          ? (deliveredWeek / (deliveredWeek + canceledWeek)) * 100.0
          : 0.0;

      // Construir serie semanal
      _weeklyData = _buildWeeklySeries(last7Delivered, start: last7StartDt, end: todayEndDt);

      setState(() {
        deliveryStats = {
          'assignedOrders': (assignedOrdersResponse as List).length,
          'activeDeliveries': (activeDeliveriesResponse as List).length,
          'completedToday': completedTodayList.length,
          'totalDeliveredAllTime': totalDelivered,
          'canceledLast30': canceledLast30,
          'successRateLast30': 0.0, // legacy (no usado visualmente)
          'successRateToday': double.parse(successToday.toStringAsFixed(1)),
          'successRateWeek': double.parse(successWeek.toStringAsFixed(1)),
          'avgEarningPerDeliveryLast30': _computeAvgEarningLast30(currentUser.id, last30StartDt),
          'todayEarnings': double.parse(todayEarnings.toStringAsFixed(2)),
        };
      });

    } catch (e) {
      debugPrint('❌ [DELIVERY MAIN] Error loading stats: $e');
    }
  }

  // Serie semanal: índice 0 = hace 6 días ... índice 6 = hoy
  List<int> _weeklyData = List.filled(7, 0);

  List<int> _buildWeeklySeries(dynamic rows, {required DateTime start, required DateTime end}) {
    final list = List<int>.filled(7, 0);
    try {
      final data = List<Map<String, dynamic>>.from(rows as List? ?? []);
      for (final row in data) {
        final tRaw = row['delivery_time'] ?? row['updated_at'] ?? row['created_at'];
        if (tRaw == null) continue;
        final dt = DateTime.parse(tRaw.toString());
        final dayIndex = dt.toLocal().difference(DateTime(start.year, start.month, start.day)).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          list[dayIndex] += 1;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [DELIVERY] Error building weekly series: $e');
    }
    return list;
  }

  double _computeAvgEarningLast30(String userId, DateTime from) {
    // Nota: Calcularemos promedio con órdenes delivered últimos 30 días usando delivery_fee
    // Para evitar múltiples viajes a red aquí, este método retorna 0.0 y lo ajustamos
    // después mediante un fetch adicional no-bloqueante.
    _computeAvgEarningLast30Async(userId, from);
    return deliveryStats['avgEarningPerDeliveryLast30']?.toDouble() ?? 0.0;
  }

  Future<void> _computeAvgEarningLast30Async(String userId, DateTime from) async {
    try {
      final resp = await SupabaseConfig.client
          .from('orders')
          .select('delivery_fee, delivery_time')
          .eq('delivery_agent_id', userId)
          .eq('status', 'delivered')
          .gte('delivery_time', from.toIso8601String());
      final list = List<Map<String, dynamic>>.from(resp as List? ?? []);
      final deliveredCount = list.length;
      final total = list.fold<double>(0.0, (sum, row) {
        final v = (row['delivery_fee'] ?? 0) as num;
        return sum + v.toDouble();
      });
      final avg = deliveredCount > 0 ? total / deliveredCount : 0.0;
      if (mounted) {
        setState(() {
          deliveryStats['avgEarningPerDeliveryLast30'] = double.parse(avg.toStringAsFixed(2));
        });
      }
    } catch (e) {
      debugPrint('⚠️ [DELIVERY] Error computing avg earnings: $e');
    }
  }

  /// Cambiar página del navbar
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() => _selectedIndex = index),
        children: [
          _buildDashboardHome(),
          const UnifiedOrdersScreen(),
          const DeliveryBalanceScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        selectedItemColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: deliveryStats['assignedOrders']! > 0
              ? Badge(
                  label: Text('${deliveryStats['assignedOrders']}'),
                  child: const Icon(Icons.list_alt),
                )
              : const Icon(Icons.list_alt),
            label: 'Pedidos',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Balance',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  /// Página principal del dashboard (index 0)
  Widget _buildDashboardHome() {
    return Scaffold(
      appBar: AppBar(
        title: Text(NavigationService.getDashboardTitle(UserRole.delivery_agent)),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        foregroundColor: Colors.white,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppThemeController.themeMode,
            builder: (_, mode, __) => IconButton(
              icon: Icon(mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
              tooltip: mode == ThemeMode.dark ? 'Modo Claro' : 'Modo Oscuro',
              onPressed: AppThemeController.toggle,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDeliveryAgentData(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.payments),
        label: const Text('Liquidar Efectivo'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SettlementScreen(),
            ),
          );
        },
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadDeliveryAgentData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con información del repartidor
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          NavigationService.getRoleIcon(UserRole.delivery_agent),
                          size: 32,
                          color: NavigationService.getRoleColor(context, UserRole.delivery_agent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _deliveryAgent?.name ?? 'Mi Perfil de Repartidor',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: NavigationService.getRoleColor(context, UserRole.delivery_agent),
                            ),
                          ),
                        ),
                        // Toggle de disponibilidad (bloqueado hasta aprobación)
                        Tooltip(
                          message: _deliveryAgent?.accountState == DeliveryAccountState.approved
                              ? 'Cambiar tu disponibilidad'
                              : 'Pendiente de aprobación del administrador',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isDeliveryAgentOnline ? 'ACTIVO' : 'PAUSADO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDeliveryAgentOnline ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Switch.adaptive(
                                value: isDeliveryAgentOnline,
                                onChanged: (_deliveryAgent?.accountState == DeliveryAccountState.approved)
                                    ? (v) => _confirmAndSetAvailability(v)
                                    : null,
                                activeColor: Colors.green,
                                inactiveThumbColor: Colors.red,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gestiona tus entregas, ganancias y estadísticas desde aquí.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Checklist y progreso (tarjeta naranja) SIEMPRE visible en el dashboard
              // Nota: El modal de bienvenida mostrará el card azul por encima, pero
              // aquí en el fondo solo debe aparecer el card naranja de progreso.
              if (_deliveryAgent != null) ...[
                DeliveryProfileProgressCard(
                  deliveryAgent: _deliveryAgent!,
                  initiallyExpanded: false,
                  onUploadDocsTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()),
                    );
                  },
                  onCompleteTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              
              // Contadores de entregas
              if (isLoadingStats)
                const Center(child: CircularProgressIndicator())
              else if (_deliveryAgent != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildDeliveryStatCard(
                        'Asignados',
                        'Pedidos por recoger',
                        (deliveryStats['assignedOrders'] as num).toInt(),
                        Colors.orange,
                        Icons.assignment,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDeliveryStatCard(
                        'En Camino',
                        'Entregas activas',
                        (deliveryStats['activeDeliveries'] as num).toInt(),
                        Colors.blue,
                        Icons.directions_bike,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDeliveryStatCard(
                        'Completados',
                        'Entregas hoy',
                        (deliveryStats['completedToday'] as num).toInt(),
                        Colors.green,
                        Icons.check_circle,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
              ],
              
              // Resumen visual
           _buildDeliveryChart(),
           const SizedBox(height: 16),
           _buildWeeklyDeliveriesChart(),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget para mostrar estadísticas de entregas
  Widget _buildDeliveryStatCard(
    String title,
    String subtitle,
    int count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 9,
              color: color.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Gráfica visual de entregas
  Widget _buildDeliveryChart() {
    final total = (deliveryStats['assignedOrders']! + deliveryStats['activeDeliveries']! + deliveryStats['completedToday']!).toInt();
    final roleColor = NavigationService.getRoleColor(context, UserRole.delivery_agent);
    final successValue = _successPeriod == SuccessPeriod.today
        ? (deliveryStats['successRateToday'] ?? 0.0)
        : (deliveryStats['successRateWeek'] ?? 0.0);
    final successLabelSuffix = _successPeriod == SuccessPeriod.today ? 'Hoy' : 'Semana';
    final avgPer = (deliveryStats['avgEarningPerDeliveryLast30'] ?? 0.0) as num;
    final avgText = '\$${avgPer.toStringAsFixed(2)}';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.withValues(alpha: 0.1),
            Colors.blue.withValues(alpha: 0.1),
            Colors.green.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🚚 Resumen de Entregas',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          
          if (total == 0)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No hay entregas para mostrar estadísticas',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            )
          else ...[
            // Barras de progreso visuales
            _buildProgressBar('Asignados', (deliveryStats['assignedOrders'] as num).toInt(), total, Colors.orange),
            const SizedBox(height: 12),
            _buildProgressBar('En Camino', (deliveryStats['activeDeliveries'] as num).toInt(), total, Colors.blue),
            const SizedBox(height: 12),
            _buildProgressBar('Completados Hoy', (deliveryStats['completedToday'] as num).toInt(), total, Colors.green),
            
            const SizedBox(height: 20),
            
            // Estadísticas adicionales
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      // Toggle periodo de éxito
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Hoy'),
                            selected: _successPeriod == SuccessPeriod.today,
                            onSelected: (v) {
                              if (v) setState(() => _successPeriod = SuccessPeriod.today);
                            },
                            selectedColor: roleColor.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: _successPeriod == SuccessPeriod.today ? roleColor : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          ChoiceChip(
                            label: const Text('Semana'),
                            selected: _successPeriod == SuccessPeriod.week,
                            onSelected: (v) {
                              if (v) setState(() => _successPeriod = SuccessPeriod.week);
                            },
                            selectedColor: roleColor.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: _successPeriod == SuccessPeriod.week ? roleColor : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat('Total Entregas', (deliveryStats['totalDeliveredAllTime'] ?? 0).toString(), Icons.local_shipping),
                      _buildStat('Tasa Éxito ($successLabelSuffix)', '${(successValue as num).toStringAsFixed(1)}%', Icons.trending_up),
                      _buildStat('Promedio/Entrega', avgText, Icons.monetization_on),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, int value, int total, Color color) {
    final percentage = total > 0 ? (value / total) : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            Text(
              '$value (${(percentage * 100).toStringAsFixed(0)}%)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percentage,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // Gráfica semanal de entregas (últimos 7 días)
  Widget _buildWeeklyDeliveriesChart() {
    final roleColor = NavigationService.getRoleColor(context, UserRole.delivery_agent);
    final maxY = (_weeklyData.isEmpty ? 1 : (_weeklyData.reduce((a, b) => a > b ? a : b))).toDouble().clamp(1, 10);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, color: roleColor),
              const SizedBox(width: 8),
              Text(
                'Entregas últimos 7 días',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.payments, color: roleColor, size: 16),
                  const SizedBox(width: 6),
                  Text('Hoy: \$${(deliveryStats['todayEarnings'] ?? 0.0).toStringAsFixed(2)}', style: TextStyle(color: roleColor, fontWeight: FontWeight.w600)),
                ]),
              )
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 2.0,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 1),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: ((maxY / 2).ceilToDouble().clamp(1, maxY)) as double,
                      getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (v, meta) {
                        final dayIndex = v.toInt();
                        if (dayIndex < 0 || dayIndex > 6) return const SizedBox.shrink();
                        final date = DateTime.now().subtract(Duration(days: 6 - dayIndex));
                        final label = ['L', 'M', 'X', 'J', 'V', 'S', 'D'][date.weekday - 1];
                        return Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey));
                      },
                    ),
                  ),
                ),
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: maxY.toDouble(),
                lineBarsData: [
                  LineChartBarData(
                    isCurved: true,
                    color: roleColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: roleColor.withValues(alpha: 0.12)),
                    spots: List.generate(7, (i) => FlSpot(i.toDouble(), _weeklyData[i].toDouble())),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Configurar escucha de cambios de autenticación
  void _setupAuthListener() {
    debugPrint('🔥*-*-*-*-*-*-*-*-START AUTH LISTENER SETUP*-*-*-*-*-*-*-*🔥');
    
    _authStateSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen((event) {
      debugPrint('🔔 [DELIVERY-AUTH] Evento de autenticación: ${event.event}');
      debugPrint('🔔 [DELIVERY-AUTH] Usuario actual: ${event.session?.user?.email} (${event.session?.user?.id})');
      debugPrint('🔔 [DELIVERY-AUTH] Usuario inicial: $_initialUserId');
      
      if (event.session?.user?.id != _initialUserId) {
        debugPrint('❌ [DELIVERY-AUTH] ===== CAMBIO DE USUARIO DETECTADO =====');
        debugPrint('❌ [DELIVERY-AUTH] Usuario inicial: $_initialUserId');
        debugPrint('❌ [DELIVERY-AUTH] Nuevo usuario: ${event.session?.user?.id}');
        debugPrint('❌ [DELIVERY-AUTH] CERRANDO DASHBOARD DE REPARTIDOR');
        
        // Limpiar todo inmediatamente
        _refreshTimer?.cancel();
        _refreshTimer = null;
        
        if (mounted) {
          // Mostrar mensaje y cerrar dashboard
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('⚠️ Dashboard cerrado: Cambio de usuario detectado'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });
    
    debugPrint('✅ [DELIVERY-AUTH] Auth listener configurado');
    debugPrint('🔥*-*-*-*-*-*-END AUTH LISTENER SETUP*-*-*-*-*-*-🔥');
  }
}