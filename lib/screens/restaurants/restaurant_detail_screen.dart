import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/checkout/checkout_screen.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';

class RestaurantDetailScreen extends StatefulWidget {
  final DoaRestaurant restaurant;

  const RestaurantDetailScreen({
    super.key,
    required this.restaurant,
  });

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DoaProduct> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'Todos';
  String? _coverImageUrl; // cargado directo de restaurants table

  // Carrito temporal (reactivo para bottom sheet)
  final ValueNotifier<Map<String, int>> _cartVN = ValueNotifier(<String, int>{});
  // Notas por item: productId → texto de instrucciones especiales (free-text)
  final Map<String, String> _itemNotes = {};
  // Modificadores seleccionados: productId → lista de selecciones
  final Map<String, List<ModifierSelection>> _itemModifiers = {};
  // Caché de grupos de modificadores: productId → lista de grupos (evita re-fetches)
  final Map<String, List<DoaModifierGroup>> _modifierGroupsCache = {};
  bool _hasActiveCouriers = true;
  StreamSubscription<void>? _couriersUpdatesSubscription;
  bool _isPreviewMode = false;

  final List<String> _categories = [
    'Todos',
    'Principales',
    'Bebidas',
    'Postres',
    'Entradas',
  ];

  @override
  void initState() {
    super.initState();
    // Detectar si el usuario actual es el dueño del restaurante para activar modo preview silencioso o explícito
    final currentUser = SupabaseConfig.client.auth.currentUser;
    if (currentUser?.id == widget.restaurant.userId) {
      _isPreviewMode = true;
    }
    _coverImageUrl = widget.restaurant.coverImageUrl;
    _tabController = TabController(length: 3, vsync: this);
    _loadProducts();
    _loadCoverImage();
    _initCourierGate();
  }

  Future<void> _initCourierGate() async {
    try {
      final hasCouriers = await DoaRepartosService.hasActiveCouriers();
      if (mounted) setState(() => _hasActiveCouriers = hasCouriers);
    } catch (_) {}
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt != null) {
      final realtime = RealtimeNotificationService.forUser(user!.id);
      _couriersUpdatesSubscription = realtime.couriersUpdated.listen((_) async {
        final hasCouriers = await DoaRepartosService.hasActiveCouriers();
        if (!mounted) return;
        setState(() => _hasActiveCouriers = hasCouriers);
        if (!hasCouriers) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'No hay repartidores activos. El pedido está temporalmente deshabilitado.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  Future<void> _loadCoverImage() async {
    try {
      final row = await SupabaseConfig.client
          .from('restaurants')
          .select('cover_image_url')
          .eq('id', widget.restaurant.id)
          .maybeSingle();
      if (!mounted) return;
      final url = row?['cover_image_url'] as String?;
      if (url != null && url.isNotEmpty) {
        setState(() => _coverImageUrl = url);
      }
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final products = await DoaRepartosService.getProductsByRestaurant(
        widget.restaurant.id,
        isAvailable: true,
      );

      setState(() {
        _products = products.map((p) => DoaProduct.fromJson(p)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando productos: $e')),
        );
      }
    }
  }

  void _updateCart(String productId, int newQuantity) {
    final next = Map<String, int>.from(_cartVN.value);
    if (newQuantity <= 0) {
      next.remove(productId);
    } else {
      next[productId] = newQuantity;
    }
    setState(() {
      _cartVN.value = next;
    });
  }

  void _addToCart(String productId) {
    final q = (_cartVN.value[productId] ?? 0) + 1;
    _updateCart(productId, q);
  }

  void _removeFromCart(String productId) {
    final current = _cartVN.value[productId] ?? 0;
    if (current <= 1) {
      _updateCart(productId, 0);
    } else {
      _updateCart(productId, current - 1);
    }
  }

  int get _totalItems =>
      _cartVN.value.values.fold(0, (sum, quantity) => sum + quantity);

  /// Genera un resumen de texto con modificadores + nota libre para mostrar en ProductCard
  String? _buildItemSummaryNote(String productId) {
    final mods = _itemModifiers[productId] ?? [];
    final note = _itemNotes[productId] ?? '';
    if (mods.isEmpty && note.isEmpty) return null;
    final parts = <String>[
      if (mods.isNotEmpty) mods.map((m) => m.name).join(', '),
      if (note.isNotEmpty) note,
    ];
    return parts.join(' · ');
  }

  double _effectivePriceForProduct(String productId) {
    final product = _products.firstWhere((p) => p.id == productId);
    final modifierDelta = (_itemModifiers[productId] ?? [])
        .fold(0.0, (sum, m) => sum + m.priceDelta);
    return product.price + modifierDelta;
  }

  double get _totalAmount {
    return _cartVN.value.entries.fold(0.0, (sum, entry) {
      return sum + _effectivePriceForProduct(entry.key) * entry.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
          // Header con imagen
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            stretch: true,
            backgroundColor: Theme.of(context).colorScheme.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCoverImage(),
                  // Gradiente superior para legibilidad de iconos de navegación
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                  ),
                  // Gradiente inferior para transición suave al contenido
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black38, Colors.transparent],
                        ),
                      ),
                      child: SizedBox(height: 80, width: double.infinity),
                    ),
                  ),
                  // Gradiente extra sobre el logo para dar espacio visual al avatar
                  const Align(
                    alignment: Alignment.bottomLeft,
                    child: SizedBox(height: 100, width: 110,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(-1, 1),
                            radius: 1.2,
                            colors: [Colors.black38, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'Menú'),
                Tab(text: 'Información'),
                Tab(text: 'Reseñas'),
              ],
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.favorite_border, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),

