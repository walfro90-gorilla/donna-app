import 'package:flutter/material.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';

/// Card de bienvenida y onboarding con diseño atractivo
class WelcomeOnboardingCard extends StatelessWidget {
  final WelcomeMessage welcomeMessage;
  final OnboardingStatus onboardingStatus;
  final VoidCallback? onActionPressed;
  final VoidCallback? onDismiss;

  const WelcomeOnboardingCard({
    super.key,
    required this.welcomeMessage,
    required this.onboardingStatus,
    this.onActionPressed,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            welcomeMessage.color.withValues(alpha: 0.1),
            welcomeMessage.color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: welcomeMessage.color.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: welcomeMessage.color.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header con mensaje de bienvenida
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: welcomeMessage.color.withValues(alpha: 0.15),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: welcomeMessage.color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    welcomeMessage.icon,
                    color: welcomeMessage.color,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        welcomeMessage.title,
                        style: TextStyle(
                          fontSize: isDesktop ? 20 : 18,
                          fontWeight: FontWeight.bold,
                          color: welcomeMessage.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        welcomeMessage.message,
                        style: TextStyle(
                          fontSize: isDesktop ? 14 : 13,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    onPressed: onDismiss,
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          
          // Barra de progreso
          if (!onboardingStatus.isComplete) ...[
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progreso del Perfil',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      Text(
                        '${onboardingStatus.completedRequired}/${onboardingStatus.totalRequired} completadas',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: welcomeMessage.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Barra de progreso visual
                  Stack(
                    children: [
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: onboardingStatus.percentage / 100,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                welcomeMessage.color,
                                welcomeMessage.color.withValues(alpha: 0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: welcomeMessage.color.withValues(alpha: 0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Porcentaje con mensaje motivacional
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${onboardingStatus.percentage}% completado',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: welcomeMessage.color,
                        ),
                      ),
                      if (onboardingStatus.percentage < onboardingStatus.minPercentageToActivate)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: Text(
                            'Falta ${onboardingStatus.minPercentageToActivate - onboardingStatus.percentage}% para activar',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Checklist de tareas (primeras 3 requeridas, mostrando completadas en verde y pendientes en rojo)
            ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚡ Tareas Prioritarias',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 12),
                    
                    // Ordenamos: pendientes primero por prioridad, luego completadas
                    ...(() {
                      final requiredTasks = onboardingStatus.tasks
                          .where((t) => !t.isOptional)
                          .toList();
                      requiredTasks.sort((a, b) {
                        if (a.isCompleted != b.isCompleted) {
                          return a.isCompleted ? 1 : -1; // pendientes primero
                        }
                        return a.priority.compareTo(b.priority);
                      });
                      final visible = requiredTasks.take(3).toList();
                      return visible.map((task) {
                        final completed = task.isCompleted;
                        final borderColor = completed
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.red.withValues(alpha: 0.3);
                        final bgColor = completed
                            ? Colors.green.withValues(alpha: 0.05)
                            : Colors.red.withValues(alpha: 0.03);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                completed ? Icons.check_circle : Icons.radio_button_unchecked,
                                color: completed ? Colors.green : Colors.red,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: completed ? Colors.green : Colors.red,
                                        decoration: completed ? TextDecoration.lineThrough : TextDecoration.none,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      task.description,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: (completed ? Colors.green : Colors.red).withValues(alpha: 0.8),
                                        decoration: completed ? TextDecoration.lineThrough : TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        );
                      });
                    })(),
                    
                    // Contador de tareas restantes para mostrar transparencia
                    Builder(builder: (_) {
                      final totalRequired = onboardingStatus.totalRequired;
                      final completedRequired = onboardingStatus.completedRequired;
                      final remaining = totalRequired - completedRequired;
                      if (totalRequired > 3 || remaining > 3) {
                        final hidden = (totalRequired - 3).clamp(0, totalRequired);
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '+ $hidden tareas más',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ],
          ],
          
          // Botón de acción
          if (onActionPressed != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onActionPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: welcomeMessage.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        onboardingStatus.isComplete 
                            ? Icons.rocket_launch 
                            : Icons.edit_note,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        welcomeMessage.actionLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
