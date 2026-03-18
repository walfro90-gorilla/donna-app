import 'package:doa_repartos/supabase/supabase_config.dart';

/// 📦 Helper utilities for order status tracking
/// Funciones estáticas para actualizar status con tracking automático
class OrderStatusHelper {

  /// 🔄 Actualizar status de orden con tracking automático
  /// Este método registra el cambio tanto en orders como en order_status_updates
  static Future<bool> updateOrderStatus(
    String orderId,
    String newStatus,
    [String? updatedBy]
  ) async {
    try {
      print('🔄 [ORDER_STATUS_HELPER] Updating order $orderId to $newStatus');

      // PASO 1: Actualizar directamente la tabla orders
      // confirm_code NO se toca — se genera una sola vez al crear la orden
      final orderUpdateData = <String, dynamic>{
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Si el status es delivered, establecer delivery_time
      if (newStatus.toLowerCase() == 'delivered' || newStatus.toLowerCase() == 'entregado') {
        orderUpdateData['delivery_time'] = DateTime.now().toIso8601String();
      }

      await SupabaseConfig.client
          .from('orders')
          .update(orderUpdateData)
          .eq('id', orderId);

      print('✅ [ORDER_STATUS_HELPER] Order status updated in orders table');

      // PASO 2: Insertar tracking en order_status_updates
      try {
        await SupabaseConfig.client
            .from('order_status_updates')
            .insert({
              'order_id': orderId,
              'status': newStatus,
              'updated_by_user_id': updatedBy,
              'created_at': DateTime.now().toIso8601String(),
            });
        print('✅ [ORDER_STATUS_HELPER] Status tracking inserted');
      } catch (trackingError) {
        print('⚠️ [ORDER_STATUS_HELPER] Warning: Could not insert tracking: $trackingError');
      }

      print('✅ [ORDER_STATUS_HELPER] Order status updated successfully');
      return true;

    } catch (e) {
      print('❌ [ORDER_STATUS_HELPER] Error updating order status: $e');
      return false;
    }
  }
  
  /// 📊 Obtener histórico de cambios de estado para una orden
  static Future<List<Map<String, dynamic>>> getOrderStatusHistory(String orderId) async {
    try {
      final response = await SupabaseConfig.client
          .from('order_status_updates')
          .select('*')
          .eq('order_id', orderId)
          .order('created_at', ascending: true);
      
      return List<Map<String, dynamic>>.from(response ?? []);
      
    } catch (e) {
      print('❌ [ORDER_STATUS_HELPER] Error getting status history: $e');
      return [];
    }
  }
  
  /// 🕐 Obtener timestamp del último cambio de status
  static Future<DateTime?> getLastStatusUpdateTime(String orderId, String status) async {
    try {
      final response = await SupabaseConfig.client
          .from('order_status_updates')
          .select('created_at')
          .eq('order_id', orderId)
          .eq('status', status)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response != null && response['created_at'] != null) {
        return DateTime.parse(response['created_at']);
      }
      return null;
      
    } catch (e) {
      print('❌ [ORDER_STATUS_HELPER] Error getting last status update time: $e');
      return null;
    }
  }
  
  /// ✅ Validar código de confirmación
  static Future<bool> validateConfirmCode(String orderId, String inputCode) async {
    try {
      print('🔍 [ORDER_STATUS_HELPER] Validating confirm code for order $orderId');
      
      final response = await SupabaseConfig.client
          .from('orders')
          .select('confirm_code')
          .eq('id', orderId)
          .single();
      
      final storedCode = response['confirm_code']?.toString();
      final isValid = storedCode != null && storedCode == inputCode;
      
      print(isValid ? 
        '✅ [ORDER_STATUS_HELPER] Confirm code validation successful' : 
        '❌ [ORDER_STATUS_HELPER] Confirm code validation failed');
      
      return isValid;
      
    } catch (e) {
      print('❌ [ORDER_STATUS_HELPER] Error validating confirm code: $e');
      return false;
    }
  }
}