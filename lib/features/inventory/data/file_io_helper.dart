import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileIoHelper {
  /// Guarda bytes con un diálogo nativo de "Guardar como" (desktop/web) o
  /// dispara compartir (mobile).
  ///
  /// `extension` sin el punto (ej: 'xlsx', 'pdf', 'csv', 'txt'). Si el
  /// usuario no agrega la extensión en el diálogo, la añadimos.
  static Future<bool> saveBytes({
    required Uint8List bytes,
    required String fileName,
    String dialogTitle = 'Guardar archivo',
    String extension = 'xlsx',
  }) async {
    final allowed = <String>[extension];

    if (kIsWeb) {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: allowed,
      );
      return result != null;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes, flush: true);
      final result = await Share.shareXFiles(
        [XFile(tempFile.path, name: fileName)],
        subject: fileName,
      );
      return result.status == ShareResultStatus.success ||
          result.status == ShareResultStatus.unavailable;
    }

    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowed,
    );
    if (path == null) return false;
    final dotExt = '.$extension';
    final fixed = path.toLowerCase().endsWith(dotExt) ? path : '$path$dotExt';
    await File(fixed).writeAsBytes(bytes, flush: true);
    return true;
  }

  static Future<Uint8List?> pickXlsxBytes() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null) return null;
    return File(path).readAsBytes();
  }
}
