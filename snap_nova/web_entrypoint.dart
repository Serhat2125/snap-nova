import 'package:flutter/material.dart';

void main() {
  runApp(const SnapNovaApp());
}

class SnapNovaApp extends StatelessWidget {
  const SnapNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SnapNova AI',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _photoTaken = false;

  // --- SAYFALAR ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          onPageChanged: (index) => setState(() => _currentPage = index),
          physics: const BouncingScrollPhysics(),
          children: [
            _buildFirstPage(),
            _buildSecondPage(),
            _buildCameraPage(),
          ],
        ),
      ),
    );
  }

  // 1. SAYFA: ÖRNEKLER
  Widget _buildFirstPage() {
    return _buildBaseTemplate(
      child: Column(
        children: [
          _buildHeroLogo(),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: _boxDecoration(Colors.cyanAccent),
              child: ListView(
                children: [
                  _AnimatedQuestion(sub: "Matematik", q: "x² - 4 = 0?", a: "x = 2, x = -2"),
                  const Divider(),
                  _AnimatedQuestion(sub: "Fizik", q: "F = m.a nedir?", a: "Newton'un 2. Yasası"),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildActionButton("Hemen Başla", () => _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.ease)),
          const SizedBox(height: 10),
          _buildPageIndicator(),
        ],
      ),
    );
  }

  // 2. SAYFA: DERSLER
  Widget _buildSecondPage() {
    final subjects = ["Matematik", "Fizik", "Kimya", "Biyoloji", "Geometri", "Tarih"];
    return _buildBaseTemplate(
      child: Column(
        children: [
          _buildHeroLogo(),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 2.5, mainAxisSpacing: 10, crossAxisSpacing: 10),
              itemCount: subjects.length,
              itemBuilder: (context, i) => Container(
                decoration: _boxDecoration(Colors.white12),
                child: Center(child: Text(subjects[i], style: const TextStyle(fontWeight: FontWeight.bold))),
              ),
            ),
          ),
          _buildActionButton("Kameraya Geç", () => _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.ease)),
          const SizedBox(height: 10),
          _buildPageIndicator(),
        ],
      ),
    );
  }

  // 3. SAYFA: KAMERA VE ÇÖZÜM
  Widget _buildCameraPage() {
    if (_photoTaken) return _buildSolutionMethodScreen();

    return Stack(
      children: [
        Container(color: Colors.black),
        // ODAKLAMA ÇERÇEVESİ (SAĞDAN SOLDAN BÜYÜTÜLDÜ)
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Soruyu Alanın İçine Al", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Container(
                width: 320, // Genişletildi
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.cyanAccent, width: 3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ],
          ),
        ),
        // ALT BUTONLAR (GALERİ, HESAP MAK., GEÇMİŞ)
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black, Colors.transparent]),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _extraTool(Icons.image, "Fotoğraflar", Colors.greenAccent, () => _navTo(const FakeGallery())),
                    _extraTool(Icons.calculate, "Hesap Mak.", Colors.orangeAccent, () => _navTo(const FakeCalculator())),
                    _extraTool(Icons.history, "Geçmiş", Colors.purpleAccent, () => _navTo(const FakeHistory())),
                  ],
                ),
                const SizedBox(height: 30),
                GestureDetector(
                  onTap: () => setState(() => _photoTaken = true),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                    child: const CircleAvatar(radius: 35, backgroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- ÇÖZÜM SEÇİM EKRANI ---
  Widget _buildSolutionMethodScreen() {
    return LayoutBuilder(builder: (context, c) {
      return SingleChildScrollView(
        child: Column(
          children: [
            // FOTOĞRAF ALANI (1/3)
            Container(
              height: c.maxHeight / 3,
              width: double.infinity,
              margin: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
              ),
              child: const Center(child: Icon(Icons.image, size: 60, color: Colors.cyanAccent)),
            ),
            const Text("Nasıl Çözelim?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            // ÇÖZÜM SEÇENEKLERİ (ORTALI VE ÇERÇEVELİ)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: _boxDecoration(Colors.cyanAccent.withOpacity(0.3)),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 15, runSpacing: 15,
                  children: [
                    _solCard("Adım Adım Çöz", "📝", "Detaylı işlem basamakları", Colors.blue),
                    _solCard("Hızlı ve Sade Çöz", "⚡", "Pratik ve net sonuçlar", Colors.amber),
                    _solCard("Video Ders", "▶️", "Sorunun konusunu videoyla öğren", Colors.red),
                    _solCard("Test Modu", "📋", "Benzer soruları çözerek kendini test et", Colors.green),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),
            const Text("Mod Seçimi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            // MODLAR (ORTALI VE ÇERÇEVELİ)
            Center(
              child: Container(
                padding: const EdgeInsets.all(15),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: _boxDecoration(Colors.purpleAccent.withOpacity(0.2)),
                child: Column(
                  children: [
                    _aiRow("SnapNova", "Hızlı AI asistanı", Colors.cyanAccent),
                    const SizedBox(height: 10),
                    _aiRow("GPT-5 Pro", "Akademik derin analiz", Colors.purpleAccent),
                  ],
                ),
              ),
            ),
            TextButton(onPressed: () => setState(() => _photoTaken = false), child: const Text("Yeniden Çek", style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      );
    });
  }

  // --- YARDIMCI METODLAR ---
  void _navTo(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (c) => page));

  Widget _extraTool(IconData i, String t, Color c, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Column(children: [Icon(i, color: c, size: 30), Text(t, style: TextStyle(fontSize: 10, color: c))]),
  );

  Widget _solCard(String t, String e, String s, Color c) => Container(
    width: 140, padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withOpacity(0.3))),
    child: Column(children: [Text(e, style: const TextStyle(fontSize: 24)), const SizedBox(height: 8), Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center), const SizedBox(height: 4), Text(s, style: const TextStyle(fontSize: 9, color: Colors.white54), textAlign: TextAlign.center)]),
  );

  Widget _aiRow(String n, String d, Color c) => Container(
    padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: c.withOpacity(0.3))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: TextStyle(color: c, fontWeight: FontWeight.bold)), Text(d, style: const TextStyle(fontSize: 10, color: Colors.white54))]), Icon(Icons.check_circle, color: c, size: 20)]),
  );

  Widget _buildHeroLogo() => Column(children: const [Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 50), Text("SnapNova", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.cyanAccent))]);

  Widget _buildActionButton(String t, VoidCallback o) => ElevatedButton(onPressed: o, style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)));

  BoxDecoration _boxDecoration(Color c) => BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: c.withOpacity(0.2)));

  Widget _buildBaseTemplate({required Widget child}) => Padding(padding: const EdgeInsets.all(20), child: child);

  Widget _buildPageIndicator() => Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(3, (i) => Container(margin: const EdgeInsets.all(4), width: _currentPage == i ? 25 : 8, height: 8, decoration: BoxDecoration(color: _currentPage == i ? Colors.cyanAccent : Colors.white24, borderRadius: BorderRadius.circular(4)))));
}

// --- EK SAYFALAR (YÖNLENDİRMELER) ---

class FakeGallery extends StatelessWidget { const FakeGallery({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("Galeri")), body: const Center(child: Text("Telefonun galerisine yönlendiriliyorsunuz..."))); }
class FakeCalculator extends StatelessWidget { const FakeCalculator({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("Hesap Makinesi")), body: const Center(child: Text("SnapNova Hesap Makinesi Aktif"))); }
class FakeHistory extends StatelessWidget { const FakeHistory({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text("Geçmiş Çözümler")), body: ListView(children: const [ListTile(title: Text("Matematik Sorusu #1"), subtitle: Text("2 gün önce çözüldü"), leading: Icon(Icons.check, color: Colors.green))])); }

class _AnimatedQuestion extends StatelessWidget {
  final String sub, q, a;
  const _AnimatedQuestion({required this.sub, required this.q, required this.a});
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(children: [Text(sub, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)), Text(q), Text(a, style: const TextStyle(color: Colors.greenAccent))]));
}