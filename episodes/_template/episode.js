// __TITLE__ — подключение серии к движку (engine/src/main.js).
import { buildShots } from './shots.js';

export default {
  title: '__TITLE__',
  buildShots,

  // «живые» части общего мира в момент t (сюжетное время):
  //   police — полицейские машины у моста, crowd — толпа на мосту, bridge — обломки/дым/вертолёт, alarm — тревога в лаборатории
  world: t => ({}),

  // цветокоррекция по сюжетному времени: night, neutral, street, lab, danger, sense, action, bridge, calm, kitchen, dawn, tag
  gradeAt(t) {
    if (t < 12) return 'tag';
    if (t < 16) return 'neutral';
    if (t < 30) return 'street';
    if (t < 42) return 'kitchen';
    return 'tag';
  },

  // где включать motion blur (только рендер на видеокарте): [[от, до], …]
  mblur: [[16, 30]],
};
