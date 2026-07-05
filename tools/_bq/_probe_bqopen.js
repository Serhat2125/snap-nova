// ✎ (bqOpen) butonu görünür mü + tıklayınca soru seçici açılıyor mu?
(async () => {
  const puppeteer = require('puppeteer');
  const path = require('path');
  const b = await puppeteer.launch({ headless: 'new' });
  let fail = 0;
  const FILES = ['golge-olusumu-isik-yayilmasi', 'dalgalar', 'elektrik', 'optik-mercekler',
    'bileske-kuvvet-vektorler', 'basit-makineler', 'akiskanlar-mekanigi'];
  for (const f of FILES) {
    const p = await b.newPage();
    await p.setViewport({ width: 412, height: 892 });
    const errs = []; p.on('pageerror', e => errs.push(e.message));
    const fp = path.resolve(__dirname, '..', '..', 'assets', f + '.html');
    await p.goto('file:///' + fp.split(path.sep).join('/'), { waitUntil: 'networkidle0', timeout: 60000 });
    await new Promise(r => setTimeout(r, 2800));
    const res = await p.evaluate(async () => {
      const wait = (ms) => new Promise(r => setTimeout(r, ms));
      const ob = document.getElementById('bqOpen');
      if (!ob) return { err: 'bqOpen yok' };
      const r = ob.getBoundingClientRect();
      const onScreen = r.width > 0 && r.top >= 0 && r.bottom <= innerHeight + 2;
      ob.click();
      await wait(350);
      const pick = document.getElementById('bqPick');
      const open = pick && pick.classList.contains('on');
      const cols = document.querySelectorAll('#bqPick .bq-opt, #bqEasy > *, #bqHard > *').length;
      const topic = (document.getElementById('bqPickTopic') || {}).textContent || '';
      return { onScreen, open, cols, topic: topic.slice(0, 40) };
    });
    const ok = res.onScreen && res.open && res.cols > 0;
    if (!ok) fail++;
    console.log((ok ? 'PASS' : 'FAIL'), f, JSON.stringify(res), 'pageerror:', errs.length ? errs[0] : 'yok');
    await p.close();
  }
  await b.close();
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('FAIL:', e.message); process.exit(1); });
