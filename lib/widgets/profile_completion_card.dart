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

    // ESTADO COMPLETO: Barra delgada estilo "Banner"
    if (isComplete) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1B5E20).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Perfil 100% completado',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.stars, color: Colors.white.withValues(alpha: 0.5), size: 18),
          ],
        ),
      );
    }

    // ESTADO PENDIENTE: Card Premium con Stepper (Diseño anterior)
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2B2624), // Fondo oscuro café profundo
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Lado Izquierdo: Progreso Circular
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 85,
                          height: 85,
                          child: CircularProgressIndicator(
                            value: percentage / 100,
                            strokeWidth: 8,
                            backgroundColor: const Color(0xFF423B38),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFA000)),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Text(
                          '$percentage%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  
                  // Lado Derecho: Título y Lista Corta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Completa tu Perfil',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Items de Checklist
                        _buildCompactStep(
                          'Información básica',
                          widget.restaurant.name.isNotEmpty && 
                          widget.restaurant.description != null && 
                          widget.restaurant.cuisineType != null,
                          showLine: true,
                        ),
                        _buildCompactStep(
                          'Imágenes del local',
                          widget.restaurant.logoUrl != null && 
                          widget.restaurant.coverImageUrl != null,
                          showLine: true,
                        ),
                        _buildCompactStep(
                          'Menú y Productos',
                          widget.productsCompleteOverride ?? false,
                          showLine: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Contenido Expandible (Checklist Detallado)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  children: [
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFF423B38), height: 1),
                    const SizedBox(height: 20),
                    _buildDetailedChecklist(),
                    const SizedBox(height: 20),
                    
                    // Estado y Botón
                    _buildStatusFooter(),
                    
                    if (!isComplete && widget.onTapComplete != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: widget.onTapComplete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFA000),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'COMPLETAR PERFIL AHORA',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Construye un paso compacto al estilo de la imagen
  Widget _buildCompactStep(String label, bool isDone, {bool showLine = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF5D4E44),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDone ? const Color(0xFFFFA000) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.check,
                size: 12,
                color: isDone ? const Color(0xFFFFA000) : Colors.white38,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isDone ? Colors.white.withValues(alpha: 0.9) : Colors.white54,
                  fontSize: 14,
                  fontWeight: isDone ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        if (showLine)
          Padding(
            padding: const EdgeInsets.only(left: 8.5),
            child: Container(
              width: 1,
              height: 10,
              color: const Color(0xFF5D4E44),
            ),
          ),
      ],
    );
  }

  /// Checklist detallado original adaptado al nuevo diseño
  Widget _buildDetailedChecklist() {
    return Column(
      children: [
        _buildChecklistSection(
          context,
          'Detalles del Negocio',
          Icons.store_outlined,
          [
            ChecklistItem(
              label: 'Nombre y Descripción',
              subtitle: 'Identidad de tu marca',
              isComplete: widget.restaurant.name.isNotEmpty && widget.restaurant.description != null,
              icon: Icons.edit,
              onTap: () => widget.onSectionTap?.call(ProfileSection.basicInfo),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildChecklistSection(
          context,
          'Visuales',
          Icons.image_outlined,
          [
            ChecklistItem(
              label: 'Logo y Portada',
              subtitle: 'Fotos de alta calidad',
              isComplete: widget.restaurant.logoUrl != null && widget.restaurant.coverImageUrl != null,
              icon: Icons.camera_alt,
              onTap: () => widget.onSectionTap?.call(ProfileSection.logo),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildChecklistSection(
          context,
          'Menú',
          Icons.restaurant_menu_outlined,
          [
            ChecklistItem(
              label: 'Catálogo de Productos',
              subtitle: 'Mínimo 3 ítems activos',
              isComplete: widget.productsCompleteOverride ?? false,
              icon: Icons.list_alt,
              onTap: () => widget.onSectionTap?.call(ProfileSection.products),
            ),
          ],
        ),
      ],
    );
  }

  /// Footer con estado de la cuenta
  Widget _buildStatusFooter() {
    final status = widget.restaurant.status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(status.icon, color: status.color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Estado: ${status.displayName}',
                  style: TextStyle(color: status.color, fontWeight: FontWeight.bold),
                ),
                Text(
                  status == RestaurantStatus.approved 
                    ? '¡Tu cuenta está lista para vender!' 
                    : 'Estamos validando tus datos...',
                  style: TextStyle(color: status.color.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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
