// @vitest-environment happy-dom
// "Choose a focus" (ported from GymMane's Train screen): startFocusWorkout builds a freestyle
// session with exactly the picked exercises, in order, each with sets to log, and refuses to
// clobber a workout already in progress.
import { act } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { startFocusWorkout } from './sheets.jsx'
import { DEF, useStore } from './store/useStore.js'
import { useUI } from './store/useUI.js'

const BENCH = '0025'
const SQUAT = '0043'
const clone = v => JSON.parse(JSON.stringify(v))
const S = () => useStore.getState().S
function install(extra = {}) {
  const st = clone(DEF)
  Object.assign(st, { routines: [], week: {}, active: null, workouts: [], weighIn: false }, extra)
  useStore.setState({ S: st, user: null })
}
beforeEach(() => { localStorage.clear(); useUI.setState({ sheets: [] }) })
afterEach(() => vi.useRealTimers())

describe('startFocusWorkout', () => {
  it('starts a freestyle session with the picked exercises in order', () => {
    install()
    act(() => startFocusWorkout([BENCH, SQUAT], 'Chest + Quads'))
    const a = S().active
    expect(a.name).toBe('Chest + Quads')
    expect(a.routineIds).toEqual([])
    expect(a.entries.map(e => e.id)).toEqual([BENCH, SQUAT])
    for (const e of a.entries) {
      expect(e.sets.length).toBeGreaterThan(0)
      expect(e.sets.every(x => x.done !== true)).toBe(true)
      expect(e.rid).toBeUndefined()
    }
  })

  it('asks for the weigh-in first when that setting is on, and starts nothing until it is answered', () => {
    install({ weighIn: true })
    act(() => startFocusWorkout([BENCH], 'Chest'))
    expect(S().active).toBeNull()
    expect(useUI.getState().sheets.length).toBe(1)
  })

  it('does nothing without picks, and never replaces a workout in progress', () => {
    install()
    act(() => startFocusWorkout([], 'x'))
    expect(S().active).toBeNull()
    install({ active: { id: 'keep', d: '2026-10-10', start: 1, routineIds: [], name: 'Mine', cur: 0, entries: [] } })
    act(() => startFocusWorkout([BENCH], 'Chest'))
    expect(S().active.id).toBe('keep')
  })
})
