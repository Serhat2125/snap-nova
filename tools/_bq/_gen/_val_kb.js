require("./kb_test_ilk.js");
const lv = globalThis.__OUT.ilkokul;
let err = 0;
const badPat = /(\$)|(\\\()|(\*\*)|(\\frac)/;
for (const zor of ["kolay","zor"]) {
  const arr = lv[zor];
  console.log(zor, "->", arr.length, "soru");
  const seen = new Set();
  arr.forEach((q,i) => {
    if (!q.q || !q.ans || !Array.isArray(q.o) || q.o.length !== 4) { console.log("  HATA idx",i,"yapi"); err++; }
    if (!Array.isArray(q.steps) || q.steps.length < 1) { console.log("  HATA idx",i,"steps"); err++; }
    if (q.o.includes(q.ans)) { console.log("  HATA idx",i,"ans o icinde"); err++; }
    if (new Set(q.o).size !== 4) { console.log("  HATA idx",i,"o tekrar"); err++; }
    if (seen.has(q.q)) { console.log("  TEKRAR idx",i,q.q.slice(0,40)); err++; }
    seen.add(q.q);
    const blob = JSON.stringify(q);
    if (badPat.test(blob)) { console.log("  HATA idx",i,"LaTeX/markdown"); err++; }
    if (q.fig) {
      if (!q.fig.startsWith("<svg") || !q.fig.endsWith("</svg>")) { console.log("  HATA idx",i,"svg sinir"); err++; }
      if (q.fig.indexOf('"') !== -1 || /href|<script/.test(q.fig)) { console.log("  HATA idx",i,"svg yasak"); err++; }
    }
  });
}
const figK = lv.kolay.filter(q=>q.fig).length;
const figZ = lv.zor.filter(q=>q.fig).length;
console.log("fig kolay:", figK, "/30  zor:", figZ, "/30  toplam:", figK+figZ, "/60 =", Math.round((figK+figZ)/60*100)+"%");
console.log("HATA sayisi:", err);
