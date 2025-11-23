import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  List<DoaProduct> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'Todos';

  // Carrito temporal (reactivo para bottom sheet)
  final ValueNotifier<Map<String, int>> _cartVN = ValueNotifier(<String, int>{});
  bool _hasActiveCouriers = true;
  StreamSubscription<void>? _couriersUpdatesSubscription;

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
    _loadProducts();
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

  double get _totalAmount {
    return _cartVN.value.entries.fold(0.0, (sum, entry) {
      final product = _products.firstWhere((p) => p.id == entry.key);
      return sum + (product.price * entry.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Header con imagen
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: widget.restaurant.imageUrl != null
                  ? Image.network(
                      widget.restaurant.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildHeaderPlaceholder(),
                    )
                  : _buildHeaderPlaceholder(),
            ),
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.favorite_outline, color: Colors.white),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Favoritos próximamente')),
                    );
                  },
                ),
              ),
            ],
          ),

          // Información del restaurante
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.restaurant.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      if (widget.restaurant.rating != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star,
                                size: 18,
                                color: Theme.of(context).colorScheme.tertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.restaurant.rating!.toStringAsFixed(1),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  if (widget.restaurant.description != null)
                    Text(
                      widget.restaurant.description!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),

                  const SizedBox(height: 16),

                  // Info de entrega
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.access_time,
                        label:
                            '${widget.restaurant.deliveryTime ?? 30}-${(widget.restaurant.deliveryTime ?? 30) + 15} min',
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.delivery_dining,
                        label: widget.restaurant.deliveryFee != null &&
                                widget.restaurant.deliveryFee! > 0
                            ? '\\\$${widget.restaurant.deliveryFee!.toStringAsFixed(0)}'
                            : 'Gratis',
                        isHighlight: widget.restaurant.deliveryFee == null ||
                            widget.restaurant.deliveryFee! == 0,
                      ),
                      const SizedBox(width: 12),
                      _InfoChip(
                        icon: Icons.circle,
                        label: widget.restaurant.isOpen ? 'Abierto' : 'Cerrado',
                        color: widget.restaurant.isOpen
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.error,
                      ),
                    ],
                  ),
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
                    color: Theme.of(context).colorScheme.surfaceVariant,
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

          // Filtros de categorías
          SliverToBoxAdapter(
            child: SizedBox(
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final isSelected = _selectedCategory == category;

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilterChip(
                      label: Text(category),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = category;
                        });
                      },
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      selectedColor:
                          Theme.of(context).colorScheme.primaryContainer,
                    ),
                  );
                },
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Lista de productos
          _isLoading
              ? const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              : _products.isEmpty
                  ? SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.restaurant_menu,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No hay productos disponibles',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = _products[index];
                          // Mapa de id -> nombre para resolver los nombres de items del combo
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
                              onAdd: _hasActiveCouriers
                                  ? () => _addToCart(product.id)
                                  : null,
                              onRemove: _hasActiveCouriers
                                  ? () => _removeFromCart(product.id)
                                  : null,
                              productNameById: productNameById,
                            ),
                          );
                        },
                        childCount: _products.length,
                      ),
                    ),
        ],
      ),

      // Botón flotante del carrito
      floatingActionButton: _totalItems > 0
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
                  'Ver carrito • \\\$${_totalAmount.toStringAsFixed(2)}',
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

  Widget _buildHeaderPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.restaurant,
            size: 80,
            color: Colors.white.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 16),
          Text(
            widget.restaurant.name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
        onUpdateCart: (productId, quantity) {
          _updateCart(productId, quantity);
        },
      ),
    );
  }

  @override
  void dispose() {
    _couriersUpdatesSubscription?.cancel();
    _cartVN.dispose();
    super.dispose();
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
            ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1)
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
                              .withValues(alpha: 0.8)),
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

  const ProductCard({
    super.key,
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    this.orderingEnabled = true,
    this.productNameById,
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
                                          .withValues(alpha: 0.8),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\\\$${product.price.toStringAsFixed(2)}',
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

  const CartBottomSheet({
    super.key,
    required this.restaurant,
    required this.cartItems,
    this.cartListenable,
    required this.products,
    required this.onUpdateCart,
    this.canCheckout = true,
  });

  double _computeTotal(Map<String, int> items) {
    return items.entries.fold(0.0, (sum, entry) {
      final product = products.firstWhere((p) => p.id == entry.key);
      return sum + (product.price * entry.value);
    });
  }

  double get _totalAmount => _computeTotal(cartListenable?.value ?? cartItems);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              color: Colors.grey[300],
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

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
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
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              Text(
                                '\\\$${product.price.toStringAsFixed(2)} c/u',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),

                        // Controles de cantidad
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  onUpdateCart(product.id, quantity - 1),
                              icon: const Icon(Icons.remove_circle_outline),
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(quantity.toString()),
                            ),
                            IconButton(
                              onPressed: () =>
                                  onUpdateCart(product.id, quantity + 1),
                              icon: const Icon(Icons.add_circle_outline),
                              constraints: const BoxConstraints(
                                  minWidth: 32, minHeight: 32),
                            ),
                          ],
                        ),

                        const SizedBox(width: 8),

                        Text(
                          '\\\$${(product.price * quantity).toStringAsFixed(2)}',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
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
                      '\\\$${_totalAmount.toStringAsFixed(2)}',
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
                            // Navigate to checkout screen
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => CheckoutScreen(
                                  restaurant: restaurant,
                                  cartItems: cartListenable?.value ?? cartItems,
                                  products: products,
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
}
