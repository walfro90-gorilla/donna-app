/// Centralized RPC name constants to avoid typos and enable refactors
/// Keep names synchronized with backend functions
class RpcNames {
  // Profiles / Users
  static const String createUserProfilePublic = 'create_user_profile_public';
  static const String ensureUserProfilePublic = 'ensure_user_profile_public';
  static const String ensureUserProfileV2 = 'ensure_user_profile_v2';
  static const String setUserPhoneIfMissing = 'set_user_phone_if_missing';
  static const String updateMyPhoneIfUnique = 'update_my_phone_if_unique';

  // Delivery Agent Registration
  static const String registerDeliveryAgentAtomic = 'register_delivery_agent_atomic';

  // Restaurant Registration
  static const String registerRestaurantAtomic = 'register_restaurant_atomic';

  // Orders
  static const String createOrderSafe = 'create_order_safe';
  static const String insertOrderItemsV2 = 'insert_order_items_v2';
  static const String acceptOrder = 'accept_order';
  static const String markOrderNotDelivered = 'mark_order_not_delivered';

  // Delivery agent profile
  static const String upsertDeliveryAgentProfile = 'upsert_delivery_agent_profile';
  static const String updateMyDeliveryProfile = 'update_my_delivery_profile';

  // Accounts / Finance
  static const String ensureClientProfileAndAccount = 'ensure_client_profile_and_account';
  static const String ensureFinancialAccount = 'ensure_financial_account';
  static const String getClientTotalDebt = 'get_client_total_debt';

  // Health / System
  static const String hasActiveCouriers = 'has_active_couriers';

  // Combos
  // Atomically creates/updates a combo product and its items in one transaction
  static const String upsertComboAtomic = 'upsert_combo_atomic';

  // Legacy or diagnostic helpers
  static const String isEmailVerified = 'is_email_verified';

  // Users location
  static const String updateUserLocation = 'update_user_location';

  // Client profile address (new schema)
  static const String updateClientDefaultAddress = 'update_client_default_address';

  // Restaurants
  static const String findNearbyRestaurants = 'rpc_find_nearby_restaurants';
}
