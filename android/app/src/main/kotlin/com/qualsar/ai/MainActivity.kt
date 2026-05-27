package com.qualsar.ai

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth (parmak izi / Face Unlock) — FlutterActivity yerine
// FlutterFragmentActivity gerekir. FlutterActivity ile çağrı yapıldığında
// `Type of biometric prompt cannot be cast to FragmentActivity` hatası alır.
class MainActivity : FlutterFragmentActivity()
