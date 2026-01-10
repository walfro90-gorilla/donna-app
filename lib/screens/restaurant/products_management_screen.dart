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
        title: const Text('Mis Productos'),
        actions: [
          if (_restaurant != null)
             IconButton(
               icon: const Icon(Icons.add_circle_outline),
               onPressed: () => _showProductDialog(),
               tooltip: 'Nuevo producto',
             ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: _restaurant != null ? FloatingActionButton.extended(
        onPressed: () => _showAddMenu(context),
        label: const Text('Agregar'),
        icon: const Icon(Icons.add),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ) : null,
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    return Column(
                      children: [
                        // Header: Search + Category Pills
                        Container(
                          padding: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).appBarTheme.backgroundColor,
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(24),
                              bottomRight: Radius.circular(24),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: TextField(
                                  controller: _searchCtrl,
                                  decoration: InputDecoration(
                                    hintText: 'Buscar en mi menú...',
                                    prefixIcon: const Icon(Icons.search),
                                    filled: true,
                                    fillColor: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.5),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                  ),
                                  onSubmitted: (_) => _loadRestaurantAndProducts(reset: true),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildCategoryFilters(),
                            ],
                          ),
                        ),

                        // List / Grid
                        Expanded(
                          child: _products.isEmpty
                              ? _buildEmptyState()
                              : RefreshIndicator(
                                  onRefresh: () => _loadRestaurantAndProducts(reset: true),
                                  child: isWide 
                                    ? _buildProductGrid()
                                    : _buildProductList(),
                                ),
                        ),
                      ],
                    );
                  }
                ),
    );
  }
  Widget _buildCategoryFilters() {
    final categories = [
      {'id': null, 'label': 'Todos', 'icon': Icons.all_inclusive},
      {'id': 'principal', 'label': 'Principales', 'icon': Icons.restaurant},
      {'id': 'bebida', 'label': 'Bebidas', 'icon': Icons.local_drink},
      {'id': 'postre', 'label': 'Postres', 'icon': Icons.cake},
      {'id': 'entrada', 'label': 'Entradas', 'icon': Icons.fastfood},
      {'id': 'combo', 'label': 'Combos', 'icon': Icons.inventory_2},
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _typeFilter == cat['id'];
          return ChoiceChip(
            selected: isSelected,
            onSelected: (v) {
              setState(() => _typeFilter = cat['id'] as String?);
              _loadRestaurantAndProducts(reset: true);
            },
            label: Text(cat['label'] as String),
            avatar: Icon(cat['icon'] as IconData, size: 16, color: isSelected ? Theme.of(context).colorScheme.onPrimary : null),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.restaurant_menu_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('No tienes productos aún', style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showProductDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Agregar mi primer producto'),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: _products.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _products.length) {
          return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        }
        return _buildProductItem(_products[index]);
      },
    );
  }

  Widget _buildProductGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _products.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _products.length) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildProductItem(_products[index]);
      },
    );
  }

  Widget _buildProductItem(DoaProduct product) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _PremiumProductCard(
        product: product,
        isCombo: _comboProductIds.contains(product.id),
        onEdit: () async {
          if (_comboProductIds.contains(product.id)) {
            DoaCombo? combo;
            try {
              final combos = await DoaRepartosService.getCombosByRestaurant(_restaurant!.id);
              final match = combos.firstWhere(
                (c) => c['product_id'] == product.id,
                orElse: () => {},
              );
              if (match.isNotEmpty) {
                combo = DoaCombo.fromJson({ ...match, 'items': match['items'] ?? [], });
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
      ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.restaurant),
            title: const Text('Producto simple'),
            subtitle: const Text('Platillo, bebida o postre individual'),
            onTap: () {
              Navigator.pop(context);
              _showProductDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2),
            title: const Text('Combo (Paquete)'),
            subtitle: const Text('Varios productos a un precio especial'),
            onTap: () async {
              Navigator.pop(context);
              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => ComboEditScreen(restaurant: _restaurant!)),
              );
              if (ok == true) await _loadRestaurantAndProducts(reset: true);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}




/// Card de producto con diseño premium
class _PremiumProductCard extends StatelessWidget {
  final DoaProduct product;
  final bool isCombo;
  final VoidCallback onEdit;
  final VoidCallback onToggleAvailability;
  final VoidCallback onDelete;

  const _PremiumProductCard({
    required this.product,
    required this.isCombo,
    required this.onEdit,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = product.isAvailable ? Colors.green : Colors.red;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withValues(alpha: isDark ? 0.3 : 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: product.isAvailable 
                ? Colors.transparent 
                : Colors.red.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Image with status overlay
            Stack(
              children: [
                Hero(
                  tag: 'product_image_${product.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: product.imageUrl != null
                        ? Image.network(
                            product.imageUrl!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),
                if (!product.isAvailable)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'PAUSADO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isCombo)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'COMBO',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${product.price.toStringAsFixed(0)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        product.isAvailable ? 'Disponible' : 'No disponible',
                        style: TextStyle(
                          color: color.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    product.isAvailable ? Icons.pause_circle_outline : Icons.play_circle_outline,
                    color: color,
                  ),
                  onPressed: onToggleAvailability,
                  visualDensity: VisualDensity.compact,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          SizedBox(width: 8),
                          Text('Eliminar', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.fastfood, color: Colors.orange),
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