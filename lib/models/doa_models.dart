/// Data models for Doa Repartos food delivery app
/// These models match the Supabase schema exactly

import 'package:flutter/material.dart';

class DoaUser {
  final String id;
  final String email;
  final String? name;
  final String? phone;
  final String? address;
  final UserRole role;
  final UserStatus status;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? lat;
  final double? lon;
  final Map<String, dynamic>? addressStructured;
  
  // Profile images
  final String? profileImageUrl;
  final String? idDocumentFrontUrl;
  final String? idDocumentBackUrl;
  
  // Vehicle info (for delivery agents)
  final String? vehicleType;
  final String? vehiclePlate;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? vehicleRegistrationUrl;
  final String? vehicleInsuranceUrl;
  final String? vehiclePhotoUrl;
  
  // Emergency contact
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  
  // Delivery agent account state (separate from user status)
  final DeliveryAccountState? accountState; // 'pending' or 'approved' from delivery_agent_profiles
  
  // Email verification status (from public.users.email_confirm)
  final bool emailConfirm;

  DoaUser({
    required this.id,
    required this.email,
    this.name,
    this.phone,
    this.address,
    required this.role,
    this.status = UserStatus.offline,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.lat,
    this.lon,
    this.addressStructured,
    this.profileImageUrl,
    this.idDocumentFrontUrl,
    this.idDocumentBackUrl,
    this.vehicleType,
    this.vehiclePlate,
    this.vehicleModel,
    this.vehicleColor,
    this.vehicleRegistrationUrl,
    this.vehicleInsuranceUrl,
    this.vehiclePhotoUrl,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.accountState,
    this.emailConfirm = false,
  });

  factory DoaUser.fromJson(Map<String, dynamic> json) {
    // Prefer common name fields in order: name, full_name, username, display_name
    final dynamicName = json['name'] ?? json['full_name'] ?? json['username'] ?? json['display_name'];
    String? normalizedName;
    if (dynamicName is String && dynamicName.trim().isNotEmpty) {
      normalizedName = dynamicName.trim();
    } else {
      // Fallback: derive a friendly label from email if available
      final emailStr = (json['email'] ?? '').toString();
      if (emailStr.contains('@')) {
        normalizedName = emailStr.split('@').first;
      } else if (emailStr.isNotEmpty) {
        normalizedName = emailStr;
      }
    }
    // New schema: prefer nested client_profiles for address-related fields
    Map<String, dynamic>? clientProfile;
    try {
      if (json['client_profiles'] is Map<String, dynamic>) {
        clientProfile = Map<String, dynamic>.from(json['client_profiles']);
      }
    } catch (_) {}

    return DoaUser(
      // Some views/tables expose the user id as user_id. Fallback to that.
      id: (json['id'] ?? json['user_id'] ?? '').toString(),
      email: json['email'] ?? '',
      name: normalizedName,
      phone: json['phone']?.toString().isEmpty == true ? null : json['phone'],
      address: (() {
        final fromProfile = clientProfile?['address']?.toString();
        if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;
        final fromUsers = json['address']?.toString();
        if (fromUsers != null && fromUsers.isNotEmpty) return fromUsers;
        return null;
      })(),
      role: UserRole.fromString(json['role'] ?? 'cliente'),
      status: UserStatus.fromString(json['status']),
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : DateTime.now(),
      lat: (() {
        final n = clientProfile?['lat'];
        if (n is num) return n.toDouble();
        if (n is String) return double.tryParse(n);
        return (json['lat'] as num?)?.toDouble();
      })(),
      lon: (() {
        final n = clientProfile?['lon'];
        if (n is num) return n.toDouble();
        if (n is String) return double.tryParse(n);
        return (json['lon'] as num?)?.toDouble();
      })(),
      addressStructured: (() {
        final a = clientProfile?['address_structured'];
        if (a is Map<String, dynamic>) return a;
        if (a is Map) return Map<String, dynamic>.from(a);
        final b = json['address_structured'];
        if (b is Map<String, dynamic>) return b;
        if (b is Map) return Map<String, dynamic>.from(b);
        return null;
      })(),
      profileImageUrl: clientProfile?['profile_image_url'] ?? json['profile_image_url'],
      idDocumentFrontUrl: json['id_document_front_url'],
      idDocumentBackUrl: json['id_document_back_url'],
      vehicleType: json['vehicle_type'],
      vehiclePlate: json['vehicle_plate'],
      vehicleModel: json['vehicle_model'],
      vehicleColor: json['vehicle_color'],
      vehicleRegistrationUrl: json['vehicle_registration_url'],
      vehicleInsuranceUrl: json['vehicle_insurance_url'],
      vehiclePhotoUrl: json['vehicle_photo_url'],
      emergencyContactName: json['emergency_contact_name'],
      emergencyContactPhone: json['emergency_contact_phone'],
      accountState: json['account_state'] != null 
          ? DeliveryAccountState.fromString(json['account_state'].toString())
          : null,
      emailConfirm: json['email_confirm'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'address': address,
      'role': role.toString(),
      'status': status.toString(),
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'lat': lat,
      'lon': lon,
      'address_structured': addressStructured,
      'profile_image_url': profileImageUrl,
      'id_document_front_url': idDocumentFrontUrl,
      'id_document_back_url': idDocumentBackUrl,
      'vehicle_type': vehicleType,
      'vehicle_plate': vehiclePlate,
      'vehicle_model': vehicleModel,
      'vehicle_color': vehicleColor,
      'vehicle_registration_url': vehicleRegistrationUrl,
      'vehicle_insurance_url': vehicleInsuranceUrl,
      'vehicle_photo_url': vehiclePhotoUrl,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'account_state': accountState?.name,
      'email_confirm': emailConfirm,
    };
  }

  // Helper methods to access address_structured data with fallback to legacy columns
  
  /// Get latitude - prefers address_structured, falls back to lat column
  double? get latitude {
    if (addressStructured != null && addressStructured!['lat'] != null) {
      final latValue = addressStructured!['lat'];
      if (latValue is num) return latValue.toDouble();
      if (latValue is String) return double.tryParse(latValue);
    }
    return lat;
  }

  /// Get longitude - prefers address_structured, falls back to lon column
  double? get longitude {
    if (addressStructured != null && addressStructured!['lon'] != null) {
      final lonValue = addressStructured!['lon'];
      if (lonValue is num) return lonValue.toDouble();
      if (lonValue is String) return double.tryParse(lonValue);
    }
    return lon;
  }

  /// Get formatted address - prefers address_structured, falls back to address column
  String? get formattedAddress {
    if (addressStructured != null && addressStructured!['formatted_address'] != null) {
      final addr = addressStructured!['formatted_address'];
      if (addr is String && addr.isNotEmpty) return addr;
    }
    return address;
  }

  /// Check if user has valid coordinates
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Get place ID from address_structured (if available)
  String? get placeId => addressStructured?['place_id'];

  /// Get city from address_structured (if available)
  String? get city => addressStructured?['city'];

  /// Get street from address_structured (if available)
  String? get street => addressStructured?['street'];

  /// Get state from address_structured (if available)
  String? get state => addressStructured?['state'];

  /// Get country from address_structured (if available)
  String? get country => addressStructured?['country'];

  /// Get postal code from address_structured (if available)
  String? get postalCode => addressStructured?['postal_code'];
}

enum UserRole {
  client,
  restaurant,
  delivery_agent,
  admin;