          // Perfil Social (nombre y descripción)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar del restaurante — renderiza sobre el SliverAppBar (content > header en z-order)
                  Transform.translate(
                    offset: const Offset(0, -42),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 20,
                                spreadRadius: 1,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            backgroundImage: widget.restaurant.logoUrl != null
                                ? NetworkImage(widget.restaurant.logoUrl!)
                                : null,
                            child: widget.restaurant.logoUrl == null
                                ? Icon(Icons.restaurant, size: 36,
                                    color: Theme.of(context).colorScheme.primary)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Nombre del restaurante junto al avatar para máximo contraste
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.restaurant.name,
                                  style: Theme.of(context).textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.restaurant.cuisineType != null)
                                  Text(
                                    widget.restaurant.cuisineType!,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        _buildSocialIconsGrid(),
                      ],
                    ),
                  ),

                      if (widget.restaurant.description != null &&
                          widget.restaurant.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            widget.restaurant.description!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.85),
                                  height: 1.5,
                                ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Info de entrega
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.access_time_outlined,
                            label:
                                '${widget.restaurant.deliveryTime ?? 30}-${(widget.restaurant.deliveryTime ?? 30) + 15} min',
                          ),
                          _InfoChip(
                            icon: Icons.delivery_dining_outlined,
                            label: widget.restaurant.deliveryFee != null &&
                                    widget.restaurant.deliveryFee! > 0
                                ? '\$${widget.restaurant.deliveryFee!.toStringAsFixed(0)}'
                                : '\$35',
                          ),
                          _InfoChip(
                            icon: widget.restaurant.isOpen
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                            label: widget.restaurant.isOpen ? 'Abierto' : 'Cerrado',
                            color: widget.restaurant.isOpen
                                ? Theme.of(context).colorScheme.secondary
                                : Theme.of(context).colorScheme.error,
                          ),
                          if (widget.restaurant.rating != null)
                            _InfoChip(
                              icon: Icons.star_outline_rounded,
                              label: widget.restaurant.rating!.toStringAsFixed(1),
                              color: Colors.amber.shade700,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
            ),
          ),

          // Aviso si no hay repartidores
          if (!_hasActiveCouriers)
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Por ahora no hay repartidores activos. Puedes explorar el menú, pero no podrás agregar al carrito ni pedir hasta que haya disponibilidad.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Contenido basado en la pestaña seleccionada
          SliverFillRemaining(
            hasScrollBody: true,
            child: TabBarView(
              controller: _tabController,
              children: [
                // PESTAÑA 1: MENÚ (Contenido original)
                CustomScrollView(
                  slivers: [
                    // Filtro de categorías
                    SliverToBoxAdapter(
                      child: Container(
                        height: 60,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _categories.length,
                          itemBuilder: (context, index) {
                            final category = _categories[index];
                            final isSelected = _selectedCategory == category;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(category),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedCategory = category;
                                  });
                                },
                                selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                checkmarkColor: Theme.of(context).colorScheme.primary,
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    // Lista de productos
                    _isLoading
                        ? const SliverFillRemaining(
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _products.isEmpty
                            ? const SliverFillRemaining(
                                child: Center(
                                  child: Text('No hay productos disponibles'),
                                ),
                              )
                            : SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final product = _products[index];
                                    final productNameById = {
                                      for (final p in _products) p.id: p.name,
                                    };
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        bottom: index == _products.length - 1 ? 100 : 16,
                                      ),
                                      child: ProductCard(
                                        product: product,
                                        quantity: _cartVN.value[product.id] ?? 0,
                                        orderingEnabled: _hasActiveCouriers,
                                        commissionBps: widget.restaurant.commissionBps,
                                        onAdd: _hasActiveCouriers
                                            ? () => _addToCart(product.id)
                                            : null,
                                        onRemove: _hasActiveCouriers
                                            ? () => _removeFromCart(product.id)
                                            : null,
                                        productNameById: productNameById,
                                        note: _buildItemSummaryNote(product.id),
                                        onNotesTap: _hasActiveCouriers && (_cartVN.value[product.id] ?? 0) > 0
                                            ? () => _showItemCustomizationSheet(product)
                                            : null,
                                      ),
                                    );
                                  },
                                  childCount: _products.length,
                                ),
                              ),
                  ],
                ),

                // PESTAÑA 2: INFORMACIÓN
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection('Horarios', Icons.access_time, _buildHoursWidget()),
                      const Divider(height: 32),
                      _buildInfoSection('Ubicación', Icons.location_on, Text(widget.restaurant.addressStructured?['address'] ?? 'No especificada')),
                      const Divider(height: 32),
                      _buildInfoSection('Cocina', Icons.restaurant, Text(widget.restaurant.cuisineType ?? 'Varia')),
                    ],
                  ),
                ),

                // PESTAÑA 3: RESEÑAS
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Aún no hay reseñas', style: TextStyle(color: Colors.grey, fontSize: 18)),
                      Text('¡Sé el primero en dejar una!', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (_isPreviewMode) _buildPreviewBanner(),
    ],
  ),
  floatingActionButton: _totalItems > 0 && !_isPreviewMode
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: FloatingActionButton.extended(
                onPressed: _hasActiveCouriers
                    ? () {
                        _showCartBottomSheet();
                      }
                    : null,
                backgroundColor: Theme.of(context).colorScheme.primary,
                icon: Badge(
                  label: Text(_totalItems.toString()),
                  child: const Icon(Icons.shopping_cart),
                ),
                label: Text(
                  'Ver carrito • \u{0024}${_totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildSocialIconsGrid() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.restaurant.facebookUrl != null)
          _buildSocialBtn(Icons.facebook, Colors.blue.shade800),
        if (widget.restaurant.instagramUrl != null)
          _buildSocialBtn(Icons.camera_alt, Colors.pink),
        if (widget.restaurant.websiteUrl != null)
          _buildSocialBtn(Icons.language, Colors.teal),
      ],
    );
  }

  Widget _buildSocialBtn(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildPreviewBanner() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE4007C), // Rosa Mexicano
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Row(
            children: [
              const Icon(Icons.visibility, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'MODO VISTA PREVIA (Dueño)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CERRAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    final coverUrl = _coverImageUrl;
    if (coverUrl == null || coverUrl.isEmpty) return _buildHeaderPlaceholder();

    return Image.network(
      coverUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildHeaderPlaceholder(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _buildHeaderPlaceholder();
      },
    );
  }

  Widget _buildHeaderPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
            Theme.of(context).colorScheme.secondary,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant,
          size: 72,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// Carga modifier_groups del producto (con caché por sesión)
  Future<List<DoaModifierGroup>> _getModifierGroups(String productId) async {
    if (_modifierGroupsCache.containsKey(productId)) {
      return _modifierGroupsCache[productId]!;
    }
    try {
      final data = await Supabase.instance.client
          .from('modifier_groups')
          .select('*, modifiers(*)')
          .eq('product_id', productId)
          .eq('is_active', true)
          .order('sort_order');
      final groups = (data as List)
          .map((g) => DoaModifierGroup.fromJson(g as Map<String, dynamic>))
          .toList();
      _modifierGroupsCache[productId] = groups;
      return groups;
    } catch (e) {
      debugPrint('⚠️ [RESTAURANT_DETAIL] Error cargando modificadores: $e');
      _modifierGroupsCache[productId] = [];
      return [];
    }
  }

  /// Muestra la hoja de personalización: si el producto tiene grupos estructurados
  /// los muestra primero; siempre termina con el campo de notas libre.
  Future<void> _showItemCustomizationSheet(DoaProduct product) async {
    final groups = await _getModifierGroups(product.id);

    if (!mounted) return;

    // Selecciones actuales (para pre-cargar si el usuario ya eligió antes)
    final currentSelections = List<ModifierSelection>.from(_itemModifiers[product.id] ?? []);
    final notesController = TextEditingController(text: _itemNotes[product.id] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItemCustomizationSheet(
        product: product,
        groups: groups,
        initialSelections: currentSelections,
        notesController: notesController,
        onConfirm: (selections, note) {
          setState(() {
            if (selections.isEmpty) {
              _itemModifiers.remove(product.id);
            } else {
              _itemModifiers[product.id] = selections;
            }
            if (note.isEmpty) {
              _itemNotes.remove(product.id);
            } else {
              _itemNotes[product.id] = note;
            }
          });
        },
      ),
    );
  }

  /// Mantiene compatibilidad con el CartBottomSheet que solo soporta notas texto
  void _showItemNotesSheet(DoaProduct product) {
    _showItemCustomizationSheet(product);
  }

  void _showCartBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CartBottomSheet(
        restaurant: widget.restaurant,
        cartItems: _cartVN.value,
        cartListenable: _cartVN,
        products: _products,
        canCheckout: _hasActiveCouriers,
        itemNotes: Map<String, String>.from(_itemNotes),
        itemModifiers: Map<String, List<ModifierSelection>>.from(_itemModifiers),
        onUpdateCart: (productId, quantity) {
          _updateCart(productId, quantity);
        },
        onUpdateItemNotes: (productId, notes) {
          setState(() {
            if (notes.isEmpty) {
              _itemNotes.remove(productId);
            } else {
              _itemNotes[productId] = notes;
            }
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    _couriersUpdatesSubscription?.cancel();
    _cartVN.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildInfoSection(String title, IconData icon, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        content,
      ],
    );
  }

  Widget _buildHoursWidget() {
    if (widget.restaurant.businessHours == null || widget.restaurant.businessHours!.isEmpty) {
      return const Text('Consultar directamente con el local');
    }
    
    return Column(
      children: widget.restaurant.businessHours!.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(entry.value.toString()),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final bool isHighlight;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isHighlight
            ? Theme.of(context).colorScheme.secondary.withOpacity(0.1)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: color ??
                (isHighlight
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7)),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color ??
                      (isHighlight
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.8)),
                  fontWeight: isHighlight ? FontWeight.w600 : null,
                ),
          ),
        ],
      ),
    );
  }
}

