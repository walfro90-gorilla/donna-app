import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/admin/restaurant_detail_admin_screen.dart';

/// Internal checklist model used only by this screen
class _RestaurantChecklist {
  final int productCount;
  final bool hasName;
  final bool hasDescription;
  final bool hasLogo;
  final bool hasCover;
  final int progress; // 0..100
  final List<String> missing; // human friendly reasons

  const _RestaurantChecklist({
    required this.productCount,
    required this.hasName,
    required this.hasDescription,
    required this.hasLogo,
    required this.hasCover,
    required this.progress,
    required this.missing,
  });

  bool get canApprove =>
      productCount >= 3 && hasName && hasDescription && hasLogo && hasCover;
}

class RestaurantsManagementScreen extends StatefulWidget {
  const RestaurantsManagementScreen({super.key});

  @override
  State<RestaurantsManagementScreen> createState() => _RestaurantsManagementScreenState();
}

class _RestaurantsManagementScreenState extends State<RestaurantsManagementScreen> {
  List<DoaRestaurant> _allRestaurants = [];
  List<DoaRestaurant> _filteredRestaurants = [];
  bool _isLoading = true;
  String _statusFilter = 'all'; // all, pending, approved, rejected
  final Map<String, _RestaurantChecklist> _checklistCache = {};

  @override
  void initState() {
    super.initState();
    _loadRestaurants();
  }

  Future<void> _loadRestaurants() async {
    setState(() => _isLoading = true);
    
    try {
      print('🔄 [ADMIN] Loading restaurants directly from Supabase...');
      
      // PRIMERO: Contar filas en la base de datos para verificar conexión real
      await _countDatabaseRows();
      
      // Cargar TODOS los restaurantes directamente de Supabase
      final restaurants = await DoaRepartosService.getRestaurants();
      
      print('✅ [ADMIN] Loaded ${restaurants.length} restaurants from Supabase');
      for (var restaurant in restaurants) {
        print('📋 Restaurant: ${restaurant.name} - Status: ${restaurant.status} - UserID: ${restaurant.userId}');
      }
      
      setState(() {
        _allRestaurants = restaurants;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ [ADMIN] Error loading restaurants: $e');
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading restaurants: $e')),
        );
      }
    }
  }

  Future<_RestaurantChecklist> _computeChecklist(DoaRestaurant r) async {
    // Evitar resultados obsoletos: siempre recalcular desde Supabase
    // (dejamos la caché solo como fallback en caso de error de red)
    final cached = _checklistCache[r.id];

    try {
      // Count active products from Supabase
      final products = await DoaRepartosService.getProductsByRestaurant(r.id, isAvailable: true);
      final count = (products).length;

      final hasName = (r.name).trim().isNotEmpty;
      final hasDesc = (r.description ?? '').trim().isNotEmpty;
      final hasLogo = (r.logoUrl ?? '').trim().isNotEmpty;
      // Aceptar cover desde cover_image_url o image_url (algunas vistas rellenan image_url)
      final hasCover = ((r.coverImageUrl ?? r.imageUrl) ?? '').trim().isNotEmpty;

      // Simple 5-item progress: name, desc, logo, cover, 3+ products
      int score = 0;
      if (hasName) score += 20;
      if (hasDesc) score += 20;
      if (hasLogo) score += 20;
      if (hasCover) score += 20;
      if (count >= 3) score += 20;

      final missing = <String>[];
      if (!hasName) missing.add('Nombre del restaurante');
      if (!hasDesc) missing.add('Descripción');
      if (!hasLogo) missing.add('Logo');
      if (!hasCover) missing.add('Imagen de portada');
      if (count < 3) missing.add('Al menos 3 productos activos');

      final result = _RestaurantChecklist(
        productCount: count,
        hasName: hasName,
        hasDescription: hasDesc,
        hasLogo: hasLogo,
        hasCover: hasCover,
        progress: score,
        missing: missing,
      );

      _checklistCache[r.id] = result; // actualizar snapshot más reciente
      return result;
    } catch (e) {
      // On error, return conservative result (cannot approve)
      final result = _RestaurantChecklist(
        productCount: 0,
        hasName: (r.name).trim().isNotEmpty,
        hasDescription: (r.description ?? '').trim().isNotEmpty,
        hasLogo: (r.logoUrl ?? '').trim().isNotEmpty,
        hasCover: (r.coverImageUrl ?? '').trim().isNotEmpty,
        progress: 0,
        missing: ['Error leyendo productos: ${e.toString()}'],
      );
      if (cached != null) {
        // Si hay caché previa úsala como último recurso visual, pero regresa el error result
        _checklistCache[r.id] = cached;
      } else {
        _checklistCache[r.id] = result;
      }
      return result;
    }
  }

