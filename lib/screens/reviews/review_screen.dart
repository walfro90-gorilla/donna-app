import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/review_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/widgets/star_rating.dart';
import 'package:flutter/material.dart';

class ReviewScreen extends StatefulWidget {
  final String orderId;
  const ReviewScreen({super.key, required this.orderId});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _service = const ReviewService();

  bool _loading = true;
  String? _restaurantId;
  String? _deliveryId;
  String? _clientId;
  late final UserRole _role;

  // Ratings state
  int _rateRestaurant = 0;
  int _rateDelivery = 0;
  int _rateClient = 0;

  final _commentRestaurant = TextEditingController();
  final _commentDelivery = TextEditingController();
  final _commentClient = TextEditingController();

  final Set<String> _tagsRestaurant = {};
  final Set<String> _tagsDelivery = {};
  final Set<String> _tagsClient = {};

  @override
  void initState() {
    super.initState();
    _role = SessionManager.instance.currentSession.role;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final subjects = await _service.getOrderSubjects(widget.orderId);
      _restaurantId = subjects['restaurant_id'];
      _deliveryId = subjects['delivery_agent_id'];
      _clientId = subjects['user_id'];
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando datos: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _commentRestaurant.dispose();
    _commentDelivery.dispose();
    _commentClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _service.sectionsForRole(_role, hasDeliveryAgent: _deliveryId != null);

    return Scaffold(
      appBar: AppBar(title: const Text('Calificar experiencia')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                children: [
                  if (sections.rateRestaurant && _restaurantId != null)
                    _ReviewCard(
                      title: 'Califica al Restaurante',
                      subtitle: '¿Cómo estuvo tu experiencia con el restaurante?',
                      avatarIcon: Icons.store,
                      rating: _rateRestaurant,
                      onRating: (v) => setState(() => _rateRestaurant = v),
                      tags: const [
                        'Comida deliciosa',
                        'Empaque seguro',
                        'Rápido',
                        'Porción pequeña',
                        'Demora en preparar',
                      ],
                      selectedTags: _tagsRestaurant,
                      controller: _commentRestaurant,
                    ),
                  if (sections.rateDelivery && _deliveryId != null) ...[
                    const SizedBox(height: 12),
                    _ReviewCard(
                      title: 'Califica al Repartidor',
                      subtitle: 'Evalúa el servicio de entrega',
                      avatarIcon: Icons.delivery_dining,
                      rating: _rateDelivery,
                      onRating: (v) => setState(() => _rateDelivery = v),
                      tags: const [
                        'Entrega rápida',
                        'Amable',
                        'Siguió instrucciones',
                        'Poco profesional',
                      ],
                      selectedTags: _tagsDelivery,
                      controller: _commentDelivery,
                    ),
                  ],
                  if (sections.rateClient && _clientId != null) ...[
                    const SizedBox(height: 12),
                    _ReviewCard(
                      title: 'Califica al Cliente',
                      subtitle: 'Tu experiencia con el cliente',
                      avatarIcon: Icons.person,
                      rating: _rateClient,
                      onRating: (v) => setState(() => _rateClient = v),
                      tags: const [
                        'Dirección clara',
                        'Respondió rápido',
                        'Amable',
                        'Propina recibida',
                      ],
                      selectedTags: _tagsClient,
                      controller: _commentClient,
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: !_canSubmit(sections) ? null : _submit,
                    child: const Text('Enviar Calificaciones'),
                  ),
                ],
              ),
            ),
    );
  }

  bool _canSubmit(ReviewSections sections) {
    if (sections.rateRestaurant && _restaurantId != null && _rateRestaurant == 0) return false;
    if (sections.rateDelivery && _deliveryId != null && _rateDelivery == 0) return false;
    if (sections.rateClient && _clientId != null && _rateClient == 0) return false;
    return true;
  }

  Future<void> _submit() async {
    final user = SupabaseConfig.auth.currentUser;
    if (user == null) return;

    try {
      final sections = _service.sectionsForRole(_role, hasDeliveryAgent: _deliveryId != null);

      // Build comments with tags
      String _merge(TextEditingController c, Set<String> tags) {
        final tagText = tags.isEmpty ? '' : '[${tags.join(', ')}] ';
        return '$tagText${c.text}'.trim();
      }

      if (sections.rateRestaurant && _restaurantId != null) {
        await _service.submitReview(
          orderId: widget.orderId,
          subjectRestaurantId: _restaurantId,
          rating: _rateRestaurant,
          comment: _merge(_commentRestaurant, _tagsRestaurant),
        );
      }
      if (sections.rateDelivery && _deliveryId != null) {
        await _service.submitReview(
          orderId: widget.orderId,
          subjectUserId: _deliveryId,
          rating: _rateDelivery,
          comment: _merge(_commentDelivery, _tagsDelivery),
        );
      }
      if (sections.rateClient && _clientId != null) {
        await _service.submitReview(
          orderId: widget.orderId,
          subjectUserId: _clientId,
          rating: _rateClient,
          comment: _merge(_commentClient, _tagsClient),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Gracias por calificar!')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
      }
    }
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData avatarIcon;
  final int rating;
  final ValueChanged<int> onRating;
  final List<String> tags;
  final Set<String> selectedTags;
  final TextEditingController controller;

  const _ReviewCard({
    required this.title,
    required this.subtitle,
    required this.avatarIcon,
    required this.rating,
    required this.onRating,
    required this.tags,
    required this.selectedTags,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 18, backgroundColor: color.withValues(alpha: 0.1), child: Icon(avatarIcon, color: color)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StarRating(value: rating, onChanged: onRating),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: -6,
            children: tags.map((t) {
              final selected = selectedTags.contains(t);
              return FilterChip(
                label: Text(t),
                selected: selected,
                onSelected: (v) {
                  if (v) {
                    selectedTags.add(t);
                  } else {
                    selectedTags.remove(t);
                  }
                  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
                  (context as Element).markNeedsBuild();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Comentario (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