class ProductCard extends StatelessWidget {
  final DoaProduct product;
  final int quantity;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final bool orderingEnabled;
  // Optional map to resolve combo item names from product_id
  final Map<String, String>? productNameById;
  // Commission in basis points (1500 = 15%). Used to calculate client-facing price.
  final int commissionBps;
  // Per-item note (shown when set)
  final String? note;
  // Callback to open notes editor
  final VoidCallback? onNotesTap;

  const ProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.orderingEnabled = true,
    this.productNameById,
    this.commissionBps = 1500,
    this.note,
    this.onNotesTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen del producto
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: product.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildProductPlaceholder(context),
                      ),
                    )
                  : _buildProductPlaceholder(context),
            ),

            const SizedBox(width: 12),

            // Información del producto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título + badge de Combo (si aplica)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((product.isCombo) ||
                          ((product.type ?? '').toLowerCase() == 'combo'))
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_offer,
                                size: 14,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Combo',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.8),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  if (product.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Lista compacta de items del combo
                  if (((product.isCombo) || ((product.type ?? '').toLowerCase() == 'combo'))
                      && (product.contains != null && product.contains!.isNotEmpty)) ...[
                    const SizedBox(height: 6),
                    _ComboItemsInlineList(
                      items: product.contains!,
                      productNameById: productNameById,
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Nota del item (si existe)
                  if (quantity > 0 && (note != null && note!.isNotEmpty)) ...[
                    GestureDetector(
                      onTap: onNotesTap,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.edit_note, size: 14, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                note!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\$${product.price.toStringAsFixed(2)}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),

                      // Controles de cantidad
                      quantity == 0
                          ? ElevatedButton(
                              onPressed: orderingEnabled ? onAdd : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(80, 32),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: const Text('Agregar'),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onNotesTap != null)
                                  IconButton(
                                    onPressed: onNotesTap,
                                    icon: Icon(
                                      (note != null && note!.isNotEmpty)
                                          ? Icons.edit_note
                                          : Icons.note_add_outlined,
                                      size: 20,
                                    ),
                                    color: Theme.of(context).colorScheme.primary,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    tooltip: 'Instrucciones especiales',
                                  ),
                                IconButton(
                                  onPressed: orderingEnabled ? onRemove : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                  color: Theme.of(context).colorScheme.primary,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    quantity.toString(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: orderingEnabled ? onAdd : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                  color: Theme.of(context).colorScheme.primary,
                                  constraints: const BoxConstraints(
                                      minWidth: 32, minHeight: 32),
                                ),
                              ],
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

  Widget _buildProductPlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.restaurant_menu,
        size: 32,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
      ),
    );
  }
}

