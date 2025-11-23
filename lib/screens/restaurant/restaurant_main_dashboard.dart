import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:confetti/confetti.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'package:doa_repartos/screens/restaurant/simple_orders_dashboard.dart';
import 'package:doa_repartos/screens/restaurant/restaurant_profile_screen.dart';
import 'package:doa_repartos/screens/restaurant/restaurant_profile_edit_screen.dart';
import 'package:doa_repartos/screens/restaurant/products_management_screen.dart';
import 'package:doa_repartos/screens/restaurant/restaurant_balance_screen.dart';
import 'package:doa_repartos/screens/profile/profile_screen.dart';
import 'package:doa_repartos/widgets/profile_completion_card.dart';
import 'package:doa_repartos/widgets/welcome_onboarding_card.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';
import 'package:doa_repartos/core/theme/app_theme_controller.dart';

/// Dashboard principal con navbar para restaurantes
class RestaurantMainDashboard extends StatefulWidget {
  const RestaurantMainDashboard({super.key});

  @override
  State<RestaurantMainDashboard> createState() => _RestaurantMainDashboardState();
}

class _RestaurantMainDashboardState extends State<RestaurantMainDashboard> {
  int _selectedIndex = 0;
  late PageController _pageController;
  
  bool isRestaurantOnline = false; // Estado online del restaurante
  DoaRestaurant? _restaurant;
  bool _showWelcomeCard = false; // Mostrar card de bienvenida (se habilita tras cargar prefs)
  bool _isFirstTime = false; // Es primera vez del usuario (se resuelve asíncronamente)
  bool _prefsResolved = false; // Evita parpadeo mostrando UI incorrecta
  Map<String, int> orderStats = {
    'newOrders': 0,
    'activeOrders': 0,
    'completedOrders': 0,
  };
  bool isLoadingStats = true;
  Timer? _refreshTimer;
  Set<String> _notifiedOrderIds = <String>{};
  RealtimeNotificationService? _realtimeService;
  StreamSubscription<List<DoaOrder>>? _ordersSubscription;
  bool _isServiceInitialized = false;
  StreamSubscription? _authStateSubscription;
  String? _initialUserId;
  bool _emailCongratsShown = false; // Evita re-mostrar el modal en la sesión
  bool _welcomeMarked = false; // Marcar bienvenida como vista al mostrar por 1ra vez
  bool _isRestaurantRole(String? role) {
    final r = (role ?? '').toLowerCase();
    return r == 'restaurante' || r == 'restaurant';
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🔥*-*-*-*-*-*-*-*-START RESTAURANT DASHBOARD DEBUG*-*-*-*-*-*-*-*🔥');
    debugPrint('🏪 [RESTAURANT] ===== INICIALIZANDO RESTAURANT DASHBOARD =====');
    
    final currentUser = SupabaseConfig.client.auth.currentUser;
    debugPrint('🔥 [RESTAURANT-INIT] Usuario en initState: ${currentUser?.email} (${currentUser?.id})');
    
    // Inicializar PageController siempre (necesario para el UI)
    _pageController = PageController();
    
    // Guardar ID del usuario inicial para detectar cambios
    _initialUserId = currentUser?.id;
    debugPrint('🔥 [RESTAURANT-INIT] ID inicial guardado: $_initialUserId');
    
    // Escuchar cambios de sesión
    _setupAuthListener();
    
    // ✅ PROTECCIÓN CRÍTICA: Verificar rol del usuario ANTES de inicializar servicios de datos
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldContinue = await _verifyUserRole();
      if (shouldContinue) {
        debugPrint('✅ [RESTAURANT] Usuario verificado, iniciando servicios...');
        await _initializeRealtimeService();
        await _loadRestaurantData();
        await _checkFirstTimeUser();
        // Mostrar modal de felicitación post-verificación de email (una sola vez)
        await _maybeShowEmailVerifiedModal();
        _startAutoRefresh();
      } else {
        debugPrint('❌ [RESTAURANT] Usuario NO verificado, NO iniciando servicios');
        debugPrint('🔥*-*-*-*-*-*-END RESTAURANT DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      }
    });
  }

  /// Mostrar modal de "Email verificado" con confetti y checklist
  Future<void> _maybeShowEmailVerifiedModal() async {
    try {
      if (_emailCongratsShown) return; // Ya se mostró en esta sesión
      final supaUser = SupabaseConfig.client.auth.currentUser;
      if (supaUser == null) return;
      if (supaUser.emailConfirmedAt == null) return; // Solo si ya confirmó email
      if (_restaurant == null) return; // Necesitamos datos del restaurante

      // Revisar preferencia para no mostrar repetido entre sesiones
      final prefs = await SupabaseConfig.client
          .from('user_preferences')
          .select('email_verified_congrats_shown')
          .eq('user_id', supaUser.id)
          .maybeSingle();

      final alreadyShown = (prefs != null) && (prefs['email_verified_congrats_shown'] == true);
      if (alreadyShown) return;

      // Calcular progreso y checklist (incluye conteo real de productos)
      final status = await _computeRestaurantProfileStatus(_restaurant!);

      if (!mounted) return;
      _emailCongratsShown = true; // Evitar re-entradas

      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) {
          return _EmailVerifiedCongratsDialog(
            percentage: status.percentage,
            items: status.items,
            onGoToProfile: () {
              Navigator.of(dialogCtx).pop();
              _onItemTapped(2); // Mi Restaurante
            },
            onGoToProducts: () {
              Navigator.of(dialogCtx).pop();
              _onItemTapped(3); // Productos
            },
          );
        },
      );