  static UserRole fromString(String role) {
    final r = role.toLowerCase();
    switch (r) {
      // Inglés (principal)
      case 'client':
      // Español (compatibilidad)
      case 'cliente':
      case 'usuario':
      case 'user':
        return UserRole.client;
      // Inglés (principal)
      case 'restaurant':
      // Español (compatibilidad)
      case 'restaurante':
        return UserRole.restaurant;
      // Inglés (principal)
      case 'delivery_agent':
      case 'delivery':
      // Español (compatibilidad)
      case 'repartidor':
      case 'rider':
      case 'courier':
        return UserRole.delivery_agent;
      case 'admin':
      case 'administrator':
        return UserRole.admin;
      default:
        return UserRole.client;
    }
  }

  /// Retorna el valor en inglés para Supabase
  String toSupabaseValue() {
    switch (this) {
      case UserRole.client:
        return 'client';
      case UserRole.restaurant:
        return 'restaurant';
      case UserRole.delivery_agent:
        return 'delivery_agent';
      case UserRole.admin:
        return 'admin';
    }
  }

  @override
  String toString() => toSupabaseValue();
}

/// Delivery agent online/offline status (from delivery_agent_profiles.status)
enum UserStatus {
  offline,
  online,
  busy;

  static UserStatus fromString(String? status) {
    if (status == null || status.isEmpty) {
      return UserStatus.offline;
    }
    return UserStatus.values.firstWhere(
      (s) => s.name == status.toLowerCase(),
      orElse: () => UserStatus.offline,
    );
  }

  @override
  String toString() => name;

  String get displayName {
    switch (this) {
      case UserStatus.offline:
        return 'Desconectado';
      case UserStatus.online:
        return 'Disponible';
      case UserStatus.busy:
        return 'Ocupado';
    }
  }

  Color get color {
    switch (this) {
      case UserStatus.offline:
        return Colors.grey;
      case UserStatus.online:
        return Colors.green;
      case UserStatus.busy:
        return Colors.orange;
    }
  }

  IconData get icon {
    switch (this) {
      case UserStatus.offline:
        return Icons.power_settings_new;
      case UserStatus.online:
        return Icons.check_circle;
      case UserStatus.busy:
        return Icons.delivery_dining;
    }
  }
}

/// Delivery agent account approval state (from delivery_agent_profiles.account_state)
enum DeliveryAccountState {
  pending,
  approved;

  static DeliveryAccountState fromString(String? state) {
    if (state == null || state.isEmpty) {
      return DeliveryAccountState.pending;
    }
    return DeliveryAccountState.values.firstWhere(
      (s) => s.name == state.toLowerCase(),
      orElse: () => DeliveryAccountState.pending,
    );
  }

  @override
  String toString() => name;

  String get displayName {
    switch (this) {
      case DeliveryAccountState.pending:
        return 'Pendiente';
      case DeliveryAccountState.approved:
        return 'Aprobado';
    }
  }

  Color get color {
    switch (this) {
      case DeliveryAccountState.pending:
        return Colors.orange;
      case DeliveryAccountState.approved:
        return Colors.green;
    }
  }

  IconData get icon {
    switch (this) {
      case DeliveryAccountState.pending:
        return Icons.hourglass_empty;
      case DeliveryAccountState.approved:
        return Icons.check_circle;
    }
  }
}

class DoaRestaurant {
  final String id;
  final String userId;
  final String name;
  final String? description;
  final String? logoUrl;
  final RestaurantStatus status;
  final bool online; // Whether restaurant is currently online/active
  final DateTime createdAt;
  final DateTime updatedAt;
  final DoaUser? user; // Populated when fetched with joins
  
  // Address (legacy text field)
  final String? address;
  final String? phone;
  
  // Address structured JSON (contains lat/lon)
  final Map<String, dynamic>? addressStructured;
  // Geolocation parsed from address_structured
  final double? lat;
  final double? lon;
  
  // Images
  final String? coverImageUrl;
  final String? menuImageUrl;
  final String? facadeImageUrl;
  final String? businessPermitUrl;
  final String? healthPermitUrl;
  
  // Business details
  final String? cuisineType;
  final Map<String, dynamic>? businessHours;
  final double? deliveryRadiusKm;
  final double? minOrderAmount;
  final int? estimatedDeliveryTimeMinutes;
  
  // Commission in basis points (1500 = 15%)
  final int commissionBps;
  
  // UI properties for display
  final String? imageUrl;
  final double? rating;
  final int? deliveryTime; // in minutes
  final double? deliveryFee;
  final bool isOpen;
  
  // Onboarding tracking
  final bool onboardingCompleted;
  final int onboardingStep;
  final int profileCompletionPercentage;

