import { expect, mock, test } from 'claude-code/testing'

const BAND = { component: 'AbovePrompt' as const, props: {} }
const HOME = 'C:/fake-home'
const SESSION = 'session-1'
const SHARED = `${HOME}/.claude/plugins/data/dev-tips-shared`

/** The engine normalises a path to the platform's separator before the event carries it. */
const isPending = (path: string) =>
  path.split('\\').join('/') === `${SHARED}/pending-${SESSION}.json`

const TIP = {
  id: 'az-pr',
  kind: 'skill',
  title: '/kros-shared:az-pr',
  body: 'Creates an Azure DevOps pull request from the current branch.',
  ref: '/kros-shared:az-pr',
  url: null,
  installState: 'installed',
  stateDir: `${HOME}/.claude/plugins/data/dev-tips-local`,
}

/**
 * The engine beneath the plugin. Nothing stands under a test's hooks, so every event the
 * plugin hands on has to be answered here or the chain has no bottom.
 */
const engineBeneath = (on: any) => {
  on('classic.SessionStart', () => ({}))
  on('ui.render', { component: 'AbovePrompt' }, ($: any, e: any) => {
    const { Box } = $.ui.resolve(e)

    return <Box />
  })
}

/**
 * A session that has started and been handed a tip.
 *
 * The test environment has no filesystem on purpose, so the handshake is served by
 * answering the engine's own `fs.read` from beneath the plugin - which is also a tighter
 * assertion than a real file: it proves the module asks for the path both sides agreed on.
 */
const given = async ($: any, on: any, tip: unknown = TIP) => {
  engineBeneath(on)
  mock.env(on, { USERPROFILE: HOME })

  on('fs.read', ($$: unknown, e: { path: string }) => {
    if (isPending(e.path)) {
      return { value: JSON.stringify(tip) }
    }

    throw new Error(`no such file: ${e.path}`)
  })

  await $.classic.SessionStart({ session_id: SESSION })
}

test('nothing was handed over, nothing is drawn', async ($, on) => {
  engineBeneath(on)
  mock.env(on, { USERPROFILE: HOME })
  await $.classic.SessionStart({ session_id: 'no-such-session' })

  const ui = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })

  expect(await ui.find({ type: 'Text', text: /💡/ })).toBeUndefined()

  await ui.unmount()
})

test('the handed-over tip is drawn, on every surface', async ($, on) => {
  await given($, on)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'dev-tips', surface, ...BAND })

    expect(await ui.find({ type: 'Text', text: /az-pr/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Creates an Azure DevOps/ })).toBeDefined()

    await ui.unmount()
  }
})

test('how to run it shows only once it is installed', async ($, on) => {
  await given($, on, { ...TIP, installState: 'marketplace-only' })

  const ui = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })

  expect(await ui.find({ type: 'Text', text: /Spúšťa sa cez/ })).toBeUndefined()

  await ui.unmount()
})

test('a tip with a document carries a link once opened', async ($, on) => {
  await given($, on, { ...TIP, url: 'https://example.invalid/doc.md' })

  const ui = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })
  await ui.press({ key: 'open' })

  expect(await ui.find({ type: 'Link' })).toBeDefined()

  await ui.unmount()
})

test('answering puts that tip away', async ($, on) => {
  await given($, on)

  const ui = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })
  await ui.press({ key: 'open' })
  await ui.press({ key: 'known' })

  expect(await ui.find({ type: 'Text', text: /az-pr/ })).toBeUndefined()

  await ui.unmount()
})

test('answering one tip does not silence the next one', async ($, on) => {
  engineBeneath(on)
  mock.env(on, { USERPROFILE: HOME })

  let served: unknown = TIP
  on('fs.read', ($$: unknown, e: { path: string }) => {
    if (isPending(e.path)) return { value: JSON.stringify(served) }

    throw new Error(`no such file: ${e.path}`)
  })
  await $.classic.SessionStart({ session_id: SESSION })

  const first = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })
  await first.press({ key: 'drop' })
  await first.unmount()

  served = { ...TIP, id: 'teapie', title: '/teapie' }

  const second = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })

  expect(await second.find({ type: 'Text', text: /teapie/ })).toBeDefined()

  await second.unmount()
})

test('the focus hint shows on a terminal and nowhere else', async ($, on) => {
  await given($, on)

  const term = await $.ui.mount({ plugin: 'dev-tips', surface: 'terminal', ...BAND })
  expect(await term.find({ type: 'Text', text: /tab aktivuje/ })).toBeDefined()
  await term.unmount()

  const desk = await $.ui.mount({ plugin: 'dev-tips', surface: 'desktop', ...BAND })
  expect(await desk.find({ type: 'Text', text: /tab aktivuje/ })).toBeUndefined()
  await desk.unmount()
})
