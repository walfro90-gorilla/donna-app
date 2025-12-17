import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/admin/client_detail_admin_screen.dart';
import 'package:doa_repartos/screens/admin/delivery_agent_detail_admin_screen.dart';
import 'package:doa_repartos/screens/admin/restaurant_detail_admin_screen.dart';
import 'package:doa_repartos/models/doa_models.dart';

class AdminGlobalSearchDelegate extends SearchDelegate {
  @override
  String get searchFieldLabel => 'Buscar ID, Nombre, Email...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().length < 3) {
      return const Center(child: Text('Ingresa al menos 3 caracteres'));
    }
    return FutureBuilder(
      future: _performSearch(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final results = snapshot.data as List<_SearchResult>;
        if (results.isEmpty) {
          return const Center(child: Text('No se encontraron resultados'));
        }
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final item = results[index];
            return ListTile(
              leading: Icon(item.icon, color: item.color),
              title: Text(item.title),
              subtitle: Text(item.subtitle),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => item.onTap(context),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(); // No suggestions for now
  }

  Future<List<_SearchResult>> _performSearch(String q) async {
    final List<_SearchResult> results = [];
    final term = '%$q%';

    // 1. Search Users (Clients & Agents)
    final users = await SupabaseConfig.client
        .from('users')
        .select()
        .or('name.ilike.$term,email.ilike.$term,phone.ilike.$term,id.eq.$q')
        .limit(10);
    
    for (final u in users) {
      final role = u['role'] ?? 'unknown';
      final isAgent = role == 'delivery_agent';
      results.add(_SearchResult(
        title: u['name'] ?? u['email'] ?? 'Usuario',
        subtitle: '${role.toUpperCase()} • ${u['email']}',
        icon: isAgent ? Icons.delivery_dining : Icons.person,
        color: isAgent ? Colors.green : Colors.blue,
        onTap: (ctx) {
          final userObj = DoaUser.fromJson(u);
          if (isAgent) {
             Navigator.push(ctx, MaterialPageRoute(builder: (_) => AdminDeliveryAgentDetailScreen(agent: userObj)));
          } else {
             Navigator.push(ctx, MaterialPageRoute(builder: (_) => AdminClientDetailScreen(client: userObj)));
          }
        },
      ));
    }

    // 2. Search Restaurants
    final rests = await SupabaseConfig.client
        .from('restaurants')
        .select()
        .ilike('name', term)
        .limit(10);
    
    for (final r in rests) {
      results.add(_SearchResult(
        title: r['name'] ?? 'Restaurante',
        subtitle: 'ID: ${r['id']}',
        icon: Icons.store,
        color: Colors.orange,
        onTap: (ctx) {
           final restObj = DoaRestaurant.fromJson(r);
           Navigator.push(ctx, MaterialPageRoute(builder: (_) => AdminRestaurantDetailScreen(restaurant: restObj)));
        },
      ));
    }

    // 3. Search Orders (by ID mainly)
    if (q.length > 5) {
       final orders = await SupabaseConfig.client
          .from('orders')
          .select()
          .ilike('id', term)
          .limit(5);
       
       for (final o in orders) {
         results.add(_SearchResult(
           title: 'Orden #${o['id'].toString().substring(0,8)}',
           subtitle: 'Status: ${o['status']} • \$${o['total_amount']}',
           icon: Icons.receipt,
           color: Colors.purple,
           onTap: (ctx) {
             // For now just show a snackbar or navigate if we had a dedicated standalone Order Detail screen
             // But we usually view orders inside User/Restaurant. 
             // Ideally we'd have a AdminOrderDetailScreen. 
             // For this scope, let's just show raw data or find parent.
             ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Navegación a Detalle de Orden directa pendiente')));
           },
         ));
       }
    }

    return results;
  }
}

class _SearchResult {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Function(BuildContext) onTap;

  _SearchResult({required this.title, required this.subtitle, required this.icon, required this.color, required this.onTap});
}
