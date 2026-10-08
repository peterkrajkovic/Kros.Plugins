/**
 * Draws the tip above the prompt.
 *
 * On the desktop Code tab a SessionStart hook's `systemMessage` is accepted, stored as a
 * `hook_system_message` attachment and never drawn (anthropics/claude-code#75534), so the
 * only deterministic way to put a notice in front of someone there is to draw it from a
 * mod. That is decision D14; this is its renderer.
 *
 * It decides nothing. Show-DevTip.ps1 applies the cooldown, maxShows, the usage
 * suppression and the source ranking, and writes what it picked to a handshake file. This
 * reads that file, draws it, and writes the answer back.
 */
import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Answer } from '../../types'

const sessionId = atom({ plugin: 'dev-tips', key: 'sessionId' } as const, null)
const isOpen = atom({ plugin: 'dev-tips', key: 'isOpen' } as const, false)
const answeredId = atom({ plugin: 'dev-tips', key: 'answeredId' } as const, null)

type Pending = {
  id: string
  kind: string
  title: string
  body: string
  ref: string | null
  url: string | null
  installState: string
  stateDir: string
}

/**
 * The handshake path. A module never receives CLAUDE_PLUGIN_DATA - the engine sets it for
 * hook processes - and the real data directory is named after the marketplace that
 * installed us, which a module has no way to learn. So both sides spell a fixed path, and
 * the session id keys it so two sessions starting together do not read each other's tip.
 */
async function readPending($: Parameters<Parameters<Register>[0]>[2] extends never ? never : any, id: string) {
  const home = (await $.env.get('USERPROFILE')) ?? (await $.env.get('HOME'))
  if (!home) return null

  try {
    const text = await $.fs.read(`${home}/.claude/plugins/data/dev-tips-shared/pending-${id}.json`)

    return JSON.parse(text) as Pending
  } catch {
    return null
  }
}

export const register: Register = on => {
  on('classic.SessionStart', async ($, e, next) => {
    // The same payload the PowerShell hook reads, so both name the handshake file alike.
    if (e.session_id) {
      await update($, sessionId, () => e.session_id)
    }

    return next(e)
  }).catch(($, e, next) => {
    // This hook gates the start of a session. A tip is never worth delaying one, so a
    // failure here hands the event on untouched and the band simply has no id to use.
    if (next.called) return undefined

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const id = await read($, sessionId)
    if (!id) return next(e)

    const pending = await readPending($, id)
    if (pending === null) return next(e)

    // Keyed by tip, not a flag: an answer must not silence the tip that comes after it.
    if ((await read($, answeredId)) === pending.id) return next(e)

    const open = await read($, isOpen)
    const { Box, Button, Link, Text } = $.ui.resolve(e)
    const choose = (value: Answer) => update($, answeredId, () => pending.id)

    return (
      <Box flexDirection="column">
        {/*
          The body stays out of this row. Sharing one narrows its column, and the terminal
          then wraps it inside that column while the row is one line tall, strewing the
          remainder across the title.
        */}
        <Box gap={1}>
          <Box flexGrow={1}>
            <Text>
              💡 <Text bold>{pending.title}</Text>
            </Text>
          </Box>
          <Box gap={1} flexShrink={0}>
            {!open && <Button key="open" label="Rozbaliť" hotkey="1" onPress={() => update($, isOpen, () => true)} />}
            {open && <Button key="close" label="Zbaliť" hotkey="1" onPress={() => update($, isOpen, () => false)} />}
            {/* U+00D7: one cell wide everywhere, unlike U+2715, which shifts the row. */}
            <Button key="drop" label="×" hotkey="2" onPress={() => choose('dropped')} />
          </Box>
        </Box>

        <Text dimColor={!open}>{pending.body}</Text>

        {pending.ref && pending.installState === 'installed' && (
          <Text dimColor>Spúšťa sa cez {pending.ref}.</Text>
        )}

        {open && (
          <Box gap={2}>
            <Button key="show" label="Ukáž ako" hotkey="3" onPress={() => choose('show')} />
            <Button key="known" label="Už to používam" hotkey="4" onPress={() => choose('known')} />
            {pending.url ? <Link href={pending.url} label="Dokumentácia" /> : null}
          </Box>
        )}

        {/* Only the terminal needs this: there a Button takes a click once its site holds
            the focus, and nothing on screen says so. */}
        {e.surface === 'terminal' && <Text dimColor>tab aktivuje ovládanie</Text>}
      </Box>
    )
  })
}
