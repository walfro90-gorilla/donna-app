import 'package:flutter/foundation.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Helper compartido para consultar el modo de cobro global y la suscripción
/// del usuario autenticado. Singleton ligero; no maneja streams ni timers.
class BillingService {
  BillingService._();
  static final BillingService instance = BillingService._();

  BillingModeConfig? _cachedMode;
  DateTime? _cachedModeAt;
  static const _modeCacheTtl = Duration(seconds: 30);

  Future<BillingModeConfig> getMode({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _cachedMode != null && _cachedModeAt != null &&
        now.difference(_cachedModeAt!) < _modeCacheTtl) {
      return _cachedMode!;
    }
    try {
      final res = await SupabaseConfig.client.rpc(RpcNames.getBillingMode);
      _cachedMode = BillingModeConfig.fromJson(Map<String, dynamic>.from(res as Map));
      _cachedModeAt = now;
      return _cachedMode!;
    } catch (e) {
      debugPrint('⚠️ [BILLING] getMode fallback to commission: $e');
      _cachedMode = const BillingModeConfig(
        mode: 'commission',
        subscriptionFeeRestaurant: 999,
        subscriptionFeeDelivery: 999,
        graceDays: 7,
      );
      _cachedModeAt = now;
      return _cachedMode!;
    }
  }

  /// Devuelve null si el usuario no tiene suscripción asociada.
  Future<({DoaSubscription? subscription, DoaSubscriptionInvoice? nextInvoice})>
      getMySubscriptionStatus() async {
    try {
      final res = await SupabaseConfig.client.rpc(RpcNames.getMySubscriptionStatus);
      final map = Map<String, dynamic>.from(res as Map);
      if (map['success'] != true || map['has_subscription'] != true) {
        return (subscription: null, nextInvoice: null);
      }
      final sub = map['subscription'] != null
          ? DoaSubscription.fromJson(Map<String, dynamic>.from(map['subscription'] as Map))
          : null;
      final inv = map['next_invoice'] != null
          ? DoaSubscriptionInvoice.fromJson(Map<String, dynamic>.from(map['next_invoice'] as Map))
          : null;
      return (subscription: sub, nextInvoice: inv);
    } catch (e) {
      debugPrint('⚠️ [BILLING] getMySubscriptionStatus error: $e');
      return (subscription: null, nextInvoice: null);
    }
  }

  /// Conveniencia: `true` si modo=subscription y la cuenta del usuario está suspended.
  Future<bool> isMyAccountSuspended() async {
    final mode = await getMode();
    if (!mode.isSubscription) return false;
    final status = await getMySubscriptionStatus();
    return status.subscription?.status == SubscriptionStatus.suspended;
  }

  void invalidate() {
    _cachedMode = null;
    _cachedModeAt = null;
  }
}
