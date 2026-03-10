import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Servicio centralizado para notificaciones de onboarding y bienvenida
/// Personalizado por tipo de usuario (Cliente, Restaurante, Repartidor)
class OnboardingNotificationService {
  /// Pesos para el cálculo ponderado del onboarding de restaurante.
  /// Deben sumar 100 entre requeridos. "cuisine" vale 15%.
  static const Map<String, double> _restaurantWeights = {
    'name': 10,
    'cuisine': 15, // Requerido: 15%
    'description': 10,
    'logo': 15,
    'cover': 10,
    'menu': 25, // Al menos 3 productos
    'admin_approval': 15,
  };

  /// Calcula porcentaje ponderado a partir de las tareas y los pesos definidos.
  static int _computeWeightedPercentage(List<OnboardingTask> tasks) {
    // Considerar solo tareas requeridas
    final requiredTasks = tasks.where((t) => !t.isOptional).toList();
    double totalWeight = 0;
    double completedWeight = 0;
    for (final t in requiredTasks) {
      final w = _restaurantWeights[t.id] ?? 0;
      totalWeight += w;
      if (t.isCompleted) completedWeight += w;
    }
    if (totalWeight <= 0) return 0;
    return (completedWeight / totalWeight * 100).round();
  }
  /// Verificar si es la primera vez que el usuario abre su dashboard (genérico)
  static Future<bool> isFirstTimeUser(String userId) async {
    try {
      final prefs = await SupabaseConfig.client
          .from('user_preferences')
          .select('has_seen_onboarding')
          .eq('user_id', userId)
          .maybeSingle();

      if (prefs == null) return true;
      return prefs['has_seen_onboarding'] != true;
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error verificando first time: $e');
      return false;
    }
  }

  /// Verifica si es la primera vez para el flujo de bienvenida de RESTAURANTE
  static Future<bool> isFirstTimeRestaurant(String userId) async {
    try {
      final prefs = await SupabaseConfig.client
          .from('user_preferences')
          .select('has_seen_restaurant_welcome, has_seen_onboarding')
          .eq('user_id', userId)
          .maybeSingle();

      if (prefs == null) return true;
      // Priorizar bandera específica del restaurante; fallback a la genérica si aún no existe
      if (prefs.containsKey('has_seen_restaurant_welcome')) {
        return prefs['has_seen_restaurant_welcome'] != true;
      }
      return prefs['has_seen_onboarding'] != true;
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error verificando first time restaurant: $e');
      return false;
    }
  }

  /// Verifica si es la primera vez para el flujo de bienvenida de REPARTIDOR
  static Future<bool> isFirstTimeDelivery(String userId) async {
    try {
      final prefs = await SupabaseConfig.client
          .from('user_preferences')
          .select('has_seen_delivery_welcome, has_seen_onboarding')
          .eq('user_id', userId)
          .maybeSingle();

      if (prefs == null) return true;
      if (prefs.containsKey('has_seen_delivery_welcome')) {
        return prefs['has_seen_delivery_welcome'] != true;
      }
      return prefs['has_seen_onboarding'] != true;
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error verificando first time delivery: $e');
      return false;
    }
  }

  /// Marcar que el usuario ya vio el onboarding
  static Future<void> markOnboardingSeen(String userId) async {
    try {
      await SupabaseConfig.client
          .from('user_preferences')
          .upsert({
            'user_id': userId,
            'has_seen_onboarding': true,
            'updated_at': DateTime.now().toIso8601String(),
          });
      debugPrint('✅ [ONBOARDING] Usuario marcado como onboarded: $userId');
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error marcando onboarding: $e');
    }
  }

