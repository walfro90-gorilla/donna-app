import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';

/// Card that shows delivery agent onboarding progress with checklist
class DeliveryProfileProgressCard extends StatefulWidget {
  final DoaUser deliveryAgent;
  final VoidCallback? onCompleteTap;
  final VoidCallback? onUploadDocsTap;
  final bool initiallyExpanded;

  const DeliveryProfileProgressCard({
    super.key,
    required this.deliveryAgent,
    this.onCompleteTap,
    this.onUploadDocsTap,
    this.initiallyExpanded = true,
  });

  @override
  State<DeliveryProfileProgressCard> createState() => _DeliveryProfileProgressCardState();
}

class _DeliveryProfileProgressCardState extends State<DeliveryProfileProgressCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final status = OnboardingNotificationService.calculateDeliveryOnboarding(widget.deliveryAgent);
    final isComplete = status.isComplete;
    final percentage = status.percentage;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              (isComplete ? Colors.green : Colors.orange).withValues(alpha: 0.08),
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isComplete ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(isComplete ? Icons.verified : Icons.assignment, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isComplete ? '¡Perfil listo para entregar!' : 'Completa tu perfil para empezar',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isComplete ? Colors.green.shade700 : Colors.orange.shade700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text('$percentage% completado', style: TextStyle(color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _expanded ? 0.5 : 0,
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(isComplete ? Colors.green : Colors.orange),
              ),
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(height: 0),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  ...status.tasks.map((t) => _TaskRow(
                        title: t.title,
                        description: t.description,
                        icon: t.icon,
                        isCompleted: t.isCompleted,
                        optional: t.isOptional,
                      )),
                  const SizedBox(height: 12),
                  if (!isComplete) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onUploadDocsTap ?? widget.onCompleteTap,
                        icon: const Icon(Icons.upload, color: Colors.white),
                        label: const Text('Completar y subir documentos', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isCompleted;
  final bool optional;
  const _TaskRow({
    required this.title,
    required this.description,
    required this.icon,
    required this.isCompleted,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isCompleted ? Colors.green : Colors.orange).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: isCompleted ? Colors.green : Colors.orange, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isCompleted ? Colors.green.shade800 : Colors.black87,
                            ),
                      ),
                    ),
                    if (optional)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text('Opcional', style: TextStyle(fontSize: 10, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? Colors.green : Colors.transparent,
              border: isCompleted ? null : Border.all(color: Colors.grey.shade400, width: 2),
            ),
            child: isCompleted ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
          ),
        ],
      ),
    );
  }
}
