// Новоград: небо, небоскрёбы (инстансы с процедурными окнами), мокрые улицы, река, мост, башня «Аркада»,
// фонари, неон, машины, дождь и молнии. Всё детерминировано.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon, glow, mesh, rng, textTexture, clamp } from './core.js';

export const U = {                       // общие униформы окружения
  flash: { value: 0 }, time: { value: 0 }, fogColor: { value: new THREE.Color(0x141a2e) }, fogDensity: { value: .0021 },
  tint: { value: new THREE.Color(1, 1, 1) }, rainTime: { value: 0 }, sense: { value: 0 },
};

const GLSL_COMMON = `
float h21(vec2 p){ p = fract(p*vec2(123.34, 456.21)); p += dot(p, p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.-2.*f);
  return mix(mix(h21(i),h21(i+vec2(1,0)),f.x), mix(h21(i+vec2(0,1)),h21(i+vec2(1,1)),f.x), f.y); }
float fbm(vec2 p){ float a=.5, s=0.; for(int i=0;i<5;i++){ s+=a*vnoise(p); p*=2.03; a*=.5; } return s; }
vec3 applyFog(vec3 col, vec3 wp){ float d = length(wp - cameraPosition); float f = 1. - exp(-fogDensity*fogDensity*d*d);
  return mix(col, fogColor, clamp(f,0.,1.)); }
`;
const UNI_DECL = `uniform float flash; uniform float time; uniform vec3 fogColor; uniform float fogDensity; uniform vec3 tint; uniform float sense;`;

/* ---------- небо: градиент + грозовые облака, подсвеченные молнией ---------- */
function makeSky() {
  const mat = new THREE.ShaderMaterial({
    uniforms: { ...U, dawn: { value: 0 } }, side: THREE.BackSide, depthWrite: false, fog: false,
    vertexShader: `varying vec3 vD; void main(){ vD = normalize(position); vec4 p = projectionMatrix*modelViewMatrix*vec4(position,1.); gl_Position = p.xyww; }`,
    fragmentShader: `${UNI_DECL} uniform float dawn; varying vec3 vD; ${GLSL_COMMON}
    void main(){
      float y = vD.y;
      vec3 top = mix(vec3(.02,.025,.06), vec3(.05,.08,.2), dawn);
      vec3 hor = mix(vec3(.22,.14,.24), vec3(.95,.55,.35), dawn);
      vec3 col = mix(hor, top, smoothstep(-.05,.45,y));
      vec2 uv = vD.xz/(y+.35)*1.6;
      float c = fbm(uv*1.3 + vec2(time*.02, 0.)), c2 = fbm(uv*3.1 - vec2(time*.03,time*.01));
      float cl = smoothstep(.35,.85,c*.7+c2*.4)*(1.-dawn*.7);
      col = mix(col, vec3(.09,.09,.15)+hor*.25, cl*smoothstep(-.1,.2,y));
      col += flash*vec3(.55,.6,1.)*(.35+cl*1.2)*smoothstep(-.1,.3,y);
      col = mix(col, vec3(.05,.12,.25), sense*.5);
      col += (h21(gl_FragCoord.xy + fract(time)*91.) - .5)/180.;
      gl_FragColor = vec4(col*tint,1.);
      #include <colorspace_fragment>
    }`,
  });
  const m = new THREE.Mesh(new THREE.SphereGeometry(2600, 48, 24), mat);
  m.renderOrder = -10; m.frustumCulled = false;
  m.userData.mat = mat;
  return m;
}

/* ---------- материал зданий: процедурные окна, витрины, вспышки ---------- */
export function buildingMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: U,
    vertexShader: `attribute vec3 aColor; attribute vec2 aSeed;
      varying vec3 vW, vN, vL, vC; varying vec2 vS;
      void main(){
        mat4 im = instanceMatrix;
        vec3 sc = vec3(length(im[0].xyz), length(im[1].xyz), length(im[2].xyz));
        vL = position*sc; vC = aColor; vS = aSeed;
        vN = normalize(mat3(modelMatrix*im)*normal);
        vec4 wp = modelMatrix*im*vec4(position,1.); vW = wp.xyz;
        gl_Position = projectionMatrix*viewMatrix*wp;
      }`,
    fragmentShader: `${UNI_DECL} varying vec3 vW, vN, vL, vC; varying vec2 vS; ${GLSL_COMMON}
      void main(){
        vec3 n = normalize(vN);
        vec3 base = vC;
        vec3 L = normalize(vec3(-.45,.75,.5));
        float dif = max(dot(n,L),0.);
        float side = 1.-step(.5, abs(n.y));
        float u = abs(n.x) > .5 ? vL.z : vL.x;
        float v = vL.y;
        float style = vS.y;
        vec3 col;
        if (side > .5) {
          float fh = style > 1.5 ? 4.2 : 3.6, cw = style > 1.5 ? 2.0 : 3.2;
          vec2 cell = floor(vec2(u/cw, v/fh)), f = fract(vec2(u/cw, v/fh));
          float win = style > 1.5 ? step(.04,f.x)*step(.3,f.y)*step(f.y,.85) : step(.2,f.x)*step(f.x,.8)*step(.28,f.y)*step(f.y,.82);
          float r = h21(cell + vS.x*37.1 + n.xz*11.3);
          float block = h21(floor(vec2(u/(cw*4.), v/(fh*3.))) + vS.x*9.);
          float lit = step(.52 + .3*block, r);
          vec3 wc = mix(vec3(1.,.74,.42), vec3(.62,.82,1.), step(.72, h21(cell*1.7+vS.x)));
          wc = mix(wc, vec3(.9,.45,1.), step(.95, h21(cell*2.3+vS.x*3.)));
          float shade = .3 + .5*dif;
          col = base*shade;
          // жизнь в окнах: силуэты людей и мерцание телевизоров
          float who = step(.9, h21(cell*3.1 + vS.x*5.)) * lit;
          vec2 q = f - vec2(.5, .5);
          float head = 1. - step(.075, length((q - vec2(0., .1))*vec2(1., .9)));
          float body = step(abs(q.x), .1) * step(q.y, .02);
          float sil = who * max(head, body) * step(.28, f.y);
          float tv = step(.965, h21(cell*4.7 + vS.x*2.)) * lit;
          vec3 tvc = vec3(.45, .65, 1.) * (.55 + .45*sin(time*11. + r*40.)*sin(time*4.3 + r*9.));
          wc = mix(wc, tvc, tv);
          float glass = win*(1.-lit);
          vec3 cWin = mix(base*shade, base*.18 + vec3(.02,.03,.06) + flash*.25, glass);
          cWin += win*lit*wc*(.55 + .45*r)*.95*(1. - .8*sil);
          // сглаживание вдали: когда окно меньше ~2 пикселей, заменяем узор средним цветом (нет ряби и «лесенки»)
          vec2 fw = fwidth(vec2(u/cw, v/fh));
          float aa = smoothstep(.18, .5, max(fw.x, fw.y));
          vec3 avg = base*shade*.7 + vec3(1.,.8,.55)*.16*(.6 + .8*(1. - block));
          col = mix(cWin, avg, aa);
          // витрины первого этажа
          float shop = step(.6, v)*step(v, 3.9)*step(.08, fract(u/7.))*step(fract(u/7.), .92);
          vec3 sc = mix(vec3(1.,.55,.25), vec3(.3,.9,1.), h21(vec2(floor(u/7.), vS.x)));
          col = mix(col, sc*.9, shop*step(.35, h21(vec2(floor(u/7.)+3., vS.x))));
          col *= mix(.55, 1., smoothstep(0., 5., v));
          // мокрые потёки
          col *= .92 + .08*vnoise(vec2(u*.7, v*.05+vS.x));
        } else {
          col = base*.5*(.6+.4*dif) + vec3(.025);
          col *= .75 + .25*vnoise(vW.xz*.8) * (.7 + .3*vnoise(vW.xz*7.));
          vec2 tl = abs(fract(vW.xz/4.) - .5);
          col *= 1. - .25*step(.47, max(tl.x, tl.y));
          float pud = smoothstep(.6, .66, vnoise(vW.xz*.35 + vS.x*20.));
          vec3 V = normalize(cameraPosition - vW);
          col = mix(col, vec3(.12,.1,.2) + flash*vec3(.6,.65,1.), pud*(.4 + .5*pow(1.-V.y, 2.)));
        }
        col += flash*vec3(.45,.5,.8)*(.25+.75*dif)*(side>.5?1.:1.4);
        col = mix(col, col*vec3(.45,.75,1.3), sense);
        col = applyFog(col, vW)*tint;
        gl_FragColor = vec4(col,1.);
        #include <colorspace_fragment>
      }`,
  });
}