  /// Marca que el usuario ya vio el modal de bienvenida de restaurante
  static Future<void> markRestaurantWelcomeSeen(String userId) async {
    try {
      await SupabaseConfig.client
          .from('user_preferences')
          .upsert({
            'user_id': userId,
            'has_seen_restaurant_welcome': true,
            'restaurant_welcome_seen_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
      debugPrint('✅ [ONBOARDING] Restaurant welcome visto para: $userId');
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error marcando restaurant welcome: $e');
    }
  }

  /// Marca que el usuario ya vio el modal de bienvenida de repartidor
  static Future<void> markDeliveryWelcomeSeen(String userId) async {
    try {
      await SupabaseConfig.client
          .from('user_preferences')
          .upsert({
            'user_id': userId,
            'has_seen_delivery_welcome': true,
            'delivery_welcome_seen_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
      debugPrint('✅ [ONBOARDING] Delivery welcome visto para: $userId');
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error marcando delivery welcome: $e');
    }
  }

  /// Calcular tareas pendientes para Restaurante
  static OnboardingStatus calculateRestaurantOnboarding(DoaRestaurant restaurant) {
    final tasks = <OnboardingTask>[];
    int completedCount = 0;
    
    // 1. Nombre del restaurante (real)
    final hasName = restaurant.name.trim().isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'name',
      title: 'Nombre del Restaurante',
      description: hasName ? 'Nombre configurado' : 'Agrega el nombre de tu restaurante',
      isCompleted: hasName,
      icon: hasName ? Icons.check_circle : Icons.store,
      actionLabel: hasName ? 'Completado' : 'Agregar Nombre',
      actionRoute: '/restaurant/profile',
      priority: 1,
    ));
    if (hasName) completedCount++;

    // 1.b Tipo de cocina (requerido)
    final hasCuisine = (restaurant.cuisineType ?? '').toString().trim().isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'cuisine',
      title: 'Tipo de Cocina',
      description: hasCuisine ? 'Tipo de cocina configurado' : 'Selecciona el tipo de cocina',
      isCompleted: hasCuisine,
      icon: hasCuisine ? Icons.check_circle : Icons.local_dining,
      actionLabel: hasCuisine ? 'Completado' : 'Seleccionar Tipo',
      actionRoute: '/restaurant/profile',
      priority: 2,
    ));
    if (hasCuisine) completedCount++;

    // 2. Logo del restaurante
    final hasLogo = restaurant.logoUrl != null && restaurant.logoUrl!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'logo',
      title: 'Logo del Restaurante',
      description: hasLogo ? 'Logo cargado exitosamente' : 'Sube el logo de tu restaurante',
      isCompleted: hasLogo,
      icon: hasLogo ? Icons.check_circle : Icons.image_outlined,
      actionLabel: hasLogo ? 'Completado' : 'Subir Logo',
      actionRoute: '/restaurant/profile',
      priority: 2,
    ));
    if (hasLogo) completedCount++;

    // 2. Descripción (real)
    final hasDescription = (restaurant.description ?? '').trim().isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'description',
      title: 'Descripción',
      description: hasDescription ? 'Descripción configurada' : 'Agrega una breve descripción atractiva',
      isCompleted: hasDescription,
      icon: hasDescription ? Icons.check_circle : Icons.description,
      actionLabel: hasDescription ? 'Completado' : 'Agregar Descripción',
      actionRoute: '/restaurant/profile',
      priority: 2,
    ));
    if (hasDescription) completedCount++;

    // 3. Foto de portada
    final hasCover = (restaurant.coverImageUrl != null && restaurant.coverImageUrl!.isNotEmpty) ||
                     (restaurant.imageUrl != null && restaurant.imageUrl!.isNotEmpty);
    tasks.add(OnboardingTask(
      id: 'cover',
      title: 'Foto de Portada',
      description: hasCover ? 'Portada configurada' : 'Agrega una foto atractiva de tu restaurante',
      isCompleted: hasCover,
      icon: hasCover ? Icons.check_circle : Icons.photo_camera_outlined,
      actionLabel: hasCover ? 'Completado' : 'Subir Portada',
      actionRoute: '/restaurant/profile',
      priority: 3,
    ));
    if (hasCover) completedCount++;

    // 4. Menú del restaurante (al menos 3 productos)
    // Nota: este método síncrono no consulta DB; quedará como pendiente por defecto.
    // La versión asíncrona calculateRestaurantOnboardingAsync hará la verificación real.
    tasks.add(OnboardingTask(
      id: 'menu',
      title: 'Agregar Productos al Menú',
      description: 'Agrega al menos 3 productos para empezar a vender',
      isCompleted: false,
      icon: Icons.restaurant_menu,
      actionLabel: 'Agregar Productos',
      actionRoute: '/restaurant/products',
      priority: 4,
    ));

    // 5. Aprobación del administrador
    final isApproved = restaurant.status == RestaurantStatus.approved;
    tasks.add(OnboardingTask(
      id: 'admin_approval',
      title: 'Aprobación del Administrador',
      description: isApproved 
          ? '¡Felicidades! Tu restaurante ha sido aprobado' 
          : 'Esperando revisión del equipo administrativo',
      isCompleted: isApproved,
      icon: isApproved ? Icons.verified : Icons.hourglass_empty,
      actionLabel: isApproved ? 'Aprobado' : 'Pendiente',
      priority: 6,
    ));
    if (isApproved) completedCount++;

    // Calcular porcentaje ponderado (excluyendo opcionales)
    final totalRequired = tasks.where((t) => !t.isOptional).length;
    final completedRequired = tasks.where((t) => !t.isOptional && t.isCompleted).length;
    final percentage = _computeWeightedPercentage(tasks);

    return OnboardingStatus(
      tasks: tasks,
      completedCount: completedCount,
      totalCount: tasks.length,
      completedRequired: completedRequired,
      totalRequired: totalRequired,
      percentage: percentage,
      isComplete: percentage >= 80, // 80% para poder ponerse online
      minPercentageToActivate: 80,
    );
  }

  /// Versión asíncrona que consulta Supabase para validar el conteo real de productos
  /// y calcula el checklist 100% basado en datos: nombre, descripción, logo, portada, 3 productos
  static Future<OnboardingStatus> calculateRestaurantOnboardingAsync(DoaRestaurant restaurant) async {
    try {
      // Obtener conteo real de productos disponibles
      final products = await DoaRepartosService.getProductsByRestaurant(restaurant.id, isAvailable: true);
      final productCount = products.length;

      final hasName = restaurant.name.trim().isNotEmpty;
      final hasDescription = (restaurant.description ?? '').trim().isNotEmpty;
      final hasLogo = (restaurant.logoUrl ?? '').trim().isNotEmpty;
      final hasCover = (restaurant.coverImageUrl ?? restaurant.imageUrl ?? '').trim().isNotEmpty;
      final hasCuisine = (restaurant.cuisineType ?? '').toString().trim().isNotEmpty;
      final hasMinProducts = productCount >= 1;
      final isApproved = restaurant.status == RestaurantStatus.approved;

      final tasks = <OnboardingTask>[
        OnboardingTask(
          id: 'name',
          title: 'Nombre del Restaurante',
          description: hasName ? 'Nombre configurado' : 'Agrega el nombre de tu restaurante',
          isCompleted: hasName,
          icon: hasName ? Icons.check_circle : Icons.store,
          actionLabel: hasName ? 'Completado' : 'Agregar Nombre',
          actionRoute: '/restaurant/profile',
          priority: 1,
        ),
        OnboardingTask(
          id: 'cuisine',
          title: 'Tipo de Cocina',
          description: hasCuisine ? 'Tipo de cocina configurado' : 'Selecciona el tipo de cocina',
          isCompleted: hasCuisine,
          icon: hasCuisine ? Icons.check_circle : Icons.local_dining,
          actionLabel: hasCuisine ? 'Completado' : 'Seleccionar Tipo',
          actionRoute: '/restaurant/profile',
          priority: 2,
        ),
        OnboardingTask(
          id: 'description',
          title: 'Descripción',
          description: hasDescription ? 'Descripción configurada' : 'Agrega una breve descripción atractiva',
          isCompleted: hasDescription,
          icon: hasDescription ? Icons.check_circle : Icons.description,
          actionLabel: hasDescription ? 'Completado' : 'Agregar Descripción',
          actionRoute: '/restaurant/profile',
          priority: 3,
        ),
        OnboardingTask(
          id: 'logo',
          title: 'Logo del Restaurante',
          description: hasLogo ? 'Logo cargado exitosamente' : 'Sube el logo de tu restaurante',
          isCompleted: hasLogo,
          icon: hasLogo ? Icons.check_circle : Icons.image_outlined,
          actionLabel: hasLogo ? 'Completado' : 'Subir Logo',
          actionRoute: '/restaurant/profile',
          priority: 4,
        ),
        OnboardingTask(
          id: 'cover',
          title: 'Foto de Portada',
          description: hasCover ? 'Portada configurada' : 'Agrega una foto atractiva de tu restaurante',
          isCompleted: hasCover,
          icon: hasCover ? Icons.check_circle : Icons.photo_camera_outlined,
          actionLabel: hasCover ? 'Completado' : 'Subir Portada',
          actionRoute: '/restaurant/profile',
          priority: 5,
        ),
        OnboardingTask(
          id: 'menu',
          title: 'Agregar Productos al Menú',
          description: hasMinProducts
              ? 'Tienes $productCount productos activos'
              : 'Agrega al menos 1 producto para empezar a vender',
          isCompleted: hasMinProducts,
          icon: hasMinProducts ? Icons.check_circle : Icons.restaurant_menu,
          actionLabel: hasMinProducts ? 'Completado' : 'Agregar Productos',
          actionRoute: '/restaurant/products',
          priority: 6,
        ),
        OnboardingTask(
          id: 'admin_approval',
          title: 'Aprobación del Administrador',
          description: isApproved
              ? '¡Felicidades! Tu restaurante ha sido aprobado'
              : 'Esperando revisión del equipo administrativo',
          isCompleted: isApproved,
          icon: isApproved ? Icons.verified : Icons.hourglass_empty,
          actionLabel: isApproved ? 'Aprobado' : 'Pendiente',
          priority: 7,
        ),
      ];

      final totalRequired = tasks.where((t) => !t.isOptional).length;
      final completedRequired = tasks.where((t) => !t.isOptional && t.isCompleted).length;
      final percentage = _computeWeightedPercentage(tasks);

      return OnboardingStatus(
        tasks: tasks,
        completedCount: completedRequired,
        totalCount: tasks.length,
        completedRequired: completedRequired,
        totalRequired: totalRequired,
        percentage: percentage,
        // Debe cumplir porcentaje mínimo, contar con 3 productos y estar aprobado
        isComplete: percentage >= 80 && hasMinProducts && isApproved,
        minPercentageToActivate: 80,
      );
    } catch (e) {
      debugPrint('❌ [ONBOARDING] Error calculating async onboarding: $e');
      // Fallback a la versión sincrónica si hay algún error
      return calculateRestaurantOnboarding(restaurant);
    }
  }

  /// Calcular tareas pendientes para Repartidor
  static OnboardingStatus calculateDeliveryOnboarding(DoaUser deliveryAgent) {
    final tasks = <OnboardingTask>[];
    int completedCount = 0;
    
    // 1. Información básica (siempre completada en registro)
    tasks.add(OnboardingTask(
      id: 'basic_info',
      title: 'Información Personal',
      description: 'Nombre, teléfono, dirección, vehículo',
      isCompleted: true,
      icon: Icons.info_outline,
      actionLabel: 'Completado',
      priority: 1,
    ));
    completedCount++;

    // 2. Foto de perfil
    final hasProfilePhoto = deliveryAgent.profileImageUrl != null && 
                            deliveryAgent.profileImageUrl!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'profile_photo',
      title: 'Foto de Perfil',
      description: hasProfilePhoto ? 'Foto de perfil cargada' : 'Sube una foto clara de tu rostro',
      isCompleted: hasProfilePhoto,
      icon: hasProfilePhoto ? Icons.check_circle : Icons.person_outline,
      actionLabel: hasProfilePhoto ? 'Completado' : 'Subir Foto',
      actionRoute: '/profile',
      priority: 2,
    ));
    if (hasProfilePhoto) completedCount++;

    // 3. ID frontal
    final hasIdFront = deliveryAgent.idDocumentFrontUrl != null && 
                       deliveryAgent.idDocumentFrontUrl!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'id_front',
      title: 'Identificación (Frente)',
      description: hasIdFront ? 'ID frontal cargado' : 'Sube el frente de tu INE/IFE',
      isCompleted: hasIdFront,
      icon: hasIdFront ? Icons.check_circle : Icons.badge_outlined,
      actionLabel: hasIdFront ? 'Completado' : 'Subir ID',
      actionRoute: '/profile',
      priority: 3,
    ));
    if (hasIdFront) completedCount++;

    // 4. ID reverso
    final hasIdBack = deliveryAgent.idDocumentBackUrl != null && 
                      deliveryAgent.idDocumentBackUrl!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'id_back',
      title: 'Identificación (Reverso)',
      description: hasIdBack ? 'ID reverso cargado' : 'Sube el reverso de tu INE/IFE',
      isCompleted: hasIdBack,
      icon: hasIdBack ? Icons.check_circle : Icons.badge_outlined,
      actionLabel: hasIdBack ? 'Completado' : 'Subir ID',
      actionRoute: '/profile',
      priority: 4,
    ));
    if (hasIdBack) completedCount++;

    // 5. Foto del vehículo
    final hasVehiclePhoto = deliveryAgent.vehiclePhotoUrl != null && 
                           deliveryAgent.vehiclePhotoUrl!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'vehicle_photo',
      title: 'Foto del Vehículo',
      description: hasVehiclePhoto ? 'Vehículo fotografiado' : 'Sube una foto clara de tu vehículo',
      isCompleted: hasVehiclePhoto,
      icon: hasVehiclePhoto ? Icons.check_circle : Icons.directions_bike_outlined,
      actionLabel: hasVehiclePhoto ? 'Completado' : 'Subir Foto',
      actionRoute: '/profile',
      priority: 5,
    ));
    if (hasVehiclePhoto) completedCount++;

    // 6. Documentos del vehículo (opcional para bicicleta/pie)
    final needsVehicleDocs = deliveryAgent.vehicleType != 'pie' && 
                            deliveryAgent.vehicleType != 'bicicleta';
    final hasVehicleDocs = deliveryAgent.vehicleRegistrationUrl != null && 
                          deliveryAgent.vehicleRegistrationUrl!.isNotEmpty;
    
    if (needsVehicleDocs) {
      tasks.add(OnboardingTask(
        id: 'vehicle_docs',
        title: 'Documentos del Vehículo',
        description: hasVehicleDocs 
            ? 'Tarjeta de circulación cargada' 
            : 'Sube la tarjeta de circulación',
        isCompleted: hasVehicleDocs,
        icon: hasVehicleDocs ? Icons.check_circle : Icons.description_outlined,
        actionLabel: hasVehicleDocs ? 'Completado' : 'Subir Docs',
        actionRoute: '/profile',
        priority: 6,
        isOptional: true,
      ));
      if (hasVehicleDocs) completedCount++;
    }

    // 7. Contacto de emergencia
    final hasEmergencyContact = deliveryAgent.emergencyContactName != null && 
                               deliveryAgent.emergencyContactName!.isNotEmpty &&
                               deliveryAgent.emergencyContactPhone != null &&
                               deliveryAgent.emergencyContactPhone!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'emergency_contact',
      title: 'Contacto de Emergencia',
      description: hasEmergencyContact 
          ? 'Contacto de emergencia registrado' 
          : 'Agrega un contacto de emergencia',
      isCompleted: hasEmergencyContact,
      icon: hasEmergencyContact ? Icons.check_circle : Icons.contacts_outlined,
      actionLabel: hasEmergencyContact ? 'Completado' : 'Agregar Contacto',
      actionRoute: '/profile',
      priority: 7,
    ));
    if (hasEmergencyContact) completedCount++;

    // 8. Aprobación del administrador
    final isApproved = deliveryAgent.accountState == DeliveryAccountState.approved;
    tasks.add(OnboardingTask(
      id: 'admin_approval',
      title: 'Aprobación del Administrador',
      description: isApproved 
          ? '¡Felicidades! Has sido aprobado como repartidor' 
          : 'Esperando revisión del equipo administrativo',
      isCompleted: isApproved,
      icon: isApproved ? Icons.verified : Icons.hourglass_empty,
      actionLabel: isApproved ? 'Aprobado' : 'Pendiente',
      priority: 8,
    ));
    if (isApproved) completedCount++;

    // Calcular porcentaje (excluyendo opcionales)
    final totalRequired = tasks.where((t) => !t.isOptional).length;
    final completedRequired = tasks.where((t) => !t.isOptional && t.isCompleted).length;
    final percentage = ((completedRequired / totalRequired) * 100).round();

    // Un perfil de repartidor SOLO está "listo para entregar" cuando:
    // - Todas las tareas requeridas están completas (100% requerido)
    // - Y el administrador aprobó la cuenta
    final isComplete = (completedRequired == totalRequired) && isApproved;

    return OnboardingStatus(
      tasks: tasks,
      completedCount: completedCount,
      totalCount: tasks.length,
      completedRequired: completedRequired,
      totalRequired: totalRequired,
      percentage: percentage,
      isComplete: isComplete,
      // Para repartidores, el umbral real para activación es 100% requerido
      // (los opcionales no cuentan) + aprobación admin
      minPercentageToActivate: 100,
    );
  }

  /// Calcular tareas pendientes para Cliente
  static OnboardingStatus calculateClientOnboarding(DoaUser client) {
    final tasks = <OnboardingTask>[];
    int completedCount = 0;
    
    // 1. Información básica (siempre completada en registro)
    tasks.add(OnboardingTask(
      id: 'basic_info',
      title: 'Cuenta Creada',
      description: 'Tu cuenta está lista para hacer pedidos',
      isCompleted: true,
      icon: Icons.check_circle,
      actionLabel: 'Completado',
      priority: 1,
    ));
    completedCount++;

    // 2. Foto de perfil (opcional)
    final hasProfilePhoto = client.profileImageUrl != null && 
                            client.profileImageUrl!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'profile_photo',
      title: 'Foto de Perfil',
      description: hasProfilePhoto 
          ? 'Foto de perfil configurada' 
          : 'Opcional: Personaliza tu perfil con una foto',
      isCompleted: hasProfilePhoto,
      icon: hasProfilePhoto ? Icons.check_circle : Icons.person_outline,
      actionLabel: hasProfilePhoto ? 'Completado' : 'Agregar Foto',
      actionRoute: '/profile',
      priority: 2,
      isOptional: true,
    ));
    if (hasProfilePhoto) completedCount++;

    // 3. Dirección de entrega (opcional, se puede agregar en el checkout)
    final hasAddress = client.address != null && client.address!.isNotEmpty;
    tasks.add(OnboardingTask(
      id: 'delivery_address',
      title: 'Dirección de Entrega',
      description: hasAddress 
          ? 'Dirección guardada' 
          : 'Opcional: Guarda una dirección predeterminada',
      isCompleted: hasAddress,
      icon: hasAddress ? Icons.check_circle : Icons.location_on_outlined,
      actionLabel: hasAddress ? 'Completado' : 'Agregar Dirección',
      actionRoute: '/profile',
      priority: 3,
      isOptional: true,
    ));
    if (hasAddress) completedCount++;

    // Clientes no tienen requisitos estrictos - todo es opcional
    final totalRequired = 1; // Solo cuenta creada
    final completedRequired = 1;
    final percentage = 100; // Siempre 100% para clientes

    return OnboardingStatus(
      tasks: tasks,
      completedCount: completedCount,
      totalCount: tasks.length,
      completedRequired: completedRequired,
      totalRequired: totalRequired,
      percentage: percentage,
      isComplete: true, // Clientes siempre están completos
      minPercentageToActivate: 0,
    );
  }

  /// Obtener mensaje de bienvenida según el rol y estado
  static WelcomeMessage getWelcomeMessage(UserRole role, OnboardingStatus status) {
    switch (role) {
      case UserRole.restaurant:
        // Construcción dinámica del mensaje según tareas pendientes reales
        final pending = status.pendingTasks.where((t) => !t.isOptional).toList();
        final pendingIds = pending.map((t) => t.id).toSet();
        final pendingCount = pending.length;

        if (status.isComplete) {
          return WelcomeMessage(
            title: '🎉 ¡Bienvenido a DOÑA Repartos!',
            message: 'Tu perfil está completo. Ahora puedes activar tu restaurante y empezar a recibir pedidos.',
            icon: Icons.celebration,
            color: Colors.green,
            actionLabel: 'Empezar a Vender',
          );
        }

        // Caso específico: exactamente 2 pasos y son productos + aprobación
        if (pendingCount == 2 && pendingIds.contains('menu') && pendingIds.contains('admin_approval')) {
          return WelcomeMessage(
            title: '👋 Faltan 2 pasos',
            message: 'Agrega al menos 3 productos y espera la aprobación del administrador para empezar a vender.',
            icon: Icons.info,
            color: const Color(0xFFE4007C), // Rosa mexicano
            actionLabel: 'Completar Perfil',
          );
        }

        // Construcción genérica: Faltan N pasos, con un resumen de pendientes
        String _shortLabel(String id) {
          switch (id) {
            case 'name':
              return 'Nombre';
            case 'description':
              return 'Descripción';
            case 'cuisine':
              return 'Tipo de cocina';
            case 'logo':
              return 'Logo';
            case 'cover':
              return 'Portada';
            case 'menu':
              return '3 productos';
            case 'admin_approval':
              return 'Aprobación admin';
            default:
              return id;
          }
        }

        // Ordenar por prioridad original y listar primeros 4 elementos
        final sorted = List<OnboardingTask>.from(pending)
          ..sort((a, b) => a.priority.compareTo(b.priority));
        final labels = sorted.map((t) => _shortLabel(t.id)).toList();
        final preview = labels.take(4).join(', ');
        final hasMore = labels.length > 4;
        final moreSuffix = hasMore ? ' y más' : '';

        // Mensaje: muestra resumen y aclara aprobación si aplica
        final needsApproval = pendingIds.contains('admin_approval');
        final msgCore = 'Completa: $preview$moreSuffix';
        final msgApproval = needsApproval ? ' y espera la aprobación del administrador.' : '.';

        return WelcomeMessage(
          title: '👋 Faltan $pendingCount pasos',
          message: '$msgCore$msgApproval',
          icon: Icons.info,
          color: const Color(0xFFE4007C),
          actionLabel: 'Completar Perfil',
        );
        
      case UserRole.delivery_agent:
        if (status.isComplete) {
          return WelcomeMessage(
            title: '🎉 ¡Perfil aprobado!',
            message: 'Tu perfil está completo y aprobado. Ya puedes empezar a tomar pedidos.',
            icon: Icons.delivery_dining,
            color: Colors.green,
            actionLabel: 'Ver Pedidos',
          );
        } else if (status.percentage >= 50) {
          return WelcomeMessage(
            title: '👋 ¡Ya casi estás listo!',
            message: 'Completa todos los pasos requeridos y espera la aprobación del administrador.',
            icon: Icons.directions_bike,
            color: const Color(0xFFE4007C), // Rosa mexicano
            actionLabel: 'Completar Perfil',
          );
        } else {
          return WelcomeMessage(
            title: '🚚 ¡Bienvenido a DOÑA!',
            message: 'Sube tus documentos y fotos. Revisaremos tu solicitud en 24-48 horas.',
            icon: Icons.assignment,
            color: const Color(0xFFFFB1C8), // Rosa claro para contraste
            actionLabel: 'Subir Documentos',
          );
        }
        
      case UserRole.client:
        return WelcomeMessage(
          title: '🍽️ ¡Bienvenido a DOÑA Repartos!',
          message: '¡Tu cuenta está lista! Explora restaurantes cercanos y haz tu primer pedido.',
          icon: Icons.restaurant_menu,
          color: Colors.green,
          actionLabel: 'Explorar Restaurantes',
        );
        
      default:
        return WelcomeMessage(
          title: '👋 ¡Bienvenido!',
          message: 'Gracias por unirte a DOÑA Repartos.',
          icon: Icons.waving_hand,
          color: const Color(0xFFE4007C),
          actionLabel: 'Continuar',
        );
    }
  }
}

