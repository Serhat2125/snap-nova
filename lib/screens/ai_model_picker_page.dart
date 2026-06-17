import 'package:flutter/material.dart';
import '../services/ai_provider_service.dart';

/// AI Modeli seçim sayfası (Ayarlar → AI Modeli).
/// Kullanıcı sağlayıcı + model seçer; seçim kalıcı kaydedilir ve tüm AI
/// çağrıları (provider verilmeyen) bu seçimi kullanır.
class AiModelPickerPage extends StatefulWidget {
  const AiModelPickerPage({super.key});

  @override
  State<AiModelPickerPage> createState() => _AiModelPickerPageState();
}

class _AiModelPickerPageState extends State<AiModelPickerPage> {
  late AiProvider _provider;
  late String _model;

  @override
  void initState() {
    super.initState();
    _provider = AiProviderService.selectedProvider;
    _model = AiProviderService.selectedModel;
  }

  Future<void> _select(AiProvider p, String modelId) async {
    await AiProviderService.setSelection(p, modelId);
    if (!mounted) return;
    setState(() {
      _provider = p;
      _model = modelId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Modeli')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Maliyet bilgisi
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Text('💰', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Maliyeti düşük tutmak için "en ucuz" işaretli modeller önerilir. '
                    'Pahalı modeller daha yetenekli ama çok daha maliyetlidir.',
                    style: TextStyle(fontSize: 13, color: cs.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final info in kAiProviders) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Row(
                children: [
                  Text(info.emoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text(info.label,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (int i = 0; i < info.models.length; i++)
                    Builder(builder: (_) {
                      final selected = _provider == info.provider &&
                          _model == info.models[i].id;
                      return ListTile(
                        dense: true,
                        onTap: () => _select(info.provider, info.models[i].id),
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected ? cs.primary : cs.outline,
                          size: 20,
                        ),
                        title: Text(info.models[i].label,
                            style: const TextStyle(fontSize: 13.5)),
                        trailing: i == 0
                            ? const Icon(Icons.savings_outlined,
                                color: Color(0xFF10B981), size: 20)
                            : null,
                      );
                    }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Seçili: ${AiProviderService.selectedInfo.label} · $_model',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}
