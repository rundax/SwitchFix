// Browser regression checks; no project npm dependencies required.
// From the repository root, serve the pages and run with playwright-cli:
//   python3 -m http.server 8765 --bind 127.0.0.1
//   playwright-cli -s=docs-tests open http://127.0.0.1:8765/
//   playwright-cli -s=docs-tests run-code "$(cat scripts/test-docs-browser.js)"
//   playwright-cli -s=docs-tests close
async page => {
  const base = await page.evaluate(() => new URL('/', location.href).href);
  const paths = ['docs/index.html', 'tutorial.html', 'docs/tutorial/index.html'];
  const errors = [];
  const onError = error => errors.push(error.message);
  page.on('pageerror', onError);
  let passed = 0;
  function check(condition, message) {
    if (!condition) throw new Error(message);
    passed++;
  }
  await page.clock.install();
  await page.emulateMedia({ reducedMotion: 'reduce' });

  try {
    for (const path of paths) {
      await page.goto(base + path);
      const tutorial = path !== 'docs/index.html';
      if (tutorial) {
        const sections = await page.locator('main > section.card').evaluateAll(nodes => nodes.map(el => el.id));
        check(JSON.stringify(sections) === JSON.stringify(['install', 'open-app', 'allow-access']), `${path}: installation follows three ordered steps`);
        check(await page.locator('#open-app').innerText().then(text => text.includes('right pane, scroll down') && text.includes('Open Anyway')), `${path}: approval explains where to scroll`);
        check(await page.locator('#allow-access').innerText().then(text => text.includes('Only if Keyboard input access is Unavailable')), `${path}: Input Monitoring is conditional`);
        check(await page.locator('.settings-link').getAttribute('href') === 'x-apple.systempreferences:com.apple.preference.security', `${path}: native Settings shortcut is available`);
        check(await page.locator('#progress-bar, #confetti-canvas, .sound-toggle').count() === 0, `${path}: no simulated setup completion or distracting overlays`);
        for (const id of ['practice-acc', 'practice-input', 'practice-correction']) {
          check(!await page.locator(`#${id}`).evaluate(el => el.open), `${path}: ${id} is optional and collapsed`);
          await page.locator(`#${id} > summary`).click();
        }
      } else {
        check(await page.locator('.install-warning a').getAttribute('href') === 'tutorial/#open-app', `${path}: warning links directly to launch approval`);
        check(await page.locator('.install-flow > li').count() === 3, `${path}: homepage shows the same three steps`);
      }
      const input = page.locator(tutorial ? '#playground-input' : '#demo-input');
      const feedback = page.locator(tutorial ? '#playground-feedback' : '#demo-status');
      const payload = '<img src=x onerror="window.xssExecuted=true"> & <svg/onload=window.xssExecuted=true> "\'';

      if (!tutorial) {
        for (const value of [payload, payload + ' ']) {
          await input.fill(value);
          check(await feedback.locator('img, svg').count() === 0, `${path}: raw input must be escaped`);
          check((await feedback.innerText()).includes(payload), `${path}: input should render literally`);
        }
        await page.evaluate(value => {
          typoDictionary[value] = { to: value, lang: value };
          simulateTypoCheck(value + ' ');
        }, payload);
        check(await feedback.locator('img, svg').count() === 0, `${path}: dictionary values must be escaped`);
        await input.fill('ghbdsn ');
        check(await input.inputValue() === 'привіт ', `${path}: ordinary correction still works`);
      }
      for (const inherited of ['constructor', '__proto__', 'toString', 'hasOwnProperty']) {
        await input.fill(inherited);
        await input.press('Space');
        await page.clock.runFor(2000);
        check(await input.inputValue() === inherited + ' ', `${path}: inherited key ${inherited} must not match`);
      }

      if (tutorial) {
        for (const id of ['switch-input', 'switch-acc']) {
          const control = page.locator(`#${id}`);
          check(Boolean(await control.getAttribute('aria-label')), `${path}: ${id} requires an accessible name`);
          await control.focus();
          await control.press('Space');
          check(await control.getAttribute('aria-checked') === 'true', `${path}: Space enables ${id}`);
          check(await page.locator('main > section.card.completed').count() === 0, `${path}: practice cannot mark actual setup complete`);
          await control.press('Enter');
          check(await control.getAttribute('aria-checked') === 'false', `${path}: Enter disables ${id}`);
          await control.dispatchEvent('keydown', { key: ' ', repeat: true });
          check(await control.getAttribute('aria-checked') === 'false', `${path}: holding a key must not repeatedly toggle`);
        }

        // Cancel in each phase: sample typing, correction delay, deletion, retyping.
        for (const elapsed of [150, 700, 1100, 1500]) {
          await page.evaluate(() => simulateTyping('ghbdtn', 'привет'));
          await page.clock.runFor(elapsed);
          await page.getByRole('button', { name: 'Clear', exact: true }).click();
          await page.clock.runFor(3000);
          check(await input.inputValue() === '', `${path}: Clear at ${elapsed}ms cancels every timer`);
          check(await feedback.innerText() === '', `${path}: Clear removes stale feedback`);
          check(await page.evaluate(() => activePlaygroundTimers.size === 0 && !playgroundInput.readOnly), `${path}: Clear releases timer and input state`);
        }
        for (const elapsed of [150, 700, 1100, 1500]) {
          await page.evaluate(() => simulateTyping('ghbdtn', 'привет'));
          await page.clock.runFor(elapsed);
          await page.evaluate(() => simulateTyping('руддщ', 'hello'));
          await page.clock.runFor(3000);
          check(await input.inputValue() === 'hello ', `${path}: switching samples at ${elapsed}ms cancels old work`);
          check(await page.evaluate(() => activePlaygroundTimers.size === 0), `${path}: completed timers leave no registry entries`);
        }
        for (const elapsed of [150, 700]) {
          await page.evaluate(() => simulateTyping('ghbdtn', 'привет'));
          await page.clock.runFor(elapsed);
          await input.fill('my own text');
          await page.clock.runFor(3000);
          check(await input.inputValue() === 'my own text', `${path}: manual input at ${elapsed}ms cancels playback`);
        }
        await page.evaluate(() => simulateTyping('ghbdtn', 'привет'));
        await page.clock.runFor(150);
        await input.press('x');
        await page.clock.runFor(3000);
        check(await input.inputValue() === 'gx', `${path}: real keystrokes cancel sample playback`);
        check(await page.evaluate(() => activePlaygroundTimers.size === 0), `${path}: real edits release all sample timers`);
        await page.evaluate(() => simulateTyping('ghbdtn', 'привет'));
        await page.clock.runFor(150);
        await input.press('Enter');
        await page.clock.runFor(3000);
        check(await input.inputValue() === 'g', `${path}: Enter on a partial sample cancels pending correction`);
        await page.evaluate(() => {
          clearPlayground();
          playgroundInput.value = 'ghbdtn';
          animateCorrection('ghbdtn', 'привет');
        });
        await input.focus();
        await input.press('x');
        check(await input.inputValue() === 'ghbdtn', `${path}: correction locks text edits`);
        const pasteBlocked = await page.evaluate(() => !playgroundInput.dispatchEvent(new InputEvent('beforeinput', {
          inputType: 'insertFromPaste', data: 'pasted', bubbles: true, cancelable: true
        })));
        check(pasteBlocked, `${path}: correction blocks paste edits too`);
        await input.press('Tab');
        check(await page.evaluate(() => document.activeElement !== playgroundInput), `${path}: correction must not trap Tab`);
        await page.clock.runFor(1500);
        check(await input.inputValue() === 'привет ', `${path}: correction finishes normally`);
        check(await page.evaluate(() => !playgroundInput.readOnly && activePlaygroundTimers.size === 0), `${path}: correction unlocks input and releases timers`);
        await input.fill('руддщ');
        await input.press('Enter');
        await page.clock.runFor(1500);
        check(await input.inputValue() === 'hello ', `${path}: manual Enter correction works`);
        await input.fill('ghbdsn');
        await input.press('Space');
        await page.clock.runFor(1500);
        check(await input.inputValue() === 'привіт ', `${path}: manual Space correction works`);
        await page.evaluate(value => animateCorrection(value, value), payload);
        await page.clock.runFor(15000);
        check(await feedback.locator('img, svg').count() === 0, `${path}: correction feedback must escape both words`);
        check((await feedback.innerText()).includes(payload), `${path}: correction feedback renders words literally`);
      }
      check(!await page.evaluate(() => window.xssExecuted), `${path}: injected code never executes`);

      const button = page.locator(tutorial ? '.copy-btn' : '#btn-copy-install');
      const label = page.locator(tutorial ? '#copy-label' : '#copy-text');
      const defaultLabel = tutorial ? 'Copy' : 'Copy Command';
      const command = (await page.locator('#install-cmd').innerText()).trim();
      for (const mode of ['native', 'absent', 'missing-method', 'rejected', 'throws', 'insecure', 'fallback-false', 'fallback-throws']) {
        await page.evaluate(mode => {
          window.copyCalls = 0;
          window.copiedText = null;
          window.fallbackCalls = 0;
          const clipboard = {
            writeText(text) {
              window.copyCalls++;
              window.copiedText = text;
              if (mode === 'throws') throw new Error('Clipboard blocked');
              return mode === 'rejected' ? Promise.reject(new Error('Permission denied')) : Promise.resolve();
            }
          };
          Object.defineProperty(navigator, 'clipboard', { configurable: true, value:
            ['absent', 'fallback-false', 'fallback-throws'].includes(mode) ? undefined : mode === 'missing-method' ? {} : clipboard
          });
          Object.defineProperty(window, 'isSecureContext', { configurable: true, value: mode !== 'insecure' });
          document.execCommand = action => {
            window.fallbackCalls++;
            if (action !== 'copy') throw new Error('Unexpected command');
            window.copiedText = document.activeElement.value;
            if (mode === 'fallback-throws') throw new Error('Legacy copy blocked');
            return mode !== 'fallback-false';
          };
        }, mode);
        await button.click();
        // Flush the async clipboard result without advancing feedback timers.
        await page.evaluate(() => Promise.resolve());
        const failed = mode.startsWith('fallback-');
        check((await label.innerText()).includes(failed ? 'Cmd+C' : 'Copied'), `${path}: ${mode} feedback`);
        check(await page.evaluate(() => window.copiedText) === command, `${path}: ${mode} copies the complete command`);
        check(await page.evaluate(() => window.fallbackCalls) === (mode === 'native' ? 0 : 1), `${path}: ${mode} chooses the correct clipboard path`);
        check(await page.locator('textarea').count() === 0, `${path}: ${mode} cleans temporary elements`);
        check(await button.evaluate(el => document.activeElement === el), `${path}: ${mode} preserves keyboard focus`);
        if (failed) check(await page.evaluate(() => getSelection().toString()) === command, `${path}: failed copy selects the command for manual copying`);
        await page.clock.runFor(3500);
        check(await label.innerText() === defaultLabel, `${path}: ${mode} resets feedback`);
      }

      // Repeated clicks while pending must share one request; later clicks reset
      // from the stable default, not the transient "Copied" label.
      await page.evaluate(() => {
        Object.defineProperty(window, 'isSecureContext', { configurable: true, value: true });
        window.copyCalls = 0;
        Object.defineProperty(navigator, 'clipboard', { configurable: true, value: {
          writeText() {
            window.copyCalls++;
            return new Promise(resolve => { window.resolveCopy = resolve; });
          }
        } });
      });
      await button.click();
      await button.click();
      check(await page.evaluate(() => window.copyCalls) === 1, `${path}: overlapping copies are guarded`);
      await page.evaluate(() => window.resolveCopy());
      await page.clock.runFor(500);
      await button.click();
      await page.evaluate(() => window.resolveCopy());
      await page.clock.runFor(3500);
      check(await label.innerText() === defaultLabel, `${path}: repeated copies restore the default label`);

      // Assets and layouts must work both on Pages and in the standalone guide.
      check(await page.locator('img').evaluateAll(images => images.every(img => img.complete && img.naturalWidth > 0)), `${path}: every screenshot and icon loads`);
      if (tutorial) {
        for (const type of ['acc', 'input']) {
          await page.locator(`#btn-toggle-${type}-real`).click();
          check(await page.locator(`#screenshot-${type}`).isVisible(), `${path}: ${type} real screenshot can be opened`);
          await page.locator(`#btn-toggle-${type}-sim`).click();
          check(!await page.locator(`#screenshot-${type}`).isVisible(), `${path}: ${type} simulator can be restored`);
        }
        for (const id of ['practice-acc', 'practice-input', 'practice-correction']) {
          await page.locator(`#${id} > summary`).click();
        }
        await page.locator('#launch-help > summary').focus();
        await page.keyboard.press('Enter');
        check(await page.locator('#launch-help').evaluate(el => el.open), `${path}: launch help opens with the keyboard`);
      }
      for (const width of [1280, 390, 320]) {
        await page.setViewportSize({ width, height: 900 });
        check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${path}: no horizontal overflow at ${width}px`);
      }
      if (tutorial) {
        await page.locator('.setup-nav a[href="#open-app"]').click();
        const top = await page.locator('#open-app').evaluate(el => el.getBoundingClientRect().top);
        check(top >= 55 && top <= 100, `${path}: launch anchor is visible below the sticky header`);
        const screenshots = await page.locator('#open-app img').evaluateAll(images => images.map(img => img.getAttribute('src')));
        check(screenshots.length === 2 && screenshots.some(src => src.endsWith('gatekeeper-open-anyway.png')), `${path}: launch approval uses both supplied screenshots`);
      }
    }
    check(errors.length === 0, `Unexpected page errors: ${errors.join('; ')}`);
    return { passed, failed: 0, pages: paths };
  } finally {
    page.off('pageerror', onError);
  }
}
