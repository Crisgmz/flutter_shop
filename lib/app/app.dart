import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/settings/presentation/app_settings_providers.dart';
import '../shared/formatters/live_settings.dart';
import 'router.dart';

class ShopPlusApp extends ConsumerWidget {
  const ShopPlusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    // Sincronizar LiveSettings (cache que usan los formatters puros)
    // cada vez que cambia la configuración global. Esto hace que money(),
    // formatDate() y formatMoney() reaccionen automáticamente.
    final currentSettings = ref.watch(appSettingsProvider).valueOrNull;
    if (currentSettings != null) {
      LiveSettings.update(
        currencySymbol: currentSettings.currencySymbol,
        currencyDecimals: currentSettings.currencyDecimals,
        thousandsSep: currentSettings.currencyThousandsSep,
        decimalPoint: currentSettings.currencyDecimalPoint,
        dateFormat: currentSettings.appDateFormat,
        timeFormat: currentSettings.appTimeFormat,
      );
    }

    return MaterialApp.router(
      title: 'Busi Pos Web',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}
