// Постобработка «как в кино»: цветокоррекция под сцену, зерно, хроматическая аберрация, виньетка;
// motion blur накоплением подкадров (на видеокарте).
import * as THREE from 'three';
import { ShaderPass } from 'three/addons/postprocessing/ShaderPass.js';
import { clamp, lerp } from './core.js';

/* Пресеты грейда: lift (тени), gamma (полутона), gain (света), насыщенность, контраст */
export const GRADES = {
  neutral: { lift: [0, 0, 0], gamma: [1, 1, 1], gain: [1, 1, 1], sat: 1, con: 1 },
  night:   { lift: [.0, .01, .035], gamma: [1.02, 1, .96], gain: [1.04, 1.0, .98], sat: 1.08, con: 1.06 },
  street:  { lift: [.0, .02, .04], gamma: [.98, 1, 1.02], gain: [1.08, 1.0, .94], sat: 1.15, con: 1.08 },   // тил-оранж
  lab:     { lift: [0, .02, .03], gamma: [1.04, .98, .96], gain: [.94, 1.04, 1.08], sat: 1.05, con: 1.05 },
  danger:  { lift: [.03, 0, .0], gamma: [.96, 1.03, 1.05], gain: [1.12, .94, .9], sat: 1.12, con: 1.12 },
  sense:   { lift: [0, .02, .05], gamma: [1.05, 1, .95], gain: [.9, 1.02, 1.1], sat: .95, con: 1.04 },
  action:  { lift: [0, .015, .04], gamma: [.97, 1, 1.03], gain: [1.1, 1.0, .92], sat: 1.2, con: 1.12 },
  bridge:  { lift: [.0, .015, .04], gamma: [.96, 1, 1.04], gain: [1.14, .98, .9], sat: 1.18, con: 1.14 },
  calm:    { lift: [.01, .015, .03], gamma: [1, 1, 1], gain: [1.04, 1.0, .97], sat: 1.0, con: 1.02 },
  kitchen: { lift: [.025, .01, 0], gamma: [.95, 1, 1.06], gain: [1.1, 1.02, .9], sat: 1.12, con: 1.04 },
  dawn:    { lift: [.03, .01, .03], gamma: [.95, 1, 1.02], gain: [1.12, 1.0, .95], sat: 1.12, con: 1.05 },
  tag:     { lift: [.0, 0, 0], gamma: [.9, 1.08, 1.08], gain: [1.12, .9, .9], sat: .9, con: 1.2 },
};
export function makeGradePass() {
  const pass = new ShaderPass({
    uniforms: {
      tDiffuse: { value: null }, lift: { value: new THREE.Vector3() }, gamma: { value: new THREE.Vector3(1, 1, 1) }, gain: { value: new THREE.Vector3(1, 1, 1) },
      sat: { value: 1 }, con: { value: 1 }, grain: { value: .03 }, ca: { value: .0002 }, vig: { value: .25 }, time: { value: 0 }, res: { value: new THREE.Vector2(1920, 1080) },
    },
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix*modelViewMatrix*vec4(position,1.); }`,
    fragmentShader: `uniform sampler2D tDiffuse; uniform vec3 lift, gamma, gain; uniform float sat, con, grain, ca, vig, time; uniform vec2 res; varying vec2 vUv;
      float h(vec2 p){ p = fract(p*vec2(443.897, 441.423)); p += dot(p, p.yx+19.19); return fract((p.x+p.y)*p.x); }
      void main(){
        vec2 d = vUv - .5;
        // лёгкая хроматическая аберрация к краям кадра
        vec2 off = d * dot(d, d) * ca * 40.;
        vec3 c = vec3(texture2D(tDiffuse, vUv + off).r, texture2D(tDiffuse, vUv).g, texture2D(tDiffuse, vUv - off).b);
        // lift / gamma / gain (в sRGB-пространстве, как в монтажке)
        c = c * gain + lift * (1. - c);
        c = pow(max(c, 0.), 1. / gamma);
        float l = dot(c, vec3(.2126, .7152, .0722));
        c = mix(vec3(l), c, sat);
        c = (c - .5) * con + .5;
        // виньетка и плёночное зерно
        c *= 1. - vig * smoothstep(.35, .85, length(d * vec2(1.2, 1.)));
        float n = h(vUv * res + fract(time * 37.1) * 113.) - .5;
        c += n * grain * (1. - l * .6);
        gl_FragColor = vec4(clamp(c, 0., 1.), 1.);
      }`,
  });
  pass.setGrade = (name, t) => {
    const g = GRADES[name] || GRADES.neutral, u = pass.uniforms;
    u.lift.value.set(...g.lift); u.gamma.value.set(...g.gamma); u.gain.value.set(...g.gain); u.sat.value = g.sat; u.con.value = g.con; u.time.value = t;
  };
  return pass;
}

/* Motion blur: усреднение нескольких подкадров внутри «открытого затвора» */
export function makeAccumulator(renderer, W, H) {
  const rt = new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType });
  const blendM = new THREE.ShaderMaterial({
    uniforms: { tex: { value: null }, w: { value: 1 } }, transparent: true, depthTest: false, depthWrite: false,
    blending: THREE.CustomBlending, blendSrc: THREE.SrcAlphaFactor, blendDst: THREE.OneFactor, blendEquation: THREE.AddEquation,
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }`,
    fragmentShader: `uniform sampler2D tex; uniform float w; varying vec2 vUv; void main(){ gl_FragColor = vec4(texture2D(tex, vUv).rgb, w); }`,
  });
  const copyM = new THREE.ShaderMaterial({
    uniforms: { tex: { value: rt.texture } }, depthTest: false, depthWrite: false,
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0., 1.); }`,
    fragmentShader: `uniform sampler2D tex; varying vec2 vUv; void main(){ gl_FragColor = vec4(texture2D(tex, vUv).rgb, 1.); }`,
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), blendM);
  const scene = new THREE.Scene(); scene.add(quad); const cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  return {
    clear() { renderer.setRenderTarget(rt); renderer.setClearColor(0x000000, 1); renderer.clear(); renderer.setRenderTarget(null); },
    add(texture, w) { quad.material = blendM; blendM.uniforms.tex.value = texture; blendM.uniforms.w.value = w; renderer.setRenderTarget(rt); renderer.autoClear = false; renderer.render(scene, cam); renderer.autoClear = true; renderer.setRenderTarget(null); },
    present() { quad.material = copyM; renderer.setRenderTarget(null); renderer.render(scene, cam); },
  };
}
