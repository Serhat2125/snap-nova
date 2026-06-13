const fs = require('fs');
const BASE = 'C:/Users/TUNA MUHENDISLIK/snap_nova/assets/';

const FILES = [
  'fotosentez.html','ekosistem-besin-zinciri.html',
  'kalitim-genotip-fenotip.html','bitki-anatomisi.html'
];

// Declutter shim: wraps CSS2DRenderer.prototype.render. After the original projects
// every .label3d to its 3D screen point, we push overlapping labels apart (same
// 16-iteration collision idea as the gold-standard updateLabels). The existing
// updateLeaderLines() then redraws connectors to the moved labels via getBoundingClientRect.
const SHIM = `
<script>
/* == GROUP-B LABEL DECLUTTER == */
(function(){
  function patch(){
    if(!window.CSS2DRenderer || !window.CSS2DRenderer.prototype) return false;
    var proto=window.CSS2DRenderer.prototype;
    if(proto.__declutterPatched) return true;
    proto.__declutterPatched=true;
    var orig=proto.render;
    proto.render=function(scene,camera){
      orig.call(this,scene,camera);
      try{ declutter(this.domElement); }catch(e){}
    };
    return true;
  }
  function declutter(root){
    if(!root) return;
    if(window.labelsVisible===false) return;
    var W=window.innerWidth, H=window.innerHeight;
    var TOP=50, BOT=H-150;
    var els=[].slice.call(root.querySelectorAll('.label3d')).filter(function(el){
      return el.style.display!=='none' && el.dataset.userHidden!=='1';
    });
    if(els.length<2) return;
    var items=[];
    els.forEach(function(el){
      var m=/translate\\(\\s*([-\\d.]+)px\\s*,\\s*([-\\d.]+)px\\s*\\)/.exec(el.style.transform||'');
      if(!m) return;
      items.push({ el:el, x:parseFloat(m[1]), y:parseFloat(m[2]),
        w:(el.offsetWidth||80)+10, h:(el.offsetHeight||22)+8,
        ox:parseFloat(m[1]), oy:parseFloat(m[2]) });
    });
    if(items.length<2) return;
    for(var it=0; it<16; it++){
      var moved=false;
      for(var i=0;i<items.length;i++){
        for(var j=i+1;j<items.length;j++){
          var A=items[i], B=items[j];
          var dx=B.x-A.x, dy=B.y-A.y;
          var minX=(A.w+B.w)/2, minY=(A.h+B.h)/2;
          if(Math.abs(dx)<minX && Math.abs(dy)<minY){
            var ovX=minX-Math.abs(dx), ovY=minY-Math.abs(dy);
            if(ovY<=ovX){ var py=ovY/2*(dy<0?-1:1); A.y-=py; B.y+=py; }
            else        { var px=ovX/2*(dx<0?-1:1); A.x-=px; B.x+=px; }
            moved=true;
          }
        }
      }
      items.forEach(function(m){
        m.x=Math.max(m.w/2+2, Math.min(W-m.w/2-2, m.x));
        m.y=Math.max(TOP, Math.min(BOT, m.y));
      });
      if(!moved) break;
    }
    items.forEach(function(m){
      if(Math.abs(m.x-m.ox)>0.5 || Math.abs(m.y-m.oy)>0.5)
        m.el.style.transform='translate(-50%, -50%) translate('+m.x+'px, '+m.y+'px)';
    });
  }
  var tries=0;
  (function spin(){ if(patch()||tries++>40) return; setTimeout(spin,150); })();
})();
</script>`;

let passed=0, skipped=0, failed=0;

for (const fname of FILES){
  const fpath = BASE + fname;
  try {
    let html = fs.readFileSync(fpath, 'utf8');
    if (html.includes('GROUP-B LABEL DECLUTTER')){
      console.log('SKIP (already): ' + fname); skipped++; continue;
    }
    html = html.replace('</body>', SHIM + '\n</body>');
    fs.writeFileSync(fpath, html, 'utf8');
    console.log('DONE: ' + fname);
    passed++;
  } catch(e){
    console.log('ERROR: ' + fname + ' - ' + e.message);
    failed++;
  }
}
console.log('\n' + passed + ' done, ' + skipped + ' skipped, ' + failed + ' failed');
