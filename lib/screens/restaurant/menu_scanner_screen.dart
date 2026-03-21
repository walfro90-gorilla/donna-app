import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Pantalla para escanear el menú físico del restaurante con IA (GPT-4o).
/// Detecta platillos, los clasifica por tipo, y propone grupos de modificadores
/// (extras, término de cocción, tamaños, etc.) para que el restaurante revise.
class MenuScannerScreen extends StatefulWidget {
  final String restaurantId;

  const MenuScannerScreen({super.key, required this.restaurantId});

  @override
  State<MenuScannerScreen> createState() => _MenuScannerScreenState();
}

class _MenuScannerScreenState extends State<MenuScannerScreen> {
  static const double _commissionRate = 0.15;

  _ScanPhase _phase = _ScanPhase.selection;
  PlatformFile? _selectedFile;
  List<_DetectedProduct> _detectedProducts = [];
  String? _errorMessage;

  // ─── Fase 1: Selección ────────────────────────────────────────────────────

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _phase = _ScanPhase.processing;
        _errorMessage = null;
      });
      await _analyzeMenu(_selectedFile!);
    }
  }

  // ─── Fase 2: Llamada al Edge Function ────────────────────────────────────

  Future<void> _analyzeMenu(PlatformFile file) async {
    try {
      final bytes = file.bytes;
      if (bytes == null) throw Exception('No se pudieron leer los bytes de la imagen');

      final response = await SupabaseConfig.client.functions.invoke(
        'analyze-menu-image',
        body: {
          'image_base64': base64Encode(bytes),
          'media_type': _resolveMediaType(file.name),
        },
      );

      if (response.status != 200) throw Exception('Error del servidor: ${response.status}');

      final data = response.data as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Error desconocido al analizar el menú');
      }

      final rawProducts = data['products'] as List<dynamic>;
      if (rawProducts.isEmpty) {
        throw Exception('No se detectaron platillos en la imagen. Intenta con una foto más clara.');
      }

      setState(() {
        _detectedProducts = rawProducts
            .map((p) => _DetectedProduct.fromJson(p as Map<String, dynamic>))
            .toList();
        _phase = _ScanPhase.review;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _phase = _ScanPhase.error;
      });
    }
  }

  String _resolveMediaType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  // ─── Fase 3: Insertar productos + modifier_groups + modifiers ─────────────

  Future<void> _insertSelectedProducts() async {
    final toInsert = _detectedProducts.where((p) => p.selected).toList();
    if (toInsert.isEmpty) return;

    setState(() => _phase = _ScanPhase.saving);

    try {
      for (final product in toInsert) {
        // 1. INSERT product → obtener ID
        final inserted = await SupabaseConfig.client
            .from('products')
            .insert({
              'restaurant_id': widget.restaurantId,
              'name': product.nameController.text.trim(),
              'description': product.descriptionController.text.trim(),
              'price': product.kitchenPrice,
              'type': product.type,
              'is_available': true,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();

        final productId = inserted['id'] as String;

        // 2. INSERT modifier_groups + modifiers (tolerante — si falla no revierte el producto)
        if (product.hasModifiers && product.modifierGroups.isNotEmpty) {
          int groupOrder = 0;
          for (final group in product.modifierGroups) {
            if (!group.enabled) continue;
            final enabledMods = group.modifiers.where((m) => m.enabled).toList();
            if (enabledMods.isEmpty) continue;

            try {
              final groupInserted = await SupabaseConfig.client
                  .from('modifier_groups')
                  .insert({
                    'product_id': productId,
                    'name': group.nameController.text.trim(),
                    'selection_type': group.selectionType,
                    'min_selections': group.minSelections,
                    'max_selections': group.maxSelections,
                    'is_required': group.isRequired,
                    'sort_order': groupOrder++,
                  })
                  .select('id')
                  .single();

              final groupId = groupInserted['id'] as String;

              int modOrder = 0;
              for (final mod in enabledMods) {
                final modName = mod.nameController.text.trim();
                if (modName.isEmpty) continue;
                await SupabaseConfig.client.from('modifiers').insert({
                  'group_id': groupId,
                  'name': modName,
                  'price_delta': mod.priceDelta,
                  'sort_order': modOrder++,
                });
              }
            } catch (modError) {
              debugPrint('⚠️ [SCANNER] Modifier group save failed (non-critical): $modError');
            }
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${toInsert.length} producto${toInsert.length == 1 ? '' : 's'} agregado${toInsert.length == 1 ? '' : 's'} al menú'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al guardar: $e';
        _phase = _ScanPhase.review;
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Menú con IA'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: switch (_phase) {
        _ScanPhase.selection => _buildSelectionPhase(),
        _ScanPhase.processing => _buildProcessingPhase(),
        _ScanPhase.review => _buildReviewPhase(),
        _ScanPhase.saving => _buildSavingPhase(),
        _ScanPhase.error => _buildErrorPhase(),
      },
    );
  }

  // ── Fase 1: Selección ─────────────────────────────────────────────────────

  Widget _buildSelectionPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.purple, size: 64),
            ),
            const SizedBox(height: 24),
            Text(
              'Escanear Menú con IA',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Sube una foto de tu carta física. La IA detecta platillos, precios y opciones extra automáticamente.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Los precios detectados son del menú físico. La app aplica automáticamente la comisión del 15%.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Seleccionar imagen del menú'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Formatos: JPG, PNG • Máx. 5 MB',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Fase 2: Procesando ────────────────────────────────────────────────────

  Widget _buildProcessingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_selectedFile?.bytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(_selectedFile!.bytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Colors.purple),
            const SizedBox(height: 16),
            Text('Analizando menú con IA...', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('GPT-4o está identificando platillos, tipos y opciones extra', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Fase 3: Revisión ──────────────────────────────────────────────────────

  Widget _buildReviewPhase() {
    final selected = _detectedProducts.where((p) => p.selected).toList();
    final totalKitchen = selected.fold(0.0, (sum, p) => sum + p.kitchenPrice);
    final totalApp = selected.fold(0.0, (sum, p) => sum + p.appPrice);
    final withModifiers = _detectedProducts.where((p) => p.hasModifiers).length;

    return Column(
      children: [
        // ── Banner resumen superior ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.purple.withValues(alpha: 0.08),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.purple, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  withModifiers > 0
                      ? '${_detectedProducts.length} platillos detectados — $withModifiers con opciones extra'
                      : '${_detectedProducts.length} platillos detectados — revisa y edita antes de guardar',
                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.purple, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        // ── Banner explicativo de comisión ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.orange.withValues(alpha: 0.06),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                    children: const [
                      TextSpan(text: 'Ingresa el '),
                      TextSpan(text: 'precio de tu menú físico', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: '. La app calcula automáticamente el '),
                      TextSpan(text: 'precio final al cliente (+15% comisión)', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: '.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Lista de productos ──
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            itemCount: _detectedProducts.length,
            itemBuilder: (context, index) => _buildProductCard(_detectedProducts[index]),
          ),
        ),

        // ── Barra inferior con totales + botón ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(child: _buildTotalChip(label: 'Total cocina', amount: totalKitchen, color: Colors.grey[700]!, icon: Icons.storefront)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTotalChip(label: 'Total en app', amount: totalApp, color: Colors.purple, icon: Icons.phone_android)),
                    ],
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selected.isNotEmpty ? _insertSelectedProducts : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    selected.isNotEmpty
                        ? 'Agregar ${selected.length} producto${selected.length == 1 ? '' : 's'} al menú'
                        : 'Selecciona al menos 1 producto',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTotalChip({required String label, required double amount, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
                Text('\$${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tarjeta de producto ───────────────────────────────────────────────────

  Widget _buildProductCard(_DetectedProduct product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: product.selected ? 2 : 0.5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: product.selected ? Colors.purple.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
            width: product.selected ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Fila: checkbox + nombre + tipo ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: product.selected,
                    activeColor: Colors.purple,
                    onChanged: (v) => setState(() => product.selected = v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Expanded(
                    child: TextField(
                      controller: product.nameController,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: product.selected ? null : Colors.grey,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Nombre del platillo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: product.type,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'principal', child: Text('Principal', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'bebida', child: Text('Bebida', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'postre', child: Text('Postre', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'entrada', child: Text('Entrada', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'combo', child: Text('Combo', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) => setState(() => product.type = v ?? 'principal'),
                    ),
                  ),
                ],
              ),

              // ── Breakdown de precio ──
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 10),
                child: _buildPriceBreakdown(product, isDark),
              ),

              // ── Descripción ──
              if (product.descriptionController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 48, top: 8),
                  child: TextField(
                    controller: product.descriptionController,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),

              // ── Opciones / Modifier groups ──
              if (product.hasModifiers && product.modifierGroups.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 48, top: 8),
                  child: _buildModifierGroupsSection(product),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceBreakdown(_DetectedProduct product, bool isDark) {
    final kitchenPrice = product.kitchenPrice;
    final commission = product.commissionAmount;
    final appPrice = product.appPrice;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: 15, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Expanded(child: Text('Precio en tu menú:', style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: product.kitchenPriceController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: const InputDecoration(
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.add_circle_outline, size: 15, color: Colors.orange[700]),
              const SizedBox(width: 6),
              Expanded(child: Text('Comisión plataforma (15%):', style: TextStyle(fontSize: 12, color: Colors.orange[700]))),
              Text(
                kitchenPrice > 0 ? '+ \$${commission.toStringAsFixed(2)}' : '—',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange[700]),
              ),
            ],
          ),
          Divider(height: 14, color: Colors.purple.withValues(alpha: 0.3)),
          Row(
            children: [
              const Icon(Icons.phone_android, size: 15, color: Colors.purple),
              const SizedBox(width: 6),
              const Expanded(child: Text('Precio al cliente (en app):', style: TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w600))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  kitchenPrice > 0 ? '\$${appPrice.toStringAsFixed(2)}' : '—',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Modifier groups section ───────────────────────────────────────────────

  Widget _buildModifierGroupsSection(_DetectedProduct product) {
    final enabledCount = product.modifierGroups.where((g) => g.enabled).length;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: Icon(Icons.tune, color: enabledCount > 0 ? Colors.purple : Colors.grey, size: 18),
        title: Text(
          'Opciones detectadas ($enabledCount activa${enabledCount == 1 ? '' : 's'})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: enabledCount > 0 ? Colors.purple : Colors.grey,
          ),
        ),
        children: product.modifierGroups.map((group) => _buildModifierGroupCard(group)).toList(),
      ),
    );
  }

  Widget _buildModifierGroupCard(_ScannedModifierGroup group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeLabel = group.selectionType == 'single' ? 'único' : 'múltiple';
    final reqLabel = group.isRequired ? 'requerido' : 'opcional';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: group.enabled ? Colors.purple.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header del grupo
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: group.nameController,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Nombre del grupo'),
                    enabled: group.enabled,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('$typeLabel · $reqLabel', style: const TextStyle(fontSize: 10, color: Colors.purple)),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.75,
                  child: Switch(
                    value: group.enabled,
                    activeColor: Colors.purple,
                    onChanged: (v) => setState(() => group.enabled = v),
                  ),
                ),
              ],
            ),
          ),
          // Lista de modifiers
          if (group.enabled) ...[
            const Divider(height: 1),
            ...group.modifiers.map((mod) => _buildModifierRow(mod)),
            TextButton.icon(
              onPressed: () => setState(() => group.modifiers.add(_ScannedModifier(name: '', priceDelta: 0))),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Agregar opción', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModifierRow(_ScannedModifier mod) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Checkbox(
              value: mod.enabled,
              activeColor: Colors.purple,
              onChanged: (v) => setState(() => mod.enabled = v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            child: TextField(
              controller: mod.nameController,
              style: TextStyle(fontSize: 12, color: mod.enabled ? null : Colors.grey),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none, hintText: 'Nombre de la opción'),
              enabled: mod.enabled,
            ),
          ),
          SizedBox(
            width: 72,
            child: TextField(
              controller: mod.priceDeltaController,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: mod.priceDelta > 0 ? Colors.orange[700] : Colors.grey[600]),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                prefixText: mod.priceDelta > 0 ? '+\$' : '\$',
              ),
              enabled: mod.enabled,
            ),
          ),
        ],
      ),
    );
  }

  // ── Guardando ─────────────────────────────────────────────────────────────

  Widget _buildSavingPhase() {
    final count = _detectedProducts.where((p) => p.selected).length;
    final modGroupCount = _detectedProducts
        .where((p) => p.selected && p.hasModifiers)
        .expand((p) => p.modifierGroups.where((g) => g.enabled))
        .length;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.purple),
          const SizedBox(height: 16),
          Text('Guardando $count producto${count == 1 ? '' : 's'}...', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          if (modGroupCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('con $modGroupCount grupo${modGroupCount == 1 ? '' : 's'} de opciones', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────

  Widget _buildErrorPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text('No se pudo analizar el menú', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Error desconocido', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red[700]), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _phase = _ScanPhase.selection;
                _selectedFile = null;
                _errorMessage = null;
              }),
              icon: const Icon(Icons.refresh),
              label: const Text('Intentar con otra imagen'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Modelos internos ──────────────────────────────────────────────────────

enum _ScanPhase { selection, processing, review, saving, error }

class _DetectedProduct {
  static const double _commissionRate = 0.15;

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController kitchenPriceController;
  String type;
  bool selected;
  bool hasModifiers;
  final List<_ScannedModifierGroup> modifierGroups;

  _DetectedProduct({
    required String name,
    required String description,
    required double kitchenPrice,
    required this.type,
    this.selected = true,
    this.hasModifiers = false,
    List<_ScannedModifierGroup>? modifierGroups,
  })  : nameController = TextEditingController(text: name),
        descriptionController = TextEditingController(text: description),
        kitchenPriceController = TextEditingController(
          text: kitchenPrice > 0 ? kitchenPrice.toStringAsFixed(2) : '',
        ),
        modifierGroups = modifierGroups ?? [];

  double get kitchenPrice => double.tryParse(kitchenPriceController.text) ?? 0.0;
  double get commissionAmount => kitchenPrice * _commissionRate;
  double get appPrice => kitchenPrice * (1 + _commissionRate);

  factory _DetectedProduct.fromJson(Map<String, dynamic> json) {
    const validTypes = {'principal', 'bebida', 'postre', 'entrada', 'combo'};
    final rawType = (json['type'] as String? ?? 'principal').toLowerCase();
    final hasModifiers = json['has_modifiers'] as bool? ?? false;
    final rawGroups = json['modifier_groups'] as List<dynamic>? ?? [];
    return _DetectedProduct(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      kitchenPrice: (json['price'] as num?)?.toDouble() ?? 0.0,
      type: validTypes.contains(rawType) ? rawType : 'principal',
      hasModifiers: hasModifiers,
      modifierGroups: rawGroups
          .map((g) => _ScannedModifierGroup.fromJson(g as Map<String, dynamic>))
          .toList(),
    );
  }
}

class _ScannedModifierGroup {
  final TextEditingController nameController;
  final String selectionType;
  final int minSelections;
  final int maxSelections;
  final bool isRequired;
  bool enabled;
  final List<_ScannedModifier> modifiers;

  _ScannedModifierGroup({
    required String name,
    required this.selectionType,
    required this.minSelections,
    required this.maxSelections,
    required this.isRequired,
    this.enabled = true,
    required this.modifiers,
  }) : nameController = TextEditingController(text: name);

  factory _ScannedModifierGroup.fromJson(Map<String, dynamic> j) =>
      _ScannedModifierGroup(
        name: j['name'] as String? ?? '',
        selectionType: j['selection_type'] as String? ?? 'single',
        minSelections: (j['min_selections'] as num?)?.toInt() ?? 0,
        maxSelections: (j['max_selections'] as num?)?.toInt() ?? 1,
        isRequired: j['is_required'] as bool? ?? false,
        modifiers: (j['modifier_groups'] as List<dynamic>? ?? j['modifiers'] as List<dynamic>? ?? [])
            .map((m) => _ScannedModifier.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class _ScannedModifier {
  final TextEditingController nameController;
  final TextEditingController priceDeltaController;
  bool enabled;

  _ScannedModifier({
    required String name,
    required double priceDelta,
    this.enabled = true,
  })  : nameController = TextEditingController(text: name),
        priceDeltaController = TextEditingController(
          text: priceDelta > 0 ? priceDelta.toStringAsFixed(0) : '0',
        );

  double get priceDelta => double.tryParse(priceDeltaController.text) ?? 0.0;

  factory _ScannedModifier.fromJson(Map<String, dynamic> j) => _ScannedModifier(
        name: j['name'] as String? ?? '',
        priceDelta: (j['price_delta'] as num?)?.toDouble() ?? 0.0,
      );
}
