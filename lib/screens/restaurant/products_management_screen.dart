import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/screens/restaurant/product_edit_screen.dart';
import 'package:doa_repartos/screens/restaurant/combo_edit_screen.dart';

/// Pantalla para gestionar productos del restaurante
class ProductsManagementScreen extends StatefulWidget {
  const ProductsManagementScreen({super.key});

  @override
  State<ProductsManagementScreen> createState() => _ProductsManagementScreenState();
}

class _ProductsManagementScreenState extends State<ProductsManagementScreen> {
  DoaRestaurant? _restaurant;
  final List<DoaProduct> _products = [];
  Set<String> _comboProductIds = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;

  // UI state
  final _searchCtrl = TextEditingController();
  bool _showAvailableOnly = false;
  String? _typeFilter; // null=all, one of: principal|bebida|postre|entrada|combo
  int _page = 0;
  static const _pageSize = 20;
  bool _hasMore = true;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRestaurantAndProducts();
    _scrollController.addListener(_onScroll);
  }

  /// Cargar restaurante y productos
  Future<void> _loadRestaurantAndProducts({bool reset = true}) async {
    try {
      setState(() => _isLoading = true);
      
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser == null) return;
      
      // Cargar restaurante
      final restaurantResponse = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      
      if (restaurantResponse != null) {
        _restaurant = DoaRestaurant.fromJson(restaurantResponse);

        if (reset) {
          _products.clear();
          _page = 0;
          _hasMore = true;
        }

        await _loadPage();

        // Load combo product ids to flag combos visually
        _comboProductIds = await DoaRepartosService.getComboProductIdsByRestaurant(_restaurant!.id);
        for (var i = 0; i < _products.length; i++) {
          final p = _products[i];
          _products[i] = DoaProduct(
            id: p.id,
            restaurantId: p.restaurantId,
            name: p.name,
            description: p.description,
            price: p.price,
            imageUrl: p.imageUrl,
            isAvailable: p.isAvailable,
            createdAt: p.createdAt,
            updatedAt: p.updatedAt,
            isCombo: _comboProductIds.contains(p.id),
          );
        }
      }
      
    } catch (e) {
      print('Error cargando datos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPage() async {
    if (_restaurant == null || !_hasMore) return;
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      var query = SupabaseConfig.client
          .from('products')
          .select()
          .eq('restaurant_id', _restaurant!.id);
      if (_showAvailableOnly) {
        query = query.eq('is_available', true);
      }
      if (_typeFilter != null && _typeFilter!.isNotEmpty) {
        query = query.eq('type', _typeFilter!);
      }
      final term = _searchCtrl.text.trim();
      if (term.isNotEmpty) {
        query = query.ilike('name', '%$term%');
      }
      final start = _page * _pageSize;
      final end = start + _pageSize - 1;
      final List<dynamic> response = await query.order('created_at', ascending: false).range(start, end);
      final newItems = response.map<DoaProduct>((json) => DoaProduct.fromJson(json)).toList();
      if (newItems.length < _pageSize) _hasMore = false;
      _products.addAll(newItems);
      _page++;
    } catch (e) {
      debugPrint('Error loading products page: $e');
      _hasMore = false;
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels > _scrollController.position.maxScrollExtent - 300) {
      _loadPage();
    }
  }

  /// Mostrar diálogo para agregar/editar producto
  Future<void> _showProductDialog({DoaProduct? product}) async {
    if (_restaurant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Primero debes crear tu restaurante')),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductEditScreen(restaurant: _restaurant!, product: product),
      ),
    );
    if (ok == true) await _loadRestaurantAndProducts();
  }

  /// Cambiar disponibilidad del producto
  Future<void> _toggleProductAvailability(DoaProduct product) async {
    try {
      await SupabaseConfig.client
          .from('products')
          .update({
            'is_available': !product.isAvailable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', product.id);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(product.isAvailable 
              ? '❌ Producto deshabilitado' 
              : '✅ Producto habilitado'),
        ),
      );
      
      await _loadRestaurantAndProducts();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  /// Eliminar producto
  Future<void> _deleteProduct(DoaProduct product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Producto'),
        content: Text('¿Estás seguro de que quieres eliminar "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        if (_comboProductIds.contains(product.id)) {
          await DoaRepartosService.deleteComboByProductId(product.id);
        } else {
          await SupabaseConfig.client.from('products').delete().eq('id', product.id);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Producto eliminado')),
        );
        
        await _loadRestaurantAndProducts();
        
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error eliminando: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Productos'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          if (_restaurant != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'new_product') {
                  await _showProductDialog();
                } else if (value == 'new_combo') {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ComboEditScreen(restaurant: _restaurant!),
                    ),
                  );
                  if (ok == true) await _loadRestaurantAndProducts();
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'new_product', child: Text('Nuevo producto')),
                PopupMenuItem(value: 'new_combo', child: Text('Nuevo combo')),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _restaurant == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Primero debes crear tu restaurante', style: TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Search + filters
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'Buscar productos',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onSubmitted: (_) => _loadRestaurantAndProducts(reset: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            selected: _showAvailableOnly,
                            onSelected: (v) async {
                              setState(() => _showAvailableOnly = v);
                              await _loadRestaurantAndProducts(reset: true);
                            },
                            label: const Text('Disponibles'),
                          ),
                          const SizedBox(width: 8),
                          PopupMenuButton<String?>(
                            onSelected: (v) async {
                              setState(() => _typeFilter = v);
                              await _loadRestaurantAndProducts(reset: true);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem<String?>(value: null, child: Text('Todos los tipos')),
                               const PopupMenuItem<String?>(value: 'principal', child: Text('Principal')),
                               const PopupMenuItem<String?>(value: 'bebida', child: Text('Bebida')),
                               const PopupMenuItem<String?>(value: 'postre', child: Text('Postre')),
                               const PopupMenuItem<String?>(value: 'entrada', child: Text('Entrada')),
                               const PopupMenuItem<String?>(value: 'combo', child: Text('Combos')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.filter_list, size: 18),
                                  const SizedBox(width: 6),
                                   Text(
                                     _typeFilter == null
                                         ? 'Todos'
                                         : (_typeFilter![0].toUpperCase() + _typeFilter!.substring(1)),
                                   ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Counter + quick add
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text('Total: ${_products.length}${_hasMore ? '+' : ''}', style: Theme.of(context).textTheme.bodyMedium),
                          const Spacer(),
                          if (_restaurant != null)
                            MenuAnchor(
                              builder: (context, controller, _) => FilledButton.tonal(
                                onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                                child: const Text('Agregar'),
                              ),
                              menuChildren: [
                                MenuItemButton(
                                  onPressed: () => _showProductDialog(),
                                  leadingIcon: const Icon(Icons.add_circle_outline),
                                  child: const Text('Producto simple'),
                                ),
                                MenuItemButton(
                                  onPressed: () async {
                                    final ok = await Navigator.of(context).push<bool>(
                                      MaterialPageRoute(
                                        builder: (_) => ComboEditScreen(restaurant: _restaurant!),
                                      ),
                                    );
                                    if (ok == true) await _loadRestaurantAndProducts(reset: true);
                                  },
                                  leadingIcon: const Icon(Icons.all_inbox_outlined),
                                  child: const Text('Combo (paquete)'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _products.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.restaurant_menu_outlined, size: 64, color: Colors.grey),
                                  const SizedBox(height: 12),
                                  const Text('No tienes productos aún', style: TextStyle(color: Colors.grey)),
                                  const SizedBox(height: 12),
                                  FilledButton(
                                    onPressed: () => _showProductDialog(),
                                    style: FilledButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                                    child: const Text('Agregar producto'),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                              itemCount: _products.length + (_isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                if (index >= _products.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }
                                final product = _products[index];
                                return _DenseProductTile(
                                  product: product,
                                  isCombo: _comboProductIds.contains(product.id),
                                  onEdit: () async {
                                    if (_comboProductIds.contains(product.id)) {
                                      // Fetch combo details
                                      DoaCombo? combo;
                                      try {
                                        final combos = await DoaRepartosService.getCombosByRestaurant(_restaurant!.id);
                                        final match = combos.firstWhere(
                                          (c) => c['product_id'] == product.id,
                                          orElse: () => {},
                                        );
                                        if (match.isNotEmpty) {
                                          combo = DoaCombo.fromJson({
                                            ...match,
                                            'items': match['items'] ?? [],
                                          });
                                        }
                                      } catch (_) {}
                                      final ok = await Navigator.of(context).push<bool>(
                                        MaterialPageRoute(
                                          builder: (_) => ComboEditScreen(
                                            restaurant: _restaurant!,
                                            comboProduct: product,
                                            combo: combo,
                                          ),
                                        ),
                                      );
                                      if (ok == true) await _loadRestaurantAndProducts(reset: true);
                                    } else {
                                      final ok = await Navigator.of(context).push<bool>(
                                        MaterialPageRoute(builder: (_) => ProductEditScreen(restaurant: _restaurant!, product: product)),
                                      );
                                      if (ok == true) await _loadRestaurantAndProducts(reset: true);
                                    }
                                  },
                                  onToggleAvailability: () => _toggleProductAvailability(product),
                                  onDelete: () => _deleteProduct(product),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

/// Card individual para mostrar producto
class ProductCard extends StatelessWidget {
  final DoaProduct product;
  final VoidCallback onEdit;
  final VoidCallback onToggleAvailability;
  final VoidCallback onDelete;

  const ProductCard({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Imagen del producto (si existe)
                if (product.imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      product.imageUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: product.isAvailable ? null : Colors.grey,
                        ),
                      ),
                      if (product.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          product.description!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: product.isAvailable 
                                ? Colors.grey.shade700 
                                : Colors.grey,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '\$${product.price.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: product.isAvailable 
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        product.isAvailable ? 'Disponible' : 'No disponible',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: product.isAvailable ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onToggleAvailability,
                    icon: Icon(
                      product.isAvailable ? Icons.visibility_off : Icons.visibility,
                      size: 16,
                    ),
                    label: Text(product.isAvailable ? 'Deshabilitar' : 'Habilitar'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: product.isAvailable ? Colors.orange : Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact list tile for products/combos
class _DenseProductTile extends StatelessWidget {
  final DoaProduct product;
  final bool isCombo;
  final VoidCallback onEdit;
  final VoidCallback onToggleAvailability;
  final VoidCallback onDelete;

  const _DenseProductTile({
    required this.product,
    required this.isCombo,
    required this.onEdit,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = product.isAvailable ? Colors.green : Colors.red;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: product.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(product.imageUrl!, width: 48, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(width: 48, height: 48, color: Colors.grey.shade200, child: const Icon(Icons.image_not_supported))),
            )
          : Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.fastfood, color: Colors.orange),
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (isCombo)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Text('Combo', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Text('\$${product.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          const SizedBox(width: 8),
          Icon(product.isAvailable ? Icons.check_circle : Icons.pause_circle, size: 16, color: color),
          const SizedBox(width: 4),
          Text(product.isAvailable ? 'Disponible' : 'No disp.', style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              onEdit();
              break;
            case 'toggle':
              onToggleAvailability();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar'))),
          PopupMenuItem(
            value: 'toggle',
            child: ListTile(
              leading: Icon(product.isAvailable ? Icons.visibility_off : Icons.visibility),
              title: Text(product.isAvailable ? 'Deshabilitar' : 'Habilitar'),
            ),
          ),
          const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Eliminar'))),
        ],
      ),
      onTap: onEdit,
    );
  }
}

/// Diálogo para agregar/editar producto
class ProductFormDialog extends StatefulWidget {
  final DoaRestaurant restaurant;
  final DoaProduct? product;

  const ProductFormDialog({
    super.key,
    required this.restaurant,
    this.product,
  });

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  
  bool _isAvailable = true;
  bool _isSaving = false;
  PlatformFile? _selectedImage;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!.name;
      _descriptionController.text = widget.product!.description ?? '';
      _priceController.text = widget.product!.price.toString();
      _isAvailable = widget.product!.isAvailable;
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      setState(() => _isSaving = true);
      
      String? imageUrl = widget.product?.imageUrl;
      
      // Subir imagen si se seleccionó una nueva
      if (_selectedImage != null) {
        final uploadedUrl = await StorageService.uploadProductImage(
          widget.restaurant.id,
          _selectedImage!,
        );
        
        if (uploadedUrl != null) {
          imageUrl = uploadedUrl;
        } else {
          throw Exception('Error al subir la imagen del producto');
        }
      }
      
      final data = {
        'restaurant_id': widget.restaurant.id,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'image_url': imageUrl,
        'is_available': _isAvailable,
        'type': 'single',
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (widget.product == null) {
        // Crear nuevo producto - Supabase auto-genera el UUID
        data['created_at'] = DateTime.now().toIso8601String();
        
        final response = await SupabaseConfig.client
            .from('products')
            .insert(data)
            .select()
            .single();
        
        Navigator.of(context).pop(DoaProduct.fromJson(response));
      } else {
        // Actualizar producto existente
        final response = await SupabaseConfig.client
            .from('products')
            .update(data)
            .eq('id', widget.product!.id)
            .select()
            .single();
        
        Navigator.of(context).pop(DoaProduct.fromJson(response));
      }
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Agregar Producto' : 'Editar Producto'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Campo de imagen
                ImageUploadField(
                  label: 'Foto del Producto',
                  hint: 'Toca para subir foto',
                  icon: Icons.camera_alt,
                  imageUrl: widget.product?.imageUrl,
                  isRequired: false,
                  onImageSelected: (file) {
                    setState(() {
                      _selectedImage = file;
                    });
                  },
                  helpText: 'Una buena foto ayuda a vender más',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Producto *',
                    hintText: 'Ej: Pizza Margherita',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (Opcional)',
                    hintText: 'Ej: Tomate, mozzarella, albahaca fresca...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  decoration: const InputDecoration(
                    labelText: 'Precio *',
                    hintText: 'Ej: 15.99',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El precio es obligatorio';
                    }
                    final price = double.tryParse(value.trim());
                    if (price == null || price <= 0) {
                      return 'Ingresa un precio válido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Producto disponible'),
                  subtitle: Text(_isAvailable 
                      ? 'Los clientes pueden ordenar este producto' 
                      : 'Este producto no aparecerá en el menú'),
                  value: _isAvailable,
                  onChanged: (value) => setState(() => _isAvailable = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveProduct,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
          ),
          child: _isSaving 
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(widget.product == null ? 'Agregar' : 'Guardar'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }
}