const vm=require('vm'),fs=require('fs');
const c={};c.globalThis=c;vm.createContext(c);
vm.runInContext(fs.readFileSync('_ur_test_c.js','utf8'),c);
const B=c.__OUT;
B.lise.kolay=B.lise.kolay.slice(0,100);
B.lise.zor=B.lise.zor.slice(0,100);
const esc=s=>String(s).replace(/\\/g,'\\\\').replace(/'/g,"\\'");
const qstr=q=>{
  const steps=q.steps.map(s=>"{t:'"+esc(s.t)+"',a:'"+esc(s.a)+"',d:'"+esc(s.d)+"'}").join(',');
  const o=q.o.map(x=>"'"+esc(x)+"'").join(',');
  return "      {q:'"+esc(q.q)+"',steps:["+steps+"],ans:'"+esc(q.ans)+"',o:["+o+"]}";
};
let out='// Üreme Sistemi — LİSE TEST soruları (100 kolay + 100 zor)\n';
out+='globalThis.__OUT = {\n  lise: {\n';
out+='    kolay: [\n'+B.lise.kolay.map(qstr).join(',\n')+'\n    ],\n';
out+='    zor: [\n'+B.lise.zor.map(qstr).join(',\n')+'\n    ]\n';
out+='  }\n};\n';
fs.writeFileSync('_ur_test_c.js',out,'utf8');
console.log('written');
