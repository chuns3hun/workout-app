// 웹 전용 입출력 (파일 다운로드 / 파일 선택)
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

void downloadFile(String content, String filename, String mime) {
  final blob = html.Blob([utf8.encode(content)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  Future.delayed(
      const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));
}

/// 사용자 탭 직후 동기적으로 호출해야 iOS Safari에서 파일 선택창이 열림.
Future<String?> pickTextFile() {
  final c = Completer<String?>();
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      c.complete(null);
      return;
    }
    final reader = html.FileReader()..readAsText(files.first);
    await reader.onLoad.first;
    c.complete(reader.result as String?);
  });
  input.click();
  return c.future;
}