  void _openChecklistSheet(DoaRestaurant restaurant, _RestaurantChecklist checklist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Checklist de ${restaurant.name}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: checklist.progress / 100.0,
                  minHeight: 10,
                  backgroundColor: Colors.grey.withValues(alpha: 0.3),
                  color: checklist.canApprove ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Text('Progreso de perfil: ${checklist.progress}%'),
              const SizedBox(height: 16),
              _buildChecklistRow('Nombre', checklist.hasName),
              _buildChecklistRow('Descripción', checklist.hasDescription),
              _buildChecklistRow('Logo', checklist.hasLogo),
              _buildChecklistRow('Imagen de portada', checklist.hasCover),
              _buildChecklistRow('Productos activos (≥ 3)', checklist.productCount >= 3,
                  trailing: Text('${checklist.productCount}', style: const TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: checklist.canApprove
                          ? () {
                              Navigator.pop(context);
                              _showUpdateDialog(restaurant, RestaurantStatus.approved);
                            }
                          : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Aprobar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green.withValues(alpha: 0.3),
                        disabledForegroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showUpdateDialog(restaurant, RestaurantStatus.rejected);
                      },
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (!checklist.canApprove && checklist.missing.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Requisitos pendientes:', style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final m in checklist.missing)
                  Row(children: [
                    const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(m)),
                  ]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildChecklistRow(String label, bool ok, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Future<void> _validateAndApprove(DoaRestaurant restaurant) async {
    final checklist = await _computeChecklist(restaurant);
    if (!mounted) return;

    if (checklist.canApprove) {
      _showUpdateDialog(restaurant, RestaurantStatus.approved);
    } else {
      // Show dialog with reasons and a button to open details
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No se puede aprobar aún'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Faltan los siguientes requisitos:'),
              const SizedBox(height: 8),
              for (final m in checklist.missing)
                Row(children: [
                  const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(child: Text(m)),
                ]),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _openChecklistSheet(restaurant, checklist);
              },
              child: const Text('Ver detalle'),
            ),
          ],
        ),
      );
    }
  }

  /// Contar filas en las tablas principales para verificar conexión a Supabase
  Future<void> _countDatabaseRows() async {
    try {
      print('📊 [DATABASE COUNT] Checking real database connection...');
      
      // Contar usuarios
      final usersData = await SupabaseConfig.client
          .from('users')
          .select('id');
      
      final usersCount = usersData?.length ?? 0;
      print('👥 [DATABASE COUNT] Users table: $usersCount rows');
      
      // Contar restaurantes
      final restaurantsData = await SupabaseConfig.client
          .from('restaurants')
          .select('id');
      
      final restaurantsCount = restaurantsData?.length ?? 0;
      print('🏪 [DATABASE COUNT] Restaurants table: $restaurantsCount rows');
      
      // Mostrar algunos datos raw de restaurants si existen
      if (restaurantsCount > 0) {
        final rawData = await SupabaseConfig.client
            .from('restaurants')
            .select('id, name, status, user_id')
            .limit(5);
            
        print('📋 [RAW DATABASE DATA] First 5 restaurants:');
        for (var row in (rawData as List? ?? [])) {
          print('  • ID: ${row['id']}, Name: ${row['name']}, Status: ${row['status']}, UserID: ${row['user_id']}');
        }
      }
      
    } catch (e) {
      print('❌ [DATABASE COUNT] Error counting database rows: $e');
    }
  }

  void _applyFilter() {
    if (_statusFilter == 'all') {
      _filteredRestaurants = _allRestaurants;
    } else {
      RestaurantStatus filterStatus;
      switch (_statusFilter) {
        case 'pending':
          filterStatus = RestaurantStatus.pending;
          break;
        case 'approved':
          filterStatus = RestaurantStatus.approved;
          break;
        case 'rejected':
          filterStatus = RestaurantStatus.rejected;
          break;
        default:
          filterStatus = RestaurantStatus.pending;
      }
      _filteredRestaurants = _allRestaurants.where((r) => r.status == filterStatus).toList();
    }
    print('🎯 [ADMIN] Filtered to ${_filteredRestaurants.length} restaurants (filter: $_statusFilter)');
  }

  Future<void> _updateRestaurantStatus(String restaurantId, RestaurantStatus status) async {
    try {
      print('🔄 [ADMIN] Updating restaurant status: $restaurantId -> ${status.toString().split('.').last}');
      
      // Usar el servicio de Supabase para actualizar el status
      await DoaRepartosService.updateRestaurantStatus(restaurantId, status.toString().split('.').last);
      
      print('✅ [ADMIN] Restaurant status updated successfully');
      await _loadRestaurants(); // Reload data
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restaurant status updated to ${status.toString().split('.').last}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ [ADMIN] Error updating restaurant status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restaurants Management'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          // Filter dropdown
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _statusFilter,
              dropdownColor: Colors.orange.shade800,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              icon: const Icon(Icons.filter_list, color: Colors.white),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Restaurants', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'pending', child: Text('Pending', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'approved', child: Text('Approved', style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected', style: TextStyle(color: Colors.white))),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() {
                    _statusFilter = value;
                    _applyFilter();
                  });
                }
              },
            ),
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildRestaurantsList(),
    );
  }

  Widget _buildRestaurantsList() {
    if (_filteredRestaurants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _statusFilter == 'all' 
                  ? 'No restaurants found'
                  : 'No $_statusFilter restaurants',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'Total restaurants in system: ${_allRestaurants.length}',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRestaurants,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredRestaurants.length,
        itemBuilder: (context, index) {
          final restaurant = _filteredRestaurants[index];
          return _buildRestaurantCard(restaurant);
        },
      ),
    );
  }

  Widget _buildRestaurantCard(DoaRestaurant restaurant) {
    Color statusColor;
    IconData statusIcon;
    
    switch (restaurant.status) {
      case RestaurantStatus.pending:
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case RestaurantStatus.approved:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case RestaurantStatus.rejected:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
    }

    return InkWell(
      onTap: () {
        // Navigate to full admin detail page
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminRestaurantDetailScreen(restaurant: restaurant),
          ),
        );
      },
      child: Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Restaurant logo/image
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade200,
                  ),
                  child: (restaurant.logoUrl?.isNotEmpty ?? false)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            restaurant.logoUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => 
                                Icon(Icons.restaurant, size: 30, color: Colors.grey),
                          ),
                        )
                      : Icon(Icons.restaurant, size: 30, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                
                // Restaurant info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        restaurant.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (restaurant.description != null && restaurant.description!.isNotEmpty)
                        Text(
                          restaurant.description!,
                          style: TextStyle(color: Colors.grey.shade600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      
                      // Status badges row
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          // Status badge
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, color: statusColor, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                restaurant.status.toString().split('.').last.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          // Email verification badge
                          if (restaurant.user != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: restaurant.user!.emailConfirm 
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: restaurant.user!.emailConfirm 
                                      ? Colors.green 
                                      : Colors.red,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    restaurant.user!.emailConfirm 
                                        ? Icons.check_circle 
                                        : Icons.warning,
                                    color: restaurant.user!.emailConfirm 
                                        ? Colors.green 
                                        : Colors.red,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    restaurant.user!.emailConfirm 
                                        ? 'Email verificado' 
                                        : 'Email pendiente',
                                    style: TextStyle(
                                      color: restaurant.user!.emailConfirm 
                                          ? Colors.green.shade700 
                                          : Colors.red.shade700,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Restaurant details
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                Text('${restaurant.rating}'),
                const SizedBox(width: 16),
                Icon(Icons.access_time, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text('${restaurant.deliveryTime} min'),
                const SizedBox(width: 16),
                Icon(Icons.delivery_dining, color: Colors.grey, size: 16),
                const SizedBox(width: 4),
                Text('\$${restaurant.deliveryFee?.toStringAsFixed(0) ?? '0'}'),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                // Details button
                TextButton.icon(
                  onPressed: () async {
                    final checklist = await _computeChecklist(restaurant);
                    if (!mounted) return;
                    _openChecklistSheet(restaurant, checklist);
                  },
                  icon: const Icon(Icons.fact_check, color: Colors.orange),
                  label: const Text('Ver checklist'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminRestaurantDetailScreen(restaurant: restaurant),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, color: Colors.blue),
                  label: const Text('Ver detalle'),
                ),
                const Spacer(),
                if (restaurant.status == RestaurantStatus.pending) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _validateAndApprove(restaurant),
                      icon: const Icon(Icons.check),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showUpdateDialog(restaurant, RestaurantStatus.rejected),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                
                if (restaurant.status == RestaurantStatus.approved) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showUpdateDialog(restaurant, RestaurantStatus.rejected),
                      icon: const Icon(Icons.block),
                      label: const Text('Suspend'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
                
                if (restaurant.status == RestaurantStatus.rejected) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showUpdateDialog(restaurant, RestaurantStatus.approved),
                      icon: const Icon(Icons.restore),
                      label: const Text('Reactivate'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }

  void _showUpdateDialog(DoaRestaurant restaurant, RestaurantStatus newStatus) {
    final bool isApproving = newStatus == RestaurantStatus.approved;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isApproving ? 'Approve Restaurant' : 'Update Restaurant Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Restaurant: ${restaurant.name}'),
            const SizedBox(height: 8),
            Text(
              isApproving
                  ? 'This will allow the restaurant to start accepting orders.'
                  : 'This action will prevent the restaurant from accepting orders.',
              style: TextStyle(
                color: isApproving ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateRestaurantStatus(restaurant.id, newStatus);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isApproving ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(isApproving ? 'Approve' : 'Update'),
          ),
        ],
      ),
    );
  }
}