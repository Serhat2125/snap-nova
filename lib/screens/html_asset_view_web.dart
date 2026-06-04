// Web platformu: HTML asset'ini <iframe> içinde gösterir.
// webview_flutter web'de desteklenmediği için 3D dersler (Three.js HTML)
// web hedefinde iframe ile yüklenir. Flutter web asset'leri kök altında
// `assets/<assetKey>` yolundan sunar; relative `./three.global.js` vb.
// referanslar iframe içinde doğru çözülür.
//
// Bu dosya yalnızca web hedefinde koşullu import ile derlenir; bu yüzden
// dart:html / dart:ui_web kullanımı kasıtlıdır (lint'ler beklenen).
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;

import 'package:flutter/widgets.dart';

final Set<String> _registered = <String>{};

Widget htmlAssetView(String url) {
  final viewType = 'qualsar-3d-iframe::$url';
  if (!_registered.contains(viewType)) {
    _registered.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..allow = 'fullscreen; accelerometer; gyroscope; magnetometer';
      return iframe;
    });
  }
  return HtmlElementView(viewType: viewType);
}
