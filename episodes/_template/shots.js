// __TITLE__ — шоты серии. Это рабочий пример-заготовка: 5 шотов, которые показывают основные приёмы.
// Время везде СЮЖЕТНОЕ (как в dialogue.json и audio/cues.py). Каждый шот — функция (lt, t): lt — время от начала шота,
// t — время серии. Шот расставляет персонажей, позы, лица, камеру и эффекты и возвращает сцену для рендера.
// Все помощники — engine/src/director.js; позы — POSE (engine/src/rig.js) и FIGHT/HEAVY (director.js).
import * as THREE from 'three';
import { makeDirector, FIGHT, V, L2W, yawTo, E, P, kf, lerp, clamp, pulse, POSE, seq, gait, squash, springAt } from 'engine/director.js';

export function buildShots(C) {
  const D = makeDirector(C);
  const { S, shot, look, move, place, face, post, impact, comic, caption, web, drone, headW, fadeIn, fadeOut, env, rimOn } = D;
  const { kitchen, lair, ch, U } = C;
  const { timur: TI, ded: DE, vera: VE, kronov: KR, shadow: SH } = ch;
  const K = kitchen.scene, Z = lair.scene;

  // 1. Холодное начало: логово Тени (s1)
  shot(0, 12, (lt, t) => {
    place(SH, Z, [0, .02, .2], 0);
    SH.pose(POSE.sitChair(t * .5));
    face(SH, 'shadow', t, { seed: 4 });
    SH.redEyes.visible = t > 1.5;
    lair.red.intensity = 10 + 6 * Math.sin(t * 2);
    move(t, [[0, [.9, 1.9, 6.4], [0, 1.6, .2], 46], [12, [.3, 1.8, 3.0], [0, 1.7, .2], 32]]);
    fadeIn(lt, 1); fadeOut(lt, 12, .5);
    return Z;
  }, { noFlash: true });

  // 2. Заставка серии
  shot(12, 16, (lt, t) => {
    D.titleCard(lt, 'СЕРИЯ __N__ · __CAPS__');
    post(o => o.fill('#000', (lt - 3.5) / .5));
    return S;
  }, { noSubs: true, noFlash: true });

  // 3. Город: Тимур в костюме на крыше у моста, говорит (t1); комикс-надпись и «кадр удара»
  shot(16, 30, (lt, t) => {
    env({ key: 1.6, rim: 2.0, rimPos: [360, 60, -420] });
    TI.setSuit(true);
    place(TI, S, [292, 74.1, -362], Math.PI / 2);                 // крыша у Северного моста, смотрит на мост (+x)
    TI.pose(seq(t - 16, [[0, POSE.heroLand()], [1.2, FIGHT.guard, .5], [6, tt => POSE.stand(tt), .6]]));
    squash(TI, springAt(t, 16.2, -.24, 15, 7));
    face(TI, 'timur', t, { squint: .5, energy: .6 });
    rimOn([292, 75.3, -362], 0xa8f0ff, 2.6);
    move(t, [[16, [286.6, 77, -355.4], [292, 75.8, -362], 50], [30, [289, 75.6, -358.6], [292, 75.6, -362], 38]]);
    impact(t, 16.2, { zoom: .12, shake: .2 });
    comic('ТУДУМ!', 560, 320, t - 16.2, { size: .5, color: '#ffffff', dur: .8 });
    fadeIn(lt, .4);
    return S;
  }, { flashK: .7 });

  // 4. Кухня деда: дед и внук за столом (d1, t2)
  shot(30, 42, (lt, t) => {
    place(DE, K, [-.55, 0, -1.45], 0); DE.pose(POSE.sitChair(t)); face(DE, 'ded', t, { seed: 2, smile: t > 37 ? .8 : 0, look: [.5, 0] });
    place(TI, K, [.55, 0, .25], Math.PI); TI.pose(FIGHT.eat(t)); face(TI, 'timur', t, { smile: .4, look: [0, -.5] });
    kitchen.flashLight.intensity = 3 + 25 * U.flash.value;
    if (t < 35) look([1.9, 1.6, 1.7], [0, .95, -.75], 42);
    else { const hp = headW(DE); look(hp.clone().add(V(.35, .02, 1.05)).toArray(), hp.clone().add(V(0, -.06, 0)).toArray(), 32); }
    fadeIn(lt, .5);
    return K;
  });

  // 5. Логотип и «продолжение следует»
  shot(42, 48, (lt, t) => {
    look([0, 100, 200], [0, 100, 0], 45);
    post(o => o.logo(lt, { sub: 'КОНЕЦ СЕРИИ __N__' }));
    post(o => o.title([{ text: 'мультфильм студии', font: '500 28px Rubik', y: 958, color: '#9fb4d8' },
      { text: 'GraphicArts Animation', font: '800 42px Unbounded', y: 1008, color: '#ffffff', stroke: 8, glow: '#ff7b1c' }], clamp((lt - 1.0) / .6)));
    post(o => o.fill('#000', (lt - 5.4) / .5));
    return S;
  }, { noSubs: true, noFlash: true });

  return D.shots;
}
