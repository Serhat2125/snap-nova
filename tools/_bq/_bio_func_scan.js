// 13 biyoloji dersinde ✎ (step/info) ve mix (test) quiz'in gerçekten soru
// render edip etmediğini headless test eder. lise seviyesinde.
(async () => {
  const puppeteer = require('puppeteer'); const path = require('path');
  const BIO = ['bitki-anatomisi', 'fotosentez', 'ekosistem-besin-zinciri', 'kalitim-genotip-fenotip',
    'hucre-organeller', 'dna-replikasyon', 'mitoz-mayoz', 'sindirim-sistemi', 'dolasim-sistemi',
    'bosaltim-sistemi', 'ureme-sistemi', 'destek-hareket-sistemi', 'denetleyici-duzenleyici-sistem'];
  const b = await puppeteer.launch({ headless: 'new' });
  const results = [];
  for (const f of BIO) {
    const p = await b.newPage(); await p.setViewport({ width: 412, height: 892 });
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    const fp = path.resolve(__dirname, '..', '..', 'assets', f + '.html');
    await p.goto('file:///' + fp.split(path.sep).join('/'), { waitUntil: 'networkidle0', timeout: 60000 });
    await new Promise(r => setTimeout(r, 2600));
    const res = await p.evaluate(async () => {
      const wait = (ms) => new Promise(r => setTimeout(r, ms));
      const out = { hasBqOpen: !!document.getElementById('bqOpen'), stepSets: 0, mixSets: 0, stepQ: 0, mixQ: 0 };
      // ✎ step yolu
      if (window.bqOpenStep) { window.bqOpenStep(); await wait(300);
        out.stepSets = document.querySelectorAll('#bqEasy .bq-go, #bqHard .bq-go').length;
        const sb = document.querySelector('#bqHard .bq-go');
        if (sb) { sb.click(); await wait(400); out.stepQ = document.querySelectorAll('#bqScroll .bq-q').length; }
        const back = document.getElementById('bqBack'); if (back) back.click(); await wait(200);
        const pk = document.getElementById('bqPick'); if (pk) pk.classList.remove('on');
      }
      // mix (Test Soruları) yolu
      if (window.bqOpenMix) { window.bqOpenMix(); await wait(300);
        out.mixSets = document.querySelectorAll('#bqHard .bq-go').length;
        const mb = document.querySelectorAll('#bqHard .bq-go');
        if (mb.length) { mb[mb.length - 1].click(); await wait(400); out.mixQ = document.querySelectorAll('#bqScroll .bq-q').length; }
      }
      return out;
    });
    res.err = errs.length ? errs[0] : '';
    results.push({ f, ...res });
    await p.close();
  }
  await b.close();
  console.log('ders'.padEnd(32), '✎buton', 'stepSet', 'stepQ', 'mixSet', 'mixQ', 'durum');
  for (const r of results) {
    const bad = r.stepQ === 0 || r.mixQ === 0;
    console.log(r.f.padEnd(32),
      String(r.hasBqOpen ? 'VAR' : 'YOK').padEnd(6),
      String(r.stepSets).padEnd(7), String(r.stepQ).padEnd(5),
      String(r.mixSets).padEnd(6), String(r.mixQ).padEnd(4),
      bad ? ('EKSİK ⚠ ' + (r.err || '')) : 'tam');
  }
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
