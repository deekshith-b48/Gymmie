// @vitest-environment happy-dom
// "My gym" in Settings: only on a Gymmie single-sign-on server AND only inside the Gymmie app,
// which is the thing that receives the request (window.GymmieApp).
import React, { act } from 'react'
import { createRoot } from 'react-dom/client'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { useStore } from '../store/useStore.js'
import Settings from './Settings.jsx'

globalThis.IS_REACT_ACT_ENVIRONMENT = true
const hosts = []
afterEach(() => { for (const h of hosts.splice(0)) h.remove(); delete window.GymmieApp; useStore.setState({ config: null }) })
function mount(config) {
  useStore.setState({ config })
  const host = document.createElement('div'); document.body.appendChild(host); hosts.push(host)
  act(() => createRoot(host).render(<MemoryRouter><Settings /></MemoryRouter>))
  return host
}
const row = host => [...host.querySelectorAll('button')].find(b => b.textContent.includes('My gym'))

describe('Settings › My gym', () => {
  it('shows and posts to the Gymmie app on an SSO server', () => {
    window.GymmieApp = { postMessage: vi.fn() }
    const r = row(mount({ sso_only: true }))
    expect(r).toBeTruthy()
    act(() => r.click())
    expect(window.GymmieApp.postMessage).toHaveBeenCalledWith('my-gym')
  })
  it('is absent without the Gymmie app, and on an ordinary server', () => {
    expect(row(mount({ sso_only: true }))).toBeFalsy()
    window.GymmieApp = { postMessage: vi.fn() }
    expect(row(mount({}))).toBeFalsy()
  })
})
