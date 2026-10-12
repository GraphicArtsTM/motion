// Серия 1 «Укус молнии» — подключение к движку.
// Движок (engine/src/main.js) берёт отсюда шоты, настройки «живого» мира, цветокоррекцию и motion blur.
import { buildShots } from './shots.js';

export default {
  title: 'Серия 1 · Укус молнии',
  buildShots,

  // какие части общего мира «живут» в момент t (сюжетное время)
  world: t => ({
    police: t >= 117 && t < 183,      // полицейские машины у моста
    crowd: t >= 117 && t < 183,       // толпа на мосту
    bridge: t >= 117 && t < 183,      // обломки, дым, вертолёт с прожектором
    alarm: t >= 62 && t < 83,         // тревога в лаборатории
  }),

  // цветокоррекция по сюжетному времени (пресеты — engine/src/post.js, GRADES)
  gradeAt(t) {
    if (t < 16.5) return 'night';
    if (t < 21) return 'neutral';
    if (t < 44) return 'street';
    if (t < 48) return 'night';
    if (t < 62) return 'lab';
    if (t < 80.2) return 'danger';
    if (t < 90) return 'night';
    if (t < 97) return 'sense';
    if (t < 117.2) return 'action';
    if (t < 175) return 'bridge';
    if (t < 183) return 'calm';
    if (t < 195) return 'kitchen';
    if (t < 203) return t >= 198.4 && t < 200.2 ? 'lab' : 'dawn';
    if (t < 207) return 'neutral';
    return 'tag';
  },

  // где включать motion blur (только рендер на видеокарте, q=high)
  mblur: [[21, 44], [44, 46], [62, 63.4], [72.5, 83], [97, 123], [123, 133], [140, 175]],
};