class _ComboItemsInlineList extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Map<String, String>? productNameById;

  const _ComboItemsInlineList({
    required this.items,
    this.productNameById,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final e in items) {
      final productId = e['product_id']?.toString() ?? '';
      final quantity = (e['quantity'] is int)
          ? e['quantity'] as int
          : int.tryParse('${e['quantity'] ?? '1'}') ?? 1;
      final name = productNameById?[productId] ?? '#${productId.isNotEmpty ? productId.substring(0, 6) : 'item'}';
      final label = quantity > 1 ? '$name x$quantity' : name;
      chips.add(Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
        ),
      ));
    }

    return Wrap(children: chips);
  }
}

class CartBottomSheet extends StatelessWidget {
  final DoaRestaurant restaurant;
  final Map<String, int> cartItems;
  final ValueListenable<Map<String, int>>? cartListenable;
  final List<DoaProduct> products;
  final Function(String, int) onUpdateCart;
  final bool canCheckout;
  final Map<String, String> itemNotes;
  final Map<String, List<ModifierSelection>> itemModifiers;
  final Function(String productId, String notes)? onUpdateItemNotes;

  const CartBottomSheet({
    super.key,
    required this.restaurant,
    required this.cartItems,
    this.cartListenable,
    required this.products,
    required this.onUpdateCart,
    this.canCheckout = true,
    this.itemNotes = const {},
    this.itemModifiers = const {},
    this.onUpdateItemNotes,
  });

