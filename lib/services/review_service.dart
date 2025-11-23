import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:flutter/foundation.dart';

class ReviewService {
  const ReviewService();

  Future<Map<String, String?>> getOrderSubjects(String orderId) async {
    try {
      final data = await SupabaseConfig.client
          .from('orders')
          .select('id, user_id, restaurant_id, delivery_agent_id')
          .eq('id', orderId)
          .maybeSingle();
      if (data == null) return {};
      return {
        'user_id': data['user_id']?.toString(),
        'restaurant_id': data['restaurant_id']?.toString(),
        'delivery_agent_id': data['delivery_agent_id']?.toString(),
      };
    } catch (e) {
      debugPrint('❌ [ReviewService] getOrderSubjects error: $e');
      rethrow;
    }
  }

  Future<bool> hasAnyReviewByAuthorForOrder({required String orderId, required String authorId}) async {
    try {
      final res = await SupabaseConfig.client
          .from('reviews')
          .select('id')
          .eq('order_id', orderId)
          .eq('author_id', authorId)
          .limit(1)
          .maybeSingle();
      return res != null;
    } catch (e) {
      debugPrint('❌ [ReviewService] hasAnyReviewByAuthorForOrder error: $e');
      return false;
    }
  }

  Future<void> submitReview({
    required String orderId,
    String? subjectUserId,
    String? subjectRestaurantId,
    required int rating,
    String? comment,
  }) async {
    assert((subjectUserId == null) ^ (subjectRestaurantId == null), 'Provide either subjectUserId or subjectRestaurantId');

    try {
      await SupabaseConfig.client.rpc('submit_review', params: {
        'p_order_id': orderId,
        'p_subject_user_id': subjectUserId,
        'p_subject_restaurant_id': subjectRestaurantId,
        'p_rating': rating,
        'p_comment': comment ?? '',
      });
    } catch (e) {
      debugPrint('❌ [ReviewService] submitReview error: $e');
      rethrow;
    }
  }

  /// Helper to know what sections should be visible for a role
  ReviewSections sectionsForRole(UserRole role, {required bool hasDeliveryAgent}) {
    switch (role) {
      case UserRole.client:
        return ReviewSections(rateRestaurant: true, rateDelivery: hasDeliveryAgent);
      case UserRole.delivery_agent:
        return ReviewSections(rateRestaurant: true, rateClient: true);
      case UserRole.restaurant:
        return ReviewSections(rateDelivery: true);
      case UserRole.admin:
        return const ReviewSections();
    }
  }
}

class ReviewSections {
  final bool rateRestaurant;
  final bool rateDelivery;
  final bool rateClient;
  const ReviewSections({this.rateRestaurant = false, this.rateDelivery = false, this.rateClient = false});

  bool get hasAny => rateRestaurant || rateDelivery || rateClient;
}
