import 'package:flutter/foundation.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Servicio para integración con MercadoPago vía Edge Functions de Supabase
/// 
/// Este servicio maneja:
/// 1. Creación de preferencias de pago (MercadoPago Checkout Pro)
/// 2. Procesamiento de pagos con tarjeta
/// 3. Consulta de estado de pagos
/// 4. Validación de webhooks
class MercadoPagoService {
  // Public Key de MercadoPago (TEST)
  static const String publicKey = 'TEST-0a2bcd27-5f9b-40c9-ab05-d7bfe539bb1b';
  
  // Nombre de la Edge Function en Supabase
  static const String _edgeFunctionName = 'create-payment';

  /// Crea una preferencia de pago en MercadoPago
  /// 
  /// [orderId] ID de la orden en Supabase (puede estar vacío si se crea tras pago)
  /// [totalAmount] Monto total a cobrar (incluye adeudo si existe)
  /// [clientDebt] Adeudo pendiente del cliente (si existe)
  /// [description] Descripción del pago
  /// [clientEmail] Email del cliente (para notificaciones de MercadoPago)
  /// [orderData] Datos de la orden para crear tras pago exitoso (opcional)
  /// 
  /// Retorna un Map con:
  /// - success: bool
  /// - preferenceId: String (ID de la preferencia creada)
  /// - initPoint: String (URL para redirigir al checkout de MercadoPago)
  /// - error: String (si hubo error)
  static Future<Map<String, dynamic>> createPaymentPreference({
    required String orderId,
    required double totalAmount,
    double? clientDebt,
    required String description,
    required String clientEmail,
    Map<String, dynamic>? orderData,
  }) async {
    try {
      debugPrint('💳 [MP_SERVICE.createPaymentPreference] Creando preferencia...');
      debugPrint('   - orderId: $orderId');
      debugPrint('   - totalAmount: $totalAmount');
      debugPrint('   - clientDebt: $clientDebt');
      debugPrint('   - description: $description');
      debugPrint('   - clientEmail: $clientEmail');
      debugPrint('   - orderData: ${orderData != null ? "Presente" : "No"}');

      final body = {
        'order_id': orderId,
        'amount': totalAmount,
        'client_debt': clientDebt ?? 0.0, // Garantizar que nunca sea null
        'description': description,
        'email': clientEmail,
      };
      
      // Si hay orderData, enviarlo para que el webhook cree la orden
      if (orderData != null) {
        body['order_data'] = orderData;
      }

      final response = await SupabaseConfig.client.functions.invoke(
        _edgeFunctionName,
        body: body,
      );

      debugPrint('📦 [MP_SERVICE.createPaymentPreference] Response status: ${response.status}');
      debugPrint('📦 [MP_SERVICE.createPaymentPreference] Response data: ${response.data}');

      if (response.status != 200) {
        throw Exception('Error ${response.status}: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        debugPrint('✅ [MP_SERVICE.createPaymentPreference] Preferencia creada exitosamente');
        debugPrint('   - preferenceId: ${data['preference_id']}');
        debugPrint('   - initPoint: ${data['init_point']}');
        return {
          'success': true,
          'preference_id': data['preference_id'],
          'init_point': data['init_point'],
          'payment_id': data['payment_id'],
        };
      } else {
        throw Exception(data['error'] ?? 'Error desconocido al crear preferencia');
      }
    } catch (e) {
      debugPrint('❌ [MP_SERVICE.createPaymentPreference] Error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Procesa un pago con tarjeta directamente (vía API de MercadoPago)
  /// 
  /// [orderId] ID de la orden en Supabase
  /// [token] Token de tarjeta generado por MercadoPago SDK
  /// [paymentMethodId] ID del método de pago (ej: "visa", "master")
  /// [amount] Monto total a cobrar
  /// [description] Descripción del pago
  /// [email] Email del pagador
  /// 
  /// Retorna un Map con:
  /// - success: bool
  /// - paymentId: int (ID del pago en MercadoPago)
  /// - status: String (estado del pago: "approved", "rejected", "pending", etc.)
  /// - error: String (si hubo error)
  static Future<Map<String, dynamic>> processCardPayment({
    required String orderId,
    required String token,
    required String paymentMethodId,
    required double amount,
    required String description,
    required String email,
  }) async {
    // NOTA: Esta función está pendiente de implementación
    // Por ahora usamos Checkout Pro (preferencias) en lugar de procesamiento directo
    throw UnimplementedError('Procesamiento directo de tarjeta no implementado. Usa createPaymentPreference.');
  }

  /// Consulta el estado de un pago en MercadoPago
  /// 
  /// [paymentId] ID del pago en MercadoPago
  /// 
  /// Retorna un Map con:
  /// - success: bool
  /// - status: String (estado del pago)
  /// - statusDetail: String (detalle del estado)
  /// - error: String (si hubo error)
  static Future<Map<String, dynamic>> getPaymentStatus(int paymentId) async {
    try {
      debugPrint('💳 [MP_SERVICE.getPaymentStatus] Consultando estado del pago: $paymentId');

      final response = await SupabaseConfig.client.functions.invoke(
        'check-payment-status',
        body: {
          'payment_id': paymentId.toString(),
        },
      );

      debugPrint('📦 [MP_SERVICE.getPaymentStatus] Response status: ${response.status}');
      debugPrint('📦 [MP_SERVICE.getPaymentStatus] Response data: ${response.data}');

      if (response.status != 200) {
        throw Exception('Error ${response.status}: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        debugPrint('✅ [MP_SERVICE.getPaymentStatus] Estado consultado exitosamente');
        debugPrint('   - status: ${data['status']}');
        return {
          'success': true,
          'status': data['status'],
          'status_detail': data['status_detail'],
        };
      } else {
        throw Exception(data['error'] ?? 'Error desconocido al consultar estado');
      }
    } catch (e) {
      debugPrint('❌ [MP_SERVICE.getPaymentStatus] Error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Reintenta un pago fallido
  /// 
  /// [orderId] ID de la orden
  /// [mpPaymentId] ID del pago original en MercadoPago
  /// 
  /// Retorna un Map con:
  /// - success: bool
  /// - newPaymentId: int (nuevo ID del pago)
  /// - status: String (estado del nuevo pago)
  /// - error: String (si hubo error)
  static Future<Map<String, dynamic>> retryPayment({
    required String orderId,
    required int mpPaymentId,
  }) async {
    // NOTA: Esta función está pendiente de implementación
    throw UnimplementedError('Retry payment no implementado aún.');
  }
}
