import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Pantalla para crear o editar un modifier_group y sus opciones (modifiers).
/// Permite configurar nombre, tipo (single/multiple), si es obligatorio, y las opciones.
class ModifierGroupEditScreen extends StatefulWidget {
  final String productId;
  final String restaurantId;
  final DoaModifierGroup? group; // null = crear nuevo

  const ModifierGroupEditScreen({
    super.key,
    required this.productId,
    required this.restaurantId,
    this.group,
  });

  @override
  State<ModifierGroupEditScreen> createState() => _ModifierGroupEditScreenState();
}

class _ModifierGroupEditScreenState extends State<ModifierGroupEditScreen> {
  final _client = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _selectionType = 'single';
  bool _isRequired = false;
  int _minSelections = 0;
  int _maxSelections = 1;
  bool _isSaving = false;

  // Lista editable de opciones (modifiers)
  final List<_ModifierDraft> _modifiers = [];

  bool get _isEditing => widget.group != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final g = widget.group!;
      _nameCtrl.text = g.name;
      _descCtrl.text = g.description ?? '';
      _selectionType = g.selectionType;
      _isRequired = g.isRequired;
      _minSelections = g.minSelections;
      _maxSelections = g.maxSelections;
      for (final m in g.modifiers) {
        _modifiers.add(_ModifierDraft(
          id: m.id,
          nameCtrl: TextEditingController(text: m.name),
          priceDelta: m.priceDelta,
          isAvailable: m.isAvailable,
          sortOrder: m.sortOrder,
        ));
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final m in _modifiers) {
      m.nameCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('El nombre del grupo es obligatorio');
      return;
    }
    if (_modifiers.isEmpty) {
      _showSnack('Agrega al menos una opción');
      return;
    }
    for (final m in _modifiers) {
      if (m.nameCtrl.text.trim().isEmpty) {
        _showSnack('Todas las opciones deben tener nombre');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      // 1. Upsert del grupo (incluye restaurant_id y registra en product_modifier_groups)
      final groupResult = await _client.rpc('upsert_modifier_group', params: {
        'p_id': _isEditing ? widget.group!.id : null,
        'p_product_id': widget.productId,
        'p_restaurant_id': widget.restaurantId,
        'p_name': name,
        'p_description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        'p_selection_type': _selectionType,
        'p_min_selections': _selectionType == 'single' ? 1 : _minSelections,
        'p_max_selections': _selectionType == 'single' ? 1 : _maxSelections,
        'p_is_required': _isRequired,
        'p_sort_order': 0,
      });

      if (groupResult == null || groupResult['success'] != true) {
        throw Exception(groupResult?['error'] ?? 'Error guardando grupo');
      }

      final groupId = groupResult['id'] as String;

      // 2. Upsert de cada modifier
      for (int i = 0; i < _modifiers.length; i++) {
        final m = _modifiers[i];
        final modResult = await _client.rpc('upsert_modifier', params: {
          'p_id': m.id,
          'p_group_id': groupId,
          'p_name': m.nameCtrl.text.trim(),
          'p_description': null,
          'p_price_delta': m.priceDelta,
          'p_is_available': m.isAvailable,
          'p_sort_order': i,
        });
        if (modResult == null || modResult['success'] != true) {
          throw Exception(modResult?['error'] ?? 'Error guardando opción');
        }
      }

      // 3. Eliminar modifiers marcados para borrar
      for (final id in _deletedModifierIds) {
        await _client.from('modifiers').delete().eq('id', id);
      }

      if (mounted) {
        Navigator.pop(context, true); // true = hubo cambios
      }
    } catch (e) {
      debugPrint('❌ [MODIFIER_GROUP_EDIT] Error: $e');
      if (mounted) _showSnack('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  final List<String> _deletedModifierIds = [];

  void _addModifier() {
    setState(() {
      _modifiers.add(_ModifierDraft(
        id: null,
        nameCtrl: TextEditingController(),
        priceDelta: 0.0,
        isAvailable: true,
        sortOrder: _modifiers.length,
      ));
    });
  }

  void _removeModifier(int index) {
    final m = _modifiers[index];
    if (m.id != null) _deletedModifierIds.add(m.id!);
    setState(() => _modifiers.removeAt(index));
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar grupo' : 'Nuevo grupo de opciones'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Nombre del grupo ──────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del grupo *',
              hintText: 'Ej: Elige tu salsa',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          // ── Tipo de selección ─────────────────────────────────────────────
          Text('Tipo de selección', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'single', label: Text('Una opción'), icon: Icon(Icons.radio_button_on)),
              ButtonSegment(value: 'multiple', label: Text('Varias'), icon: Icon(Icons.check_box)),
            ],
            selected: {_selectionType},
            onSelectionChanged: (val) => setState(() {
              _selectionType = val.first;
              if (_selectionType == 'single') {
                _minSelections = 0;
                _maxSelections = 1;
              }
            }),
          ),
          const SizedBox(height: 16),

          if (_selectionType == 'multiple') ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mínimo', border: OutlineInputBorder()),
                    onChanged: (v) => _minSelections = int.tryParse(v) ?? 0,
                    controller: TextEditingController(text: _minSelections.toString()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Máximo', border: OutlineInputBorder()),
                    onChanged: (v) => _maxSelections = int.tryParse(v) ?? 1,
                    controller: TextEditingController(text: _maxSelections.toString()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Obligatorio ───────────────────────────────────────────────────
          SwitchListTile(
            title: const Text('Selección obligatoria'),
            subtitle: const Text('El cliente debe elegir antes de ordenar'),
            value: _isRequired,
            onChanged: (v) => setState(() => _isRequired = v),
            activeColor: cs.primary,
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(height: 32),

          // ── Opciones (modifiers) ──────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Opciones', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _addModifier,
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_modifiers.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Sin opciones aún. Toca "Agregar" para añadir.', textAlign: TextAlign.center),
            ),
          ..._modifiers.asMap().entries.map((entry) {
            final index = entry.key;
            final m = entry.value;
            return _ModifierRow(
              draft: m,
              onDelete: () => _removeModifier(index),
              onPriceChanged: (v) => setState(() => m.priceDelta = v),
              onAvailableChanged: (v) => setState(() => m.isAvailable = v),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _ModifierDraft {
  String? id;
  final TextEditingController nameCtrl;
  double priceDelta;
  bool isAvailable;
  int sortOrder;

  _ModifierDraft({
    required this.id,
    required this.nameCtrl,
    required this.priceDelta,
    required this.isAvailable,
    required this.sortOrder,
  });
}

class _ModifierRow extends StatelessWidget {
  final _ModifierDraft draft;
  final VoidCallback onDelete;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<bool> onAvailableChanged;

  const _ModifierRow({
    required this.draft,
    required this.onDelete,
    required this.onPriceChanged,
    required this.onAvailableChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: draft.nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Nombre (ej: BBQ)',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '+\$0',
                  border: InputBorder.none,
                  prefixText: '\$',
                ),
                controller: TextEditingController(
                  text: draft.priceDelta == 0 ? '' : draft.priceDelta.toStringAsFixed(2),
                ),
                onChanged: (v) => onPriceChanged(double.tryParse(v) ?? 0.0),
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Theme.of(context).colorScheme.error,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          ],
        ),
      ),
    );
  }
}
