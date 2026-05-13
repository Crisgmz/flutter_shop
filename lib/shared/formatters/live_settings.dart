// LiveSettings: cache estática mutable que las funciones de formato puras
// (sin Riverpod) leen para presentar moneda y fechas según `app_settings`.
//
// Por qué no usamos Riverpod aquí:
//   - 17+ archivos llaman `money(...)`, `formatDate(...)`, `formatMoney(...)`.
//   - Migrar todos a `Consumer` rompe ergonomía (formateo en helpers no-build,
//     en Builders, en repositorios).
//   - Solución: `LiveSettings` es un singleton mutable. Un `Consumer` único en
//     `ShopPlusApp` sincroniza este cache cuando cambia `appSettingsProvider`.
//   - Las funciones de formato leen los campos estáticos sin overhead.
//
// Reactividad UI: tras `LiveSettings.update(...)`, los widgets que usen
// formatters sólo re-rinden si el ancestro Consumer que dispara el update
// también escucha el cambio (lo cual ocurre porque `appSettingsProvider`
// notifica a sus listeners). Es decir: el árbol entero re-construye con
// los nuevos valores en pantalla.

class LiveSettings {
  LiveSettings._();

  /// Símbolo de moneda. Default: RD$.
  static String currencySymbol = r'RD$';

  /// Cantidad de decimales. Default: 2.
  static int currencyDecimals = 2;

  /// Separador de miles (1 char). Default: ','.
  static String thousandsSep = ',';

  /// Punto decimal (1 char). Default: '.'.
  static String decimalPoint = '.';

  /// Formato de fecha. Default: dd-MM-yyyy. Acepta:
  /// 'dd-MM-yyyy', 'dd/MM/yyyy', 'MM-dd-yyyy', 'yyyy-MM-dd'.
  static String dateFormat = 'dd/MM/yyyy';

  /// Formato de hora: '12h' | '24h'. Default: '12h'.
  static String timeFormat = '12h';

  static void update({
    String? currencySymbol,
    int? currencyDecimals,
    String? thousandsSep,
    String? decimalPoint,
    String? dateFormat,
    String? timeFormat,
  }) {
    if (currencySymbol != null) LiveSettings.currencySymbol = currencySymbol;
    if (currencyDecimals != null) LiveSettings.currencyDecimals = currencyDecimals;
    if (thousandsSep != null) LiveSettings.thousandsSep = thousandsSep;
    if (decimalPoint != null) LiveSettings.decimalPoint = decimalPoint;
    if (dateFormat != null) LiveSettings.dateFormat = dateFormat;
    if (timeFormat != null) LiveSettings.timeFormat = timeFormat;
  }
}
