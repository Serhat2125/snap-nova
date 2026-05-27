import 'package:flutter/material.dart';

/// Bir konu için 3D model tanımı (hücre, güneş sistemi, yer şekilleri gibi).
///
/// `glbUrl` model_viewer_plus'a verilen kaynak adresi — public CDN URL veya
/// `assets/3d/...glb` lokal asset olabilir. İlk versiyonda placeholder URL'ler
/// kullanılıyor; gerçek modeller hazır olduğunda Firebase Storage URL'i veya
/// asset path'i konacak.
class Topic3DModel {
  final String id;
  final String name;
  final String subject;
  final String description;
  final String glbUrl;
  final List<Topic3DPart> parts;
  final String? animationName;
  final bool hasCrossSection;
  final String? compareWithId;

  const Topic3DModel({
    required this.id,
    required this.name,
    required this.subject,
    required this.description,
    required this.glbUrl,
    required this.parts,
    this.animationName,
    this.hasCrossSection = false,
    this.compareWithId,
  });
}

/// Modelin üzerindeki bir parça — hücre çekirdeği, atom çekirdeği, dağ vb.
///
/// `hotspotPosition` ve `hotspotNormal` model_viewer_plus'ın slot mekanizmasıyla
/// kullanılır ("x y z" formatı, modelin 3D uzayında). Gerçek modeller hazır
/// olunca Blender / model-viewer editor ile kalibre edilecek; şu an placeholder.
class Topic3DPart {
  final String id;
  final String name;
  final String info;
  final String hotspotPosition;
  final String hotspotNormal;
  final Color color;

  const Topic3DPart({
    required this.id,
    required this.name,
    required this.info,
    this.hotspotPosition = '0m 0m 0m',
    this.hotspotNormal = '0 1 0',
    this.color = Colors.blueAccent,
  });
}