  double _effectivePrice(String productId) {
    final product = products.firstWhere((p) => p.id == productId);
    final delta = (itemModifiers[productId] ?? []).fold(0.0, (s, m) => s + m.priceDelta);
    return product.price + delta;
  }

  double _computeTotal(Map<String, int> items) {
    return items.entries.fold(0.0, (sum, entry) {
      return sum + _effectivePrice(entry.key) * entry.value;
    });
  }

  double get _totalAmount => _computeTotal(cartListenable?.value ?? cartItems);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ValueListenableBuilder<Map<String, int>>(
              valueListenable: cartListenable ?? ValueNotifier(cartItems),
              builder: (context, _, __) {
                return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu pedido',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),

                const SizedBox(height: 16),

                // Lista de productos en el carrito
                ...(cartListenable?.value ?? cartItems).entries.map((entry) {
                  final product = products.firstWhere((p) => p.id == entry.key);
                  final quantity = entry.value;

                  final itemNote = itemNotes[product.id];
                  final mods = itemModifiers[product.id] ?? [];
                  final unitPrice = _effectivePrice(product.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '\$${unitPrice.toStringAsFixed(2)} c/u',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  if (mods.isNotEmpty)
                                    Text(
                                      mods.map((m) => m.name).join(', '),
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontStyle: FontStyle.italic,
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            // Controles de cantidad
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () => onUpdateCart(product.id, quantity - 1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(quantity.toString()),
                                ),
                                IconButton(
                                  onPressed: () => onUpdateCart(product.id, quantity + 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                ),
                              ],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '\$${(unitPrice * quantity).toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        // Nota del item
                        if (itemNote != null && itemNote.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              if (onUpdateItemNotes != null) {
                                _showCartItemNotesSheet(context, product, itemNote);
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.edit_note, size: 14, color: Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      itemNote,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontStyle: FontStyle.italic,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (onUpdateItemNotes != null)
                          GestureDetector(
                            onTap: () => _showCartItemNotesSheet(context, product, ''),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(Icons.note_add_outlined, size: 13, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Agregar nota',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),

                const Divider(),

                // Total
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '\$${_totalAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Botón de pedir
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canCheckout
                        ? () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => CheckoutScreen(
                                  restaurant: restaurant,
                                  cartItems: cartListenable?.value ?? cartItems,
                                  products: products,
                                  itemNotes: Map<String, String>.from(itemNotes),
                                  itemModifiers: Map<String, List<ModifierSelection>>.from(itemModifiers),
                                ),
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      canCheckout
                          ? 'Continuar con el pedido'
                          : 'No hay repartidores activos',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ),
              ],
            );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCartItemNotesSheet(BuildContext context, DoaProduct product, String currentNote) {
    final controller = TextEditingController(text: currentNote);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                product.name,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Instrucciones especiales',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: 'Ej: salsa BBQ, sin cebolla, extra picante...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (currentNote.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        onUpdateItemNotes?.call(product.id, '');
                        Navigator.pop(ctx);
                      },
                      child: const Text('Eliminar nota'),
                    )
                  else
                    const SizedBox.shrink(),
                  ElevatedButton(
                    onPressed: () {
                      onUpdateItemNotes?.call(product.id, controller.text.trim());
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Listo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ItemCustomizationSheet: Hoja de personalización estilo DoorDash
// Muestra grupos de modificadores (single/multiple) + campo de notas libre
// ─────────────────────────────────────────────────────────────────────────────

class _ItemCustomizationSheet extends StatefulWidget {
  final DoaProduct product;
  final List<DoaModifierGroup> groups;
  final List<ModifierSelection> initialSelections;
  final TextEditingController notesController;
  final void Function(List<ModifierSelection> selections, String note) onConfirm;

  const _ItemCustomizationSheet({
    required this.product,
    required this.groups,
    required this.initialSelections,
    required this.notesController,
    required this.onConfirm,
  });

  @override
  State<_ItemCustomizationSheet> createState() => _ItemCustomizationSheetState();
}

class _ItemCustomizationSheetState extends State<_ItemCustomizationSheet> {
  // Selecciones actuales: groupId → lista de ModifierSelection (para multiple) o una sola (single)
  late Map<String, List<ModifierSelection>> _selectionsByGroup;

  @override
  void initState() {
    super.initState();
    // Inicializar desde selecciones previas
    _selectionsByGroup = {};
    for (final sel in widget.initialSelections) {
      _selectionsByGroup.putIfAbsent(sel.groupId, () => []).add(sel);
    }
  }

  bool get _isValid {
    for (final group in widget.groups) {
      if (!group.isRequired) continue;
      final selected = _selectionsByGroup[group.id] ?? [];
      if (selected.isEmpty) return false;
    }
    return true;
  }

  void _toggleModifier(DoaModifierGroup group, DoaModifier modifier) {
    setState(() {
      final current = _selectionsByGroup[group.id] ?? [];
      final sel = ModifierSelection(
        modifierId: modifier.id,
        groupId: group.id,
        name: modifier.name,
        groupName: group.name,
        priceDelta: modifier.priceDelta,
      );

      if (group.isSingle) {
        // Single: siempre reemplazar
        _selectionsByGroup[group.id] = [sel];
      } else {
        // Multiple: toggle
        final exists = current.any((s) => s.modifierId == modifier.id);
        if (exists) {
          _selectionsByGroup[group.id] = current.where((s) => s.modifierId != modifier.id).toList();
        } else {
          if (current.length < group.maxSelections) {
            _selectionsByGroup[group.id] = [...current, sel];
          }
        }
      }
    });
  }

  bool _isSelected(String groupId, String modifierId) {
    return (_selectionsByGroup[groupId] ?? []).any((s) => s.modifierId == modifierId);
  }

  void _confirm() {
    final allSelections = _selectionsByGroup.values.expand((list) => list).toList();
    widget.onConfirm(allSelections, widget.notesController.text.trim());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título
                  Text(widget.product.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // Grupos de modificadores
                  ...widget.groups.map((group) => _buildGroup(group, cs)),

                  // Instrucciones especiales (texto libre, siempre al final)
                  const SizedBox(height: 8),
                  Text(
                    'Instrucciones especiales',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: widget.notesController,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Sin cebolla, extra picante...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          // Botón confirmar
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isValid ? _confirm : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
                ),
                child: Text(
                  _isValid ? 'Listo' : 'Selecciona las opciones obligatorias',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(DoaModifierGroup group, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(group.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (group.isRequired)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text('Obligatorio', style: TextStyle(fontSize: 10, color: cs.error, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        if (group.description != null && group.description!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(group.description!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
          ),
        const SizedBox(height: 8),
        ...group.modifiers.map((modifier) => _buildModifierRow(group, modifier, cs)),
        const Divider(height: 24),
      ],
    );
  }

  Widget _buildModifierRow(DoaModifierGroup group, DoaModifier modifier, ColorScheme cs) {
    final selected = _isSelected(group.id, modifier.id);
    return InkWell(
      onTap: () => _toggleModifier(group, modifier),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            if (group.isSingle)
              Icon(selected ? Icons.radio_button_on : Icons.radio_button_off, color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.4), size: 22)
            else
              Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.4), size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(modifier.name, style: Theme.of(context).textTheme.bodyMedium)),
            if (modifier.priceDelta > 0)
              Text('+\$${modifier.priceDelta.toStringAsFixed(2)}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600, fontSize: 13)),
            if (modifier.priceDelta == 0)
              Text('Gratis', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
