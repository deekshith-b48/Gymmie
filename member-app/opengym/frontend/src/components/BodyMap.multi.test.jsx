// @vitest-environment happy-dom
import React, { act } from 'react'
import { createRoot } from 'react-dom/client'
import { afterEach, describe, expect, it, vi } from 'vitest'
import BodyMap from './BodyMap.jsx'

globalThis.IS_REACT_ACT_ENVIRONMENT = true
const hosts = []
afterEach(() => { for (const h of hosts.splice(0)) h.remove() })

async function mount(el) {
  const host = document.createElement('div'); document.body.appendChild(host); hosts.push(host)
  const root = createRoot(host)
  await act(async () => { root.render(el) })
  await vi.waitFor(() => expect(host.querySelector('.bm-m')).not.toBeNull())
  return host
}

describe('BodyMap selection', () => {
  it('shows several selected muscles at once when given a list', async () => {
    const host = await mount(<BodyMap onMuscle={() => {}} selected={['chest', 'biceps']} />)
    const on = [...host.querySelectorAll('.bm-m.sel')].map(p => p.getAttribute('aria-label'))
    expect(on.length).toBeGreaterThan(1)
    expect(host.querySelectorAll('.bm-m[aria-pressed="true"]').length).toBe(on.length)
  })

  it('still takes a single slug, and nothing selected shows nothing selected', async () => {
    const one = await mount(<BodyMap onMuscle={() => {}} selected="chest" />)
    expect(one.querySelectorAll('.bm-m.sel').length).toBeGreaterThan(0)
    const none = await mount(<BodyMap onMuscle={() => {}} selected={[]} />)
    expect(none.querySelectorAll('.bm-m.sel').length).toBe(0)
  })

  it('reports the tapped muscle', async () => {
    const pick = vi.fn()
    const host = await mount(<BodyMap onMuscle={pick} selected={[]} />)
    await act(async () => { host.querySelector('.bm-m').dispatchEvent(new MouseEvent('click', { bubbles: true })) })
    expect(pick).toHaveBeenCalledTimes(1)
  })
})
