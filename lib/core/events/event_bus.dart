import 'dart:async';
import 'package:doa_repartos/core/session/user_session.dart';

/// Sistema de eventos profesional para comunicación entre servicios
class EventBus {
  static EventBus? _instance;
  static EventBus get instance => _instance ??= EventBus._();
  EventBus._();

  final Map<Type, List<StreamSubscription>> _subscriptions = {};
  final Map<Type, StreamController> _controllers = {};

  /// Publica un evento
  void publish<T extends AppEvent>(T event) {
    print('🔔 [EVENT] Publishing: ${T.toString()}');
    final controller = _getController<T>();
    if (controller.hasListener) {
      controller.add(event);
    } else {
      print('⚠️ [EVENT] No listeners for ${T.toString()}');
    }
  }

  /// Se suscribe a eventos de un tipo específico
  StreamSubscription<T> subscribe<T extends AppEvent>(
    void Function(T event) onEvent, {
    String? tag,
  }) {
    print('📻 [EVENT] Subscribing to: ${T.toString()} ${tag != null ? '($tag)' : ''}');
    final controller = _getController<T>();
    final subscription = controller.stream.cast<T>().listen(onEvent);
    
    _subscriptions.putIfAbsent(T, () => []).add(subscription);
    return subscription;
  }

  /// Cancela todas las suscripciones de un tipo
  void unsubscribeAll<T extends AppEvent>() {
    print('🔇 [EVENT] Unsubscribing all: ${T.toString()}');
    final subscriptions = _subscriptions[T];
    if (subscriptions != null) {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
      subscriptions.clear();
    }
  }

  /// Emite un evento (alias para publish)
  void emit<T extends AppEvent>(T event) {
    publish(event);
  }

  /// Escucha eventos de un tipo específico
  Stream<T> on<T extends AppEvent>() {
    final controller = _getController<T>();
    return controller.stream.cast<T>();
  }

  /// Limpia todos los eventos y suscripciones
  void clear() {
    print('🧹 [EVENT] Clearing all events and subscriptions');
    for (final subscriptions in _subscriptions.values) {
      for (final subscription in subscriptions) {
        subscription.cancel();
      }
    }
    _subscriptions.clear();
    
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }

  StreamController<T> _getController<T extends AppEvent>() {
    return _controllers.putIfAbsent(
      T,
      () => StreamController<T>.broadcast(),
    ) as StreamController<T>;
  }
}

/// Clase base para todos los eventos de la app
abstract class AppEvent {
  final DateTime timestamp;
  final String? userId;
  
  const AppEvent({
    required this.timestamp,
    this.userId,
  });
  
  // Factory removido - se debe crear instancias específicas de eventos
}

// Clase _DefaultEvent removida - no era necesaria

// ===== EVENTOS DE SESIÓN =====
class SessionStartedEvent extends AppEvent {
  final UserSession session;
  
  SessionStartedEvent({
    required this.session,
    required DateTime timestamp,
  }) : super(timestamp: timestamp, userId: session.userId);
}

class SessionEndedEvent extends AppEvent {
  final String reason;
  
  const SessionEndedEvent({
    required this.reason,
    required DateTime timestamp,
    String? userId,
  }) : super(timestamp: timestamp, userId: userId);
}

class SessionSwitchedEvent extends AppEvent {
  final UserSession oldSession;
  final UserSession newSession;
  
  SessionSwitchedEvent({
    required this.oldSession,
    required this.newSession,
    required DateTime timestamp,
  }) : super(timestamp: timestamp, userId: newSession.userId);
}

class SessionChangedEvent extends AppEvent {
  final UserSession? newSession;
  final UserSession? previousSession;
  
  SessionChangedEvent({
    this.newSession,
    this.previousSession,
  }) : super(
    timestamp: DateTime.now(), 
    userId: newSession?.userId ?? previousSession?.userId,
  );
}

// ===== EVENTOS DE DATOS =====
class DataUpdatedEvent extends AppEvent {
  final String dataType;
  final Map<String, dynamic> data;
  
  const DataUpdatedEvent({
    required this.dataType,
    required this.data,
    required DateTime timestamp,
    String? userId,
  }) : super(timestamp: timestamp, userId: userId);
}

class ErrorEvent extends AppEvent {
  final String error;
  final String context;
  final dynamic details;
  
  const ErrorEvent({
    required this.error,
    required this.context,
    this.details,
    required DateTime timestamp,
    String? userId,
  }) : super(timestamp: timestamp, userId: userId);
}