import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/widgets/restaurant_card.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  List<DoaRestaurant> _allRestaurants = [];
  List<DoaRestaurant> _filteredRestaurants = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'Todos';
  StreamSubscription<void>? _restaurantsUpdatesSubscription;
  StreamSubscription<void>? _couriersUpdatesSubscription;
  bool _hasActiveCouriers = true;

  final List<String> _filters = [
    'Todos',
    'Abiertos',
    'Mejor valorados',
    'Más rápidos',
    'Envío gratis',
  ];

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
    _setupRealtimeUpdates();
  }
  
  @override
  void dispose() {
    _restaurantsUpdatesSubscription?.cancel();
    _couriersUpdatesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRestaurants() async {
    try {
      debugPrint('🔄 [RESTAURANTS] Cargando restaurantes para pantalla de lista...');
      // Gate: mostrar restaurantes solo si hay repartidores activos
      final hasCouriers = await DoaRepartosService.hasActiveCouriers();
      if (mounted) setState(() => _hasActiveCouriers = hasCouriers);
      if (!hasCouriers) {
        debugPrint('⛔ [RESTAURANTS] No hay repartidores activos. Ocultando lista.');
        if (mounted) {
          setState(() {
            _allRestaurants = [];
            _filteredRestaurants = [];
            _isLoading = false;
          });
        }
        return;
      }
      
      // CRÍTICO: Obtener solo restaurantes aprobados Y online (TRUE)
      final allRestaurants = await DoaRepartosService.getRestaurants(status: 'approved', isOnline: true);
      
      debugPrint('📊 [RESTAURANTS] Total restaurantes aprobados y online: ${allRestaurants.length}');
      
      // Log cada restaurante para debugging
      for (var restaurant in allRestaurants) {
        debugPrint('🏪 [RESTAURANTS] ${restaurant.name}: ONLINE (aprobado)');
      }
      
      setState(() {
        // Todos los restaurantes obtenidos ya están aprobados y online
        _allRestaurants = allRestaurants;
        _applyFilters();
        _isLoading = false;
      });
      
      debugPrint('🎯 [RESTAURANTS] Restaurantes mostrados en lista: ${_allRestaurants.length}');
      
    } catch (e) {
      debugPrint('❌ [RESTAURANTS] Error cargando restaurantes: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando restaurantes: $e')),
        );
      }
    }
  }
  
  /// Configurar actualizaciones en tiempo real
  void _setupRealtimeUpdates() {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) {
      debugPrint('⚠️ [RESTAURANTS] Sin usuario autenticado, no configurando tiempo real');
      return;
    }
    
    final realtimeService = RealtimeNotificationService.forUser(user!.id);
    
    // Escuchar actualizaciones de restaurantes (online/offline)
    _restaurantsUpdatesSubscription = realtimeService.restaurantsUpdated.listen((_) {
      debugPrint('🔔 [RESTAURANTS] Actualización de restaurantes recibida en tiempo real');
      
      // Recargar la lista de restaurantes cuando hay cambios
      _loadRestaurants();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🍴 ¡Lista actualizada!'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    // Escuchar cambios en disponibilidad de repartidores (online/offline)
    _couriersUpdatesSubscription = realtimeService.couriersUpdated.listen((_) {
      debugPrint('🔔 [RESTAURANTS] Cambio de repartidores detectado en tiempo real');
      _loadRestaurants();
    });
  }

  void _applyFilters() {
    var filtered = List<DoaRestaurant>.from(_allRestaurants);

    // Aplicar filtro de búsqueda
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((restaurant) {
        return restaurant.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (restaurant.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      }).toList();
    }

    // Aplicar filtros específicos
    switch (_selectedFilter) {
      case 'Abiertos':
        filtered = filtered.where((r) => r.isOpen).toList();
        break;
      case 'Mejor valorados':
        filtered.sort((a, b) {
          final ratingA = a.rating ?? 0.0;
          final ratingB = b.rating ?? 0.0;
          return ratingB.compareTo(ratingA);
        });
        break;
      case 'Más rápidos':
        filtered.sort((a, b) {
          // Usar directamente el deliveryTime como int, con fallback a 60
          final timeA = a.deliveryTime ?? 60;
          final timeB = b.deliveryTime ?? 60;
          return timeA.compareTo(timeB);
        });
        break;
      case 'Envío gratis':
        filtered = filtered.where((r) => r.deliveryFee == 0.0).toList();
        break;
    }

    setState(() {
      _filteredRestaurants = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Restaurantes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: TextField(
                onChanged: (value) {
                  _searchQuery = value;
                  _applyFilters();
                },
                decoration: InputDecoration(
                  hintText: 'Buscar restaurantes...',
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),

          // Filtros horizontales
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedFilter = filter;
                      });
                      _applyFilters();
                    },
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    checkmarkColor: Theme.of(context).colorScheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Lista de restaurantes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRestaurants.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                                Icon(
                                  _hasActiveCouriers ? Icons.search_off : Icons.info_outline,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                                ),
                            const SizedBox(height: 16),
                            Text(
                                  !_hasActiveCouriers
                                      ? 'Por ahora no hay repartidores activos'
                                      : _searchQuery.isNotEmpty
                                          ? 'No se encontraron restaurantes'
                                          : 'No hay restaurantes disponibles',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                                if (!_hasActiveCouriers) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Cuando haya al menos 1 repartidor disponible, verás los restaurantes aquí.',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ] else if (_searchQuery.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Intenta con otros términos de búsqueda',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadRestaurants,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredRestaurants.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: RestaurantCard(
                                restaurant: _filteredRestaurants[index],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}