/* ---------- улицы ---------- */
function groundMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: U,
    vertexShader: `varying vec3 vW; void main(){ vec4 wp = modelMatrix*vec4(position,1.); vW = wp.xyz; gl_Position = projectionMatrix*viewMatrix*wp; }`,
    fragmentShader: `${UNI_DECL} uniform float rainTime; varying vec3 vW; ${GLSL_COMMON}
      void main(){
        vec2 p = vW.xz;
        vec2 m = mod(p + 10., 80.);                 // 0..20 — улица, 20..80 — квартал
        float streetX = step(m.x, 20.), streetZ = step(m.y, 20.);
        float street = max(streetX, streetZ);
        vec3 asphalt = vec3(.045,.05,.065) * (.8 + .4*vnoise(p*.4));
        vec3 walk = vec3(.12,.12,.14) * (.85 + .15*step(.5, fract(p.x*.5)+fract(p.y*.5)*.0));
        vec3 col = mix(walk, asphalt, street);
        // разметка
        float cx = abs(m.x - 10.), cz = abs(m.y - 10.);
        float dashZ = step(cx, .12) * step(.5, fract(p.y/6.)) * streetX * (1.-streetZ);
        float dashX = step(cz, .12) * step(.5, fract(p.x/6.)) * streetZ * (1.-streetX);
        float edgeX = step(abs(cx-8.6), .1) * streetX * (1.-streetZ);
        float edgeZ = step(abs(cz-8.6), .1) * streetZ * (1.-streetX);
        float zebra = step(.5, fract(p.x*.8)) * step(abs(m.y-23.),2.) * streetX + step(.5, fract(p.y*.8)) * step(abs(m.x-23.),2.) * streetZ;
        col += vec3(.75,.72,.6)*(dashZ+dashX)*.55 + vec3(.6)*(edgeX+edgeZ)*.35 + vec3(.5)*zebra*.25*street;
        // пятна света фонарей (сетка фонарей вдоль улиц, шаг 25 м)
        vec2 lp = vec2(m.x < 10. ? 1.2 : 18.8, 0.);
        float dl1 = length(vec2(m.x - (m.x<10.?1.:19.), mod(p.y, 25.) - 12.5));
        float dl2 = length(vec2(m.y - (m.y<10.?1.:19.), mod(p.x, 25.) - 12.5));
        float pool = exp(-dl1*dl1/26.)*streetX + exp(-dl2*dl2/26.)*streetZ;
        col += vec3(1.,.72,.42)*pool*.38;
        // мокрый асфальт: френель + отражённое свечение города + лужи
        vec3 V = normalize(cameraPosition - vW);
        float fr = pow(1. - max(V.y, 0.), 4.);
        float puddle = smoothstep(.55, .62, vnoise(p*.12) );
        vec3 refl = vec3(.08,.07,.13) + flash*vec3(.7,.75,1.);
        refl += vec3(1.,.7,.4)*pool*.6;
        // отражения неоновых вывесок в лужах вдоль проспекта — вытянутые цветные полосы
        vec3 neon = .55 + .45*cos(6.2832*(h21(vec2(floor((p.y + 8.)/34.), 3.)) + vec3(0., .33, .67)));
        float lane = step(abs(p.x), 11.) * (.5 + .5*sin(p.y*.9 + vnoise(p*.3)*4.)) * smoothstep(.0, .4, vnoise(vec2(p.x*.6, p.y*.05)));
        refl += neon * lane * .55;
        col = mix(col, refl, fr*(.25 + .5*puddle));
        // рябь от капель
        vec2 rc = floor(p*1.5); vec2 rf = fract(p*1.5)-.5; float ph = fract(rainTime*1.3 + h21(rc));
        float ring = smoothstep(.03,.0, abs(length(rf) - ph*.3)) * (1.-ph) * puddle;
        col += vec3(.25,.3,.4)*ring*.12;
        col += flash*vec3(.25,.28,.4);
        col = mix(col, col*vec3(.45,.75,1.3), sense);
        col = applyFog(col, vW)*tint;
        gl_FragColor = vec4(col,1.);
        #include <colorspace_fragment>
      }`,
  });
}

