// Usage: node render.js in.html out.png width height [transparent]
const { chromium } = require(process.env.PW || 'playwright');
(async () => {
  const [inp, out, w, h, transp] = process.argv.slice(2);
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1243/chrome-linux64/chrome' });
  const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: 1 });
  await page.goto('file://' + require('path').resolve(inp));
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(300);
  await page.screenshot({ path: out, omitBackground: transp === '1', clip: { x: 0, y: 0, width: +w, height: +h } });
  await browser.close();
})();