  DoaRestaurant({
    required this.id,
    required this.userId,
    required this.name,
    this.description,
    this.logoUrl,
    required this.status,
    this.online = false,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.address,
    this.phone,
    this.addressStructured,
    this.lat,
    this.lon,
    this.coverImageUrl,
    this.menuImageUrl,
    this.facadeImageUrl,
    this.businessPermitUrl,
    this.healthPermitUrl,
    this.cuisineType,
    this.businessHours,
    this.deliveryRadiusKm,
    this.minOrderAmount,
    this.estimatedDeliveryTimeMinutes,
    this.commissionBps = 1500,
    // UI properties with defaults
    this.imageUrl,
    this.rating,
    this.deliveryTime,
    this.deliveryFee,
    this.isOpen = true,
    // Onboarding properties
    this.onboardingCompleted = false,
    this.onboardingStep = 0,
    this.profileCompletionPercentage = 0,
  });

  factory DoaRestaurant.fromJson(Map<String, dynamic> json) {
    // Parse address_structured and extract lat/lon from it
    final addressStructured = json['address_structured'] != null
        ? Map<String, dynamic>.from(json['address_structured'])
        : null;
    final lat = addressStructured != null
        ? (addressStructured['lat'] as num?)?.toDouble()
        : null;
    final lon = addressStructured != null
        ? (addressStructured['lon'] as num?)?.toDouble()
        : null;

    return DoaRestaurant(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
      description: json['description'],
      logoUrl: json['logo_url'],
      status: RestaurantStatus.fromString(json['status']),
      online: json['online'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      user: json['users'] != null ? DoaUser.fromJson(json['users']) : 
            json['user'] != null ? DoaUser.fromJson(json['user']) : null,
      address: json['address'],
      phone: json['phone'],
      addressStructured: addressStructured,
      lat: lat,
      lon: lon,
      commissionBps: json['commission_bps'] ?? 1500,
      coverImageUrl: json['cover_image_url'],
      menuImageUrl: json['menu_image_url'],
      facadeImageUrl: json['facade_image_url'],
      businessPermitUrl: json['business_permit_url'],
      healthPermitUrl: json['health_permit_url'],
      cuisineType: json['cuisine_type'],
      businessHours: json['business_hours'] != null ? Map<String, dynamic>.from(json['business_hours']) : null,
      deliveryRadiusKm: json['delivery_radius_km'] != null ? (json['delivery_radius_km'] as num).toDouble() : null,
      minOrderAmount: json['min_order_amount'] != null ? (json['min_order_amount'] as num).toDouble() : null,
      estimatedDeliveryTimeMinutes: json['estimated_delivery_time_minutes'],
      // UI properties
      imageUrl: json['image_url'] ?? json['cover_image_url'] ?? json['logo_url'],
      rating: json['rating'] != null ? (json['rating'] as num).toDouble() : null,
      deliveryTime: json['delivery_time'] != null ? json['delivery_time'] as int : json['estimated_delivery_time_minutes'],
      deliveryFee: json['delivery_fee'] != null ? (json['delivery_fee'] as num).toDouble() : null,
      isOpen: json['is_open'] ?? true,
      // Onboarding properties
      onboardingCompleted: json['onboarding_completed'] ?? false,
      onboardingStep: json['onboarding_step'] ?? 0,
      profileCompletionPercentage: json['profile_completion_percentage'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'description': description,
      'logo_url': logoUrl,
      'status': status.toString(),
      'online': online,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'address_structured': addressStructured,
      'lat': lat,
      'lon': lon,
      'cover_image_url': coverImageUrl,
      'menu_image_url': menuImageUrl,
      'facade_image_url': facadeImageUrl,
      'business_permit_url': businessPermitUrl,
      'health_permit_url': healthPermitUrl,
      'cuisine_type': cuisineType,
      'business_hours': businessHours,
      'delivery_radius_km': deliveryRadiusKm,
      'min_order_amount': minOrderAmount,
      'estimated_delivery_time_minutes': estimatedDeliveryTimeMinutes,
      'onboarding_completed': onboardingCompleted,
      'onboarding_step': onboardingStep,
      'profile_completion_percentage': profileCompletionPercentage,
    };
  }

  // Helper methods to access address_structured data with fallback to legacy columns
  
  /// Get latitude - prefers address_structured, falls back to lat column, then user.lat
  double? get latitude {
    if (addressStructured != null && addressStructured!['lat'] != null) {
      final latValue = addressStructured!['lat'];
      if (latValue is num) return latValue.toDouble();
      if (latValue is String) return double.tryParse(latValue);
    }
    if (lat != null) return lat;
    return user?.latitude;
  }

  /// Get longitude - prefers address_structured, falls back to lon column, then user.lon
  double? get longitude {
    if (addressStructured != null && addressStructured!['lon'] != null) {
      final lonValue = addressStructured!['lon'];
      if (lonValue is num) return lonValue.toDouble();
      if (lonValue is String) return double.tryParse(lonValue);
    }
    if (lon != null) return lon;
    return user?.longitude;
  }

  /// Get formatted address - prefers address_structured, falls back to user.address
  String? get formattedAddress {
    if (addressStructured != null && addressStructured!['formatted_address'] != null) {
      final addr = addressStructured!['formatted_address'];
      if (addr is String && addr.isNotEmpty) return addr;
    }
    return user?.formattedAddress;
  }

  /// Check if restaurant has valid coordinates
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Get place ID from address_structured (if available)
  String? get placeId => addressStructured?['place_id'];

  /// Get city from address_structured (if available)
  String? get city => addressStructured?['city'];

  /// Get street from address_structured (if available)
  String? get street => addressStructured?['street'];

  /// Get state from address_structured (if available)
  String? get state => addressStructured?['state'];

  /// Get country from address_structured (if available)
  String? get country => addressStructured?['country'];

  /// Get postal code from address_structured (if available)
  String? get postalCode => addressStructured?['postal_code'];

  DoaRestaurant copyWith({
    String? id,
    String? userId,
    String? name,
    String? description,
    String? logoUrl,
    RestaurantStatus? status,
    bool? online,
    DateTime? createdAt,
    DateTime? updatedAt,
    DoaUser? user,
    Map<String, dynamic>? addressStructured,
    double? lat,
    double? lon,
    String? coverImageUrl,
    String? menuImageUrl,
    String? businessPermitUrl,
    String? healthPermitUrl,
    String? cuisineType,
    Map<String, dynamic>? businessHours,
    double? deliveryRadiusKm,
    double? minOrderAmount,
    int? estimatedDeliveryTimeMinutes,
    String? imageUrl,
    double? rating,
    int? deliveryTime,
    double? deliveryFee,
    bool? isOpen,
    bool? onboardingCompleted,
    int? onboardingStep,
    int? profileCompletionPercentage,
  }) {
    return DoaRestaurant(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      description: description ?? this.description,
      logoUrl: logoUrl ?? this.logoUrl,
      status: status ?? this.status,
      online: online ?? this.online,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user ?? this.user,
      addressStructured: addressStructured ?? this.addressStructured,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      menuImageUrl: menuImageUrl ?? this.menuImageUrl,
      businessPermitUrl: businessPermitUrl ?? this.businessPermitUrl,
      healthPermitUrl: healthPermitUrl ?? this.healthPermitUrl,
      cuisineType: cuisineType ?? this.cuisineType,
      businessHours: businessHours ?? this.businessHours,
      deliveryRadiusKm: deliveryRadiusKm ?? this.deliveryRadiusKm,
      minOrderAmount: minOrderAmount ?? this.minOrderAmount,
      estimatedDeliveryTimeMinutes: estimatedDeliveryTimeMinutes ?? this.estimatedDeliveryTimeMinutes,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      isOpen: isOpen ?? this.isOpen,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      onboardingStep: onboardingStep ?? this.onboardingStep,
      profileCompletionPercentage: profileCompletionPercentage ?? this.profileCompletionPercentage,
    );
  }
}

enum RestaurantStatus {
  pending,
  approved,
  rejected;

  static RestaurantStatus fromString(String? status) {
    if (status == null || status.isEmpty) {
      return RestaurantStatus.pending;
    }
    return RestaurantStatus.values.firstWhere(
      (s) => s.name == status.toLowerCase(),
      orElse: () => RestaurantStatus.pending,
    );
  }

  @override
  String toString() => name;
}

/// Extension con helpers visuales para RestaurantStatus
extension RestaurantStatusExtension on RestaurantStatus {
  String get displayName {
    switch (this) {
      case RestaurantStatus.pending:
        return 'Pendiente';
      case RestaurantStatus.approved:
        return 'Aprobado';
      case RestaurantStatus.rejected:
        return 'Rechazado';
    }
  }

  Color get color {
    switch (this) {
      case RestaurantStatus.pending:
        return Colors.orange;
      case RestaurantStatus.approved:
        return Colors.green;
      case RestaurantStatus.rejected:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case RestaurantStatus.pending:
        return Icons.hourglass_empty;
      case RestaurantStatus.approved:
        return Icons.check_circle;
      case RestaurantStatus.rejected:
        return Icons.cancel;
    }
  }
}

class DoaProduct {
  final String id;
  final String restaurantId;
  final String name;
  final String? description;
  final double price;
  final String? imageUrl;
  final bool isAvailable;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// Product type as per DB schema: 'principal' | 'bebida' | 'postre' | 'entrada' | 'combo'
  final String? type;

  /// When type == 'combo', contains the JSONB array of objects
  /// [{'product_id': 'uuid', 'quantity': 1}, ...]
  /// We keep a permissive type to align with DB jsonb and avoid tight coupling.
  final List<Map<String, dynamic>>? contains;

  // Flag computed client-side to mark if this product is a combo
  final bool isCombo;

  DoaProduct({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
    required this.createdAt,
    required this.updatedAt,
    this.type,
    this.contains,
    this.isCombo = false,
  });

  factory DoaProduct.fromJson(Map<String, dynamic> json) {
    // print('🍕 [PRODUCT] Parsing product from JSON: $json');
    
    try {
      return DoaProduct(
        id: json['id'] ?? '',
        restaurantId: json['restaurant_id'] ?? '',
        name: json['name'] ?? 'Producto sin nombre',
        description: json['description'],
        price: json['price'] != null ? (json['price'] as num).toDouble() : 0.0,
        imageUrl: json['image_url'],
        isAvailable: json['is_available'] ?? true,
        createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
        updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
        // Prefer explicit 'type' column if present per updated schema
        type: (json['type'] as String?)?.toLowerCase(),
        // contains can come as jsonb array of objects or a legacy array of uuids
        contains: () {
          final raw = json['contains'];
          if (raw == null) return null;
          if (raw is List) {
            if (raw.isEmpty) return <Map<String, dynamic>>[];
            // If elements are maps, pass through
            if (raw.first is Map) {
              return raw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
            }
            // If elements are strings (legacy UUID[]), convert to objects with quantity=1
            if (raw.first is String) {
              return raw
                  .whereType<String>()
                  .map<Map<String, dynamic>>((id) => {
                        'product_id': id,
                        'quantity': 1,
                      })
                  .toList();
            }
          }
          return null;
        }(),
        // Backward compatibility: compute isCombo from 'type' or boolean flags
        isCombo: ((json['type'] as String?)?.toLowerCase() == 'combo')
            || (json['is_combo'] == true)
            || (json['product_type'] == 'combo'),
      );
    } catch (e) {
      print('❌ [PRODUCT] Error parsing product: $e');
      print('📍 [PRODUCT] Problematic JSON: $json');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'restaurant_id': restaurantId,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'is_available': isAvailable,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (type != null) 'type': type,
      if (contains != null) 'contains': contains,
      // Do not persist isCombo here; combo linkage lives in product_combos
    };
  }
}

/// Combo model backed by tables: product_combos and product_combo_items
class DoaCombo {
  final String id; // combo id
  final String productId; // points to products.id that customers buy
  final String restaurantId;
  final List<DoaComboItem> items;
  final DateTime createdAt;

  DoaCombo({
    required this.id,
    required this.productId,
    required this.restaurantId,
    required this.items,
    required this.createdAt,
  });

  factory DoaCombo.fromJson(Map<String, dynamic> json) {
    return DoaCombo(
      id: json['id'] ?? '',
      productId: json['product_id'] ?? '',
      restaurantId: json['restaurant_id'] ?? json['restaurants']?['id'] ?? '',
      items: (json['items'] as List?)?.map((e) => DoaComboItem.fromJson(e)).toList() ?? const [],
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : DateTime.now(),
    );
  }
}

class DoaComboItem {
  final String id;
  final String comboId;
  final String productId;
  final int quantity;
  final DoaProduct? product; // embedded when joined

  const DoaComboItem({
    required this.id,
    required this.comboId,
    required this.productId,
    required this.quantity,
    this.product,
  });

  factory DoaComboItem.fromJson(Map<String, dynamic> json) {
    return DoaComboItem(
      id: json['id'] ?? '',
      comboId: json['combo_id'] ?? '',
      productId: json['product_id'] ?? '',
      quantity: (json['quantity'] ?? 1) as int,
      product: json['product'] != null ? DoaProduct.fromJson(json['product']) : null,
    );
  }
}

class DoaOrder {
  final String id;
  final String userId;
  final String? restaurantId; // Ahora nullable para manejar casos con restaurant_id NULL
  final String? deliveryAgentId;
  final OrderStatus status;
  final double totalAmount;
  final PaymentMethod? paymentMethod;
  final String? deliveryAddress; // Ahora nullable para manejar casos con delivery_address NULL
  final String? deliveryLatlng;
  final double? deliveryLat;
  final double? deliveryLon;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? assignedAt; // Timestamp cuando se asignó a un repartidor
  final DateTime? deliveryTime; // Tiempo estimado de entrega
  final DateTime? pickupTime; // Tiempo de recogida
  final double? deliveryFee; // Tarifa de delivery
  final String? confirmCode; // Código de 3 dígitos para confirmar entrega
  final String? pickupCode; // Código de 4 dígitos para recoger en restaurante
  final String? orderNotes; // Notas del pedido (opcional)
  final DoaUser? user;
  final DoaRestaurant? restaurant;
  final DoaUser? deliveryAgent;
  final List<DoaOrderItem>? orderItems;

  DoaOrder({
    required this.id,
    required this.userId,
    this.restaurantId, // Ahora opcional
    this.deliveryAgentId,
    required this.status,
    required this.totalAmount,
    this.paymentMethod,
    this.deliveryAddress, // Ahora opcional
    this.deliveryLatlng,
    this.deliveryLat,
    this.deliveryLon,
    required this.createdAt,
    required this.updatedAt,
    this.assignedAt, // Timestamp opcional cuando se asignó a un repartidor
    this.deliveryTime, // Tiempo estimado de entrega opcional
    this.pickupTime, // Tiempo de recogida opcional
    this.deliveryFee, // Tarifa de delivery opcional
    this.confirmCode, // Código de confirmación opcional
    this.pickupCode, // Código de recogida opcional
    this.orderNotes, // Notas del pedido opcionales
    this.user,
    this.restaurant,
    this.deliveryAgent,
    this.orderItems,
  });

  // Getter de conveniencia para acceder a los items del pedido
  List<DoaOrderItem>? get items => orderItems;

  factory DoaOrder.fromJson(Map<String, dynamic> json) {
    // Debugging: Log de datos recibidos para identificar problemas
    // debugPrint('🔧 [MODELS] ===== PARSING ORDER =====');
    // debugPrint('🔧 [MODELS] Order ID: ${json['id']?.toString().substring(0, 8) ?? 'NO_ID'}');
    // debugPrint('🔧 [MODELS] Restaurant ID: ${json['restaurant_id']}');
    // debugPrint('🔧 [MODELS] User ID: ${json['user_id']}');
    // debugPrint('🔧 [MODELS] Status: ${json['status']}');
    // debugPrint('🔧 [MODELS] Raw JSON: $json');
    
    try {
      final order = DoaOrder(
        id: json['id']?.toString() ?? '',
        userId: json['user_id']?.toString() ?? '',
        restaurantId: json['restaurant_id']?.toString(), // Nullable, acepta null
        deliveryAgentId: json['delivery_agent_id']?.toString(),
        status: OrderStatus.fromString(json['status']?.toString() ?? 'pending'),
        totalAmount: json['total_amount'] != null ? (json['total_amount'] as num).toDouble() : 0.0,
        paymentMethod: json['payment_method'] != null 
            ? PaymentMethod.fromString(json['payment_method'].toString()) 
            : null,
        deliveryAddress: json['delivery_address']?.toString(), // Nullable, acepta null
        deliveryLatlng: json['delivery_latlng']?.toString(),
        deliveryLat: (json['delivery_lat'] as num?)?.toDouble(),
        deliveryLon: (json['delivery_lon'] as num?)?.toDouble(),
        createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'].toString()) : DateTime.now(),
        updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'].toString()) : DateTime.now(),
        assignedAt: json['assigned_at'] != null ? DateTime.parse(json['assigned_at'].toString()) : null,
        deliveryTime: json['delivery_time'] != null ? DateTime.parse(json['delivery_time'].toString()) : null,
        pickupTime: json['pickup_time'] != null ? DateTime.parse(json['pickup_time'].toString()) : null,
        deliveryFee: json['delivery_fee'] != null ? (json['delivery_fee'] as num).toDouble() : null,
        confirmCode: json['confirm_code']?.toString(),
        pickupCode: json['pickup_code']?.toString(),
        orderNotes: json['order_notes']?.toString(),
        user: json['user'] != null ? DoaUser.fromJson(json['user']) : null,
        restaurant: json['restaurant'] != null ? DoaRestaurant.fromJson(json['restaurant']) : null,
        deliveryAgent: () {
          // debugPrint('🚚 [MODELS] 🔍 Buscando delivery agent...');
          // debugPrint('🚚 [MODELS] delivery_agent_id: ${json['delivery_agent_id']}');
          // debugPrint('🚚 [MODELS] delivery_agent_user: ${json['delivery_agent_user'] != null}');
          
          if (json['delivery_agent_user'] != null) {
            // debugPrint('✅ [MODELS] ✅ delivery_agent_user encontrado');
            return DoaUser.fromJson(json['delivery_agent_user']);
          } else if (json['delivery_agent'] != null) {
            // debugPrint('✅ [MODELS] ✅ delivery_agent encontrado');
            return DoaUser.fromJson(json['delivery_agent']);
          } else if (json['delivery_agents'] != null) {
            // debugPrint('✅ [MODELS] ✅ delivery_agents encontrado');
            return DoaUser.fromJson(json['delivery_agents']);
          } else {
            // debugPrint('❌ [MODELS] ❌ NO se encontró delivery agent (pero ID existe: ${json['delivery_agent_id']})');
            return null;
          }
        }(),
        orderItems: json['order_items'] != null 
            ? (json['order_items'] as List).map((item) => DoaOrderItem.fromJson(item)).toList()
            : null,
      );
      
      // debugPrint('✅ [MODELS] Order parseado exitosamente: ${order.id}');
      return order;
    } catch (e) {
      print('❌ [MODELS] Error parsing DoaOrder: $e');
      print('📋 [MODELS] Problematic JSON data:');
      json.forEach((key, value) {
        print('   $key: $value (${value.runtimeType})');
      });
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'restaurant_id': restaurantId,
      'delivery_agent_id': deliveryAgentId,
      'status': status.toString(),
      'total_amount': totalAmount,
      'payment_method': paymentMethod?.toString(),
      'delivery_address': deliveryAddress,
      'delivery_latlng': deliveryLatlng,
      'delivery_lat': deliveryLat,
      'delivery_lon': deliveryLon,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'assigned_at': assignedAt?.toIso8601String(),
      'delivery_time': deliveryTime?.toIso8601String(),
      'pickup_time': pickupTime?.toIso8601String(),
      'delivery_fee': deliveryFee,
      'confirm_code': confirmCode,
      'pickup_code': pickupCode,
      'order_notes': orderNotes,
    };
  }

  DoaOrder copyWith({
    String? id,
    String? userId,
    String? restaurantId,
    String? deliveryAgentId,
    OrderStatus? status,
    double? totalAmount,
    PaymentMethod? paymentMethod,
    String? deliveryAddress,
    String? deliveryLatlng,
    double? deliveryLat,
    double? deliveryLon,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? assignedAt,
    DateTime? deliveryTime,
    DateTime? pickupTime,
    double? deliveryFee,
    String? confirmCode,
    String? pickupCode,
    String? orderNotes,
    DoaUser? user,
    DoaRestaurant? restaurant,
    DoaUser? deliveryAgent,
    List<DoaOrderItem>? orderItems,
  }) {
    return DoaOrder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      restaurantId: restaurantId ?? this.restaurantId,
      deliveryAgentId: deliveryAgentId ?? this.deliveryAgentId,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      deliveryLatlng: deliveryLatlng ?? this.deliveryLatlng,
      deliveryLat: deliveryLat ?? this.deliveryLat,
      deliveryLon: deliveryLon ?? this.deliveryLon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignedAt: assignedAt ?? this.assignedAt,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      pickupTime: pickupTime ?? this.pickupTime,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      confirmCode: confirmCode ?? this.confirmCode,
      pickupCode: pickupCode ?? this.pickupCode,
      orderNotes: orderNotes ?? this.orderNotes,
      user: user ?? this.user,
      restaurant: restaurant ?? this.restaurant,
      deliveryAgent: deliveryAgent ?? this.deliveryAgent,
      orderItems: orderItems ?? this.orderItems,
    );
  }
}

enum OrderStatus {
  pending,
  confirmed,
  inPreparation,
  readyForPickup,
  assigned,      // Nuevo status: repartidor asignado
  onTheWay,
  delivered,
  canceled,
  notDelivered;  // Status: no se pudo entregar (cliente no responde, dirección falsa, etc.)