/* ---------- вода ---------- */
function waterMaterial() {
  return new THREE.ShaderMaterial({
    uniforms: U,
    vertexShader: `varying vec3 vW; void main(){ vec4 wp = modelMatrix*vec4(position,1.); vW = wp.xyz; gl_Position = projectionMatrix*viewMatrix*wp; }`,
    fragmentShader: `${UNI_DECL} varying vec3 vW; ${GLSL_COMMON}
      void main(){
        vec2 p = vW.xz;
        float w = fbm(p*.05 + vec2(time*.05, time*.02));
        vec3 col = vec3(.02,.04,.08) + vec3(.03,.05,.09)*w;
        // отражения огней дальнего берега — вертикальные дорожки
        float lane = pow(vnoise(vec2(p.y*.08, 0.)), 3.) * smoothstep(.35, .9, vnoise(vec2(p.y*.4, p.x*.05 - time*.5)));
        col += vec3(1.,.65,.35)*lane*.55*smoothstep(-200., 200., p.x - 300.);
        vec3 V = normalize(cameraPosition - vW);
        float fr = pow(1. - max(V.y,0.), 3.);
        col += vec3(.16,.13,.25)*fr + flash*vec3(.5,.55,.9)*(.3+fr);
        col = applyFog(col, vW)*tint;
        gl_FragColor = vec4(col,1.);
        #include <colorspace_fragment>
      }`,
  });
}

/* ---------- дождь: отрезки, падающие в шейдере вокруг камеры ---------- */
function makeRain(n = 9000) {
  const box = 60;
  const r = rng(77);
  const pos = new Float32Array(n * 6), seed = new Float32Array(n * 2), end = new Float32Array(n * 2);
  for (let i = 0; i < n; i++) {
    const x = r() * box, y = r() * box, z = r() * box;
    pos.set([x, y, z, x, y, z], i * 6);
    seed.set([r(), r()], i * 2);
    end.set([0, 1], i * 2);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('aEnd', new THREE.BufferAttribute(end, 1));
  const mat = new THREE.ShaderMaterial({
    uniforms: { ...U, box: { value: box }, len: { value: 1.3 }, center: { value: new THREE.Vector3() }, alpha: { value: .7 }, wind: { value: new THREE.Vector2(.08, .03) } },
    transparent: true, depthWrite: false,
    vertexShader: `uniform float rainTime, box, len; uniform vec3 center; uniform vec2 wind; attribute float aEnd; varying float vA;
      void main(){
        vec3 p = position;
        p.y -= rainTime*26.;
        p.xz += wind*rainTime*26.;
        p = mod(p - center + box*.5, box) + center - box*.5;
        p.y += aEnd*len; p.xz -= aEnd*wind*len;
        vA = 1. - aEnd*.7;
        vec4 mv = viewMatrix*vec4(p,1.);
        vA *= smoothstep(1., 4., -mv.z) * (1. - smoothstep(box*.35, box*.5, -mv.z));
        gl_Position = projectionMatrix*mv;
      }`,
    fragmentShader: `uniform float alpha; uniform float flash; uniform float sense; varying float vA;
      void main(){ vec3 c = mix(vec3(.62,.7,.85), vec3(.6,1.,1.1), sense) + flash*.6; gl_FragColor = vec4(c, vA*alpha*(1.+sense)); }`,
  });
  const ls = new THREE.LineSegments(g, mat);
  ls.frustumCulled = false; ls.renderOrder = 5;
  ls.userData.mat = mat;
  return ls;
}

/* ---------- молния: ломаная из тонких светящихся сегментов ---------- */
export function makeBolt(a, b, seed = 1, o = {}) {
  const r = rng(seed);
  const pts = [a.clone()];
  const n = o.segs || 18, dir = b.clone().sub(a);
  for (let i = 1; i < n; i++) {
    const p = a.clone().addScaledVector(dir, i / n);
    const amp = dir.length() * .045 * (o.jag || 1);
    p.x += (r() - .5) * amp * 2; p.z += (r() - .5) * amp * 2; p.y += (r() - .5) * amp * .5;
    pts.push(p);
  }
  pts.push(b.clone());
  const geos = [];
  const seg = (p, q, w) => {
    const len = p.distanceTo(q);
    const gg = new THREE.CylinderGeometry(w, w, len, 5, 1);
    gg.translate(0, len / 2, 0);
    const m4 = new THREE.Matrix4().lookAt(p, q, new THREE.Vector3(0, 1, 0).applyAxisAngle(new THREE.Vector3(1, 0, 0), .001));
    const qu = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 1, 0), q.clone().sub(p).normalize());
    gg.applyQuaternion(qu); gg.translate(p.x, p.y, p.z);
    geos.push(gg);
  };
  const W = o.width || .9;
  for (let i = 0; i < pts.length - 1; i++) seg(pts[i], pts[i + 1], W);
  for (let k = 0; k < (o.branches ?? 5); k++) {       // ветки
    const i0 = 2 + Math.floor(r() * (pts.length - 6));
    let p = pts[i0].clone();
    for (let j = 0; j < 5; j++) {
      const q = p.clone().add(new THREE.Vector3((r() - .5) * 18, -6 - r() * 10, (r() - .5) * 18).multiplyScalar((o.scale || 1)));
      seg(p, q, W * .45); p = q;
    }
  }
  const m = new THREE.Mesh(mergeGeometries(geos), glow(0xcfe0ff, 6, { transparent: true }));
  m.frustumCulled = false;
  return m;
}

