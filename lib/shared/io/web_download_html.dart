// Implementación web: dispara una descarga creando un <a download> con
// un Object URL. Es el patrón estándar en navegadores cuando el usuario
// generó bytes en memoria (PDF / XLSX exportados).

// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

bool downloadBytesInBrowser({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
  return true;
}
