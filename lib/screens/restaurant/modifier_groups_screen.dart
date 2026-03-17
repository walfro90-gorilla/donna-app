import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/screens/restaurant/modifier_group_edit_screen.dart';

/// Pantalla que lista los modifier_groups de un producto y permite crear/editar/eliminar.
class ModifierGroupsScreen extends StatefulWidget {
  final String productId;
  final String productName;

  const ModifierGroupsScreen({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<ModifierGroupsScreen> createState() => _ModifierGroupsScreenState();
}

class _ModifierGroupsScreenState extends State<ModifierGroupsScreen> {
  final _client = Supabase.instance.client;
  List<DoaModifierGroup> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    try {
      final data = await _client
          .from('modifier_groups')
          .select('*, modifiers(*)')
          .eq('product_id', widget.productId)
          .eq('is_active', true)
          .order('sort_order');

      setState(() {
        _groups = (data as List)
            .map((g) => DoaModifierGroup.fromJson(g as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ [MODIFIER_GROUPS] Error cargando grupos: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteGroup(DoaModifierGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text('¿Eliminar "${group.name}" y todas sus opciones?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _client.from('modifier_groups').update({'is_active': false}).eq('id', group.id);
      await _loadGroups();
    } catch (e) {
      debugPrint('❌ [MODIFIER_GROUPS] Error eliminando grupo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _openGroupEdit([DoaModifierGroup? group]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ModifierGroupEditScreen(
          productId: widget.productId,
          group: group,
        ),
      ),
    );
    if (changed == true) await _loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personalización', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.productName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openGroupEdit(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo grupo'),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? _buildEmptyState(cs)
              : RefreshIndicator(
                  onRefresh: _loadGroups,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: _groups.length,
                    itemBuilder: (context, index) => _buildGroupCard(_groups[index]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.tune, size: 64, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('Sin grupos de opciones', style: TextStyle(fontSize: 18, color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Text(
            'Agrega grupos para que los clientes\npersonalicen su pedido',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(DoaModifierGroup group) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(
                group.isSingle ? Icons.radio_button_on : Icons.check_box,
                color: cs.primary,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (group.isRequired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Obligatorio', style: TextStyle(fontSize: 10, color: cs.error, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            subtitle: Text(
              group.isSingle ? 'Una opción' : 'Varias opciones (${group.minSelections}–${group.maxSelections})',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: () => _openGroupEdit(group), icon: const Icon(Icons.edit_outlined, size: 20)),
                IconButton(
                  onPressed: () => _deleteGroup(group),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: cs.error,
                ),
              ],
            ),
          ),
          if (group.modifiers.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: group.modifiers.map((m) {
                  return Chip(
                    label: Text(
                      m.priceDelta > 0 ? '${m.name}  +\$${m.priceDelta.toStringAsFixed(0)}' : m.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: cs.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
