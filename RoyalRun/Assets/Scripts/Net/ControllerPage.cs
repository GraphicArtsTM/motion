// Страница-пульт для телефона. Телефон открывает её по адресу http://IP:порт.
// Тексты страницы есть на трёх языках (русский, английский, узбекский) - словарь I18N в скрипте.
// Язык подставляется сервером вместо метки __RR_LANG__ (см. ControllerPage.Build) и меняется
// на лету сообщением {"t":"lang"} от игры.
// Палец по экрану - бег (джойстик), короткое касание - прыжок ({"t":"jump"}).
// В C# строке @"..." двойная кавычка записывается как "".
public static class ControllerPage
{
    public const string LangToken = "__RR_LANG__";

    public const string Html = @"<!DOCTYPE html>
<html lang='ru'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover'>
<meta name='theme-color' content='#150d29'>
<title>Royal Run - controller</title>
<style>
:root{--c:#9a8cc0;--gold:#ffd54f;--bg1:#241545;--bg2:#0e0919}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none;-webkit-touch-callout:none}
html,body{margin:0;height:100%;background:var(--bg2);color:#fff;font-family:system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;overscroll-behavior:none;overflow:hidden}
body{background:radial-gradient(120% 80% at 50% 0%,var(--bg1),var(--bg2))}
.screen{display:none;position:fixed;inset:0;flex-direction:column;align-items:center;padding:calc(env(safe-area-inset-top,0px) + 16px) 16px calc(env(safe-area-inset-bottom,0px) + 16px)}
h1{margin:4px 0 0;font-size:36px;letter-spacing:3px;color:var(--gold);text-shadow:0 3px 0 #6d4c00}
.crown{font-size:58px;line-height:1;margin-top:6px}
.sub{opacity:.75;margin:6px 0 18px;text-align:center;line-height:1.35;white-space:pre-line}
input{width:100%;max-width:340px;font-size:22px;padding:15px 16px;border-radius:16px;border:2px solid #4a4266;background:#1d1636;color:#fff;text-align:center;-webkit-user-select:text;user-select:text;outline:none}
input:focus{border-color:var(--gold)}
button{font-size:22px;font-weight:800;padding:16px 22px;border:0;border-radius:18px;color:#1a1030;background:linear-gradient(#ffe27a,#ffc107);width:100%;max-width:340px;box-shadow:0 5px 0 #a67c00}
button:active{transform:translateY(3px);box-shadow:0 2px 0 #a67c00}
button:disabled{opacity:.35;box-shadow:none}
button.ghost{background:#ffffff18;color:#fff;box-shadow:none;border:2px solid #ffffff30}
#join,#wait,#count,#results{justify-content:center;gap:12px}
.pill{display:inline-flex;align-items:center;gap:8px;padding:7px 14px;border-radius:999px;background:#ffffff14;font-size:15px}
.dot{width:11px;height:11px;border-radius:50%;background:#e53935;box-shadow:0 0 8px #e53935}
.dot.ok{background:#43d65f;box-shadow:0 0 8px #43d65f}
.hint{font-size:14px;opacity:.6;text-align:center;max-width:320px;line-height:1.4;min-height:20px}
.spin{width:54px;height:54px;border-radius:50%;border:6px solid #ffffff25;border-top-color:var(--gold);animation:sp 1s linear infinite}
@keyframes sp{to{transform:rotate(360deg)}}
#head{display:flex;align-items:center;gap:12px;width:100%;max-width:420px;padding:10px 14px;border-radius:18px;background:#ffffff12;border-left:8px solid var(--c)}
#head .badge{width:42px;height:42px;border-radius:50%;background:var(--c);display:flex;align-items:center;justify-content:center;font-weight:900;font-size:22px;color:#1a1030}
#head b{font-size:21px;display:block}
#head span{font-size:13px;opacity:.65}
#cards{flex:1;width:100%;max-width:420px;overflow-y:auto;display:flex;flex-direction:column;gap:10px;margin:12px 0;padding:2px 2px 6px;-webkit-overflow-scrolling:touch;touch-action:pan-y}
.card{display:flex;align-items:center;gap:12px;padding:12px 14px;border-radius:18px;background:#ffffff10;border:3px solid transparent;text-align:left;position:relative;flex:0 0 auto}
.card .face{flex:0 0 46px;height:46px;border-radius:50%;border:3px solid #ffffff40;display:flex;align-items:center;justify-content:center;font-size:24px}
.card b{display:block;font-size:20px}
.card span{display:block;font-size:14px;opacity:.75;line-height:1.25}
.card.sel{border-color:var(--c);background:#ffffff1f;box-shadow:0 0 18px var(--c)}
.card.taken{opacity:.3}
.card .tag{position:absolute;right:12px;top:10px;font-size:12px;font-weight:800;padding:3px 8px;border-radius:8px;background:#00000066;display:none}
.card.taken .tag,.card.sel .tag{display:block}
#status{min-height:22px;opacity:.85;margin:0 0 10px;text-align:center;font-size:15px}
#countNum{font-size:170px;font-weight:900;color:var(--gold);text-shadow:0 7px 0 #6d4c00;animation:pop 1s ease-out infinite}
@keyframes pop{0%{transform:scale(1.5);opacity:.2}35%{transform:scale(1);opacity:1}100%{transform:scale(.9);opacity:.9}}
#play{padding:0;touch-action:none;background:radial-gradient(circle at 50% 65%,#33265a,#0e0919 70%)}
#hud{position:absolute;top:calc(env(safe-area-inset-top,0px) + 12px);left:14px;right:14px;pointer-events:none}
#hud .row{display:flex;justify-content:space-between;align-items:flex-end;font-size:30px;font-weight:900}
#hud small{display:block;font-size:11px;font-weight:700;opacity:.55;letter-spacing:2px}
#bar{height:12px;border-radius:8px;background:#ffffff20;margin-top:8px;overflow:hidden}
#barFill{height:100%;width:100%;border-radius:8px;background:#43d65f;transition:width .25s linear,background .3s}
#hint{position:absolute;bottom:20%;left:0;right:0;text-align:center;pointer-events:none}
#hint .ring{width:120px;height:120px;border-radius:50%;border:4px dashed #ffffff55;margin:0 auto 14px;animation:pulse 1.6s ease-in-out infinite}
@keyframes pulse{50%{transform:scale(1.12);opacity:.5}}
#hint div:last-child{opacity:.6;font-size:17px}
#over{position:absolute;top:36%;left:0;right:0;text-align:center;font-size:36px;font-weight:900;color:#ff8a80;display:none;pointer-events:none;text-shadow:0 3px 0 #000a}
#paused{position:absolute;inset:0;display:none;align-items:center;justify-content:center;flex-direction:column;background:#000a;font-size:44px;font-weight:900;color:var(--gold);pointer-events:none;text-shadow:0 4px 0 #000}
#paused small{font-size:16px;font-weight:600;color:#fff;opacity:.7;margin-top:8px}
#flash{position:absolute;inset:0;pointer-events:none;box-shadow:inset 0 0 90px 24px #ff1744;opacity:0;transition:opacity .35s}
#base,#knob{position:absolute;border-radius:50%;display:none;pointer-events:none}
#base{width:140px;height:140px;margin:-70px 0 0 -70px;border:4px solid var(--c);background:#ffffff14}
#knob{width:64px;height:64px;margin:-32px 0 0 -32px;background:var(--c);box-shadow:0 4px 14px #0008}
#medal{font-size:84px;line-height:1}
#rank{font-size:34px;font-weight:900;color:var(--gold)}
#list{width:100%;max-width:340px;margin:8px 0 14px}
.row2{display:flex;justify-content:space-between;align-items:center;padding:11px 14px;border-radius:14px;background:#ffffff12;margin-bottom:8px;font-size:20px;border-left:7px solid #888}
.row2.me{outline:3px solid var(--gold)}
#banner{position:fixed;left:0;right:0;top:0;padding:calc(env(safe-area-inset-top,0px) + 8px) 12px 8px;background:#b71c1c;text-align:center;display:none;z-index:9;font-weight:700}
#fx{margin-top:8px;font-size:18px;font-weight:800;min-height:24px;text-align:center}
#fx b{color:var(--gold);font-size:24px}
#fx .sh{color:#66e6ff}
#fx .mg{color:#ff8a80}
</style>
</head>
<body>
<div id='banner'></div>

<div id='join' class='screen'>
  <div class='crown'>👑</div>
  <h1>ROYAL RUN</h1>
  <p class='sub' data-i='joinSub'></p>
  <input id='nameIn' maxlength='12' autocomplete='off'>
  <button id='joinBtn' disabled data-i='joinBtn'></button>
  <div class='pill'><span class='dot' id='conDot'></span><span id='conText'></span></div>
  <p class='hint' id='conHint'></p>
</div>

<div id='wait' class='screen'>
  <div class='spin'></div>
  <h1 style='font-size:26px' data-i='waitTitle'></h1>
  <p class='sub' id='waitMsg'></p>
</div>

<div id='lobby' class='screen'>
  <div id='head'><div class='badge' id='slotNum'>1</div><div><b id='who'></b><span data-i='lobbyHead'></span></div></div>
  <div id='cards'></div>
  <p id='status'></p>
  <button id='readyBtn' disabled></button>
</div>

<div id='count' class='screen'>
  <p class='sub' data-i='getReady'></p>
  <div id='countNum'>3</div>
</div>

<div id='play' class='screen'>
  <div id='hud'>
    <div class='row'>
      <div><small data-i='time'></small><span id='hTime'>0</span></div>
      <div style='text-align:right'><small data-i='score'></small><span id='hScore'>0</span></div>
    </div>
    <div id='bar'><div id='barFill'></div></div>
    <div id='fx'></div>
  </div>
  <div id='hint'><div class='ring'></div><div data-i='drag'></div></div>
  <div id='over' data-i='timeUp'></div>
  <div id='paused'><span data-i='paused'></span><small data-i='pausedSub'></small></div>
  <div id='flash'></div>
  <div id='base'></div><div id='knob'></div>
</div>

<div id='results' class='screen'>
  <div id='medal'>🏆</div>
  <div id='rank'></div>
  <div id='list'></div>
  <button id='againBtn' data-i='again'></button>
</div>

<script>
(function(){
var $=function(i){return document.getElementById(i)};
var LANG='__RR_LANG__';
var I18N={
 en:{
  joinSub:""This is your controller.\nEnter a name and jump in!"",
  namePh:""Your name"",
  joinBtn:""Join the game"",
  connecting:""Connecting to the game..."",
  connected:""Connected to the game"",
  noCon:""No connection to the game"",
  noConHint:""Make sure the phone is on the same Wi-Fi network as the computer and the address starts with http://"",
  lost:""Connection lost"",
  reconnecting:""Reconnecting..."",
  lostBanner:""Connection lost. Reconnecting..."",
  waitTitle:""Please wait"",
  notReadyYet:""The game is not ready yet."",
  cantJoin:""You cannot join this game"",
  lobbyHead:""Pick a hero and tap READY"",
  ready:""READY"",
  notReady:""Not ready"",
  yours:""YOURS"",
  taken:""TAKEN"",
  tapHero:""Tap a hero to choose"",
  allSet:""All set? Tap READY"",
  waitOthers:""Waiting for the others: {0} of {1} ready"",
  getReady:""Get ready!"",
  go:""GO!"",
  time:""TIME"",
  score:""SCORE"",
  drag:""Drag your finger to run, tap to jump"",
  shield:""SHIELD"",
  magnet:""MAGNET"",
  timeUp:""TIME'S UP"",
  paused:""PAUSED"",
  pausedSub:""The host paused the game"",
  again:""Play again""
 },
 ru:{
  joinSub:""Это твой пульт.\nВведи имя и вперёд!"",
  namePh:""Твоё имя"",
  joinBtn:""Войти в игру"",
  connecting:""Подключаемся к игре..."",
  connected:""Подключено к игре"",
  noCon:""Нет связи с игрой"",
  noConHint:""Проверь, что телефон в той же сети Wi-Fi, что и компьютер, а адрес начинается с http://"",
  lost:""Связь потеряна"",
  reconnecting:""Переподключаемся..."",
  lostBanner:""Связь потеряна. Переподключаемся..."",
  waitTitle:""Подожди"",
  notReadyYet:""Игра ещё не готова."",
  cantJoin:""Нельзя присоединиться к этой игре"",
  lobbyHead:""Выбери героя и нажми ГОТОВ"",
  ready:""ГОТОВ"",
  notReady:""Не готов"",
  yours:""ТВОЙ"",
  taken:""ЗАНЯТ"",
  tapHero:""Нажми на героя, чтобы выбрать"",
  allSet:""Всё готово? Нажми ГОТОВ"",
  waitOthers:""Ждём остальных: готовы {0} из {1}"",
  getReady:""Приготовься!"",
  go:""ВПЕРЁД!"",
  time:""ВРЕМЯ"",
  score:""ОЧКИ"",
  drag:""Води пальцем - бег, коснись - прыжок"",
  shield:""ЩИТ"",
  magnet:""МАГНИТ"",
  timeUp:""ВРЕМЯ ВЫШЛО"",
  paused:""ПАУЗА"",
  pausedSub:""Ведущий поставил игру на паузу"",
  again:""Играть ещё""
 },
 uz:{
  joinSub:""Bu sizning pultingiz.\nIsmingizni yozing va boshlang!"",
  namePh:""Ismingiz"",
  joinBtn:""O‘yinga kirish"",
  connecting:""O‘yinga ulanmoqda..."",
  connected:""O‘yinga ulandi"",
  noCon:""O‘yin bilan aloqa yo‘q"",
  noConHint:""Telefon kompyuter bilan bir xil Wi-Fi tarmog‘ida ekanini va manzil http:// bilan boshlanishini tekshiring"",
  lost:""Aloqa uzildi"",
  reconnecting:""Qayta ulanmoqda..."",
  lostBanner:""Aloqa uzildi. Qayta ulanmoqda..."",
  waitTitle:""Kuting"",
  notReadyYet:""O‘yin hali tayyor emas."",
  cantJoin:""Bu o‘yinga qo‘shilib bo‘lmaydi"",
  lobbyHead:""Qahramon tanlang va TAYYOR tugmasini bosing"",
  ready:""TAYYOR"",
  notReady:""Tayyor emas"",
  yours:""SIZNIKI"",
  taken:""BAND"",
  tapHero:""Tanlash uchun qahramonga bosing"",
  allSet:""Hammasi tayyormi? TAYYOR tugmasini bosing"",
  waitOthers:""Boshqalar kutilmoqda: {0} / {1} tayyor"",
  getReady:""Tayyorlaning!"",
  go:""OLG‘A!"",
  time:""VAQT"",
  score:""OCHKO"",
  drag:""Barmoq bilan yurgizing - yugurish, tegining - sakrash"",
  shield:""QALQON"",
  magnet:""MAGNIT"",
  timeUp:""VAQT TUGADI"",
  paused:""PAUZA"",
  pausedSub:""Boshlovchi o‘yinni to‘xtatdi"",
  again:""Yana o‘ynash""
 }
};
if(!I18N[LANG])LANG='ru';
function tr(k){var d=I18N[LANG]||I18N.en;var s=d[k];if(s===undefined)s=I18N.en[k];return s===undefined?k:s}
function fmt(k){var s=tr(k);for(var i=1;i<arguments.length;i++){s=s.split('{'+(i-1)+'}').join(arguments[i])}return s}

var SCREENS=['join','wait','lobby','count','play','results'];
var cid=null,savedName='';
try{cid=localStorage.getItem('rr_cid');savedName=localStorage.getItem('rr_name')||''}catch(e){}
if(!cid){cid=Math.random().toString(36).slice(2)+Date.now().toString(36);try{localStorage.setItem('rr_cid',cid)}catch(e){}}

var ws=null,wantJoin=false,noRetry=false,current='',tries=0;
var me={slot:0,chars:[],char:-1,ready:false,color:'#9a8cc0'};
var lastLobby=null,lastResults=null,conState='connecting';
var COLORS=['#ef5350','#42a5f5','#66bb6a'];

function applyLang(){
  document.documentElement.lang=LANG;
  var els=document.querySelectorAll('[data-i]');
  for(var i=0;i<els.length;i++){els[i].textContent=tr(els[i].getAttribute('data-i'))}
  $('nameIn').placeholder=tr('namePh');
  renderCon();
  if(lastLobby)updateLobby(lastLobby);
  if(lastResults&&current==='results')showResults(lastResults);
}
function show(id){
  current=id;
  $('paused').style.display='none';
  SCREENS.forEach(function(s){$(s).style.display=(s===id?'flex':'none')});
}
function banner(text){var b=$('banner');if(text){b.textContent=text;b.style.display='block'}else{b.style.display='none'}}
function send(o){if(ws&&ws.readyState===1){ws.send(JSON.stringify(o));return true}return false}
function renderCon(){
  var ok=(conState==='ok');
  $('conDot').className='dot'+(ok?' ok':'');
  var t='connecting',h='';
  if(conState==='ok')t='connected';
  else if(conState==='fail'){t='noCon';h='noConHint'}
  else if(conState==='lost'){t='lost';h='reconnecting'}
  $('conText').textContent=tr(t);
  $('conHint').textContent=h?tr(h):'';
  $('joinBtn').disabled=!ok;
}
function setCon(state){conState=state;renderCon()}

function connect(){
  if(noRetry)return;
  tries++;
  var failTimer=setTimeout(function(){
    if(ws&&ws.readyState!==1){setCon('fail')}
  },4000);
  try{ws=new WebSocket('ws://'+location.host+'/ws')}catch(e){setTimeout(connect,1500);return}
  ws.onopen=function(){
    clearTimeout(failTimer);
    tries=0;banner('');
    setCon('ok');
    if(wantJoin){send({t:'join',cid:cid,name:savedName})}
  };
  ws.onmessage=function(ev){var m;try{m=JSON.parse(ev.data)}catch(e){return}handle(m)};
  ws.onclose=function(){
    clearTimeout(failTimer);
    endTouch();
    if(noRetry)return;
    setCon('lost');
    if(current!=='join')banner(tr('lostBanner'));
    setTimeout(connect,1500);
  };
}

function setLang(l){if(l&&I18N[l]&&l!==LANG){LANG=l;applyLang()}}

function handle(m){
  if(m.lang)setLang(m.lang);
  switch(m.t){
    case 'lang':
      break;
    case 'joined':
      me.slot=m.slot;me.chars=m.chars||[];me.color=m.color;
      document.documentElement.style.setProperty('--c',m.color);
      $('who').textContent=m.name;
      $('slotNum').textContent=(m.slot+1);
      buildCards();
      if(current==='join'||current==='wait'||current==='')show('lobby');
      break;
    case 'wait':
      wantJoin=true;
      $('waitMsg').textContent=m.msg||tr('notReadyYet');
      show('wait');
      setTimeout(function(){if(current==='wait')send({t:'join',cid:cid,name:savedName})},2000);
      break;
    case 'full':
      noRetry=true;wantJoin=false;
      banner(m.msg||tr('cantJoin'));
      break;
    case 'lobby':
      me.char=m.char;me.ready=m.ready;
      lastLobby=m;
      updateLobby(m);
      show('lobby');
      break;
    case 'count':
      $('countNum').textContent=(m.n>0?m.n:tr('go'));
      $('countNum').style.animation='none';void $('countNum').offsetWidth;$('countNum').style.animation='';
      show('count');
      break;
    case 'play':
      if(current!=='play'){show('play');$('hint').style.display='block'}
      $('hTime').textContent=m.time.toFixed(1);
      $('hScore').textContent=m.score;
      var r=Math.max(0,Math.min(1,m.time/40));
      var f=$('barFill');f.style.width=(r*100)+'%';
      f.style.background=r>0.4?'#43d65f':(r>0.2?'#ffc107':'#ff5252');
      $('over').style.display=m.over?'block':'none';
      var fx=[];
      if(m.mult>1)fx.push('<b>x'+m.mult+'</b>');
      if(m.shield)fx.push('<span class=\'sh\'>'+tr('shield')+'</span>');
      if(m.magnet)fx.push('<span class=\'mg\'>'+tr('magnet')+'</span>');
      $('fx').innerHTML=fx.join(' ');
      break;
    case 'pause':
      $('paused').style.display=(m.on&&current==='play')?'flex':'none';
      break;
    case 'hit':
      if(navigator.vibrate){navigator.vibrate(150)}
      var fl=$('flash');fl.style.opacity=1;setTimeout(function(){fl.style.opacity=0},180);
      break;
    case 'results':
      lastResults=m;
      showResults(m);
      break;
  }
}

var FACES=['👑','🛡️','🏹','⚗️','🔥'];
function buildCards(){
  var box=$('cards');box.innerHTML='';
  me.chars.forEach(function(c,i){
    var d=document.createElement('div');
    d.className='card';d.id='card'+i;
    var face=document.createElement('div');face.className='face';
    face.style.background=c.c+'55';face.textContent=FACES[i%FACES.length];
    var txt=document.createElement('div');
    var b=document.createElement('b');b.textContent=c.n;
    var sp=document.createElement('span');sp.textContent=c.d;
    txt.appendChild(b);txt.appendChild(sp);
    var tag=document.createElement('div');tag.className='tag';
    d.appendChild(face);d.appendChild(txt);d.appendChild(tag);
    d.addEventListener('click',function(){send({t:'char',id:i})});
    box.appendChild(d);
  });
}

function updateLobby(m){
  me.chars.forEach(function(c,i){
    var el=$('card'+i);if(!el)return;
    var mine=(i===me.char),tk=(m.taken&&m.taken[i]&&!mine);
    el.className='card'+(mine?' sel':'')+(tk?' taken':'');
    el.querySelector('.tag').textContent=mine?tr('yours'):tr('taken');
  });
  var rb=$('readyBtn');
  rb.disabled=(me.char<0);
  rb.textContent=me.ready?tr('notReady'):tr('ready');
  rb.className=me.ready?'ghost':'';
  var st=$('status');
  if(me.char<0)st.textContent=tr('tapHero');
  else if(!me.ready)st.textContent=tr('allSet');
  else st.textContent=fmt('waitOthers',m.readyCount,m.players);
}

function placeText(rk){
  if(LANG==='ru')return rk+'-е место';
  if(LANG==='uz')return rk+'-o‘rin';
  var sfx=['th','st','nd','rd'];
  var ord=(rk%100>=11&&rk%100<=13)?'th':(sfx[rk%10<4?rk%10:0]);
  return rk+ord+' place';
}

function showResults(m){
  var medals=['🥇','🥈','🥉'];
  $('medal').textContent=medals[m.rank-1]||'🏁';
  $('rank').textContent=placeText(m.rank);
  var l=$('list');l.innerHTML='';
  (m.list||[]).forEach(function(r,i){
    var d=document.createElement('div');
    d.className='row2'+(r.slot===me.slot?' me':'');
    d.style.borderLeftColor=COLORS[r.slot%3];
    var a=document.createElement('span');a.textContent=(i+1)+'. '+r.name;
    var b=document.createElement('b');b.textContent=r.score;
    d.appendChild(a);d.appendChild(b);l.appendChild(d);
  });
  if(current!=='results')$('againBtn').disabled=false;
  show('results');
}

$('joinBtn').addEventListener('click',function(){
  var n=$('nameIn').value.trim();
  savedName=n;
  try{localStorage.setItem('rr_name',n)}catch(e){}
  wantJoin=true;
  send({t:'join',cid:cid,name:n});
});
$('nameIn').addEventListener('keydown',function(e){if(e.key==='Enter'){$('joinBtn').click()}});
$('readyBtn').addEventListener('click',function(){send({t:'ready',v:!me.ready})});
$('againBtn').addEventListener('click',function(){$('againBtn').disabled=true;send({t:'again'})});

/* ---------- floating joystick ---------- */
var area=$('play'),base=$('base'),knob=$('knob');
var R=70,DEAD=0.12,active=-1,ox=0,oy=0,vx=0,vy=0,lastSend=0,pending=null,downAt=0,maxMove=0;

function sendNow(){pending=null;lastSend=Date.now();send({t:'move',x:+vx.toFixed(3),y:+vy.toFixed(3)})}
function sendMove(force){
  var n=Date.now();
  if(force||n-lastSend>=33){sendNow()}
  else if(pending===null){pending=setTimeout(sendNow,33-(n-lastSend))}
}
function place(el,x,y){el.style.left=x+'px';el.style.top=y+'px'}
function update(e){
  var dx=e.clientX-ox,dy=e.clientY-oy,d=Math.sqrt(dx*dx+dy*dy);
  if(d>maxMove)maxMove=d;
  if(d>R){dx*=R/d;dy*=R/d;d=R}
  place(knob,ox+dx,oy+dy);
  if(d<R*DEAD){vx=0;vy=0}else{vx=dx/R;vy=-dy/R}
  sendMove(false);
}
function endTouch(){
  if(active===-1)return;
  active=-1;vx=0;vy=0;
  if(pending!==null){clearTimeout(pending);pending=null}
  base.style.display='none';knob.style.display='none';
  send({t:'move',x:0,y:0});
}
area.addEventListener('pointerdown',function(e){
  if(active!==-1)return;
  active=e.pointerId;
  try{area.setPointerCapture(e.pointerId)}catch(x){}
  ox=e.clientX;oy=e.clientY;downAt=Date.now();maxMove=0;
  place(base,ox,oy);place(knob,ox,oy);
  base.style.display='block';knob.style.display='block';
  $('hint').style.display='none';
  update(e);e.preventDefault();
});
area.addEventListener('pointermove',function(e){if(e.pointerId===active){update(e);e.preventDefault()}});
area.addEventListener('pointerup',function(e){
  if(e.pointerId!==active)return;
  // a short touch without dragging = jump
  if(Date.now()-downAt<250&&maxMove<18){send({t:'jump'});if(navigator.vibrate){navigator.vibrate(20)}}
  endTouch();
});
area.addEventListener('pointercancel',function(e){if(e.pointerId===active)endTouch()});
setInterval(function(){if(active!==-1)sendMove(true)},200);
document.addEventListener('visibilitychange',function(){if(document.hidden)endTouch()});
document.addEventListener('contextmenu',function(e){e.preventDefault()});
// block page scrolling only during the game - in the lobby the hero list must scroll
document.addEventListener('touchmove',function(e){if(current==='play')e.preventDefault()},{passive:false});

/* ---------- start ---------- */
$('nameIn').value=savedName;
applyLang();
show('join');
connect();
})();
</script>
</body>
</html>
";

    // Страница с нужным языком. Вызывается из сетевого потока - Unity API здесь не используется.
    public static string Build(string langCode)
    {
        return Html.Replace(LangToken, langCode);
    }
}
