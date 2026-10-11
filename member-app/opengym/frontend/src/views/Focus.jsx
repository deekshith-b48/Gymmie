import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useStore } from '../store/useStore.js'
import { allExercises, searchExercises } from '../lib/exercises.js'
import { activeProfile, exAvailable } from '../lib/equipment.js'
import { MUSCLES, MUSCLE_NAME, musclesOf } from '../lib/muscles.js'
import { exCount } from '../lib/format.js'
import { t, exerciseNameFor, exerciseNameClass } from '../lib/i18n.js'
import { tappable } from '../lib/use-sheet-keyboard.js'
import { sortFavouritesFirst } from '../lib/favourites.js'
import { startFocusWorkout } from '../sheets.jsx'
import BodyMap from '../components/BodyMap.jsx'
import { Thumb } from '../components/Media.jsx'
import Icon from '../components/Icon.jsx'
import { Button } from '../components/ui.jsx'

// "Choose a focus" → "Pick exercises" → Start. Ported from GymMane's Train screen: tap the muscles
// you want to train on the body map, review the exercises that hit them, tick the ones you want and
// start a freestyle session with exactly those.
export default function Focus() {
  const nav = useNavigate()
  const S = useStore(s => s.S)
  const [step, setStep] = useState(1)
  const [muscles, setMuscles] = useState([])
  const [picks, setPicks] = useState([])
  const [q, setQ] = useState('')
  const [shown, setShown] = useState(60)

  const profile = activeProfile(S)
  const catalog = useMemo(() => {
    const all = allExercises(S)
    return profile ? all.filter(e => exAvailable(S, e)) : all
  }, [S.customEx, S.equipFilterOn, S.activeEquipId, S.equipProfiles])

  const toggleMuscle = m => setMuscles(cur => cur.includes(m) ? cur.filter(x => x !== m) : [...cur, m])
  const matching = useMemo(() => {
    if (!muscles.length) return []
    // Primary hits first, then exercises that only work the muscle as a helper.
    const score = e => Math.max(...muscles.map(m => musclesOf(e)[m] === 1 ? 2 : musclesOf(e)[m] ? 1 : 0))
    return catalog.map(e => [e, score(e)]).filter(([, s]) => s > 0).sort((a, b) => b[1] - a[1]).map(([e]) => e)
  }, [catalog, muscles])
  const list = sortFavouritesFirst(searchExercises(matching, q), S)
  const togglePick = id => setPicks(cur => cur.includes(id) ? cur.filter(x => x !== id) : [...cur, id])
  const label = muscles.map(m => t(MUSCLE_NAME[m])).join(' + ')

  const back = () => { if (step === 2) setStep(1); else nav(-1) }
  const start = () => { if (picks.length) startFocusWorkout(picks, label) }

  return <div className="narrow">
    <div className="hdr">
      <button className="iconbtn" onClick={back} aria-label={t('Back')}><Icon name="chevronLeft" /></button>
      <div style={{ flex: 1, marginInlineStart: 12 }}>
        <div className="sub" style={{ textTransform: 'uppercase', letterSpacing: '.12em', fontSize: 11 }}>{step === 1 ? t('Step 1 of 2') : t('Step 2 of 2')}</div>
        <h1>{step === 1 ? t('Choose a focus') : label}</h1>
      </div>
    </div>

    {step === 1 && <>
      <div className="card">
        <BodyMap className="tappable" body={S.body} selected={muscles} onMuscle={toggleMuscle} />
      </div>
      <div className="dim small" style={{ textAlign: 'center', margin: '8px 0 12px' }}>{t('Tap the muscles you want to train')}</div>
      <div className="chips" style={{ minHeight: 38, marginBottom: 14 }}>
        {muscles.map(m => <button key={m} className="chip on" onClick={() => toggleMuscle(m)}>{t(MUSCLE_NAME[m])} <Icon name="xmark" /></button>)}
      </div>
      <Button variant="primary" disabled={!muscles.length} onClick={() => { setPicks([]); setQ(''); setShown(60); setStep(2) }}>{t('Continue')}</Button>
    </>}

    {step === 2 && <>
      <div className="search-row" style={{ marginBottom: 12 }}><div className={'search' + (q ? ' has-clear' : '')}>
        <input className="input" placeholder={t('Search…')} value={q} onChange={e => { setQ(e.target.value); setShown(60) }} />
        {q && <button className="clear" onClick={() => setQ('')} aria-label={t('Clear')}><Icon name="xmark" /></button>}
      </div></div>
      <div className="list" style={{ paddingBottom: 90 }}>
        {list.slice(0, shown).map(e => {
          const on = picks.includes(e.id)
          const primary = muscles.some(m => musclesOf(e)[m] === 1)
          return <div key={e.id} className={'item' + (on ? ' on' : '')} aria-pressed={on} {...tappable(() => togglePick(e.id))}>
            <Thumb ex={e} />
            <div className="grow"><div className={`tt ${exerciseNameClass(e)}`}>{exerciseNameFor(e)}</div>
              <div className="ss">{t(primary ? 'Primary target' : 'Also trains')}</div></div>
            <Icon name={on ? 'checkCircle' : 'plus'} className={on ? 'accent chev' : 'chev'} />
          </div>
        })}
        {list.length === 0 && <div className="empty"><div className="ico"><Icon name="magnifier" /></div>{t('No match')}</div>}
      </div>
      {list.length > shown && <Button onClick={() => setShown(s => s + 60)}>{t('Show more')}</Button>}
      <div style={{ position: 'sticky', bottom: 'calc(var(--sab, 0px) + 74px)', padding: '10px 0', background: 'linear-gradient(to top,var(--bg) 60%,transparent)' }}>
        <Button variant="primary" disabled={!picks.length} icon={picks.length ? 'play' : undefined} onClick={start}>
          {picks.length ? `${t('Start')} · ${exCount(picks.length)}` : t('Pick an exercise')}
        </Button>
      </div>
    </>}
  </div>
}
