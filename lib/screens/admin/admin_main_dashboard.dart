import 'package:flutter/material.dart';
import 'package:doa_repartos/screens/admin/simple_admin_dashboard.dart';
import 'package:doa_repartos/screens/admin/restaurants_management_screen.dart';
import 'package:doa_repartos/screens/admin/delivery_agents_management_screen.dart';
import 'package:doa_repartos/screens/admin/clients_management_screen.dart';
import 'package:doa_repartos/screens/admin/orders_monitor_screen.dart';
import 'package:doa_repartos/core/theme/app_theme_controller.dart';
import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/screens/auth/login_screen.dart';

/// Admin shell with a persistent bottom navigation bar
/// Hosts top-level admin areas as tabs so navigation feels consistent
class AdminMainDashboard extends StatefulWidget {
  const AdminMainDashboard({super.key});

  @override
  State<AdminMainDashboard> createState() => _AdminMainDashboardState();
}

class _AdminMainDashboardState extends State<AdminMainDashboard> {
  int _index = 0;

  late final List<Widget> _pages = const [
    // Each page manages its own AppBar and content
    SimpleAdminDashboard(),
    OrdersMonitorScreen(),
    RestaurantsManagementScreen(),
    DeliveryAgentsManagementScreen(),
    ClientsManagementScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Keep outer Scaffold minimal so inner pages can use their own AppBar
    final bool useRail = MediaQuery.of(context).size.width >= 1200;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppThemeController.themeMode,
            builder: (_, mode, __) => IconButton(
              icon: Icon(mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
              tooltip: mode == ThemeMode.dark ? 'Modo Claro' : 'Modo Oscuro',
              onPressed: AppThemeController.toggle,
            ),
          ),
          // Reubicados: Centro de notificaciones y Mi sesión (solo iconos)
          IconButton(
            tooltip: 'Centro de notificaciones',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DeliveryAgentsManagementScreen(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                try {
                  await SessionManager.instance.signOut();
                } catch (_) {}
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false, // allow child app bars to control status bar spacing
        child: Row(
          children: [
            if (useRail) ...[
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.selected,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard),
                    label: Text('Inicio'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: Text('Pedidos'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.store_outlined),
                    selectedIcon: Icon(Icons.store),
                    label: Text('Restaurantes'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.delivery_dining),
                    selectedIcon: Icon(Icons.delivery_dining),
                    label: Text('Repartidores'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: Text('Clientes'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: IndexedStack(
                index: _index,
                children: _pages,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: 'Inicio',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: 'Pedidos',
                ),
                NavigationDestination(
                  icon: Icon(Icons.store_outlined),
                  selectedIcon: Icon(Icons.store),
                  label: 'Restaurantes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.delivery_dining),
                  selectedIcon: Icon(Icons.delivery_dining),
                  label: 'Repartidores',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Clientes',
                ),
              ],
            ),
    );
  }
}
