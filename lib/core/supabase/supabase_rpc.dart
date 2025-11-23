import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Standardized RPC response used in the app
class RpcResponse<T> {
  final bool success;
  final T? data;
  final String? error;

  const RpcResponse({required this.success, this.data, this.error});

  Map<String, dynamic> toJson() => {
        'success': success,
        'data': data,
        'error': error,
      };

  @override
  String toString() => 'RpcResponse(success: $success, data: $data, error: $error)';
}

/// Thin wrapper around Supabase.rpc that standardizes return shape and errors.
/// - Normalizes function-not-found cases.
/// - Optionally coerces common backend payloads into {success, data, error}.
class SupabaseRpc {
  /// Calls an RPC and returns RpcResponse.
  /// Any thrown PostgrestException is caught and converted to RpcResponse.error.
  static Future<RpcResponse<dynamic>> call(
    String functionName, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final result = await SupabaseConfig.client
          .rpc(functionName, params: params ?? const {})
          .timeout(timeout);

      // Attempt to normalize various backend result shapes
      if (result is Map<String, dynamic>) {
        if (result.containsKey('success') || result.containsKey('error')) {
          final bool ok = (result['success'] == true) && result['error'] == null;
          return RpcResponse(success: ok, data: result['data'] ?? result, error: result['error']?.toString());
        }
        return RpcResponse(success: true, data: result);
      }

      // Booleans often used for simple health checks
      if (result is bool) {
        return RpcResponse(success: true, data: result);
      }

      // For scalar values (uuid, text, number)
      if (result != null) {
        return RpcResponse(success: true, data: result);
      }

      return RpcResponse(success: true, data: null);
    } on PostgrestException catch (e) {
      // Normalize function-not-found and schema cache cases for graceful fallback
      final message = e.message;
      final code = e.code ?? '';
      final fnMiss = code == 'PGRST202' || code == '42883' || message.contains('Could not find the function') || message.contains('schema cache');
      final normalizedMessage = fnMiss ? 'FUNCTION_NOT_FOUND: ${e.message}' : e.message;
      debugPrint('❌ [RPC] $functionName error: ${e.code} ${e.message}');
      return RpcResponse(success: false, error: normalizedMessage);
    } catch (e) {
      debugPrint('❌ [RPC] $functionName unexpected error: $e');
      return RpcResponse(success: false, error: e.toString());
    }
  }
}
