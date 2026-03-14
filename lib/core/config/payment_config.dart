import 'package:doa_repartos/models/doa_models.dart';

/// Central payment feature flags.
///
/// To enable a method: uncomment it in [enabledMethods] and hot-restart.
/// No backend change is required for enabling cash or card.
/// SPEI/CoDi additionally requires running:
///   sql_migrations/2026-03-13_ADD_spei_codi_payment_method.sql
class PaymentConfig {
  PaymentConfig._();

  /// Methods shown and selectable in checkout.
  /// Order determines display order in the UI.
  static const List<PaymentMethod> enabledMethods = [
    PaymentMethod.cash,
    // PaymentMethod.card,      // MercadoPago — activar cuando esté listo
    // PaymentMethod.spei_codi, // SPEI/CoDi   — activar cuando esté listo
  ];

  static bool isEnabled(PaymentMethod method) =>
      enabledMethods.contains(method);
}