      // Persistir bandera para no volver a mostrar
      await SupabaseConfig.client
          .from('user_preferences')
          .upsert({
            'user_id': supaUser.id,
            'email_verified_congrats_shown': true,
            'updated_at': DateTime.now().toIso8601String(),
          });
    } catch (e) {
      debugPrint('❌ [EMAIL-CONGRATS] Error mostrando modal: $e');
    }
  }

  /// Calcula porcentaje y checklist usando el servicio de onboarding (mismo cálculo que Mi Restaurante)
  Future<_ProfileChecklistStatus> _computeRestaurantProfileStatus(DoaRestaurant r) async {
    try {
      final status = await OnboardingNotificationService.calculateRestaurantOnboardingAsync(r);

      // Mapear tareas a items del diálogo de bienvenida
      final items = status.tasks.map((t) {
        IconData icon;
        switch (t.id) {
          case 'name':
            icon = Icons.store; break;
          case 'description':
            icon = Icons.description; break;
          case 'cuisine':
            icon = Icons.local_dining; break;
          case 'logo':
            icon = Icons.image; break;
          case 'cover':
            icon = Icons.photo; break;
          case 'menu':
            icon = Icons.restaurant_menu; break;
          case 'admin_approval':
            icon = Icons.verified; break;
          default:
            icon = t.icon;
        }
        return _ChecklistItem(label: t.title, completed: t.isCompleted, icon: icon);
      }).toList();

      final hasMinProducts = status.tasks.any((t) => t.id == 'menu' && t.isCompleted);
      return _ProfileChecklistStatus(
        percentage: status.percentage,
        items: items,
        hasMinProducts: hasMinProducts,
      );
    } catch (e) {
      debugPrint('⚠️ [PROFILE-STATUS] Error calculando estado via servicio: $e');
      // Fallback simple si algo falla
      int productCount = 0;
      try {
        final products = await SupabaseConfig.client
            .from('products')
            .select('id')
            .eq('restaurant_id', r.id)
            .eq('is_available', true);
        productCount = (products as List).length;
      } catch (_) {}
      final hasName = (r.name).trim().isNotEmpty;
      final hasDesc = (r.description ?? '').trim().isNotEmpty;
      final hasLogo = (r.logoUrl ?? '').trim().isNotEmpty;
      final hasCover = (r.coverImageUrl ?? '').trim().isNotEmpty || (r.imageUrl ?? '').trim().isNotEmpty;
      final hasMinProducts = productCount >= 3;
      final items = <_ChecklistItem>[
        _ChecklistItem(label: 'Nombre del Restaurante', completed: hasName, icon: Icons.store),
        _ChecklistItem(label: 'Descripción', completed: hasDesc, icon: Icons.description),
        _ChecklistItem(label: 'Logo', completed: hasLogo, icon: Icons.image),
        _ChecklistItem(label: 'Portada', completed: hasCover, icon: Icons.photo),
        _ChecklistItem(label: 'Al menos 3 productos', completed: hasMinProducts, icon: Icons.restaurant_menu),
      ];
      final totalReq = items.length;
      final completed = items.where((i) => i.completed).length;
      final percentage = ((completed / totalReq) * 100).round();
      return _ProfileChecklistStatus(percentage: percentage, items: items, hasMinProducts: hasMinProducts);
    }
  }
  
  /// Verificar que el usuario actual sea un restaurante
  Future<bool> _verifyUserRole() async {
    try {
      debugPrint('🔍 [RESTAURANT] ===== VERIFICANDO TIPO DE USUARIO =====');
      
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [RESTAURANT] Usuario no autenticado');
        debugPrint('🔥*-*-*-*-*-*-END RESTAURANT DASHBOARD DEBUG*-*-*-*-*-*-🔥');
        return false;
      }
      
      debugPrint('👤 [RESTAURANT] Usuario ID: ${user!.id}');
      debugPrint('📧 [RESTAURANT] Usuario Email: ${user.email}');
      
      // Verificar rol del usuario en la BD
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();
          
      final userRole = userData['role'] as String?;
      debugPrint('👑 [RESTAURANT] Usuario Role: $userRole');
      
      if (!_isRestaurantRole(userRole)) {
        debugPrint('❌ [RESTAURANT] ===== ERROR CRÍTICO: USUARIO NO ES RESTAURANTE =====');
        debugPrint('❌ [RESTAURANT] Usuario role: $userRole, pero dashboard es para restaurante');
        debugPrint('❌ [RESTAURANT] ⚠️ CANCELANDO TODA INICIALIZACIÓN DE DASHBOARD ⚠️');
        debugPrint('❌ [RESTAURANT] NO se ejecutarán timers, servicios ni cargas de datos');
        
        // Mostrar error al usuario
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: Dashboard incorrecto para tu rol: $userRole'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        debugPrint('🔥*-*-*-*-*-*-END RESTAURANT DASHBOARD DEBUG*-*-*-*-*-*-🔥');
        return false;
      }
      
      debugPrint('✅ [RESTAURANT] ===== USUARIO RESTAURANTE VERIFICADO =====');
      debugPrint('🔥*-*-*-*-*-*-END RESTAURANT DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      return true;
      
    } catch (e) {
      debugPrint('❌ [RESTAURANT] Error verificando rol de usuario: $e');
      debugPrint('🔥*-*-*-*-*-*-END RESTAURANT DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      return false;
    }
  }

  @override
  void dispose() {
    debugPrint('🔥*-*-*-*-*-*-*-*-START RESTAURANT DISPOSE*-*-*-*-*-*-*-*🔥');
    debugPrint('🧹 [RESTAURANT] Limpiando dashboard del restaurante...');
    
    final currentUser = SupabaseConfig.client.auth.currentUser;
    debugPrint('🔥 [RESTAURANT-DISPOSE] Usuario en dispose: ${currentUser?.email} (${currentUser?.id})');
    
    _refreshTimer?.cancel();
    _refreshTimer = null;
    debugPrint('✅ [RESTAURANT-DISPOSE] Timer cancelado');
    
    _authStateSubscription?.cancel();
    _authStateSubscription = null;
    debugPrint('✅ [RESTAURANT-DISPOSE] Auth listener cancelado');
    
    _cleanupRealtimeService();
    _pageController.dispose();
    
    debugPrint('✅ [RESTAURANT] Dashboard del restaurante limpiado exitosamente');
    debugPrint('🔥*-*-*-*-*-*-END RESTAURANT DISPOSE*-*-*-*-*-*-🔥');
    super.dispose();
  }
  
  /// Inicializar servicio de tiempo real por usuario
  Future<void> _initializeRealtimeService() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        debugPrint('❌ [RESTAURANT REALTIME] Usuario no autenticado');
        return;
      }
      
      debugPrint('🎯 [RESTAURANT REALTIME] ===== INICIALIZANDO SERVICIO TIEMPO REAL =====');
      debugPrint('👤 [RESTAURANT REALTIME] Usuario: ${user.email} (${user.id})');
      
      // Crear instancia del servicio por usuario
      _realtimeService = RealtimeNotificationService.forUser(user.id);
      
      // Inicializar el servicio
      await _realtimeService!.initialize();
      _isServiceInitialized = true;
      
      debugPrint('✅ [RESTAURANT REALTIME] Servicio inicializado exitosamente');
      
    } catch (e) {
      debugPrint('❌ [RESTAURANT REALTIME] Error inicializando servicio: $e');
    }
  }
  
  /// Limpiar servicio de tiempo real
  Future<void> _cleanupRealtimeService() async {
    try {
      debugPrint('🧹 [RESTAURANT REALTIME] ===== LIMPIANDO SERVICIO =====');
      
      await _ordersSubscription?.cancel();
      _ordersSubscription = null;
      
      if (_realtimeService != null) {
        await _realtimeService!.dispose();
        _realtimeService = null;
      }
      
      _isServiceInitialized = false;
      debugPrint('✅ [RESTAURANT REALTIME] Servicio limpiado exitosamente');
      
    } catch (e) {
      debugPrint('❌ [RESTAURANT REALTIME] Error limpiando servicio: $e');
    }
  }

  /// Iniciar polling cada 6 segundos para dashboard principal
  void _startAutoRefresh() {
    debugPrint('🔥*-*-*-*-*-*-*-*-START AUTO-REFRESH SETUP*-*-*-*-*-*-*-*🔥');
    
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (timer) async {
      if (mounted && _selectedIndex == 0) {
        debugPrint('🔄 [RESTAURANT MAIN] Auto-refresh en dashboard principal...');
        
        // ✅ PROTECCIÓN CRÍTICA: Verificar que el usuario siga siendo un restaurante ANTES de cada refresh
        final currentUser = SupabaseConfig.client.auth.currentUser;
        if (currentUser == null) {
          debugPrint('❌ [RESTAURANT-TIMER] No hay usuario logueado, cancelando timer');
          timer.cancel();
          return;
        }
        
        debugPrint('🔥 [RESTAURANT-TIMER] Usuario en timer: ${currentUser.email} (${currentUser.id})');
        
        try {
          // Verificar rol rápidamente
          final userData = await SupabaseConfig.client
              .from('users')
              .select('role')
              .eq('id', currentUser.id)
              .single();
              
          final userRole = userData['role'] as String?;
          debugPrint('🔍 [RESTAURANT-TIMER] Rol del usuario: $userRole');
          
          if (!_isRestaurantRole(userRole)) {
            debugPrint('❌ [RESTAURANT-TIMER] ===== TIMER CANCELADO: USUARIO NO ES RESTAURANTE =====');
            debugPrint('❌ [RESTAURANT-TIMER] Usuario role: $userRole, cancelando timer del restaurante');
            timer.cancel();
            _refreshTimer = null;
            return;
          }
          
          debugPrint('✅ [RESTAURANT-TIMER] Usuario verificado como restaurante, continuando refresh');
          _loadRestaurantData(showLoading: false);
          
        } catch (e) {
          debugPrint('❌ [RESTAURANT-TIMER] Error verificando rol en timer: $e');
          timer.cancel();
          _refreshTimer = null;
        }
      }
    });
    
    debugPrint('✅ [RESTAURANT] Timer de auto-refresh configurado exitosamente');
    debugPrint('🔥*-*-*-*-*-*-END AUTO-REFRESH SETUP*-*-*-*-*-*-🔥');
  }

  /// Cargar datos del restaurante y estadísticas
  Future<void> _loadRestaurantData({bool showLoading = true}) async {
    debugPrint('🔥*-*-*-*-*-*-*-*-START LOAD RESTAURANT DATA*-*-*-*-*-*-*-*🔥');
    
    if (showLoading && mounted) setState(() => isLoadingStats = true);
    
    try {
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ [LOAD] No hay usuario logueado');
        debugPrint('🔥*-*-*-*-*-*-END LOAD RESTAURANT DATA*-*-*-*-*-*-🔥');
        return;
      }
      
      debugPrint('🔄 [LOAD] Loading restaurant for user: ${currentUser.id}');
      debugPrint('🔄 [LOAD] User email: ${currentUser.email}');
      
      // ✅ PROTECCIÓN ADICIONAL: Verificar rol ANTES de cualquier operación de BD
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', currentUser.id)
          .single();
          
      final userRole = userData['role'] as String?;
      debugPrint('🔍 [LOAD] Verificación previa - Usuario role: $userRole');
      
      if (!_isRestaurantRole(userRole)) {
        debugPrint('❌ [LOAD] ===== CARGA CANCELADA: USUARIO NO ES RESTAURANTE =====');
        debugPrint('❌ [LOAD] Usuario role: $userRole, cancelando carga de datos de restaurante');
        debugPrint('🔥*-*-*-*-*-*-END LOAD RESTAURANT DATA*-*-*-*-*-*-🔥');
        return;
      }
      
      debugPrint('✅ [LOAD] Usuario verificado como restaurante, continuando carga...');

      // Obtener información del restaurante con logs detallados
      final restaurantResponse = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      
      debugPrint('🔄 [LOAD] Database response: $restaurantResponse');
      
      if (restaurantResponse != null) {
        _restaurant = DoaRestaurant.fromJson(restaurantResponse);
        debugPrint('✅ [LOAD] Restaurant data loaded: ${_restaurant?.name} - Online: ${_restaurant?.online}');
        setState(() {
          isRestaurantOnline = _restaurant?.online ?? false;
        });
        
        await _loadOrderStats();
      } else {
        debugPrint('❌ [LOAD] No restaurant found for user ${currentUser.id}');
        
        // ✅ PROTECCIÓN CRÍTICA: Verificar rol antes de crear restaurante
        final userData = await SupabaseConfig.client
            .from('users')
            .select('role')
            .eq('id', currentUser.id)
            .single();
            
        final userRole = userData['role'] as String?;
        debugPrint('🔍 [LOAD] Usuario role: $userRole');
        
        if (!_isRestaurantRole(userRole)) {
          debugPrint('❌ [LOAD] ERROR: No se puede crear restaurante para rol: $userRole');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Error: No puedes acceder al dashboard de restaurante. Tu rol es: $userRole'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }
        
        // Intentar crear un restaurante de prueba para este usuario RESTAURANTE
        debugPrint('🔧 [LOAD] Intentando crear restaurante para usuario verificado...');
        
        try {
          final newRestaurantData = {
            'user_id': currentUser.id,
            'name': 'Mi Restaurante (${currentUser.email?.split('@').first ?? 'usuario'})',
            'description': 'Restaurante creado automáticamente',
            'logo_url': 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
            'address': 'Dirección no especificada',
            'phone': '000-000-0000',
            'online': false,  // Empezar offline por seguridad
            'status': 'pending'
          };
          
          debugPrint('🔧 [LOAD] Creating restaurant with data: $newRestaurantData');
          
          final createResponse = await SupabaseConfig.client
              .from('restaurants')
              .insert(newRestaurantData)
              .select()
              .single();
              
          debugPrint('✅ [LOAD] Restaurant created successfully: $createResponse');
          
          _restaurant = DoaRestaurant.fromJson(createResponse);
          setState(() {
            isRestaurantOnline = _restaurant?.online ?? false;
          });
          
          await _loadOrderStats();
          
          // Mostrar mensaje de información al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('🏪 Se ha creado tu perfil de restaurante. Actualiza tu información en "Mi Restaurante"'),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'IR A PERFIL',
                  textColor: Colors.white,
                  onPressed: () => _onItemTapped(2), // Ir a página de perfil de restaurante
                ),
              ),
            );
          }
          
        } catch (createError) {
          debugPrint('❌ [LOAD] Error creating restaurant: $createError');
          
          // Si falla crear, mostrar información de debugging
          final allRestaurants = await SupabaseConfig.client
              .from('restaurants')
              .select();
          debugPrint('🔍 [LOAD] All restaurants in database: $allRestaurants');
          
          // Verificar si el usuario actual está en la tabla de usuarios
          final userInDB = await SupabaseConfig.client
              .from('users')
              .select()
              .eq('id', currentUser.id)
              .maybeSingle();
          debugPrint('🔍 [LOAD] User in database: $userInDB');
          
          // Mostrar error al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Error: No se pudo crear el perfil del restaurante. Error: $createError'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }
      
    } catch (e) {
      debugPrint('❌ [RESTAURANT MAIN] Error loading data: $e');
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
      debugPrint('🔥*-*-*-*-*-*-END LOAD RESTAURANT DATA*-*-*-*-*-*-🔥');
    }
  }

  /// Cargar estadísticas de pedidos
  Future<void> _loadOrderStats() async {
    if (_restaurant == null) return;
    
    try {
      // Pedidos nuevos (pending)
      final newOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('restaurant_id', _restaurant!.id)
          .eq('status', 'pending');

      final newCount = (newOrdersResponse as List).length;
      final previousNewCount = orderStats['newOrders']!;

      // Pedidos activos
      final activeOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('restaurant_id', _restaurant!.id)
          .inFilter('status', ['confirmed', 'in_preparation', 'ready_for_pickup']);

      // Pedidos completados hoy
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day).toIso8601String();
      final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();
      
      final completedOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('restaurant_id', _restaurant!.id)
          .eq('status', 'delivered')
          .gte('created_at', todayStart)
          .lte('created_at', todayEnd);

      setState(() {
        orderStats = {
          'newOrders': newCount,
          'activeOrders': (activeOrdersResponse as List).length,
          'completedOrders': (completedOrdersResponse as List).length,
        };
      });

      // Notificar si hay nuevos pedidos
      if (newCount > previousNewCount && newCount > 0) {
        _showNewOrderNotification(newCount);
      }

    } catch (e) {
      debugPrint('❌ [RESTAURANT MAIN] Error loading stats: $e');
    }
  }

  /// Mostrar notificación de nuevo pedido
  void _showNewOrderNotification(int newOrderCount) {
    // SnackBar prominente
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '🔔 ¡$newOrderCount ${newOrderCount == 1 ? 'NUEVO PEDIDO' : 'NUEVOS PEDIDOS'}!',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.deepOrange,
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'VER PEDIDOS',
          textColor: Colors.white,
          onPressed: () => _onItemTapped(1), // Ir a página de pedidos
        ),
      ),
    );

    // Simular sonido de notificación
    debugPrint('🔊 [SOUND] ¡DING! DING! ¡Nuevo pedido recibido!');
    
    // Mostrar toast adicional
    _showToast('🍕 ¡Tienes ${newOrderCount == 1 ? 'un nuevo pedido' : '$newOrderCount nuevos pedidos'} esperando!');
  }

  /// Manejar click en sección del perfil
  void _handleProfileSectionTap(ProfileSection section) async {
    if (_restaurant == null) return;
    
    // Navegar a la pantalla de edición de perfil con la sección específica
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RestaurantProfileEditScreen(
          restaurant: _restaurant!,
          initialSection: section,
        ),
      ),
    );
    
    // Si se guardaron cambios, recargar datos
    if (result == true) {
      await _loadRestaurantData();
    }
  }
  
  /// Manejar click en sección del perfil (LEGACY)
  void _handleProfileSectionTapLegacy(ProfileSection section) {
    switch (section) {
      case ProfileSection.basicInfo:
        // Ir a pantalla de perfil del restaurante (tab de información básica)
        _onItemTapped(2);
        break;
      case ProfileSection.logo:
        // Ir a pantalla de perfil del restaurante (tab de imágenes)
        _onItemTapped(2);
        break;
      case ProfileSection.cover:
        // Ir a pantalla de perfil del restaurante (tab de imágenes)
        _onItemTapped(2);
        break;
      case ProfileSection.products:
        // Ir a pantalla de productos
        _onItemTapped(3);
        break;
    }
  }

  /// Mostrar toast notification
  void _showToast(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.1,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.restaurant, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    
    Timer(const Duration(seconds: 4), () {
      overlayEntry.remove();
    });
  }

  /// Toggle estado online/offline del restaurante con confirmación
  Future<void> _toggleOnlineStatus() async {
    debugPrint('🔘 [TOGGLE] _toggleOnlineStatus() called');
    debugPrint('🔘 [TOGGLE] Restaurant: ${_restaurant?.toJson()}');
    debugPrint('🔘 [TOGGLE] Current isRestaurantOnline: $isRestaurantOnline');
    
    if (_restaurant == null) {
      debugPrint('❌ [TOGGLE] Restaurant is null, cannot toggle');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Error: No se pudo cargar la información del restaurante'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    final newOnlineStatus = !isRestaurantOnline;
    debugPrint('🔘 [TOGGLE] New status will be: $newOnlineStatus');
    
    // ✅ VALIDACIÓN CRÍTICA: Verificar que el restaurante pueda ponerse online
    if (newOnlineStatus) {
      // Verificar estado de aprobación
      if (_restaurant!.status != RestaurantStatus.approved) {
        _showCannotGoOnlineDialog(
          '🔒 Restaurante No Aprobado',
          'Tu restaurante debe ser aprobado por el administrador antes de poder recibir pedidos.\n\n'
          'Estado actual: ${_restaurant!.status.displayName}',
          Icons.lock,
          Colors.red,
        );
        return;
      }
      
      // Verificar completado del perfil
      if (_restaurant!.profileCompletionPercentage < 70) {
        _showCannotGoOnlineDialog(
          '📝 Perfil Incompleto',
          'Completa tu perfil al menos un 70% para poder ponerte ONLINE y recibir pedidos.\n\n'
          'Progreso actual: ${_restaurant!.profileCompletionPercentage}%\n\n'
          'Completa:\n'
          '• Información básica del restaurante\n'
          '• Logo del restaurante\n'
          '• Al menos 1 producto en el menú',
          Icons.edit_note,
          Colors.orange,
        );
        return;
      }
    }
    
    // Mostrar modal de confirmación
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // No cerrar tocando afuera
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                newOnlineStatus ? Icons.power_settings_new : Icons.power_off,
                color: newOnlineStatus ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  newOnlineStatus ? '¿Prender Restaurante?' : '¿Apagar Restaurante?',
                  style: TextStyle(
                    color: newOnlineStatus ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                newOnlineStatus 
                  ? '🟢 Al PRENDER tu restaurante:'
                  : '🔴 Al APAGAR tu restaurante:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ...( newOnlineStatus ? [
                _buildConfirmationItem('✅', 'Aparecerás en la lista de restaurantes disponibles'),
                _buildConfirmationItem('📱', 'Los clientes podrán hacer pedidos'),
                _buildConfirmationItem('🔔', 'Recibirás notificaciones de nuevos pedidos'),
                _buildConfirmationItem('💰', 'Podrás generar ventas y ganancias'),
              ] : [
                _buildConfirmationItem('❌', 'No aparecerás en la lista de restaurantes'),
                _buildConfirmationItem('🚫', 'Los clientes NO podrán hacer pedidos'),
                _buildConfirmationItem('🔕', 'No recibirás nuevos pedidos'),
                _buildConfirmationItem('⏸️', 'Tus ventas se pausarán temporalmente'),
              ]),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (newOnlineStatus ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (newOnlineStatus ? Colors.green : Colors.orange).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      newOnlineStatus ? Icons.info : Icons.warning,
                      color: newOnlineStatus ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        newOnlineStatus 
                          ? 'Asegúrate de estar listo para recibir y preparar pedidos.'
                          : 'Podrás volver a prender tu restaurante en cualquier momento.',
                        style: TextStyle(
                          fontSize: 13,
                          color: newOnlineStatus ? Colors.green.shade700 : Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: newOnlineStatus ? Colors.green : Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                newOnlineStatus ? 'SÍ, PRENDER' : 'SÍ, APAGAR',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
    
    // Si el usuario canceló, no hacer nada
    if (confirmed != true) return;
    
    // Proceder con el cambio
    try {
      debugPrint('🔘 [TOGGLE] Updating database...');
      debugPrint('🔘 [TOGGLE] Restaurant ID: ${_restaurant!.id}');
      debugPrint('🔘 [TOGGLE] Setting online to: $newOnlineStatus');
      
      // Actualizar en Supabase
      final response = await SupabaseConfig.client
          .from('restaurants')
          .update({'online': newOnlineStatus})
          .eq('id', _restaurant!.id)
          .select();
      
      debugPrint('🔘 [TOGGLE] Database response: $response');
      
      // Actualizar el objeto restaurant local también
      _restaurant = _restaurant!.copyWith(online: newOnlineStatus);
      
      setState(() {
        isRestaurantOnline = newOnlineStatus;
      });
      
      debugPrint('✅ [TOGGLE] Estado actualizado correctamente. Nuevo estado: $newOnlineStatus');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newOnlineStatus 
              ? '🟢 ¡Tu restaurante está ahora ONLINE! Puedes recibir pedidos'
              : '🔴 Tu restaurante está ahora OFFLINE. No recibirás nuevos pedidos',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: newOnlineStatus ? Colors.green : Colors.grey.shade700,
          duration: const Duration(seconds: 4),
          action: newOnlineStatus ? SnackBarAction(
            label: 'VER PEDIDOS',
            textColor: Colors.white,
            onPressed: () => _onItemTapped(1),
          ) : null,
        ),
      );
      
    } catch (e) {
      debugPrint('❌ [TOGGLE] Error updating online status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al actualizar el estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Helper para items de confirmación
  Widget _buildConfirmationItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Mostrar diálogo cuando no se puede poner online
  void _showCannotGoOnlineDialog(String title, String message, IconData icon, Color color) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          if (color == Colors.orange) ...[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _onItemTapped(2); // Ir a perfil del restaurante
              },
              child: const Text('Completar Perfil'),
            ),
          ],
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
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
          const SimpleOrdersDashboard(),
          const RestaurantProfileScreen(),
          const ProductsManagementScreen(),
          const RestaurantBalanceScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        selectedItemColor: NavigationService.getRoleColor(context, UserRole.restaurant),
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: orderStats['newOrders']! > 0
              ? Badge(
                  label: Text('${orderStats['newOrders']}'),
                  child: const Icon(Icons.receipt_long),
                )
              : const Icon(Icons.receipt_long),
            label: 'Pedidos',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: 'Mi Restaurante',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: 'Productos',
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
        title: Text(NavigationService.getDashboardTitle(UserRole.restaurant)),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.restaurant),
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
          if (_restaurant != null)
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    isRestaurantOnline ? Icons.power : Icons.power_off,
                    color: isRestaurantOnline ? Colors.limeAccent : Colors.white,
                    size: 22,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Switch.adaptive(
                    value: isRestaurantOnline,
                    onChanged: (_) => _toggleOnlineStatus(),
                    activeColor: Colors.white,
                    activeTrackColor: Colors.greenAccent.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadRestaurantData(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadRestaurantData(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con toggle online/offline
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: NavigationService.getRoleColor(context, UserRole.restaurant).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: NavigationService.getRoleColor(context, UserRole.restaurant).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          NavigationService.getRoleIcon(UserRole.restaurant),
                          size: 32,
                          color: NavigationService.getRoleColor(context, UserRole.restaurant),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _restaurant?.name ?? 'Mi Restaurante',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: NavigationService.getRoleColor(context, UserRole.restaurant),
                            ),
                          ),
                        ),
                        // Toggle de estado removido del dashboard por solicitud
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Gestiona tu restaurante, productos y pedidos desde aquí.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Card de bienvenida y onboarding (solo cuando preferencias estén resueltas)
              if (_restaurant != null && _prefsResolved && _showWelcomeCard && _isFirstTime) ...[
                FutureBuilder<OnboardingStatus>(
                  future: OnboardingNotificationService.calculateRestaurantOnboardingAsync(_restaurant!),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: const [
                              SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Expanded(child: Text('Calculando progreso de tu perfil...')),
                            ],
                          ),
                        ),
                      );
                    }

                    final onboardingStatus = snapshot.data!;
                    final welcomeMessage = OnboardingNotificationService.getWelcomeMessage(UserRole.restaurant, onboardingStatus);

                    return WelcomeOnboardingCard(
                      welcomeMessage: welcomeMessage,
                      onboardingStatus: onboardingStatus,
                      onActionPressed: () {
                        // Marcar como visto cuando el usuario toma acción
                        final user = SupabaseConfig.client.auth.currentUser;
                        if (user != null && !_welcomeMarked) {
                          _welcomeMarked = true;
                          OnboardingNotificationService.markRestaurantWelcomeSeen(user.id);
                        }
                        if (onboardingStatus.isComplete) {
                          _onItemTapped(1); // Ir a pedidos
                        } else {
                          _onItemTapped(2); // Ir a perfil para completar
                        }
                      },
                       onDismiss: () {
                        setState(() => _showWelcomeCard = false);
                        // Marcar como visto al cerrar
                        final user = SupabaseConfig.client.auth.currentUser;
                        if (user != null && !_welcomeMarked) {
                           _welcomeMarked = true;
                           OnboardingNotificationService.markRestaurantWelcomeSeen(user.id);
                        }
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
              
              // Card de progreso de completado del perfil (solo si no es primera vez y prefs resueltas)
              if (_restaurant != null && _prefsResolved && !_isFirstTime && _restaurant!.profileCompletionPercentage < 100)
                FutureBuilder<_ProfileChecklistStatus>(
                  future: _computeRestaurantProfileStatus(_restaurant!),
                  builder: (context, snapshot) {
                    final overridePerc = snapshot.data?.percentage;
                    return ProfileCompletionCard(
                      restaurant: _restaurant!,
                      percentageOverride: overridePerc,
                      productsCompleteOverride: snapshot.data?.hasMinProducts ?? false,
                      onTapComplete: () => _onItemTapped(2), // Ir a perfil de restaurante
                      onSectionTap: _handleProfileSectionTap,
                    );
                  },
                ),
              
              // Acceso rápido a Liquidaciones
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.payments, color: Colors.orange),
                  ),
                  title: const Text('Liquidaciones de Efectivo'),
                  subtitle: const Text('Confirma las liquidaciones pendientes de repartidores'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RestaurantBalanceScreen(initialTabIndex: 1),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              
              // Contadores de pedidos
              if (isLoadingStats)
                const Center(child: CircularProgressIndicator())
              else if (_restaurant != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: _buildOrderStatCard(
                        'Nuevos',
                        'Por aceptar',
                        orderStats['newOrders']!,
                        Colors.orange,
                        Icons.pending_actions,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildOrderStatCard(
                        'En Curso',
                        'Preparando/Listos',
                        orderStats['activeOrders']!,
                        Colors.blue,
                        Icons.restaurant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildOrderStatCard(
                        'Terminados',
                        'Completados hoy',
                        orderStats['completedOrders']!,
                        Colors.green,
                        Icons.check_circle,
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
              ],
              
              // Gráfica de pedidos
              _buildOrderChart(),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget para mostrar estadísticas de pedidos
  Widget _buildOrderStatCard(
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

  /// Verificar si es la primera vez del usuario
  Future<void> _checkFirstTimeUser() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        // Asegurar que exista el registro en user_preferences
        try {
          await SupabaseConfig.client.from('user_preferences').upsert({
            'user_id': user.id,
          });
        } catch (e) {
          debugPrint('⚠️ [RESTAURANT] No se pudo upsert user_preferences (no-fatal): $e');
        }

        final isFirst = await OnboardingNotificationService.isFirstTimeRestaurant(user.id);
        if (mounted) {
          setState(() {
            _isFirstTime = isFirst;
            _showWelcomeCard = isFirst; // solo mostrar si realmente es primera vez
            _prefsResolved = true; // ya sabemos qué mostrar
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [RESTAURANT] Error verificando primera vez: $e');
      if (mounted) {
        setState(() {
          _prefsResolved = true; // evitar spinner infinito y parpadeos
          _isFirstTime = false;
          _showWelcomeCard = false;
        });
      }
    }
  }
  
  /// Gráfica visual de pedidos
  Widget _buildOrderChart() {
    final total = orderStats['newOrders']! + orderStats['activeOrders']! + orderStats['completedOrders']!;
    
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
            '📊 Resumen de Pedidos',
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
                  'No hay pedidos para mostrar estadísticas',
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            )
          else ...[
            // Barras de progreso visuales
            _buildProgressBar('Nuevos Pedidos', orderStats['newOrders']!, total, Colors.orange),
            const SizedBox(height: 12),
            _buildProgressBar('En Proceso', orderStats['activeOrders']!, total, Colors.blue),
            const SizedBox(height: 12),
            _buildProgressBar('Completados', orderStats['completedOrders']!, total, Colors.green),
            
            const SizedBox(height: 20),
            
            // Estadísticas adicionales
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStat('Total Pedidos', total.toString(), Icons.receipt),
                  _buildStat('Tasa Éxito', total > 0 ? '${((orderStats['completedOrders']! / total) * 100).toStringAsFixed(0)}%' : '0%', Icons.trending_up),
                  _buildStat('Promedio/Pedido', '\$${(total * 25).toStringAsFixed(0)}', Icons.monetization_on),
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
  
  /// Configurar escucha de cambios de autenticación
  void _setupAuthListener() {
    debugPrint('🔥*-*-*-*-*-*-*-*-START AUTH LISTENER SETUP*-*-*-*-*-*-*-*🔥');
    
    _authStateSubscription = SupabaseConfig.client.auth.onAuthStateChange.listen((event) {
      debugPrint('🔔 [RESTAURANT-AUTH] Evento de autenticación: ${event.event}');
      debugPrint('🔔 [RESTAURANT-AUTH] Usuario actual: ${event.session?.user?.email} (${event.session?.user?.id})');
      debugPrint('🔔 [RESTAURANT-AUTH] Usuario inicial: $_initialUserId');
      
      if (event.session?.user?.id != _initialUserId) {
        debugPrint('❌ [RESTAURANT-AUTH] ===== CAMBIO DE USUARIO DETECTADO =====');
        debugPrint('❌ [RESTAURANT-AUTH] Usuario inicial: $_initialUserId');
        debugPrint('❌ [RESTAURANT-AUTH] Nuevo usuario: ${event.session?.user?.id}');
        debugPrint('❌ [RESTAURANT-AUTH] CERRANDO DASHBOARD DE RESTAURANTE');
        
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
    
    debugPrint('✅ [RESTAURANT-AUTH] Auth listener configurado');
    debugPrint('🔥*-*-*-*-*-*-END AUTH LISTENER SETUP*-*-*-*-*-*-🔥');
  }
}

/// Estructura para checklist visual (scope de archivo)
class _ProfileChecklistStatus {
  final int percentage;
  final List<_ChecklistItem> items;
  final bool hasMinProducts; // true si existen al menos 3 productos activos
  const _ProfileChecklistStatus({required this.percentage, required this.items, required this.hasMinProducts});
}

class _ChecklistItem {
  final String label;
  final bool completed;
  final IconData icon;
  const _ChecklistItem({required this.label, required this.completed, required this.icon});
}

/// Dialogo de felicitación por email verificado con confetti y checklist
class _EmailVerifiedCongratsDialog extends StatefulWidget {
  final int percentage;
  final List<_ChecklistItem> items;
  final VoidCallback onGoToProfile;
  final VoidCallback onGoToProducts;

  const _EmailVerifiedCongratsDialog({
    required this.percentage,
    required this.items,
    required this.onGoToProfile,
    required this.onGoToProducts,
  });

  @override
  State<_EmailVerifiedCongratsDialog> createState() => _EmailVerifiedCongratsDialogState();
}

class _EmailVerifiedCongratsDialogState extends State<_EmailVerifiedCongratsDialog> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    // Lanzar confetti después de construir el cuadro de diálogo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _confetti.play();
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.celebration, color: Colors.green, size: 28),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '¡Felicidades! Tu email fue confirmado',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ahora es necesario completar tu perfil para empezar a vender con Doña.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 12),
              // Progreso
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: widget.percentage / 100,
                        minHeight: 10,
                        backgroundColor: cs.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.percentage >= 80 ? Colors.green : (widget.percentage >= 50 ? Colors.orange : Colors.red),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${widget.percentage}%'),
                ],
              ),
              const SizedBox(height: 12),
              // Checklist
              ...widget.items.map((i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          i.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: i.completed ? Colors.green : Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Icon(i.icon, size: 16, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(i.label)),
                      ],
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Después'),
            ),
            FilledButton.icon(
              onPressed: widget.onGoToProfile,
              icon: const Icon(Icons.store),
              label: const Text('Completar Perfil'),
            ),
            OutlinedButton.icon(
              onPressed: widget.onGoToProducts,
              icon: const Icon(Icons.restaurant_menu),
              label: const Text('Agregar Productos'),
            ),
          ],
        ),
        // Confetti overlay
        Positioned(
          top: 0,
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.08,
            numberOfParticles: 30,
            gravity: 0.4,
            colors: const [
              Colors.green,
              Colors.orange,
              Colors.pink,
              Colors.blue,
              Colors.purple,
            ],
          ),
        ),
      ],
    );
  }
}