  static OrderStatus fromString(String status) {
    switch (status) {
      case 'pending':
        return OrderStatus.pending;
      case 'confirmed':
        return OrderStatus.confirmed;
      case 'in_preparation':
        return OrderStatus.inPreparation;
      case 'ready_for_pickup':
        return OrderStatus.readyForPickup;
      case 'assigned':
        return OrderStatus.assigned;
      case 'on_the_way':
      case 'en_camino':  // Soporte para valores legacy
        return OrderStatus.onTheWay;
      case 'delivered':
        return OrderStatus.delivered;
      case 'canceled':
        return OrderStatus.canceled;
      case 'not_delivered':
        return OrderStatus.notDelivered;
      default:
        return OrderStatus.pending;
    }
  }

  @override
  String toString() {
    switch (this) {
      case OrderStatus.confirmed:
        return 'confirmed';
      case OrderStatus.inPreparation:
        return 'in_preparation';
      case OrderStatus.readyForPickup:
        return 'ready_for_pickup';
      case OrderStatus.assigned:
        return 'assigned';
      case OrderStatus.onTheWay:
        return 'on_the_way';
      case OrderStatus.delivered:
        return 'delivered';
      case OrderStatus.canceled:
        return 'canceled';
      case OrderStatus.notDelivered:
        return 'not_delivered';
      default:
        return 'pending';
    }
  }
}

extension OrderStatusUI on OrderStatus {
  String get displayName {
    switch (this) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.confirmed:
        return 'Confirmada';
      case OrderStatus.inPreparation:
        return 'En preparación';
      case OrderStatus.readyForPickup:
        return 'Lista para recoger';
      case OrderStatus.assigned:
        return 'Asignada';
      case OrderStatus.onTheWay:
        return 'En camino';
      case OrderStatus.delivered:
        return 'Entregada';
      case OrderStatus.canceled:
        return 'Cancelada';
      case OrderStatus.notDelivered:
        return 'No Entregada';
    }
  }

