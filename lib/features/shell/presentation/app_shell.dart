import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/extensions/iterable_extensions.dart';
import '../../../shared/responsive/responsive.dart';
import '../../../shared/widgets/app_page_layout.dart';
import '../../auth/presentation/auth_providers.dart';
import 'shell_nav_items.dart';
import 'shell_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).matchedLocation;
    final authRepository = ref.read(authRepositoryProvider);
    final branchesAsync = ref.watch(shellBranchOptionsProvider);
    final branchNameAsync = ref.watch(shellCurrentBranchNameProvider);
    final userAsync = ref.watch(shellUserInfoProvider);
    final accessAsync = ref.watch(shellAccessProfileProvider);
    final branches = branchesAsync.valueOrNull ?? const <ShellBranchOption>[];
    final branchName = branchNameAsync.valueOrNull ?? 'Sucursal principal';
    final userInfo = userAsync.valueOrNull;
    final effectiveRoleLabel =
        accessAsync.valueOrNull?.roleLabel ?? userInfo?.roleLabel;
    final visibleNavItemsAsync = ref.watch(shellVisibleNavItemsProvider);
    final visibleNavSectionsAsync = ref.watch(shellVisibleNavSectionsProvider);
    final visibleNavItems = visibleNavItemsAsync.valueOrNull ?? navItems;
    final visibleNavSections =
        visibleNavSectionsAsync.valueOrNull ?? navSections;
    final showSidebar = context.showDesktopSidebar;

    Future<void> signOut() async {
      await authRepository.signOut();
    }

    Future<void> selectBranch(String branchId) async {
      if (branchId.isEmpty) return;
      final messenger = ScaffoldMessenger.of(context);
      final current = branches.where((item) => item.isDefault).firstOrNull;
      if (current?.branchId == branchId) return;

      try {
        final client = ref.read(supabaseClientProvider);
        await client.rpc(
          'set_current_branch',
          params: {'target_branch_id': branchId},
        );
        invalidateBranchScopedData(ref);
        messenger.showSnackBar(
          const SnackBar(content: Text('Sucursal actualizada')),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo cambiar sucursal: $error')),
        );
      }
    }

    final currentNavItem =
        visibleNavItems.where((item) => item.path == currentPath).firstOrNull ??
        navItems.where((item) => item.path == currentPath).firstOrNull;
    final isCurrentPathVisible =
        currentPath == '/panel' ||
        visibleNavItems.any((item) => item.path == currentPath);
    final layoutMode = appPageLayoutModeForPath(currentPath);

    return Scaffold(
      drawer: showSidebar
          ? null
          : _MobileMenuDrawer(
              currentPath: currentPath,
              navSections: visibleNavSections,
              onNavigate: (path) {
                context.go(path);
                Navigator.of(context).pop();
              },
              onSignOut: signOut,
            ),
      body: Row(
        children: [
          if (showSidebar)
            _DesktopSidebar(
              currentPath: currentPath,
              navSections: visibleNavSections,
              onNavigate: context.go,
              onSignOut: signOut,
            ),
          Expanded(
            child: Scaffold(
              appBar: _TopBar(
                title: currentNavItem?.label ?? 'Shop+',
                currentPath: currentPath,
                branchName: branchName,
                branchOptions: branches,
                userInfo: userInfo,
                effectiveRoleLabel: effectiveRoleLabel,
                navSections: visibleNavSections,
                onSelectBranch: selectBranch,
                onSignOut: signOut,
              ),
              body: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: AppTokens.contentGradient,
                ),
                child: SafeArea(
                  top: false,
                  child: AppPageLayout(
                    mode: layoutMode,
                    child: isCurrentPathVisible
                        ? child
                        : _RoleRestrictedView(
                            onGoHome: () => context.go('/panel'),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget implements PreferredSizeWidget {
  const _TopBar({
    required this.title,
    required this.currentPath,
    required this.branchName,
    required this.branchOptions,
    required this.userInfo,
    required this.effectiveRoleLabel,
    required this.navSections,
    required this.onSelectBranch,
    required this.onSignOut,
  });

  final String title;
  final String currentPath;
  final String branchName;
  final List<ShellBranchOption> branchOptions;
  final ShellUserInfo? userInfo;
  final String? effectiveRoleLabel;
  final List<NavSection> navSections;
  final Future<void> Function(String branchId) onSelectBranch;
  final Future<void> Function() onSignOut;

  @override
  Size get preferredSize => const Size.fromHeight(64); // Slightly taller for more breathing room

  @override
  Widget build(BuildContext context) {
    final isMobile = !context.showDesktopSidebar;
    
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: AppTokens.foreground,
      surfaceTintColor: Colors.white,
      automaticallyImplyLeading: isMobile,
      centerTitle: false,
      title: Row(
        children: [
          if (!isMobile) ...[
            // Subtle indicator of where we are if needed, or just spacers
            const SizedBox(width: AppTokens.s8),
          ],
          const Spacer(),
          // Branch Selector
          _BranchSelector(
            currentBranchName: branchName,
            options: branchOptions,
            onSelect: onSelectBranch,
          ),
          const SizedBox(width: AppTokens.s16),
          // User Profile
          _UserProfileMenu(
            userInfo: userInfo,
            effectiveRoleLabel: effectiveRoleLabel,
            onSignOut: onSignOut,
          ),
          const SizedBox(width: AppTokens.s8),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xFFF1F5F9)),
      ),
    );
  }
}

class _BranchSelector extends StatelessWidget {
  const _BranchSelector({
    required this.currentBranchName,
    required this.options,
    required this.onSelect,
  });

  final String currentBranchName;
  final List<ShellBranchOption> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelect,
      tooltip: 'Cambiar sucursal',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => options.map((b) => PopupMenuItem(
        value: b.branchId,
        child: Row(
          children: [
            Icon(b.isDefault ? Icons.check_circle : Icons.storefront, size: 18, color: b.isDefault ? AppTokens.primary : AppTokens.mutedForeground),
            const SizedBox(width: 12),
            Text(b.name, style: TextStyle(fontWeight: b.isDefault ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      )).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apartment_rounded, size: 18, color: Color(0xFF64748B)),
            const SizedBox(width: 8),
            Text(
              currentBranchName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }
}

class _UserProfileMenu extends StatelessWidget {
  const _UserProfileMenu({
    required this.userInfo,
    required this.effectiveRoleLabel,
    required this.onSignOut,
  });

  final ShellUserInfo? userInfo;
  final String? effectiveRoleLabel;
  final VoidCallback onSignOut;

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = userInfo?.displayName ?? '';
    final roleLabel = effectiveRoleLabel ?? userInfo?.roleLabel ?? '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              name.isEmpty ? 'Usuario' : name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
            ),
            if (roleLabel.isNotEmpty)
              Text(
                roleLabel,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            color: Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: name.isEmpty
                ? const Icon(Icons.person_rounded, color: Colors.white, size: 20)
                : Text(
                    _initials(name),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onSignOut,
          icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFF94A3B8)),
          tooltip: 'Cerrar sesión',
        ),
      ],
    );
  }
}


class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.currentPath,
    required this.navSections,
    required this.onNavigate,
    required this.onSignOut,
  });

  final String currentPath;
  final List<NavSection> navSections;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppTokens.sidebarWidth,
      decoration: const BoxDecoration(gradient: AppTokens.sidebarGradient),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s22,
                AppTokens.s16,
                AppTokens.s18,
                AppTokens.s16,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    color: Colors.white,
                    size: AppTokens.iconSizeL,
                  ),
                  const SizedBox(width: AppTokens.s10),
                  const Text(
                    'Shop+',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.s10,
                      vertical: AppTokens.s6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.sidebarOverlay,
                      borderRadius: BorderRadius.circular(AppTokens.s14),
                    ),
                    child: const Text(
                      'Shell v1',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTokens.sidebarDivider, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppTokens.s12),
                children: [
                  for (final section in navSections) ...[
                    _SidebarSectionLabel(label: section.label),
                    const SizedBox(height: AppTokens.s6),
                    for (final item in section.items)
                      _SidebarItem(
                        icon: item.icon,
                        label: item.label,
                        selected: item.path == currentPath,
                        onTap: () => onNavigate(item.path),
                      ),
                    const SizedBox(height: AppTokens.s12),
                  ],
                ],
              ),
            ),
            const Divider(color: AppTokens.sidebarDivider, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.s12,
                AppTokens.s10,
                AppTokens.s12,
                AppTokens.s12,
              ),
              child: _SidebarItem(
                icon: Icons.logout,
                label: 'Salir',
                selected: false,
                onTap: () => onSignOut(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMenuDrawer extends StatelessWidget {
  const _MobileMenuDrawer({
    required this.currentPath,
    required this.navSections,
    required this.onNavigate,
    required this.onSignOut,
  });

  final String currentPath;
  final List<NavSection> navSections;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(280.0, 320.0).toDouble(),
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTokens.sidebarGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s16,
                  AppTokens.s12,
                  AppTokens.s12,
                  AppTokens.s12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, color: Colors.white),
                    const SizedBox(width: AppTokens.s8),
                    const Expanded(
                      child: Text(
                        'Shop+ RD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar menú',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppTokens.sidebarDivider, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.s8,
                    AppTokens.s12,
                    AppTokens.s8,
                    AppTokens.s12,
                  ),
                  children: [
                    for (final section in navSections) ...[
                      _SidebarSectionLabel(label: section.label),
                      const SizedBox(height: AppTokens.s6),
                      for (final item in section.items)
                        _SidebarItem(
                          icon: item.icon,
                          label: item.label,
                          selected: item.path == currentPath,
                          onTap: () => onNavigate(item.path),
                        ),
                      const SizedBox(height: AppTokens.s12),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.s8,
                  0,
                  AppTokens.s8,
                  AppTokens.s12,
                ),
                child: _SidebarItem(
                  icon: Icons.logout,
                  label: 'Salir',
                  selected: false,
                  onTap: () => onSignOut(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s14,
        AppTokens.s10,
        AppTokens.s14,
        AppTokens.s4,
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Color(0xCFFFFFFF),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _RoleRestrictedView extends StatelessWidget {
  const _RoleRestrictedView({required this.onGoHome});

  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE8EC),
                      borderRadius: BorderRadius.circular(AppTokens.radiusL),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppTokens.error,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s16),
                  Text(
                    'Acceso restringido para este rol',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTokens.s8),
                  Text(
                    'La navegación ya oculta este módulo según el rol activo. Usa el panel para continuar con acciones permitidas.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s16),
                  FilledButton.icon(
                    onPressed: onGoHome,
                    icon: const Icon(Icons.grid_view_rounded),
                    label: const Text('Volver al panel'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      child: Material(
        color: selected ? AppTokens.sidebarItemSelected : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s14,
              vertical: AppTokens.s12,
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: AppTokens.iconSizeM),
                const SizedBox(width: AppTokens.s12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
