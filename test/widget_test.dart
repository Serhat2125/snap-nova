import 'package:flutter/material.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:math_expressions/math_expressions.dart' hide Stack;

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { cameras = await availableCameras(); } catch (e) { print('Kamera hatası: $e'); }
  runApp(const SnapNovaApp());
}

class SnapNovaApp extends StatelessWidget {
  const SnapNovaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, title: 'SnapNova', theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0F172A)), home: const MainScreen());
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSingleMode = true;
  bool _isFlashOn = false;
  bool _photoTaken = false;
  String _selectedAI = "";
  File? _selectedImage;

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }

  void _takePhoto() { setState(() { _photoTaken = true; }); }

  void _goBack() { if (_currentPage > 0) { _pageController.previousPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut); } }

  Future<void> _pickImageFromGallery() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) { setState(() { _selectedImage = File(image.path); _photoTaken = true; }); }
    } catch (e) { print('Galeri hatası: $e'); }
  }

  void _openCalculator() { Navigator.push(context, MaterialPageRoute(builder: (context) => const CalculatorScreen())); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: PageView(controller: _pageController, onPageChanged: (index) => setState(() => _currentPage = index), physics: const BouncingScrollPhysics(), children: [_buildFirstPage(), _buildSecondPage(), _buildCameraPage()])));
  }

  Widget _buildFirstPage() {
    final List<Map<String, String>> questions = [
      {'subject': 'Matematik', 'question': 'x² + 5x + 6 = 0 denkleminin köklerini bulunuz.', 'solution': 'x² + 5x + 6 = (x + 2)(x + 3) = 0\nx + 2 = 0 → x = -2\nx + 3 = 0 → x = -3', 'explanation': 'Çarpanlarına ayırma yöntemiyle kökler -2 ve -3 bulunur.'},
      {'subject': 'Fizik', 'question': '10 kg kütleli bir cisme 50 N kuvvet uygulanıyor. İvmesi kaç m/s² olur?', 'solution': 'Newton\'un 2. yasası: F = m·a\na = F/m = 50/10 = 5 m/s²', 'explanation': 'Kuvvet arttıkça ivme artar, kütle arttıkça ivme azalır.'},
      {'subject': 'Kimya', 'question': 'H₂ + O₂ → H₂O tepkimesini denkleştiriniz.', 'solution': 'Adım 1: Oksijen için sağ tarafa 2H₂O yaz.\nAdım 2: Hidrojen dengesi için sol tarafa 2H₂ ekle.\nSonuç: 2H₂ + O₂ → 2H₂O', 'explanation': 'Atom sayıları korunur: 4 H, 2 O her iki tarafta.'},
      {'subject': 'Biyoloji', 'question': 'Fotosentezin temel denklemini yazınız.', 'solution': '6CO₂ + 6H₂O → C₆H₁₂O₆ + 6O₂', 'explanation': 'Karbondioksit ve su, ışık enerjisiyle glikoz ve oksijene dönüşür.'},
    ];
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 450), child: Padding(padding: const EdgeInsets.all(20.0), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 48), SizedBox(width: 8), Text("SnapNova", style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: Colors.cyanAccent))]), const SizedBox(height: 6), const Text("Her soruyu anında çözer.", style: TextStyle(fontSize: 16, color: Colors.white70)), const SizedBox(height: 20), Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))), child: ListView.separated(itemCount: questions.length, separatorBuilder: (context, index) => const Divider(color: Colors.white24, thickness: 0.5), itemBuilder: (context, index) { final q = questions[index]; return _AnimatedQuestion(question: q); }))), const SizedBox(height: 12), GestureDetector(onTap: () => _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut), child: Container(width: double.infinity, height: 52, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]), borderRadius: BorderRadius.circular(20)), child: const Center(child: Text("Başla", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))))), const SizedBox(height: 16), Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (index) => AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 5), height: 4, width: _currentPage == index ? 32 : 14, decoration: BoxDecoration(color: _currentPage == index ? Colors.cyanAccent : Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(10)))))]))));
  }

  Widget _buildSecondPage() {
    final List<Map<String, dynamic>> subjects = [
      {'icon': Icons.calculate, 'name': 'Matematik', 'color': Colors.cyanAccent}, {'icon': Icons.science, 'name': 'Fizik', 'color': Colors.blueAccent}, {'icon': Icons.biotech, 'name': 'Kimya', 'color': Colors.tealAccent}, {'icon': Icons.eco, 'name': 'Biyoloji', 'color': Colors.greenAccent},
      {'icon': Icons.library_books, 'name': 'Edebiyat', 'color': Colors.indigoAccent}, {'icon': Icons.history, 'name': 'Tarih', 'color': Colors.brown}, {'icon': Icons.map, 'name': 'Coğrafya', 'color': Colors.redAccent}, {'icon': Icons.language, 'name': 'Dil Bilgisi', 'color': Colors.orange},
      {'icon': Icons.psychology, 'name': 'Psikoloji', 'color': Colors.orangeAccent}, {'icon': Icons.trending_up, 'name': 'Ekonomi', 'color': Colors.pinkAccent}, {'icon': Icons.code, 'name': 'Algoritma', 'color': Colors.blueGrey}, {'icon': Icons.menu_book, 'name': 'Felsefe', 'color': Colors.amber},
      {'icon': Icons.restaurant, 'name': 'Beslenme', 'color': Colors.lightGreen}, {'icon': Icons.public, 'name': 'Sosyoloji', 'color': Colors.cyan}, {'icon': Icons.gavel, 'name': 'Hukuk', 'color': Colors.deepPurpleAccent}, {'icon': Icons.auto_stories, 'name': 'Geometri', 'color': Colors.purpleAccent},
    ];
    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 450), child: Padding(padding: const EdgeInsets.all(20.0), child: Column(children: [Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent), onPressed: _goBack)), Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: const [Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 24), SizedBox(width: 8), Text("SnapNova", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.cyanAccent))]), const SizedBox(height: 12), const Text("Her derste her konuda istediğin her şeyi sor SnapNova anında çözsün.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3))])), const SizedBox(height: 16), Expanded(child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))), child: GridView.builder(itemCount: subjects.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.8, crossAxisSpacing: 10, mainAxisSpacing: 2), itemBuilder: (context, index) { final subject = subjects[index]; return Column(children: [Expanded(child: Row(children: [Icon(subject['icon'] as IconData, color: subject['color'] as Color, size: 18), const SizedBox(width: 10), Expanded(child: Text(subject['name'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.9)), overflow: TextOverflow.ellipsis))])), Divider(color: Colors.white.withOpacity(0.1), thickness: 0.5)]); }))), const SizedBox(height: 12), GestureDetector(onTap: () => _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut), child: Container(width: double.infinity, height: 52, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]), borderRadius: BorderRadius.circular(20)), child: const Center(child: Text("Devam Et", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87))))), const SizedBox(height: 16), Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (index) => AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 5), height: 4, width: _currentPage == index ? 32 : 14, decoration: BoxDecoration(color: _currentPage == index ? Colors.cyanAccent : Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(10)))))]))));
  }

  Widget _buildCameraPage() {
    if (_photoTaken) { return _buildSolutionMethodScreen(); }
    return CameraScreen(isSingleMode: _isSingleMode, isFlashOn: _isFlashOn, onModeChange: (mode) => setState(() => _isSingleMode = mode), onFlashToggle: () => setState(() => _isFlashOn = !_isFlashOn), onPhotoTaken: _takePhoto, onGalleryTap: _pickImageFromGallery, onCalculatorTap: _openCalculator, onBackPressed: _goBack);
  }

  Widget _buildSolutionMethodScreen() {
    return Container(width: double.infinity, height: double.infinity, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1a2332), Color(0xFF2d1b4e)])), child: SafeArea(child: LayoutBuilder(builder: (context, constraints) { return SingleChildScrollView(child: Column(children: [Align(alignment: Alignment.centerLeft, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.cyanAccent, size: 28), onPressed: () { setState(() { _photoTaken = false; _selectedAI = ""; _selectedImage = null; }); })), Container(height: constraints.maxHeight * 0.4, margin: const EdgeInsets.symmetric(horizontal: 20), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2)), child: _selectedImage != null ? ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_selectedImage!, fit: BoxFit.cover)) : Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.photo_library, color: Colors.cyanAccent, size: 60), SizedBox(height: 10), Text("Çekilen Fotoğraf", style: TextStyle(color: Colors.white70, fontSize: 16))]))), const SizedBox(height: 20), const Text("Nasıl Çözelim?", textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 15), Center(child: Container(constraints: const BoxConstraints(maxWidth: 800), margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1e2a3a), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 3)), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [_modernSolutionCard("Adım Adım Çöz", "📝", "Soruyu adım adım ve öğrenerek çöz", const Color(0xFF2563eb)), const SizedBox(width: 10), _modernSolutionCard("Pratik Çözüm", "⚡", "Sorunun ait olduğu konuya bak", const Color(0xFFf59e0b)), const SizedBox(width: 10), _modernSolutionCard("Video Ders", "▶️", "Sorunun konusunu videoyla öğren", const Color(0xFF0891b2)), const SizedBox(width: 10), _modernSolutionCard("Konu Anlatımı", "💡", "Teorik bilgileri öğren", const Color(0xFF10b981)), const SizedBox(width: 10), _modernSolutionCard("Test Modu", "📋", "Benzer soruları çözerek kendini test et", const Color(0xFF8b5cf6))])))), const SizedBox(height: 20), const Text("Hangi Modu Kullanmak İstersin?", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 15), Center(child: Container(constraints: const BoxConstraints(maxWidth: 600), margin: const EdgeInsets.symmetric(horizontal: 20), padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1e2a3a), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.purpleAccent.withOpacity(0.4), width: 3)), child: Column(children: [_aiModelCard("SnapNova", "Genel amaçlı hızlı çözüm", Colors.cyanAccent), const SizedBox(height: 12), _aiModelCard("GPT-5 Pro", "Karmaşık problemler", Colors.purpleAccent), const SizedBox(height: 12), _aiModelCard("Gemini Pro", "Görsel analiz", Colors.blueAccent), const SizedBox(height: 12), _aiModelCard("Claude Max", "Uzun metin analizi", Colors.orangeAccent)]))), const SizedBox(height: 20)])); })));
  }

  Widget _modernSolutionCard(String title, String emoji, String description, Color color) {
    return Container(width: 115, padding: const EdgeInsets.all(10), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withOpacity(0.3), color.withOpacity(0.1)]), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.5), width: 2)), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), child: Text(emoji, style: const TextStyle(fontSize: 24))), const SizedBox(height: 8), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 4), Container(height: 1, width: 40, color: color.withOpacity(0.6)), const SizedBox(height: 4), Text(description, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.7), height: 1.2))]));
  }

  Widget _aiModelCard(String name, String description, Color color) {
    bool isSelected = _selectedAI == name;
    return GestureDetector(onTap: () { setState(() { _selectedAI = name; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name ile çözüm başlatılıyor..."), backgroundColor: color, duration: const Duration(seconds: 1))); }, child: Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: isSelected ? [color.withOpacity(0.4), color.withOpacity(0.2)] : [color.withOpacity(0.2), color.withOpacity(0.05)]), borderRadius: BorderRadius.circular(18), border: Border.all(color: isSelected ? color : color.withOpacity(0.3), width: isSelected ? 3 : 2)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(description, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11))]), if (isSelected) Icon(Icons.check_circle, color: color, size: 26)])));
  }
}

class CameraScreen extends StatefulWidget {
  final bool isSingleMode;
  final bool isFlashOn;
  final Function(bool) onModeChange;
  final VoidCallback onFlashToggle;
  final VoidCallback onPhotoTaken;
  final VoidCallback onGalleryTap;
  final VoidCallback onCalculatorTap;
  final VoidCallback onBackPressed;
  const CameraScreen({Key? key, required this.isSingleMode, required this.isFlashOn, required this.onModeChange, required this.onFlashToggle, required this.onPhotoTaken, required this.onGalleryTap, required this.onCalculatorTap, required this.onBackPressed}) : super(key: key);
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  @override
  void initState() { super.initState(); _initializeCamera(); }
  Future<void> _initializeCamera() async { if (cameras.isEmpty) return; _cameraController = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false); try { await _cameraController!.initialize(); if (mounted) { setState(() => _isCameraInitialized = true); } } catch (e) { print('Kamera hatası: $e'); } }
  @override
  void didUpdateWidget(CameraScreen oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.isFlashOn != widget.isFlashOn && _cameraController != null) { _cameraController!.setFlashMode(widget.isFlashOn ? FlashMode.torch : FlashMode.off); } }
  @override
  void dispose() { _cameraController?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Stack(children: [_isCameraInitialized && _cameraController != null ? SizedBox.expand(child: CameraPreview(_cameraController!)) : Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))), if (widget.isSingleMode) Container(color: Colors.black.withOpacity(0.5), child: Center(child: Container(width: 280, height: 180, decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent, width: 3), borderRadius: BorderRadius.circular(15))))), Positioned(top: 20, left: 20, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28), onPressed: widget.onBackPressed)), Align(alignment: Alignment.bottomCenter, child: Container(height: 340, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.95), Colors.transparent])), child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white12)), child: Row(mainAxisSize: MainAxisSize.min, children: [_modeToggleButton("Çoklu", !widget.isSingleMode, () => widget.onModeChange(false)), _modeToggleButton("Tekli", widget.isSingleMode, () => widget.onModeChange(true))])), const SizedBox(height: 25), Row(mainAxisAlignment: MainAxisAlignment.center, children: [GestureDetector(onTap: widget.onGalleryTap, child: Column(children: const [Icon(Icons.image, color: Colors.greenAccent, size: 35), SizedBox(height: 4), Text("Fotoğraflar", style: TextStyle(fontSize: 9, color: Colors.greenAccent))])), const SizedBox(width: 30), GestureDetector(onTap: widget.onPhotoTaken, child: Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)), child: Container(width: 75, height: 75, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)))), const SizedBox(width: 30), GestureDetector(onTap: widget.onFlashToggle, child: Column(children: [Icon(Icons.light_mode, color: widget.isFlashOn ? Colors.amber : Colors.white70, size: 35), Text(widget.isFlashOn ? "AÇIK" : "KAPALI", style: TextStyle(fontSize: 9, color: widget.isFlashOn ? Colors.amber : Colors.white54))]))]), const SizedBox(height: 30), Container(margin: const EdgeInsets.only(bottom: 35, left: 20, right: 20), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white12)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_coloredIconButton(Icons.calculate, "Hesap Mak.", Colors.orangeAccent, widget.onCalculatorTap), _coloredIconButton(Icons.history, "Geçmiş", Colors.purpleAccent, () {}), _coloredIconButton(Icons.qr_code_scanner, "Tara", Colors.cyanAccent, () {})]))])))]);
  }
  Widget _modeToggleButton(String label, bool isActive, VoidCallback onTap) { return GestureDetector(onTap: onTap, child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8), decoration: BoxDecoration(color: isActive ? Colors.cyanAccent : Colors.transparent, borderRadius: BorderRadius.circular(25)), child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isActive ? Colors.black : Colors.white60)))); }
  Widget _coloredIconButton(IconData icon, String label, Color color, VoidCallback onTap) { return GestureDetector(onTap: onTap, child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.4))), child: Icon(icon, color: color, size: 24)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.9)), textAlign: TextAlign.center)])); }
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({Key? key}) : super(key: key);
  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _expression = "";
  String _result = "0";
  bool _isScientific = false;
  void _onButtonPressed(String value) { setState(() { if (value == "C") { _expression = ""; _result = "0"; } else if (value == "⌫") { if (_expression.isNotEmpty) { _expression = _expression.substring(0, _expression.length - 1); } } else if (value == "=") { _calculateResult(); } else { _expression += value; } }); }
  void _calculateResult() { try { String expr = _expression.replaceAll("×", "*").replaceAll("÷", "/").replaceAll("π", "3.14159265359").replaceAll("e", "2.71828182846"); Parser p = Parser(); Expression exp = p.parse(expr); ContextModel cm = ContextModel(); double eval = exp.evaluate(EvaluationType.REAL, cm); _result = eval.toString(); if (_result.endsWith('.0')) { _result = _result.substring(0, _result.length - 2); } } catch (e) { _result = "Hata"; } }
  @override
  Widget build(BuildContext context) { return Scaffold(backgroundColor: const Color(0xFF0F172A), appBar: AppBar(backgroundColor: const Color(0xFF1e293b), title: const Text("Hesap Makinesi"), actions: [TextButton(onPressed: () { setState(() { _isScientific = !_isScientific; }); }, child: Text(_isScientific ? "Basit" : "Bilimsel", style: const TextStyle(color: Colors.cyanAccent)))]), body: Column(children: [Expanded(flex: 2, child: Container(width: double.infinity, padding: const EdgeInsets.all(20), color: const Color(0xFF1e293b), child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(_expression, style: const TextStyle(fontSize: 24, color: Colors.white70), textAlign: TextAlign.right), const SizedBox(height: 10), Text(_result, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.cyanAccent), textAlign: TextAlign.right)]))), Expanded(flex: 5, child: Container(padding: const EdgeInsets.all(10), child: _isScientific ? _buildScientificButtons() : _buildBasicButtons()))])); }
  Widget _buildBasicButtons() { final buttons = [["C", "⌫", "%", "÷"], ["7", "8", "9", "×"], ["4", "5", "6", "-"], ["1", "2", "3", "+"], ["(", "0", ")", "="]]; return GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 1.2, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: 20, itemBuilder: (context, index) { int row = index ~/ 4; int col = index % 4; String label = buttons[row][col]; Color bgColor = _getButtonColor(label); return ElevatedButton(onPressed: () => _onButtonPressed(label), style: ElevatedButton.styleFrom(backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(label, style: const TextStyle(fontSize: 24, color: Colors.white))); }); }
  Widget _buildScientificButtons() { final buttons = [["sin", "cos", "tan", "÷"], ["log", "ln", "√", "×"], ["x²", "x^y", "π", "-"], ["7", "8", "9", "+"], ["4", "5", "6", "C"], ["1", "2", "3", "⌫"], ["(", "0", ")", "="]]; return GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 1.0, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: 28, itemBuilder: (context, index) { int row = index ~/ 4; int col = index % 4; String label = buttons[row][col]; Color bgColor = _getButtonColor(label); return ElevatedButton(onPressed: () => _onButtonPressed(label), style: ElevatedButton.styleFrom(backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text(label, style: const TextStyle(fontSize: 18, color: Colors.white))); }); }
  Color _getButtonColor(String label) { if (label == "C" || label == "⌫") { return Colors.redAccent.withOpacity(0.7); } else if (label == "=") { return Colors.cyanAccent.withOpacity(0.7); } else if (["+", "-", "×", "÷", "%"].contains(label)) { return Colors.orangeAccent.withOpacity(0.7); } else if (["sin", "cos", "tan", "log", "ln", "√", "x²", "x^y", "π", "e"].contains(label)) { return Colors.purpleAccent.withOpacity(0.7); } else { return Colors.white.withOpacity(0.1); } }
}