/* ---------- машины ---------- */
const CAR_COLORS = [0xd8342c, 0xf2c230, 0x2b6fd6, 0xeeeeee, 0x262a33, 0x1c9a6a, 0xff8a1d, 0x7b3fc4];
export function makeCar(i, taxi = false) {
  const g = new THREE.Group();
  const col = taxi ? 0xffc21a : CAR_COLORS[i % CAR_COLORS.length];
  const OL = .05;
  mesh(new RoundedBoxGeometry(2.0, .75, 4.4, 3, .25), toon(col), { pos: [0, .7, 0], outline: OL, parent: g });
  mesh(new RoundedBoxGeometry(1.75, .62, 2.3, 3, .25), toon(0x1a2333), { pos: [0, 1.35, -.2], outline: OL, parent: g });
  if (taxi) mesh(new THREE.BoxGeometry(.6, .22, .3), glow(0xffe08a, 1.6), { pos: [0, 1.75, -.2], outline: .03, parent: g });
  const wheel = new THREE.CylinderGeometry(.38, .38, .3, 14);
  for (const [x, z] of [[1, 1.4], [-1, 1.4], [1, -1.4], [-1, -1.4]]) mesh(wheel, toon(0x111111), { pos: [x * .95, .38, z], rot: [0, 0, Math.PI / 2], outline: false, parent: g });
  const hl = glow(0xfff4d6, 4), tl = glow(0xff2020, 3);
  for (const x of [-.65, .65]) {
    mesh(new THREE.BoxGeometry(.42, .16, .05), hl, { pos: [x, .78, 2.21], outline: false, parent: g });
    mesh(new THREE.BoxGeometry(.42, .14, .05), tl, { pos: [x, .82, -2.21], outline: false, parent: g });
  }
  // конус света фар
  const beam = new THREE.Mesh(new THREE.ConeGeometry(2.4, 14, 16, 1, true), new THREE.MeshBasicMaterial({ color: 0xfff1cc, transparent: true, opacity: .06, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending }));
  beam.rotation.x = -Math.PI / 2; beam.position.set(0, .7, 2.2 + 7); g.add(beam);
  g.traverse(m => { if (m.isMesh) m.frustumCulled = false; });
  return g;
}

/* ---------- автобус №42 ---------- */
export function makeBus() {
  const g = new THREE.Group();
  const OL = .06;
  const body = new THREE.Group(); g.add(body);
  mesh(new RoundedBoxGeometry(2.6, 3.0, 12, 3, .35), toon(0xc9c9c2), { pos: [0, 1.95, 0], outline: OL, parent: body });
  mesh(new RoundedBoxGeometry(2.64, .7, 12.04, 3, .2), toon(0xe0352b), { pos: [0, .9, 0], outline: false, parent: body });
  mesh(new THREE.BoxGeometry(2.66, 1.0, 10.2), glow(0xffd9a0, 1.05), { pos: [0, 2.35, -.4], outline: false, parent: body });   // окна (тёплый салон)
  for (let i = 0; i < 6; i++) mesh(new THREE.BoxGeometry(2.7, 1.05, .14), toon(0x1a1d24), { pos: [0, 2.35, -5.2 + i * 1.75], outline: false, parent: body });
  mesh(new THREE.BoxGeometry(2.4, 1.4, .08), toon(0x1b2a3a, { emissive: 0x0a1420 }), { pos: [0, 2.3, 6.0], outline: false, parent: body }); // лобовое
  const sign = textTexture('42', { size: 140, color: '#ffb31a', bg: '#120a02' });
  const sm = new THREE.Mesh(new THREE.PlaneGeometry(1.2, .45), new THREE.MeshBasicMaterial({ map: sign.tex, color: new THREE.Color(2.2, 2.2, 2.2) }));
  sm.position.set(0, 3.2, 6.03); body.add(sm);
  const side = textTexture('42  НОВОГРАД', { size: 90, color: '#ffffff', weight: 700 });
  for (const sx of [1, -1]) {
    const sp = new THREE.Mesh(new THREE.PlaneGeometry(4.2, .45), new THREE.MeshBasicMaterial({ map: side.tex, transparent: true }));
    sp.position.set(sx * 1.33, .9, 0); sp.rotation.y = sx * Math.PI / 2; body.add(sp);
  }
  const wheel = new THREE.CylinderGeometry(.55, .55, .4, 16);
  for (const [x, z] of [[1.15, 4], [-1.15, 4], [1.15, -3.8], [-1.15, -3.8]]) mesh(wheel, toon(0x121212), { pos: [x, .55, z], rot: [0, 0, Math.PI / 2], outline: false, parent: body });
  for (const x of [-.8, .8]) mesh(new THREE.BoxGeometry(.4, .25, .06), glow(0xfff4d6, 4), { pos: [x, .95, 6.02], outline: false, parent: body });
  g.userData.body = body;
  g.traverse(m => { if (m.isMesh) m.frustumCulled = false; });
  return g;
}

/* ---------- велосипед ---------- */
export function makeBike() {
  const g = new THREE.Group();
  const frame = toon(0x15b9a8), dark = toon(0x111111);
  const tube = (a, b, r = .03, mat = frame) => {
    const A = new THREE.Vector3(...a), B = new THREE.Vector3(...b), len = A.distanceTo(B);
    const m = mesh(new THREE.CylinderGeometry(r, r, len, 8), mat, { outline: .012, parent: g });
    m.position.copy(A).add(B).multiplyScalar(.5);
    m.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), B.clone().sub(A).normalize());
  };
  const wheels = [];
  for (const z of [.55, -.55]) {
    const w = new THREE.Group(); w.position.set(0, .35, z); g.add(w); wheels.push(w);
    mesh(new THREE.TorusGeometry(.33, .035, 8, 28), dark, { rot: [0, Math.PI / 2, 0], outline: .01, parent: w });
    for (let i = 0; i < 6; i++) mesh(new THREE.BoxGeometry(.01, .6, .01), toon(0x9aa0aa), { rot: [i * Math.PI / 6, 0, 0], outline: false, parent: w });
  }
  tube([0, .35, -.55], [0, .55, -.05]); tube([0, .55, -.05], [0, .38, .05]); tube([0, .38, .05], [0, .35, -.55]);
  tube([0, .55, -.05], [0, .8, .42]); tube([0, .38, .05], [0, .75, .4]); tube([0, .35, .55], [0, .85, .44]);
  tube([0, .55, -.05], [0, .82, -.12]);
  mesh(new RoundedBoxGeometry(.1, .05, .26, 2, .02), dark, { pos: [0, .84, -.14], outline: .01, parent: g });
  tube([-.28, .9, .42], [.28, .9, .42], .022, dark);
  mesh(new THREE.BoxGeometry(.1, .06, .02), glow(0xffffff, 3), { pos: [0, .8, .5], outline: false, parent: g });
  g.userData.wheels = wheels;
  g.traverse(m => { if (m.isMesh) m.frustumCulled = false; });
  return g;
}

