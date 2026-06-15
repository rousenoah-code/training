'use client'

import { useEffect, useState, useRef } from 'react'
import { supabase } from '@/lib/supabase'

interface PollConfig {
  question: string
  option_a: string
  option_b: string
  option_c: string
  option_d: string
}

const OPTIONS = ['a', 'b', 'c', 'd'] as const
type Option = (typeof OPTIONS)[number]

const LABEL_MAP: Record<Option, string> = { a: 'Option A', b: 'Option B', c: 'Option C', d: 'Option D' }
const FIELD_MAP: Record<Option, keyof PollConfig> = {
  a: 'option_a',
  b: 'option_b',
  c: 'option_c',
  d: 'option_d',
}

function Spinner() {
  return (
    <div className="flex items-center justify-center min-h-screen">
      <div
        className="w-12 h-12 rounded-full border-4 border-transparent animate-spin"
        style={{ borderTopColor: '#C23B6F', borderRightColor: '#C23B6F' }}
      />
    </div>
  )
}

export default function AdminPage() {
  const [form, setForm] = useState<PollConfig>({
    question: '',
    option_a: '',
    option_b: '',
    option_c: '',
    option_d: '',
  })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [success, setSuccess] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [resetError, setResetError] = useState<string | null>(null)
  const [voteCounts, setVoteCounts] = useState<Record<Option, number>>({ a: 0, b: 0, c: 0, d: 0 })
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)

  async function loadVotes() {
    const { data } = await supabase.from('votes').select('option')
    if (data) {
      const counts: Record<Option, number> = { a: 0, b: 0, c: 0, d: 0 }
      data.forEach((v) => {
        if (v.option in counts) counts[v.option as Option]++
      })
      setVoteCounts(counts)
    }
  }

  useEffect(() => {
    async function loadPoll() {
      const { data } = await supabase.from('poll_config').select('*').eq('id', 1).single()
      if (data) {
        setForm({
          question: data.question,
          option_a: data.option_a,
          option_b: data.option_b,
          option_c: data.option_c,
          option_d: data.option_d,
        })
      }
      setLoading(false)
    }

    loadPoll()
    loadVotes()

    const channel = supabase
      .channel('admin-votes-realtime')
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'votes' }, (payload) => {
        const opt = payload.new.option as Option
        if (OPTIONS.includes(opt)) {
          setVoteCounts((prev) => ({ ...prev, [opt]: prev[opt] + 1 }))
        }
      })
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'votes' }, () => {
        loadVotes()
      })
      .subscribe()

    channelRef.current = channel

    return () => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current)
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function handleSave(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    setSaveError(null)
    const { error } = await supabase.from('poll_config').update(form).eq('id', 1)
    setSaving(false)
    if (error) {
      setSaveError('Failed to save: ' + error.message)
    } else {
      setSuccess(true)
      setTimeout(() => setSuccess(false), 3000)
    }
  }

  async function handleReset() {
    if (!confirm('Are you sure you want to delete all votes? This cannot be undone.')) return
    setResetError(null)
    // Use gte on created_at to satisfy Supabase's requirement for a filter on delete
    const { error } = await supabase.from('votes').delete().gte('created_at', '1970-01-01')
    if (error) {
      setResetError('Failed to reset votes: ' + error.message)
    }
  }

  const totalVotes = Object.values(voteCounts).reduce((a, b) => a + b, 0)

  if (loading) return <Spinner />

  return (
    <main className="min-h-screen px-4 py-12 flex flex-col items-center">
      <div className="w-full max-w-[680px]">
        <h1 className="text-2xl font-bold mb-8 text-center" style={{ color: '#3D4A5C' }}>
          Poll Admin
        </h1>

        <form onSubmit={handleSave} className="flex flex-col gap-4 mb-6">
          <div>
            <label className="block text-sm font-bold mb-1" style={{ color: '#3D4A5C' }}>
              Question
            </label>
            <input
              className="w-full rounded-2xl border-2 px-4 py-3 text-sm outline-none"
              style={{ borderColor: '#C23B6F', color: '#3D4A5C', backgroundColor: '#fff' }}
              value={form.question}
              onChange={(e) => setForm((f) => ({ ...f, question: e.target.value }))}
              required
            />
          </div>

          {OPTIONS.map((opt) => (
            <div key={opt}>
              <label className="block text-sm font-bold mb-1" style={{ color: '#3D4A5C' }}>
                {LABEL_MAP[opt]}
                <span className="ml-2 text-xs font-normal" style={{ color: '#C23B6F' }}>
                  ({voteCounts[opt]} votes)
                </span>
              </label>
              <input
                className="w-full rounded-2xl border-2 px-4 py-3 text-sm outline-none"
                style={{ borderColor: '#C23B6F', color: '#3D4A5C', backgroundColor: '#fff' }}
                value={form[FIELD_MAP[opt]]}
                onChange={(e) => setForm((f) => ({ ...f, [FIELD_MAP[opt]]: e.target.value }))}
                required
              />
            </div>
          ))}

          {saveError && (
            <p className="text-sm" style={{ color: '#C23B6F' }}>
              {saveError}
            </p>
          )}
          {success && (
            <p className="text-sm font-bold" style={{ color: '#C23B6F' }}>
              Poll updated!
            </p>
          )}

          <button
            type="submit"
            disabled={saving}
            className="rounded-2xl px-6 py-3 font-bold text-white transition-opacity hover:opacity-90 min-h-[48px]"
            style={{ backgroundColor: '#C23B6F' }}
          >
            {saving ? 'Saving...' : 'Save'}
          </button>
        </form>

        <div className="my-8 h-px" style={{ backgroundColor: 'rgba(194, 59, 111, 0.2)' }} />

        <div>
          <h2 className="text-lg font-bold mb-2" style={{ color: '#3D4A5C' }}>
            Live Vote Counts
          </h2>
          <p className="text-sm mb-4" style={{ color: '#9CA3AF' }}>
            {totalVotes} votes total
          </p>
          <div className="flex flex-col gap-2 mb-6">
            {OPTIONS.map((opt) => (
              <div
                key={opt}
                className="flex items-center justify-between rounded-2xl bg-white px-5 py-3 shadow-sm"
              >
                <span className="text-sm font-medium" style={{ color: '#3D4A5C' }}>
                  {form[FIELD_MAP[opt]] || LABEL_MAP[opt]}
                </span>
                <span
                  className="text-xs font-bold px-3 py-1 rounded-full text-white"
                  style={{ backgroundColor: '#C23B6F' }}
                >
                  {voteCounts[opt]}
                </span>
              </div>
            ))}
          </div>

          {resetError && (
            <p className="text-sm mb-3" style={{ color: '#C23B6F' }}>
              {resetError}
            </p>
          )}

          <button
            onClick={handleReset}
            className="w-full rounded-2xl px-6 py-3 font-bold transition-colors hover:bg-pink-50 min-h-[48px]"
            style={{ border: '2px solid #C23B6F', color: '#C23B6F', backgroundColor: 'transparent' }}
          >
            Reset All Votes
          </button>
        </div>
      </div>
    </main>
  )
}
