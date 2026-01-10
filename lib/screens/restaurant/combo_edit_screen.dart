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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Editar Combo' : 'Nuevo Combo'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Section
              Center(
                child: ImageUploadField(
                  label: 'Imagen del Combo',
                  hint: 'Toca para subir foto',
                  icon: Icons.add_a_photo_outlined,
                  imageUrl: widget.comboProduct?.imageUrl,
                  isRequired: false,
                  onImageSelected: (file) => setState(() => _selectedImage = file),
                  helpText: 'Una imagen clara ayuda a vender más',
                ),
              ),
              const SizedBox(height: 32),

              // Info Section
              _buildSectionTitle('Información General'),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _nameCtrl,
                decoration: _buildInputDecoration('Nombre del combo', Icons.drive_file_rename_outline),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descCtrl,
                maxLines: 1,
                decoration: _buildInputDecoration('Descripción (opcional)', Icons.description_outlined),
              ),
              const SizedBox(height: 16),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      decoration: _buildInputDecoration('Precio del combo', Icons.payments_outlined).copyWith(
                        prefixText: r'$ ',
                        prefixStyle: TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => (double.tryParse((v ?? '').trim()) ?? 0) > 0 ? null : 'Precio inválido',
                      onChanged: (_) => setState(() {}), // Update summary chip
                    ),
                  ),
                  const SizedBox(width: 12),
                  _summaryChip(),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Availability Switch
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withValues(alpha: isDark ? 0.3 : 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isAvailable,
                  onChanged: (v) => setState(() => _isAvailable = v),
                  title: const Text('Combo disponible', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _isAvailable ? 'Aparecerá en el menú' : 'Oculto para clientes',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                  activeColor: theme.colorScheme.primary,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Components Section
              _buildSectionTitle('Componentes del Combo'),
              const SizedBox(height: 8),
              Text(
                'Selecciona entre 2 y 9 unidades totales para armar este combo.',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              
              if (_allProducts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text('No hay productos simples disponibles', style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ..._allProducts.map((p) => _productSelectorTile(p)),
                
              const SizedBox(height: 40),
              
              // Save Button
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isEdit ? 'GUARDAR CAMBIOS' : 'CREAR COMBO',
                        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 22),
      filled: true,
      fillColor: theme.colorScheme.surfaceVariant.withValues(alpha: isDark ? 0.2 : 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
      labelStyle: TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        fontSize: 14,
      ),
    );
  }

  Widget _productSelectorTile(DoaProduct p) {
    final theme = Theme.of(context);
    final qty = _selectedItems[p.id] ?? 0;
    final isSelected = qty > 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSelected 
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : theme.colorScheme.surfaceVariant.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected 
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: p.imageUrl != null
              ? Image.network(p.imageUrl!, width: 50, height: 50, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildPlaceholder())
              : _buildPlaceholder(),
        ),
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          r'$' + p.price.toStringAsFixed(0),
          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
        ),
        trailing: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 18),
                onPressed: qty > 0 ? () {
                  setState(() {
                    _selectedItems[p.id] = qty - 1;
                    if (_selectedItems[p.id] == 0) _selectedItems.remove(p.id);
                  });
                } : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  qty.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                onPressed: () {
                  final totalUnits = _selectedItems.values.fold<int>(0, (a, b) => a + b);
                  if (totalUnits >= 9) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 9 unidades por combo')));
                    return;
                  }
                  setState(() => _selectedItems[p.id] = qty + 1);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 50,
      height: 50,
      color: Colors.grey.withValues(alpha: 0.1),
      child: const Icon(Icons.fastfood_outlined, color: Colors.grey, size: 24),
    );
  }

  Widget _summaryChip() {
    final theme = Theme.of(context);
    final total = _componentsTotal;
    final priceStr = _priceCtrl.text.replaceAll(',', '.');
    final price = double.tryParse(priceStr) ?? 0;
    final diff = price - total;
    final isSaving = price < total && price > 0;
    
    final color = isSaving ? Colors.green : (price > 0 ? Colors.orange : Colors.grey);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            isSaving ? 'Ahorro: \$${(total - price).toStringAsFixed(0)}' : 'Suma base',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10),
          ),
          Text(
            r'$' + total.toStringAsFixed(0),
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

