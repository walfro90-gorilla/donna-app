import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/screens/restaurants/restaurant_detail_screen.dart';

class RestaurantCard extends StatelessWidget {
  final DoaRestaurant restaurant;

  const RestaurantCard({
    super.key,
    required this.restaurant,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          try {
            debugPrint('🏭 [RESTAURANT_CARD] Navegando a detalle del restaurante: ${restaurant.name}');
            debugPrint('🏭 [RESTAURANT_CARD] Restaurant ID: ${restaurant.id}');
            
            // Verificar que el context siga siendo válido
            if (!context.mounted) {
              debugPrint('❌ [RESTAURANT_CARD] Context no válido, cancelando navegación');
              return;
            }
            
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (builderContext) {
                  try {
                    debugPrint('🏗️ [RESTAURANT_CARD] Construyendo RestaurantDetailScreen');
                    return RestaurantDetailScreen(restaurant: restaurant);
                  } catch (e) {
                    debugPrint('❌ [RESTAURANT_CARD] Error construyendo pantalla: $e');
                    
                    // Fallback: pantalla de error
                    return Scaffold(
                      appBar: AppBar(
                        title: const Text('Error'),
                        leading: IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () => Navigator.of(builderContext).pop(),
                        ),
                      ),
                      body: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 64, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('Error cargando restaurante: ${restaurant.name}'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => Navigator.of(builderContext).pop(),
                              child: const Text('Volver'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            );
            
            debugPrint('✅ [RESTAURANT_CARD] Navegación completada exitosamente');
            
          } catch (e) {
            debugPrint('❌ [RESTAURANT_CARD] CRITICAL ERROR en navegación: $e');
            debugPrint('❌ [RESTAURANT_CARD] Stack trace: ${StackTrace.current}');
            
            // Mostrar error al usuario si el contexto sigue válido
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Error abriendo restaurante: ${restaurant.name}'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen del restaurante
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: restaurant.imageUrl != null
                  ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.network(
                        restaurant.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(context),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildPlaceholder(context);
                        },
                      ),
                    )
                  : _buildPlaceholder(context),
            ),
            
            // Contenido
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nombre y rating
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          restaurant.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (restaurant.rating != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 16,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                restaurant.rating!.toStringAsFixed(1),
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Descripción
                  if (restaurant.description != null && restaurant.description!.isNotEmpty)
                    Text(
                      restaurant.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  
                  const SizedBox(height: 12),
                  
                  // Info adicional
                  Row(
                    children: [
                      // Tiempo de entrega
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${restaurant.deliveryTime ?? 30}-${(restaurant.deliveryTime ?? 30) + 15} min',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Costo de envío
                      Icon(
                        Icons.delivery_dining,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        restaurant.deliveryFee != null && restaurant.deliveryFee! > 0
                            ? '\\\$${restaurant.deliveryFee!.toStringAsFixed(0)}'
                            : 'Gratis',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: restaurant.deliveryFee != null && restaurant.deliveryFee! > 0
                              ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                              : Theme.of(context).colorScheme.secondary,
                          fontWeight: restaurant.deliveryFee == null || restaurant.deliveryFee! == 0
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Estado abierto/cerrado
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: restaurant.isOpen
                              ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1)
                              : Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          restaurant.isOpen ? 'Abierto' : 'Cerrado',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: restaurant.isOpen
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.restaurant,
            size: 48,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            restaurant.name,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}