  Color get color {
    switch (this) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.inPreparation:
        return Colors.purple;
      case OrderStatus.readyForPickup:
        return Colors.cyan;
      case OrderStatus.assigned:
        return Colors.indigo;
      case OrderStatus.onTheWay:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.canceled:
        return Colors.red;
      case OrderStatus.notDelivered:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case OrderStatus.pending:
        return Icons.pending;
      case OrderStatus.confirmed:
        return Icons.check_circle;
      case OrderStatus.inPreparation:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.shopping_bag;
      case OrderStatus.assigned:
        return Icons.person_pin;
      case OrderStatus.onTheWay:
        return Icons.delivery_dining;
      case OrderStatus.delivered:
        return Icons.done_all;
      case OrderStatus.canceled:
        return Icons.cancel;
      case OrderStatus.notDelivered:
        return Icons.cancel;
    }
  }
}

enum PaymentMethod {
  card,
  cash;

  static PaymentMethod fromString(String method) {
    return PaymentMethod.values.firstWhere(
      (m) => m.name == method,
      orElse: () => PaymentMethod.cash,
    );
  }

  @override
  String toString() => name;
}

class DoaOrderItem {
  final String id;
  final String orderId;
  final String productId;
  final int quantity;
  final double priceAtTimeOfOrder;
  final DateTime createdAt;
  final DoaProduct? product;

  DoaOrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.quantity,
    required this.priceAtTimeOfOrder,
    required this.createdAt,
    this.product,
  });

  // Getter de conveniencia para acceder al precio
  double get price => priceAtTimeOfOrder;

  factory DoaOrderItem.fromJson(Map<String, dynamic> json) {
    // print('🔧 [ORDER_ITEM] Parsing order item: ${json['id']}');
    // print('🔧 [ORDER_ITEM] Raw JSON: $json');
    
    try {
      return DoaOrderItem(
        id: json['id'] ?? '',
        orderId: json['order_id'] ?? '',
        productId: json['product_id'] ?? '',
        quantity: json['quantity'] ?? 0,
        priceAtTimeOfOrder: json['price_at_time_of_order'] != null 
          ? (json['price_at_time_of_order'] as num).toDouble() 
          : 0.0,
        createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
        product: json['product'] != null ? DoaProduct.fromJson(json['product']) : null,
      );
    } catch (e) {
      print('❌ [ORDER_ITEM] Error parsing order item: $e');
      print('📍 [ORDER_ITEM] Problematic field values:');
      print('   - id: ${json['id']} (${json['id'].runtimeType})');
      print('   - order_id: ${json['order_id']} (${json['order_id'].runtimeType})');
      print('   - product_id: ${json['product_id']} (${json['product_id'].runtimeType})');
      print('   - quantity: ${json['quantity']} (${json['quantity'].runtimeType})');
      print('   - price_at_time_of_order: ${json['price_at_time_of_order']} (${json['price_at_time_of_order'].runtimeType})');
      print('   - created_at: ${json['created_at']} (${json['created_at'].runtimeType})');
      print('   - product: ${json['product']} (${json['product'].runtimeType})');
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'quantity': quantity,
      'price_at_time_of_order': priceAtTimeOfOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class DoaPayment {
  final String id;
  final String orderId;
  final String? stripePaymentId;
  final double amount;
  final PaymentStatus status;
  final DateTime createdAt;

  DoaPayment({
    required this.id,
    required this.orderId,
    this.stripePaymentId,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  factory DoaPayment.fromJson(Map<String, dynamic> json) {
    return DoaPayment(
      id: json['id'],
      orderId: json['order_id'],
      stripePaymentId: json['stripe_payment_id'],
      amount: (json['amount'] as num).toDouble(),
      status: PaymentStatus.fromString(json['status']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'stripe_payment_id': stripePaymentId,
      'amount': amount,
      'status': status.toString(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

enum PaymentStatus {
  pending,
  succeeded,
  failed;

  static PaymentStatus fromString(String status) {
    return PaymentStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => PaymentStatus.pending,
    );
  }

  @override
  String toString() => name;
}

/// Historial de cambios de estado de órdenes
/// Registra cada cambio de status con timestamp preciso
class OrderStatusUpdate {
  final String id;
  final String orderId;
  final OrderStatus status;
  final String? updatedBy;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const OrderStatusUpdate({
    required this.id,
    required this.orderId,
    required this.status,
    this.updatedBy,
    required this.createdAt,
    this.metadata,
  });

  factory OrderStatusUpdate.fromJson(Map<String, dynamic> json) {
    return OrderStatusUpdate(
      id: json['id']?.toString() ?? '',
      orderId: json['order_id']?.toString() ?? '',
      status: OrderStatus.fromString(json['status']?.toString() ?? 'pending'),
      updatedBy: json['updated_by']?.toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
      metadata: json['metadata'] != null 
          ? Map<String, dynamic>.from(json['metadata']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'status': status.toString(),
      'updated_by': updatedBy,
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }
}

// FINANCIAL SYSTEM MODELS

/// Cuenta financiera para restaurantes y repartidores
class DoaAccount {
  final String id;
  final String userId;
  final AccountType accountType;
  final double balance;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DoaAccount({
    required this.id,
    required this.userId,
    required this.accountType,
    required this.balance,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DoaAccount.fromJson(Map<String, dynamic> json) {
    return DoaAccount(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      accountType: AccountType.fromString(json['account_type']?.toString() ?? 'restaurant'),
      balance: double.tryParse(json['balance']?.toString() ?? '0.0') ?? 0.0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at'].toString()) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'account_type': accountType.toString(),
      'balance': balance,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  DoaAccount copyWith({
    String? id,
    String? userId,
    AccountType? accountType,
    double? balance,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DoaAccount(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      accountType: accountType ?? this.accountType,
      balance: balance ?? this.balance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum AccountType {
  restaurant,
  delivery_agent;

  static AccountType fromString(String type) {
    return AccountType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => AccountType.restaurant,
    );
  }

  @override
  String toString() => name;

  String get displayName {
    switch (this) {
      case AccountType.restaurant:
        return 'Restaurante';
      case AccountType.delivery_agent:
        return 'Repartidor';
    }
  }
}

/// Transacción financiera individual (inmutable)
class DoaAccountTransaction {
  final String id;
  final String accountId;
  final TransactionType type;
  final double amount;
  final String? orderId;
  final String? settlementId;
  final String? description;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const DoaAccountTransaction({
    required this.id,
    required this.accountId,
    required this.type,
    required this.amount,
    this.orderId,
    this.settlementId,
    this.description,
    this.metadata,
    required this.createdAt,
  });

  factory DoaAccountTransaction.fromJson(Map<String, dynamic> json) {
    return DoaAccountTransaction(
      id: json['id']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      type: TransactionType.fromString(json['type']?.toString() ?? 'ORDER_REVENUE'),
      amount: double.tryParse(json['amount']?.toString() ?? '0.0') ?? 0.0,
      orderId: json['order_id']?.toString(),
      settlementId: json['settlement_id']?.toString(),
      description: json['description']?.toString(),
      metadata: json['metadata'] != null 
          ? Map<String, dynamic>.from(json['metadata']) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'].toString()) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'account_id': accountId,
      'type': type.toString(),
      'amount': amount,
      'order_id': orderId,
      'settlement_id': settlementId,
      'description': description,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isCredit => amount > 0;
  bool get isDebit => amount < 0;
}

enum TransactionType {
  ORDER_REVENUE,
  PLATFORM_COMMISSION,
  DELIVERY_EARNING,
  CASH_COLLECTED,
  SETTLEMENT_PAYMENT,
  SETTLEMENT_RECEPTION;

  static TransactionType fromString(String type) {
    return TransactionType.values.firstWhere(
      (t) => t.name == type,
      orElse: () => TransactionType.ORDER_REVENUE,
    );
  }

  @override
  String toString() => name;

  String get displayName {
    switch (this) {
      case TransactionType.ORDER_REVENUE:
        return 'Ingreso por Pedido';
      case TransactionType.PLATFORM_COMMISSION:
        return 'Comisión Plataforma';
      case TransactionType.DELIVERY_EARNING:
        return 'Ganancia Entrega';
      case TransactionType.CASH_COLLECTED:
        return 'Efectivo Recibido';
      case TransactionType.SETTLEMENT_PAYMENT:
        return 'Pago Liquidación';
      case TransactionType.SETTLEMENT_RECEPTION:
        return 'Recepción Liquidación';
    }
  }

  Color get color {
    switch (this) {
      case TransactionType.ORDER_REVENUE:
      case TransactionType.DELIVERY_EARNING:
      case TransactionType.SETTLEMENT_PAYMENT:
        return Colors.green;
      case TransactionType.PLATFORM_COMMISSION:
      case TransactionType.CASH_COLLECTED:
      case TransactionType.SETTLEMENT_RECEPTION:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case TransactionType.ORDER_REVENUE:
        return Icons.restaurant;
      case TransactionType.PLATFORM_COMMISSION:
        return Icons.percent;
      case TransactionType.DELIVERY_EARNING:
        return Icons.delivery_dining;
      case TransactionType.CASH_COLLECTED:
        return Icons.money;
      case TransactionType.SETTLEMENT_PAYMENT:
        return Icons.payment;
      case TransactionType.SETTLEMENT_RECEPTION:
        return Icons.money_off;
    }
  }
}

/// Liquidación de efectivo entre repartidor y restaurante
class DoaSettlement {
  final String id;
  final String payerAccountId;
  final String receiverAccountId;
  final double amount;
  final SettlementStatus status;
  final String confirmationCode;
  final DateTime initiatedAt;
  final DateTime? completedAt;
  final String? completedBy;
  final String? notes;

  // Populated from joins
  final DoaUser? payer;
  final DoaUser? receiver;

  const DoaSettlement({
    required this.id,
    required this.payerAccountId,
    required this.receiverAccountId,
    required this.amount,
    required this.status,
    required this.confirmationCode,
    required this.initiatedAt,
    this.completedAt,
    this.completedBy,
    this.notes,
    this.payer,
    this.receiver,
  });

  factory DoaSettlement.fromJson(Map<String, dynamic> json) {
    return DoaSettlement(
      id: json['id']?.toString() ?? '',
      payerAccountId: json['payer_account_id']?.toString() ?? '',
      receiverAccountId: json['receiver_account_id']?.toString() ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0.0') ?? 0.0,
      status: SettlementStatus.fromString(json['status']?.toString() ?? 'pending'),
      confirmationCode: json['confirmation_code']?.toString() ?? '',
      initiatedAt: json['initiated_at'] != null 
          ? DateTime.parse(json['initiated_at'].toString()) 
          : DateTime.now(),
      completedAt: json['completed_at'] != null 
          ? DateTime.parse(json['completed_at'].toString()) 
          : null,
      completedBy: json['completed_by']?.toString(),
      notes: json['notes']?.toString(),
      payer: json['payer'] != null ? DoaUser.fromJson(json['payer']) : null,
      receiver: json['receiver'] != null ? DoaUser.fromJson(json['receiver']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'payer_account_id': payerAccountId,
      'receiver_account_id': receiverAccountId,
      'amount': amount,
      'status': status.toString(),
      'confirmation_code': confirmationCode,
      'initiated_at': initiatedAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'completed_by': completedBy,
      'notes': notes,
    };
  }

  DoaSettlement copyWith({
    String? id,
    String? payerAccountId,
    String? receiverAccountId,
    double? amount,
    SettlementStatus? status,
    String? confirmationCode,
    DateTime? initiatedAt,
    DateTime? completedAt,
    String? completedBy,
    String? notes,
    DoaUser? payer,
    DoaUser? receiver,
  }) {
    return DoaSettlement(
      id: id ?? this.id,
      payerAccountId: payerAccountId ?? this.payerAccountId,
      receiverAccountId: receiverAccountId ?? this.receiverAccountId,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      confirmationCode: confirmationCode ?? this.confirmationCode,
      initiatedAt: initiatedAt ?? this.initiatedAt,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      notes: notes ?? this.notes,
      payer: payer ?? this.payer,
      receiver: receiver ?? this.receiver,
    );
  }
}

enum SettlementStatus {
  pending,
  completed,
  cancelled;

  static SettlementStatus fromString(String status) {
    return SettlementStatus.values.firstWhere(
      (s) => s.name == status,
      orElse: () => SettlementStatus.pending,
    );
  }

  @override
  String toString() => name;

  String get displayName {
    switch (this) {
      case SettlementStatus.pending:
        return 'Pendiente';
      case SettlementStatus.completed:
        return 'Completada';
      case SettlementStatus.cancelled:
        return 'Cancelada';
    }
  }

  Color get color {
    switch (this) {
      case SettlementStatus.pending:
        return Colors.orange;
      case SettlementStatus.completed:
        return Colors.green;
      case SettlementStatus.cancelled:
        return Colors.red;
    }
  }
}