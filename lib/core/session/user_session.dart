import 'package:doa_repartos/models/doa_models.dart';

/// Modelo de sesión de usuario con datos completos y estado
class UserSession {
  final String userId;
  final String email;
  final UserRole role;
  final DateTime loginTime;
  final Map<String, dynamic> userData;
  
  // Estados específicos por rol
  final DoaRestaurant? restaurant;
  final DoaUser? deliveryAgent;
  final DoaUser? clientData;
  
  const UserSession({
    required this.userId,
    required this.email,
    required this.role,
    required this.loginTime,
    required this.userData,
    this.restaurant,
    this.deliveryAgent,
    this.clientData,
  });

  /// Crea una sesión vacía para logout
  static UserSession empty() => UserSession(
    userId: '',
    email: '',
    role: UserRole.client,
    loginTime: DateTime.now(),
    userData: {},
  );

  /// Verifica si es una sesión válida
  bool get isValid => userId.isNotEmpty && email.isNotEmpty;

  /// Verifica si es una sesión vacía
  bool get isEmpty => userId.isEmpty;

  /// Copia la sesión con nuevos datos
  UserSession copyWith({
    String? userId,
    String? email,
    UserRole? role,
    DateTime? loginTime,
    Map<String, dynamic>? userData,
    DoaRestaurant? restaurant,
    DoaUser? deliveryAgent,
    DoaUser? clientData,
  }) => UserSession(
    userId: userId ?? this.userId,
    email: email ?? this.email,
    role: role ?? this.role,
    loginTime: loginTime ?? this.loginTime,
    userData: userData ?? this.userData,
    restaurant: restaurant ?? this.restaurant,
    deliveryAgent: deliveryAgent ?? this.deliveryAgent,
    clientData: clientData ?? this.clientData,
  );

  /// Convierte a Map para debugging
  Map<String, dynamic> toDebugMap() => {
    'userId': userId,
    'email': email,
    'role': role.name,
    'loginTime': loginTime.toIso8601String(),
    'hasRestaurant': restaurant != null,
    'hasDeliveryAgent': deliveryAgent != null,
    'hasClientData': clientData != null,
  };

  @override
  String toString() => 'UserSession(${role.name}: $email)';
}

/// Estados posibles de una sesión
enum SessionState {
  idle,           // Sin sesión activa
  initializing,   // Inicializando sesión
  active,         // Sesión activa
  switching,      // Cambiando entre usuarios
  terminating,    // Cerrando sesión
  error,          // Error en sesión
}