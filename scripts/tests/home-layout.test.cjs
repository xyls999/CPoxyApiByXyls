// Browser integration regression: the sanitized, shadow-root landing page fits both viewports.
// NODE_PATH must point to the browser-tools node_modules directory containing puppeteer-core.
const assert = require('node:assert/strict')
const puppeteer = require('puppeteer-core')

async function main() {
  const browser = await puppeteer.connect({ browserURL: 'http://127.0.0.1:9222' })
  const page = await browser.newPage()
  try {
    for (const width of [390, 1440]) {
      await page.setViewport({ width, height: 850, deviceScaleFactor: 1 })
      await page.goto('http://127.0.0.1:3000/', { waitUntil: 'networkidle2' })
      await page.waitForFunction(() => [...document.querySelectorAll('*')].some(e => e.shadowRoot?.querySelector('.cpa-home')))
      const actual = await page.evaluate(() => {
        const shadow = [...document.querySelectorAll('*')].find(e => e.shadowRoot?.querySelector('.cpa-home')).shadowRoot
        const root = shadow.querySelector('.cpa-home')
        const preview = shadow.querySelector('.cpa-preview')
        const hero = shadow.querySelector('.cpa-hero')
        const header = document.querySelector('header')
        return {
          viewport: innerWidth,
          bodyScroll: document.documentElement.scrollWidth,
          rootScroll: root.scrollWidth,
          rootClient: root.clientWidth,
          previewRight: preview.getBoundingClientRect().right,
          heroTop: hero.getBoundingClientRect().top,
          headerBottom: header?.getBoundingClientRect().bottom ?? 0,
          duplicateNav: Boolean(shadow.querySelector('.cpa-nav')),
        }
      })
      assert.equal(actual.viewport, width)
      assert.equal(actual.duplicateNav, false, 'Use the existing application header, not a second menu')
      assert.ok(actual.heroTop >= actual.headerBottom, 'Hero must not overlap application header')
      assert.ok(actual.previewRight <= width + 1, `Preview clipped at ${width}px: ${JSON.stringify(actual)}`)
      assert.ok(actual.bodyScroll <= width + 1, `Document horizontally scrolls at ${width}px: ${JSON.stringify(actual)}`)
      assert.ok(actual.rootScroll <= actual.rootClient + 1, `Landing horizontally scrolls at ${width}px: ${JSON.stringify(actual)}`)
      console.log(`PASS: homepage fits ${width}px viewport without overlap or horizontal clipping`)
    }
  } finally {
    await page.close()
    await browser.disconnect()
  }
}

main().catch(err => { console.error(err); process.exitCode = 1 })
