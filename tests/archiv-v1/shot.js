const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1100, height: 900 }, deviceScaleFactor: 1 });
  await p.goto('file:///tmp/bc-build/sim/report/BuyCheck-Bericht.html');
  await p.screenshot({ path: '/tmp/bc-build/shots/report-top.png' });
  const h = await p.evaluate(() => document.body.scrollHeight);
  console.log('height', h);
  await p.evaluate(() => { const d = [...document.querySelectorAll('details')].find(x => x.textContent.includes('Belastungstest')); d.open = true; d.scrollIntoView(); });
  await p.screenshot({ path: '/tmp/bc-build/shots/report-stress.png' });
  await p.evaluate(() => { const d = [...document.querySelectorAll('details')].find(x => x.textContent.includes('Laufwerks-Gesundheit')); d.open = true; d.scrollIntoView(); });
  await p.screenshot({ path: '/tmp/bc-build/shots/report-storage.png' });
  await b.close();
})();
