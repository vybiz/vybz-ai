(()=>{const L=[['index.html','Home'],['studio.html','Record'],['songwriter.html','Write'],['trends.html','Trends'],['master.html','Mix'],['editor.html','Edit'],['account.html','Me']];
const c=document.createElement('style');c.textContent='nav{position:fixed;left:0;right:0;bottom:0;display:flex;background:#0f0f17;border-top:1px solid #2a2a3a;padding-bottom:env(safe-area-inset-bottom,0px);z-index:9}nav a{flex:1;text-align:center;padding:14px 2px;color:#9a98b0;text-decoration:none;font-size:11px}nav a.on{color:#a78bfa;font-weight:700}main{padding-bottom:96px!important}';
document.head.append(c);const n=document.createElement('nav'),p=location.pathname;
L.forEach(([h,t])=>{const a=document.createElement('a');a.href=h;a.textContent=t;if(p.endsWith(h)||(h==='index.html'&&p.endsWith('/')))a.className='on';n.append(a);});
document.body.append(n);})();
