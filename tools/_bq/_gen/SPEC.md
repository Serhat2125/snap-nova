# Soru Bankası Üretim Spec'i (bq sistemi)

Bu dosya, 3D biyoloji derslerine eklenecek **Test Soruları** ve **Bilgi Paneli** sorularının
üretim kurallarını tanımlar. ÜRETTİĞİN içerik bir ders kitabı kalitesinde olmalı.

## Çıktı biçimi (ZORUNLU)
Tek bir JS dosyası yaz; içeriği SADECE şu olsun (başka satır/yorum yok):
```js
globalThis.__OUT = { ... };
```
`...` yapısı, sana verilen göreve göre (TEST mi INFO mu) aşağıdaki şekildedir.

## Soru nesnesi formatı

### TEST sorusu (şıklı)
```json
{
  "q": "Soru metni (net, sınav dili)",
  "steps": [ {"t":"Adım başlığı","a":"Kısa cevap/anahtar","d":"1-2 cümle açıklama"} ],
  "ans": "Doğru cevap (kısa)",
  "o": ["yanlış şık 1","yanlış şık 2","yanlış şık 3","yanlış şık 4"]
}
```
- `o` = **TAM 4 adet YANLIŞ çeldirici**. Doğru cevabı (`ans`) `o` İÇİNE KOYMA. Motor ans'ı ayrı ekler.
- Çeldiriciler makul ama açıkça yanlış olmalı; saçma/komik şık YOK.
- TEST'te `steps` genelde **1 adım** (kısa gerekçe) yeterli; lise zor'da 1-2 adım olabilir.

### INFO sorusu (ŞIKSIZ — bilgi paneli)
```json
{
  "q": "Soru metni",
  "steps": [
    {"t":"1. adım başlığı","a":"ara cevap","d":"açıklama cümlesi"},
    {"t":"2. adım başlığı","a":"ara cevap","d":"açıklama cümlesi"}
  ],
  "ans": "Nihai sonuç (kısa cümle)"
}
```
- INFO'da `o` alanı **YOK** (şıksız).
- Çözüm **çok adımlı ve detaylı**: ilkokul/ortaokul kolay = 2 adım; lise/zor = 2-3 adım.
- Her adımda `d` (detay) dolu ve öğretici olsun.

## İçerik / dil kuralları (ÇOK ÖNEMLİ)
- Tamamı **Türkçe**, ders kitabı kalitesi.
- **Unicode sembol** kullan: ² ³ ⁺ ⁻ → ⇌ × · ↑ ↓ ; LaTeX/`$...$`/`\(...\)`/markdown `**` artığı **YASAK**.
- Ondalık ayraç **virgül** (3,5 gibi). Birim varsa yaz (mol, kJ, nm).
- Seviyeye uygun derinlik:
  - **İlkokul**: çok sade, günlük dil, somut. Soyut/ileri terim yok.
  - **Ortaokul**: temel kavramlar, basit mekanizma.
  - **Lise**: tam akademik derinlik, mekanizma, karşılaştırma, yorum.
- Aynı seviye/zorluk içinde sorular **benzersiz** olsun (tekrar yok).
- Konu DIŞINA çıkma; verilen alt konuya/derse sadık kal.
- `<b>...</b>` ile önemli kelimeyi vurgulayabilirsin (sadece `<b>` destekli).

## Doğrulama (yazmadan önce)
Yazdığın dosyayı `node -e` ile yükleyip parse edilebildiğini ve sayıların TAM tuttuğunu
kontrol et. Sayı eksikse tamamla. Bittiğinde dosya yolunu ve sayıları bildir.
