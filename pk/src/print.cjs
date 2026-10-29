// Печатает HTML в PDF (A4) через Chromium.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [dir, out] = process.argv.slice(2).map(p => path.resolve(p));
  const browser = await chromium.launch();
  const page = await browser.newPage();
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.html'))) {
    await page.goto('file://' + path.join(dir, f), { waitUntil: 'load' });
    await page.pdf({ path: path.join(out, f.replace(/\.html$/, '.pdf')), preferCSSPageSize: true, printBackground: true });
  }
  await browser.close();
})();