class _AnimatedQuestion extends StatefulWidget {
  final Map<String, String> question;
  const _AnimatedQuestion({required this.question});
  @override
  State<_AnimatedQuestion> createState() => _AnimatedQuestionState();
}

class _AnimatedQuestionState extends State<_AnimatedQuestion> {
  String _displayedSolution = "";
  String _displayedExplanation = "";
  Timer? _timer;
  int _solutionIndex = 0;
  int _explanationIndex = 0;
  bool _solutionComplete = false;
  @override
  void initState() { super.initState(); _startAnimation(); }
  void _startAnimation() { _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) { if (_solutionIndex < widget.question['solution']!.length) { setState(() { _displayedSolution = widget.question['solution']!.substring(0, _solutionIndex + 1); _solutionIndex++; }); } else if (!_solutionComplete) { setState(() { _solutionComplete = true; }); } else if (_explanationIndex < widget.question['explanation']!.length) { setState(() { _displayedExplanation = widget.question['explanation']!.substring(0, _explanationIndex + 1); _explanationIndex++; }); } else { timer.cancel(); } }); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [Text(widget.question['subject']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.cyanAccent)), const SizedBox(height: 4), Text(widget.question['question']!, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center), const SizedBox(height: 8), Text(_displayedSolution, style: const TextStyle(fontSize: 12, color: Colors.white70), textAlign: TextAlign.center), if (_displayedExplanation.isNotEmpty) Text(_displayedExplanation, style: const TextStyle(fontSize: 11, color: Colors.white54), textAlign: TextAlign.center)])); }
}