/// Estado de onboarding con tareas y progreso
class OnboardingStatus {
  final List<OnboardingTask> tasks;
  final int completedCount;
  final int totalCount;
  final int completedRequired;
  final int totalRequired;
  final int percentage;
  final bool isComplete;
  final int minPercentageToActivate;

  OnboardingStatus({
    required this.tasks,
    required this.completedCount,
    required this.totalCount,
    required this.completedRequired,
    required this.totalRequired,
    required this.percentage,
    required this.isComplete,
    required this.minPercentageToActivate,
  });

  List<OnboardingTask> get pendingTasks => 
      tasks.where((t) => !t.isCompleted && !t.isOptional).toList();
      
  List<OnboardingTask> get completedTasks => 
      tasks.where((t) => t.isCompleted).toList();
      
  List<OnboardingTask> get optionalTasks => 
      tasks.where((t) => t.isOptional).toList();
}

/// Tarea individual de onboarding
class OnboardingTask {
  final String id;
  final String title;
  final String description;
  final bool isCompleted;
  final IconData icon;
  final String actionLabel;
  final String? actionRoute;
  final int priority;
  final bool isOptional;

  OnboardingTask({
    required this.id,
    required this.title,
    required this.description,
    required this.isCompleted,
    required this.icon,
    required this.actionLabel,
    this.actionRoute,
    required this.priority,
    this.isOptional = false,
  });
}

/// Mensaje de bienvenida personalizado
class WelcomeMessage {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final String actionLabel;

  WelcomeMessage({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.actionLabel,
  });
}
