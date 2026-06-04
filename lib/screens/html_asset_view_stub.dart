// Web dışı platformlar (Android/iOS/masaüstü) için yer tutucu.
// Bu dosya yalnızca derleme zamanı koşullu import ile seçilir; çalışma
// zamanında kIsWeb=false olduğundan htmlAssetView ASLA çağrılmaz.
import 'package:flutter/widgets.dart';

Widget htmlAssetView(String url) => const SizedBox.shrink();
