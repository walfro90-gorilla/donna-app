import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Card que muestra el progreso de completado del perfil del restaurante
/// Ahora es desplegable: muestra encabezado + barra de progreso y al tocar
/// despliega checklist, bloque de estado y botón de acción.
class ProfileCompletionCard extends StatefulWidget {
  final DoaRestaurant restaurant;
  final VoidCallback? onTapComplete;
  final Function(ProfileSection)? onSectionTap;
  final int? percentageOverride; // Permite usar porcentaje calculado sin incluir foto de menú
  // Permite indicar explícitamente si el requisito de productos mínimos está completo (>=3)
  final bool? productsCompleteOverride;
  final bool initiallyExpanded;

  const ProfileCompletionCard({
    super.key,
    required this.restaurant,
    this.onTapComplete,
    this.onSectionTap,
    this.percentageOverride,
    this.productsCompleteOverride,
    this.initiallyExpanded = false,
  });

  @override
  State<ProfileCompletionCard> createState() => _ProfileCompletionCardState();
}

class _ProfileCompletionCardState extends State<ProfileCompletionCard> with SingleTickerProviderStateMixin {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final percentage = widget.percentageOverride ?? widget.restaurant.profileCompletionPercentage;
    final isComplete = percentage >= 100;
    final isPending = widget.restaurant.status == RestaurantStatus.pending;
    final isApproved = widget.restaurant.status == RestaurantStatus.approved;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isComplete ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
              isComplete ? Colors.green.withValues(alpha: 0.05) : Colors.orange.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header clickable
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
                    child: Icon(
                      isComplete ? Icons.check_circle : Icons.edit_note,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isComplete ? '¡Perfil Completo!' : 'Completa tu Perfil',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isComplete ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$percentage% completado',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _expanded ? 0.5 : 0.0,
                    child: Icon(
                      Icons.expand_more,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Barra de progreso (siempre visible)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: percentage / 100,
                minHeight: 12,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? Colors.green : Colors.orange,
                ),
              ),
            ),

            // Contenido expandible
            AnimatedCrossFade(
              firstChild: const SizedBox(height: 0),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Checklist (solo lectura)
                  _buildChecklistSection(
                    context,
                    'Información del Restaurante',
                    Icons.info_outline,
                    [
                      ChecklistItem(
                        label: 'Nombre del restaurante',
                        subtitle: 'Nombre comercial único',
                        isComplete: widget.restaurant.name.isNotEmpty,
                        icon: Icons.store,
                        onTap: () => widget.onSectionTap?.call(ProfileSection.basicInfo),
                      ),
                      ChecklistItem(
                        label: 'Descripción',
                        subtitle: 'Cuéntanos sobre tu restaurante',
                        isComplete: widget.restaurant.description != null && widget.restaurant.description!.isNotEmpty,
                        icon: Icons.description,
                        onTap: () => widget.onSectionTap?.call(ProfileSection.basicInfo),
                      ),
                      ChecklistItem(
                        label: 'Tipo de cocina',
                        subtitle: 'Ej: Italiana, Mexicana, etc.',
                        isComplete: widget.restaurant.cuisineType != null,
                        icon: Icons.local_dining,
                        onTap: () => widget.onSectionTap?.call(ProfileSection.basicInfo),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _buildChecklistSection(
                    context,
                    'Imágenes y Visual',
                    Icons.image_outlined,
                    [
                      ChecklistItem(
                        label: 'Logo del restaurante',
                        subtitle: 'Imagen cuadrada (recomendado 512x512)',
                        isComplete: widget.restaurant.logoUrl != null,
                        icon: Icons.image,
                        onTap: () => widget.onSectionTap?.call(ProfileSection.logo),
                      ),
                      ChecklistItem(
                        label: 'Foto de portada',
                        subtitle: 'Imagen horizontal (recomendado 1920x1080)',
                        isComplete: widget.restaurant.coverImageUrl != null,
                        icon: Icons.photo_camera,
                        onTap: () => widget.onSectionTap?.call(ProfileSection.cover),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  _buildChecklistSection(
                    context,
                    'Productos y Menú',
                    Icons.restaurant_menu_outlined,
                    [
                      ChecklistItem(
                        label: 'Agregar productos',
                        subtitle: 'Mínimo 3 productos para empezar a vender',
                        isComplete: widget.productsCompleteOverride ?? false,
                        icon: Icons.restaurant_menu,
                        onTap: () => widget.onSectionTap?.call(ProfileSection.products),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Estado del restaurante
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.restaurant.status.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.restaurant.status.color.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(widget.restaurant.status.icon, color: widget.restaurant.status.color, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estado: ${widget.restaurant.status.displayName}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: widget.restaurant.status.color,
                                ),
                              ),
                              if (isPending) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Tu restaurante está siendo revisado por el equipo',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ] else if (isApproved) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  '¡Puedes ponerte ONLINE y recibir pedidos!',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (!isComplete && widget.onTapComplete != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onTapComplete,
                        icon: const Icon(Icons.edit),
                        label: const Text('Completar Perfil'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para construir una sección del checklist con múltiples items
  Widget _buildChecklistSection(
    BuildContext context,
    String sectionTitle,
    IconData sectionIcon,
    List<ChecklistItem> items,
  ) {
    final completedCount = items.where((item) => item.isComplete).length;
    final totalCount = items.where((item) => !item.isOptional).length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(sectionIcon, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              sectionTitle,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: completedCount == totalCount 
                    ? Colors.green.withValues(alpha: 0.15) 
                    : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$completedCount/$totalCount',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: completedCount == totalCount ? Colors.green.shade700 : Colors.orange.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Section items
        ...items.map((item) => _buildChecklistItem(context, item)),
      ],
    );
  }
  
  Widget _buildChecklistItem(
    BuildContext context,
    ChecklistItem item,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: item.isComplete 
                  ? Colors.green.withValues(alpha: 0.4) 
                  : Colors.grey.withValues(alpha: 0.25),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(10),
            color: item.isComplete 
                ? Colors.green.withValues(alpha: 0.08) 
                : Colors.white,
            boxShadow: item.isComplete
                ? [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              // Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: item.isComplete 
                      ? Colors.green.withValues(alpha: 0.2) 
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  color: item.isComplete ? Colors.green.shade700 : Colors.orange.shade700,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: item.isComplete ? Colors.green.shade800 : Colors.black87,
                            ),
                          ),
                        ),
                        if (item.isOptional)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Opcional',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status circle: checked or empty circle
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Container(
                  key: ValueKey(item.isComplete),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.isComplete ? Colors.green : Colors.transparent,
                    border: item.isComplete
                        ? null
                        : Border.all(color: Colors.grey.shade400, width: 2),
                  ),
                  child: item.isComplete
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper method para calcular porcentaje manualmente (fallback si el backend no lo calcula)
extension RestaurantCompletion on DoaRestaurant {
  int calculateCompletionPercentage() {
    int score = 0;
    // Ajustado: eliminar "foto del menú" del cálculo
    const totalFields = 9;

    // Obligatorio: nombre
    if (name.isNotEmpty) score++;
    
    // Obligatorio: descripción
    if (description != null && description!.isNotEmpty) score++;
    
    // Crítico: logo
    if (logoUrl != null) score++;
    
    // Recomendado: cover image
    if (coverImageUrl != null) score++;
    
    // Eliminado: menu image (no afecta el porcentaje)
    
    // Recomendado: tipo de cocina
    if (cuisineType != null) score++;
    
    // Recomendado: horarios
    if (businessHours != null) score++;
    
    // Recomendado: radio de entrega
    if (deliveryRadiusKm != null) score++;
    
    // Recomendado: tiempo estimado
    if (estimatedDeliveryTimeMinutes != null) score++;
    
    // Crítico: al menos 1 producto (esto se debe validar externamente)
    score++; // Asumimos que hay productos por ahora
    
    return (score * 100) ~/ totalFields;
  }

  bool get canGoOnline {
    return status == RestaurantStatus.approved && 
           profileCompletionPercentage >= 70;
  }

  String get onlineBlockedReason {
    if (status != RestaurantStatus.approved) {
      return 'Tu restaurante debe ser aprobado por el administrador';
    }
    if (profileCompletionPercentage < 70) {
      return 'Completa tu perfil al menos un 70% para poder vender';
    }
    return '';
  }
}

/// Enum para identificar las secciones del perfil
enum ProfileSection {
  basicInfo,
  logo,
  cover,
  products,
}

/// Modelo para items del checklist
class ChecklistItem {
  final String label;
  final String subtitle;
  final bool isComplete;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isOptional;

  const ChecklistItem({
    required this.label,
    required this.subtitle,
    required this.isComplete,
    required this.icon,
    this.onTap,
    this.isOptional = false,
  });
}