/* ---------- город целиком ---------- */
export function makeCity() {
  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x141a2e, .0021);
  const sky = makeSky(); scene.add(sky);
  const city = { scene, sky, refs: {} };

  // освещение для тун-материалов персонажей и объектов
  const hemi = new THREE.HemisphereLight(0x8a9cff, 0x241a22, 1.1); scene.add(hemi);
  const key = new THREE.DirectionalLight(0xbcd0ff, 1.4); key.position.set(-60, 120, 80); scene.add(key); scene.add(key.target);
  const rim = new THREE.DirectionalLight(0xff9a4a, 1.2); rim.position.set(80, 40, -100); scene.add(rim); scene.add(rim.target);
  const fill = new THREE.PointLight(0x55e6ff, 0, 40, 1.6); scene.add(fill);
  Object.assign(city, { hemi, key, rim, fill });

  // земля и вода
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(3400, 3400), groundMaterial());
  ground.rotation.x = -Math.PI / 2; ground.position.set(-300, 0, -300);
  // земля обрывается к реке: делаем двумя полосами
  ground.geometry = new THREE.PlaneGeometry(1980, 3400); ground.position.set(330 - 990, 0, -300);
  scene.add(ground);
  const farBank = new THREE.Mesh(new THREE.PlaneGeometry(1400, 3400), groundMaterial());
  farBank.rotation.x = -Math.PI / 2; farBank.position.set(610 + 700, 0, -300); scene.add(farBank);
  const water = new THREE.Mesh(new THREE.PlaneGeometry(400, 3400), waterMaterial());
  water.rotation.x = -Math.PI / 2; water.position.set(470, -30, -300); scene.add(water);
  // набережные
  const embank = toon(0x2a2c36);
  for (const x of [330, 610]) mesh(new THREE.BoxGeometry(4, 31, 3400), embank, { pos: [x + (x < 400 ? 2 : -2), -15, -300], outline: false, parent: scene });

  // здания
  const r = rng(2024);
  const items = [];
  const PAL = [[.2, .22, .3], [.25, .2, .22], [.18, .24, .27], [.24, .22, .3], [.3, .26, .24], [.16, .18, .24]];
  const add = (x, z, w, d, h, style = 1, col) => items.push({ x, z, w, d, h, style, col: col || PAL[Math.floor(r() * PAL.length)] });
  const SPECIAL = {
    '40,-440': 'tower', '120,-440': () => add(120, -440, 54, 54, 112, 1, [.24, .2, .22]),
    '280,-440': () => add(282, -440, 52, 54, 88, 1, [.22, .22, .3]),
    '200,-440': () => add(200, -440, 54, 54, 104, 1, [.2, .22, .3]),
    '200,-360': () => add(200, -362, 54, 50, 96, 1, [.26, .22, .24]),
    '280,-360': () => add(282, -362, 52, 50, 74, 1, [.2, .24, .28]),
    '120,-360': () => add(120, -362, 54, 50, 84, 1),
  };
  for (let bx = -6; bx <= 3; bx++) for (let bz = -12; bz <= 3; bz++) {
    const cx = bx * 80 + 40, cz = bz * 80 + 40;
    const key = cx + ',' + cz;
    if (SPECIAL[key]) { if (SPECIAL[key] !== 'tower') SPECIAL[key](); continue; }
    const near = Math.hypot(cx - 40, cz + 440);
    const tall = (near < 260 ? 70 : 30) + (Math.abs(cx) < 100 ? 30 : 0);
    const mode = r();
    const lots = mode < .35 ? [[0, 0, 56, 56]] : mode < .7 ? [[-14.5, 0, 27, 56], [14.5, 0, 27, 56]] : [[-14.5, -14.5, 27, 27], [14.5, -14.5, 27, 27], [-14.5, 14.5, 27, 27], [14.5, 14.5, 27, 27]];
    for (const [ox, oz, w, d] of lots) add(cx + ox, cz + oz, w - r() * 3, d - r() * 3, tall * (.5 + r() * 1.2) + 12, r() < .25 ? 2 : 1);
  }
  // дальний берег и силуэты на горизонте
  for (let i = 0; i < 160; i++) add(650 + r() * 700, -1100 + r() * 1500, 20 + r() * 30, 20 + r() * 30, 20 + r() * 120, r() < .3 ? 2 : 1);
  for (let i = 0; i < 140; i++) { const a = r() * Math.PI * 2, R = 1150 + r() * 500; add(-150 + Math.cos(a) * R, -300 + Math.sin(a) * R, 40 + r() * 60, 40 + r() * 60, 60 + r() * 260, r() < .4 ? 2 : 1); }

  const bgeo = new THREE.BoxGeometry(1, 1, 1); bgeo.translate(0, .5, 0);
  const inst = new THREE.InstancedMesh(bgeo, buildingMaterial(), items.length);
  const aColor = new Float32Array(items.length * 3), aSeed = new Float32Array(items.length * 2);
  const m4 = new THREE.Matrix4();
  items.forEach((b, i) => {
    m4.makeScale(b.w, b.h, b.d); m4.setPosition(b.x, 0, b.z);
    inst.setMatrixAt(i, m4);
    aColor.set(b.col, i * 3); aSeed.set([r(), b.style], i * 2);
  });
  inst.geometry.setAttribute('aColor', new THREE.InstancedBufferAttribute(aColor, 3));
  inst.geometry.setAttribute('aSeed', new THREE.InstancedBufferAttribute(aSeed, 2));
  inst.frustumCulled = false;
  scene.add(inst);
  city.buildings = items;

  // крыши: парапеты, вентиляция, баки — мелочь инстансами
  const roofBits = [];
  for (const b of items) {
    if (Math.abs(b.x) > 700 || b.z < -1000) continue;
    const n = 1 + Math.floor(r() * 3);
    for (let i = 0; i < n; i++) roofBits.push([b.x + (r() - .5) * b.w * .6, b.h, b.z + (r() - .5) * b.d * .6, 2 + r() * 5, 1.5 + r() * 3, 2 + r() * 5]);
  }
  const rb = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1).translate(0, .5, 0), toon(0x3a3f4c), roofBits.length);
  roofBits.forEach((v, i) => { m4.makeScale(v[3], v[4], v[5]); m4.setPosition(v[0], v[1], v[2]); rb.setMatrixAt(i, m4); });
  scene.add(rb);
  // мигающие красные огни на крышах высоток
  const beacons = [];
  for (const b of items) if (b.h > 120 && Math.hypot(b.x, b.z + 300) < 1300) beacons.push([b.x, b.h + 1.5, b.z]);
  const bk = new THREE.InstancedMesh(new THREE.SphereGeometry(.9, 8, 6), glow(0xff2a2a, 4), beacons.length);
  beacons.forEach((v, i) => { m4.makeTranslation(...v); bk.setMatrixAt(i, m4); });
  scene.add(bk); city.beacons = bk;

  // фонари вдоль улиц (рядом с местом действия)
  const lamps = [];
  for (let s = -12; s <= 4; s++) for (let q = -12; q <= 3; q++) {
    // вдоль проспектов (ось z) x=80s±9 и вдоль улиц (ось x) z=80q±9
    if (Math.abs(s * 80) > 340) continue;
    for (let j = 0; j < 3; j++) {
      const z = q * 80 + 12.5 + j * 25;
      lamps.push([s * 80 - 9, z, 1], [s * 80 + 9, z, -1]);
    }
  }
  const pole = new THREE.InstancedMesh(new THREE.CylinderGeometry(.12, .16, 8, 6).translate(0, 4, 0), toon(0x1f232b), lamps.length);
  const bulb = new THREE.InstancedMesh(new THREE.SphereGeometry(.35, 8, 6), glow(0xffcf8a, 3.5), lamps.length);
  lamps.forEach(([x, z, s], i) => {
    m4.makeTranslation(x, 0, z); pole.setMatrixAt(i, m4);
    m4.makeTranslation(x + s * 1.2, 8, z); bulb.setMatrixAt(i, m4);
  });
  scene.add(pole, bulb);
  // объёмный свет: конусы под фонарями, подсвеченные дождём
  const coneM = new THREE.MeshBasicMaterial({ color: new THREE.Color(0xffc880).multiplyScalar(.5), transparent: true, opacity: .07, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide });
  const cone = new THREE.InstancedMesh(new THREE.ConeGeometry(3.2, 8, 20, 1, true).translate(0, 4, 0), coneM, lamps.length);
  lamps.forEach(([x, z, sd], i) => { m4.makeTranslation(x + sd * 1.2, 0, z); cone.setMatrixAt(i, m4); });
  cone.frustumCulled = false; cone.renderOrder = 3; scene.add(cone); city.lampCones = cone;

  // неоновые вертикальные вывески вдоль проспекта
  const SIGNS = [['ЛАПША', '#ff3d7f'], ['КИНО', '#3df2ff'], ['24/7', '#ffd23d'], ['АПТЕКА', '#3dff8a'], ['СУШИ', '#ff6a3d'], ['КАРАОКЕ', '#c06bff'],
    ['ХОСТЕЛ', '#3d9bff'], ['БАР', '#ff3d3d'], ['ФОТО', '#fff13d'], ['ЧАЙ', '#3dffd8'], ['ИГРЫ', '#ff3dd8'], ['ДОНЕР', '#ffa23d']];
  const signTex = SIGNS.map(([t, c]) => {
    const cvs = document.createElement('canvas'); cvs.width = 128; cvs.height = 128 * t.length + 40;
    const g = cvs.getContext('2d'); g.fillStyle = '#07070c'; g.fillRect(0, 0, cvs.width, cvs.height);
    g.strokeStyle = c; g.lineWidth = 6; g.strokeRect(8, 8, 112, cvs.height - 16);
    g.font = '900 96px Unbounded'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillStyle = c;
    g.shadowColor = c; g.shadowBlur = 16;
    [...t].forEach((ch, i) => g.fillText(ch, 64, 20 + 128 * i + 64));
    const tx = new THREE.CanvasTexture(cvs); tx.colorSpace = THREE.SRGBColorSpace;
    return { tx, h: t.length };
  });
  const signs = new THREE.Group(); scene.add(signs);
  let si = 0;
  for (let z = 260; z > -420; z -= 34) for (const sx of [-1, 1]) {
    if (r() < .25) continue;
    const S = signTex[si++ % signTex.length];
    const hgt = S.h * 2.2 + .6;
    const m = new THREE.Mesh(new THREE.BoxGeometry(.4, hgt, 2.2), [
      new THREE.MeshBasicMaterial({ color: 0x0a0a10 }), new THREE.MeshBasicMaterial({ color: 0x0a0a10 }),
      new THREE.MeshBasicMaterial({ color: 0x0a0a10 }), new THREE.MeshBasicMaterial({ color: 0x0a0a10 }),
      new THREE.MeshBasicMaterial({ map: S.tx, color: new THREE.Color(2.2, 2.2, 2.2) }), new THREE.MeshBasicMaterial({ map: S.tx, color: new THREE.Color(2.2, 2.2, 2.2) })]);
    m.rotation.y = Math.PI / 2;
    m.position.set(sx * 12.2, 9 + r() * 14 + hgt / 2, z + r() * 10);
    signs.add(m);
  }

  // крыша, где очнётся Тимур (здание 120,-440, h=112)
  const roof = new THREE.Group(); roof.position.set(120, 112, -440); scene.add(roof);
  const rm = toon(0x3d4250), rd = toon(0x2a2e38), rust = toon(0x6b4a3a);
  for (const [x, z, w, d] of [[0, 27, 54, .6], [0, -27, 54, .6], [27, 0, .6, 54], [-27, 0, .6, 54]]) mesh(new THREE.BoxGeometry(w, 1.1, d), rd, { pos: [x, .55, z], outline: .03, parent: roof });
  const tank = new THREE.Group(); tank.position.set(-12, 0, -10); roof.add(tank);
  mesh(new THREE.CylinderGeometry(2.6, 2.6, 4.5, 20), rust, { pos: [0, 5.4, 0], outline: .05, parent: tank });
  mesh(new THREE.ConeGeometry(2.9, 1.4, 20), rd, { pos: [0, 8.3, 0], outline: .05, parent: tank });
  for (const [x, z] of [[1.8, 1.8], [-1.8, 1.8], [1.8, -1.8], [-1.8, -1.8]]) mesh(new THREE.CylinderGeometry(.15, .15, 3.2, 6), rd, { pos: [x, 1.6, z], outline: .02, parent: tank });
  for (const [x, z] of [[2, 4], [5, 4], [14, -8], [-3, 14]]) {
    mesh(new RoundedBoxGeometry(2.2, 1.4, 1.6, 2, .1), rm, { pos: [x, .7, z], outline: .03, parent: roof });
    mesh(new THREE.CylinderGeometry(.55, .55, .1, 16), rd, { pos: [x, 1.42, z], outline: false, parent: roof });
  }
  mesh(new RoundedBoxGeometry(4, 3, 3.5, 2, .1), rm, { pos: [16, 1.5, 12], outline: .04, parent: roof });
  mesh(new THREE.BoxGeometry(1.2, 2.2, .1), toon(0x1a1d24), { pos: [16, 1.1, 10.2], outline: false, parent: roof });
  mesh(new THREE.BoxGeometry(.4, .25, .1), glow(0x3dff8a, 2), { pos: [16, 2.5, 10.2], outline: false, parent: roof });
  mesh(new THREE.CylinderGeometry(.08, .12, 14, 6), rd, { pos: [-20, 7, 18], outline: .02, parent: roof });
  mesh(new THREE.SphereGeometry(.35, 8, 6), glow(0xff2a2a, 4), { pos: [-20, 14.2, 18], outline: false, parent: roof });
  for (let i = 0; i < 5; i++) mesh(new THREE.CylinderGeometry(.06, .06, 10, 4), rd, { pos: [-20 + i * .2, 5, 18], rot: [0, 0, (i - 2) * .25], outline: false, parent: roof });

  // башня «Аркада»
  city.tower = makeTower(scene);
  // мост
  city.bridge = makeBridge(scene);

  // дождь и молнии
  city.rain = makeRain(); scene.add(city.rain);
  city.bolts = new THREE.Group(); scene.add(city.bolts);

  // машины на проспекте
  city.cars = [];
  for (let i = 0; i < 26; i++) {
    const c = makeCar(i, i % 4 === 1); scene.add(c);
    const lane = [-6.5, -2.5, 2.5, 6.5][i % 4];
    city.cars.push({ g: c, lane, dir: lane < 0 ? 1 : -1, off: (i * 61.7) % 520, speed: 9 + (i * 3.3) % 6 });
  }
  return city;
}

