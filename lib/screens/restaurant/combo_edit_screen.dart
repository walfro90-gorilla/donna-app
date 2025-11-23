import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/supabase/supabase_config.dart' as supa;
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ComboEditScreen extends StatefulWidget {
  final DoaRestaurant restaurant;
  final DoaProduct? comboProduct; // if editing existing combo, this is the product row
  final DoaCombo? combo; // optional combo metadata

  const ComboEditScreen({super.key, required this.restaurant, this.comboProduct, this.combo});

  @override
  State<ComboEditScreen> createState() => _ComboEditScreenState();
}

class _ComboEditScreenState extends State<ComboEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  bool _isAvailable = true;
  bool _saving = false;
  PlatformFile? _selectedImage;

  // products to compose
  List<DoaProduct> _allProducts = [];
  final Map<String, int> _selectedItems = {}; // productId -> quantity

  @override
  void initState() {
    super.initState();
    final p = widget.comboProduct;
    if (p != null) {
      _nameCtrl.text = p.name;
      _descCtrl.text = p.description ?? '';
      _priceCtrl.text = p.price.toStringAsFixed(2);
      _isAvailable = p.isAvailable;
    }
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      // Load all available products from this restaurant; we'll exclude combos locally
      final list = await supa.DoaRepartosService.getProductsByRestaurant(widget.restaurant.id, isAvailable: true);
      final products = list.map((e) => DoaProduct.fromJson(e)).where((p) => p.id != widget.comboProduct?.id).toList();
      // Mark combo flags if possible
      final comboIds = await supa.DoaRepartosService.getComboProductIdsByRestaurant(widget.restaurant.id);
      for (var i = 0; i < products.length; i++) {
        products[i] = DoaProduct(
          id: products[i].id,
          restaurantId: products[i].restaurantId,
          name: products[i].name,
          description: products[i].description,
          price: products[i].price,
          imageUrl: products[i].imageUrl,
          isAvailable: products[i].isAvailable,
          createdAt: products[i].createdAt,
          updatedAt: products[i].updatedAt,
          isCombo: comboIds.contains(products[i].id),
        );
      }
      if (mounted) setState(() => _allProducts = products.where((p) => !p.isCombo).toList());

      // Preload combo items if editing
      if (widget.combo != null) {
        for (final item in widget.combo!.items) {
          _selectedItems[item.productId] = item.quantity;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando productos: $e')),
        );
      }
    }
  }

  double get _componentsTotal {
    double sum = 0;
    for (final entry in _selectedItems.entries) {
      final p = _allProducts.firstWhere((e) => e.id == entry.key, orElse: () => DoaProduct(
        id: '', restaurantId: '', name: '', price: 0, isAvailable: true, createdAt: DateTime.now(), updatedAt: DateTime.now()));
      sum += p.price * entry.value;
    }
    return sum;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Validar mínimo 2 y máximo 9 unidades totales
    final totalUnits = _selectedItems.values.fold<int>(0, (a, b) => a + b);
    if (totalUnits < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El combo debe tener mínimo 2 unidades')));
      return;
    }
    if (totalUnits > 9) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El combo admite máximo 9 unidades')));
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl = widget.comboProduct?.imageUrl;
      if (_selectedImage != null) {
        imageUrl = await StorageService.uploadProductImage(widget.restaurant.id, _selectedImage!);
      }

      final productPayload = {
        'restaurant_id': widget.restaurant.id,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'image_url': imageUrl,
        'is_available': _isAvailable,
        'type': 'combo',
        'updated_at': DateTime.now().toIso8601String(),
        if (widget.comboProduct == null) 'created_at': DateTime.now().toIso8601String(),
      };

      // Items se envía por separado - la RPC calculará 'contains' automáticamente
      final items = _selectedItems.entries
          .map((e) => {'product_id': e.key, 'quantity': e.value})
          .toList();

      await supa.DoaRepartosService.upsertCombo(
        productId: widget.comboProduct?.id,
        product: productPayload,
        items: items,
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error guardando combo: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.comboProduct != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar combo' : 'Nuevo combo'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ImageUploadField(
              label: 'Imagen del Combo',
              hint: 'Toca para subir foto',
              icon: Icons.camera_alt,
              imageUrl: widget.comboProduct?.imageUrl,
              isRequired: false,
              onImageSelected: (file) => setState(() => _selectedImage = file),
              helpText: 'Una imagen clara del combo ayuda a vender',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del combo *',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Precio del combo *',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0 ? null : 'Precio inválido',
                  ),
                ),
                const SizedBox(width: 12),
                _summaryChip(),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _isAvailable,
              onChanged: (v) => setState(() => _isAvailable = v),
              title: const Text('Combo disponible'),
              subtitle: Text(_isAvailable ? 'Aparecerá en el menú' : 'Oculto para clientes'),
            ),
            const SizedBox(height: 8),
            Text('Componentes del combo', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_allProducts.isEmpty)
              const Text('Aún no tienes productos simples disponibles'),
            for (final p in _allProducts)
              _productSelectorTile(p),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(isEdit ? 'Guardar cambios' : 'Crear combo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productSelectorTile(DoaProduct p) {
    final qty = _selectedItems[p.id] ?? 0;
    final selected = qty > 0;
    return ListTile(
      leading: p.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(p.imageUrl!, width: 44, height: 44, fit: BoxFit.cover),
            )
          : const CircleAvatar(child: Icon(Icons.fastfood)),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('\$${p.price.toStringAsFixed(2)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                if (_selectedItems.containsKey(p.id)) {
                  _selectedItems[p.id] = (qty - 1).clamp(0, 999);
                  if (_selectedItems[p.id] == 0) _selectedItems.remove(p.id);
                }
              });
            },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? Colors.orange.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(qty.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: () {
              // Respetar máximo 9 unidades totales
              final totalUnits = _selectedItems.values.fold<int>(0, (a, b) => a + b);
              if (totalUnits >= 9) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 9 unidades por combo')));
                return;
              }
              setState(() {
                _selectedItems[p.id] = qty + 1;
              });
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip() {
    final total = _componentsTotal;
    final price = double.tryParse(_priceCtrl.text) ?? 0;
    final diff = price - total;
    final color = diff >= 0 ? Colors.green : Colors.red;
    return Tooltip(
      message: 'Suma componentes: \$${total.toStringAsFixed(2)}\nDiferencia vs precio: \$${diff.toStringAsFixed(2)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Componentes', style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
            Text('\$${total.toStringAsFixed(2)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
