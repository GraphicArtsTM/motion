// Серия 2 «Сигнал» — подключение к движку (см. engine/src/main.js).
import { buildShots } from './shots.js';

export default {
  title: 'Серия 2 · Сигнал',
  buildShots,

  // «живые» части общего мира: в этой серии мост спокоен, полиции и толпы нет; тревога — когда дроны в лаборатории
  world: t => ({ alarm: t >= 186.4 && t < 206 }),

  gradeAt(t) {
    if (t < 16.5) return 'tag';
    if (t < 20.5) return 'neutral';
    if (t < 48) return 'kitchen';
    if (t < 78) return 'street';
    if (t < 96) return 'lab';
    if (t < 108) return t > 98.3 && t < 101.6 ? 'sense' : 'night';
    if (t < 150) return 'action';
    if (t < 186) return 'lab';
    if (t < 206) return 'danger';
    if (t < 222.3) return 'kitchen';
    if (t < 226) return 'neutral';
    return 'tag';
  },

  mblur: [[48.4, 64], [96, 150], [186, 206]],
};