/* дорожный трафик: позиция машины по времени */
export function updateTraffic(city, t, zMin = -380, zMax = 240, filter) {
  const L = zMax - zMin;
  city.cars.forEach((c, i) => {
    if (filter && !filter(c, i)) { c.g.visible = false; return; }
    c.g.visible = true;
    const s = ((c.off + c.speed * t) % L + L) % L;
    const z = c.dir > 0 ? zMin + s : zMax - s;
    c.g.position.set(c.lane, 0, z);
    c.g.rotation.y = c.dir > 0 ? 0 : Math.PI;
  });
}

function makeTower(scene) {
  const T = new THREE.Group(); T.position.set(40, 0, -440); scene.add(T);
  const mat = buildingMaterial();
  const parts = [[0, 0, 0, 50, 258, 50, 2], [0, 282, 0, 50, 22, 50, 2], [0, 304, 0, 40, 16, 40, 2]];
  const bgeo = new THREE.BoxGeometry(1, 1, 1); bgeo.translate(0, .5, 0);
  const inst = new THREE.InstancedMesh(bgeo, mat, parts.length);
  const aColor = new Float32Array(parts.length * 3), aSeed = new Float32Array(parts.length * 2);
  const m4 = new THREE.Matrix4();
  parts.forEach((p, i) => { m4.makeScale(p[3], p[4], p[5]); m4.setPosition(p[0], p[1], p[2]); inst.setMatrixAt(i, m4); aColor.set([.12, .2, .28], i * 3); aSeed.set([.37 + i, 2], i * 2); });
  inst.geometry.setAttribute('aColor', new THREE.InstancedBufferAttribute(aColor, 3));
  inst.geometry.setAttribute('aSeed', new THREE.InstancedBufferAttribute(aSeed, 2));
  inst.frustumCulled = false; T.add(inst);
  // стеклянный этаж лаборатории 258..282: перекладины + стекло
  const glass = new THREE.MeshBasicMaterial({ color: 0x5fb7ff, transparent: true, opacity: .12, depthWrite: false, side: THREE.DoubleSide });
  const frameM = toon(0x1a2230);
  const glassPanels = new THREE.Group(); T.add(glassPanels);
  for (const [sx, sz, ry] of [[1, 0, Math.PI / 2], [-1, 0, Math.PI / 2], [0, 1, 0], [0, -1, 0]]) {
    const p = new THREE.Mesh(new THREE.PlaneGeometry(50, 24), glass);
    p.position.set(sx * 25, 270, sz * 25); p.rotation.y = ry; p.userData.side = [sx, sz]; glassPanels.add(p);
    for (let i = -2; i <= 2; i++) {
      const b = new THREE.Mesh(new THREE.BoxGeometry(.5, 24, .5), frameM);
      b.position.set(sx * 25 + (sz ? i * 10 : 0), 270, sz * 25 + (sx ? i * 10 : 0)); T.add(b);
    }
  }
  for (const y of [258.3, 281.7]) mesh(new THREE.BoxGeometry(51, .8, 51), frameM, { pos: [0, y, 0], outline: false, parent: T });
  // светящийся пояс и логотип
  for (const y of [281, 304]) mesh(new THREE.BoxGeometry(50.6, .6, 50.6), glow(0x3ff0ff, 2.5), { pos: [0, y, 0], outline: false, parent: T });
  const logo = textTexture('АРКАДА', { size: 160, color: '#7ff8ff' });
  for (const [sx, sz, ry] of [[0, 1, 0], [1, 0, Math.PI / 2], [0, -1, Math.PI], [-1, 0, -Math.PI / 2]]) {
    const p = new THREE.Mesh(new THREE.PlaneGeometry(30, 30 / logo.aspect), new THREE.MeshBasicMaterial({ map: logo.tex, transparent: true, color: new THREE.Color(2.4, 2.4, 2.4) }));
    p.position.set(sx * 25.3, 293, sz * 25.3); p.rotation.y = ry; T.add(p);
  }
  // шпиль
  mesh(new THREE.CylinderGeometry(.6, 4, 56, 12), toon(0x39414f), { pos: [0, 320 + 28, 0], outline: false, parent: T });
  const tip = mesh(new THREE.SphereGeometry(1.2, 10, 8), glow(0xff3030, 4), { pos: [0, 377, 0], outline: false, parent: T });
  T.userData = { glassPanels, tip };
  return T;
}

