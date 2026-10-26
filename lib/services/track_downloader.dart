import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/model/track.dart';
import '../data/repository/ng_repository.dart';

class TrackDownloader {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36';
  static final _repo = NgRepository();

  static Future<void> download(Track track, BuildContext context) async {
    var url = track.mp3Url;
    if (url == null || url.isEmpty) {
      try {
        await _repo.enrichTrack(track);
        url = track.mp3Url;
      } catch (_) {}
    }
    if (url == null || url.isEmpty) {
      if (context.mounted) {
        _snack(context, 'Не удалось получить ссылку на трек', isError: true);
      }
      return;
    }

    final filename = _sanitize('${track.artist} - ${track.title}.mp3');

    try {
      if (!context.mounted) return;
      _snack(context, 'Скачивание…');
      final res = await http.get(Uri.parse(url),
          headers: {'User-Agent': _ua}).timeout(const Duration(minutes: 5));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить трек',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['mp3'],
        bytes: res.bodyBytes,
      );

      // The user cancelled the system save dialog.
      if (savedPath == null) return;

      if (context.mounted) {
        _snack(context, 'Сохранено: $filename');
      }
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Ошибка скачивания: $e', isError: true);
      }
    }
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');

  static void _snack(BuildContext context, String msg,
      {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade800 : null,
      duration: Duration(seconds: isError ? 4 : 2),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