function makeBridge(scene) {
  const B = new THREE.Group(); scene.add(B);
  const steel = toon(0x8a3a2c), conc = toon(0x4a4c55), dark = toon(0x22252c);
  const z0 = -400, x0 = 300, x1 = 640;
  mesh(new THREE.BoxGeometry(x1 - x0, 2.4, 24), conc, { pos: [(x0 + x1) / 2, -1.2, z0], outline: false, parent: B });
  // проезжая часть с разметкой
  const road = textTexture(' ', { size: 10 });
  mesh(new THREE.BoxGeometry(x1 - x0, .1, 20), toon(0x1c1f27), { pos: [(x0 + x1) / 2, .05, z0], outline: false, parent: B });
  for (let x = x0 + 4; x < x1; x += 8) mesh(new THREE.BoxGeometry(3.5, .12, .25), glow(0xd8d2b0, .9), { pos: [x, .08, z0], outline: false, parent: B });
  // перила (с проломом у автобуса)
  for (const s of [1, -1]) for (let x = x0; x < x1; x += 2.5) {
    if (s === 1 && x > 446 && x < 462) continue;
    mesh(new THREE.BoxGeometry(.15, 1.1, .15), dark, { pos: [x, .55, z0 + s * 11.5], outline: false, parent: B });
  }
  for (const s of [1, -1]) {
    if (s === 1) { mesh(new THREE.BoxGeometry(446 - x0, .2, .25), steel, { pos: [(x0 + 446) / 2, 1.1, z0 + 11.5], outline: false, parent: B });
      mesh(new THREE.BoxGeometry(x1 - 462, .2, .25), steel, { pos: [(462 + x1) / 2, 1.1, z0 + 11.5], outline: false, parent: B }); }
    else mesh(new THREE.BoxGeometry(x1 - x0, .2, .25), steel, { pos: [(x0 + x1) / 2, 1.1, z0 - 11.5], outline: false, parent: B });
  }
  // пилоны
  const towers = [];
  for (const tx of [390, 550]) {
    const T = new THREE.Group(); T.position.set(tx, 0, z0); B.add(T); towers.push(T);
    for (const s of [1, -1]) mesh(new THREE.BoxGeometry(3.2, 135, 3.2), steel, { pos: [0, 135 / 2 - 30, s * 12.5], outline: .15, parent: T });
    for (const y of [12, 55, 98]) mesh(new THREE.BoxGeometry(2.6, 3, 25), steel, { pos: [0, y, 0], outline: .15, parent: T });
    for (const s of [1, -1]) {
      mesh(new THREE.CylinderGeometry(.15, .7, 22, 8), toon(0x9aa2b0), { pos: [0, 105 + 11, s * 12.5], outline: .08, parent: T });
      mesh(new THREE.SphereGeometry(.6, 8, 6), glow(0xff3030, 4), { pos: [0, 128, s * 12.5], outline: false, parent: T });
    }
  }
  // несущие тросы — цепные линии
  const cableMat = toon(0xa04a38);
  const cableY = x => {
    if (x < 390) return 2 + (105 - 2) * Math.pow((x - x0) / (390 - x0), 1.6);
    if (x > 550) return 2 + (105 - 2) * Math.pow((x1 - x) / (x1 - 550), 1.6);
    const u = (x - 470) / 80; return 14 + (105 - 14) * u * u;
  };
  for (const s of [1, -1]) {
    const pts = []; for (let x = x0; x <= x1; x += 4) pts.push(new THREE.Vector3(x, cableY(x), z0 + s * 12.5));
    const tube = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 120, .45, 6), cableMat); B.add(tube);
    for (let x = x0 + 8; x < x1 - 4; x += 8) {
      const h = cableY(x); if (h < 2.5) continue;
      if (s === 1 && x > 448 && x < 460) continue;
      mesh(new THREE.CylinderGeometry(.07, .07, h, 4), dark, { pos: [x, h / 2, z0 + s * 12.5], outline: false, parent: B });
    }
  }
  // фонари моста
  for (let x = x0 + 10; x < x1; x += 30) for (const s of [1, -1]) {
    mesh(new THREE.CylinderGeometry(.1, .12, 7, 6), dark, { pos: [x, 3.5, z0 + s * 11], outline: false, parent: B });
    mesh(new THREE.SphereGeometry(.35, 8, 6), glow(0xffd7a0, 3.5), { pos: [x, 7, z0 + s * 10.4], outline: false, parent: B });
  }
  B.userData = { towers, cableY, z0 };
  return B;
}

/* Глобальная функция вспышек: список ударов молнии [{t, ...}] → интенсивность вспышки */
export function flashAt(t, strikes) {
  let f = 0;
  for (const s of strikes) {
    const d = t - s.t;
    if (d < -.05 || d > 1.2) continue;
    const k = s.k ?? 1;
    // двойной-тройной «мерцающий» удар
    f += k * (Math.exp(-Math.pow((d - .0) / .05, 2)) + .7 * Math.exp(-Math.pow((d - .16) / .05, 2)) + .45 * Math.exp(-Math.pow((d - .32) / .07, 2)) + .25 * Math.exp(-d * 3) * (d > 0 ? 1 : 0));
  }
  return clamp(f, 0, 2.2);
}
