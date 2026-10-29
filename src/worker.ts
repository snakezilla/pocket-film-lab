/// <reference lib="webworker" />
import { renderFilmPixels, type Recipe } from './engine/film'
import { parseLut } from './engine/lut'

export interface JobRequest {
  readonly id: number
  readonly pixels: ArrayBuffer
  readonly width: number
  readonly height: number
  readonly recipe: Recipe
  readonly lut: ArrayBuffer
  readonly lutSize: number
}

export type JobResponse =
  | { readonly id: number; readonly ok: true; readonly pixels: ArrayBuffer; readonly ms: number }
  | { readonly id: number; readonly ok: false; readonly error: string }

const scope = self as unknown as DedicatedWorkerGlobalScope

scope.onmessage = (event: MessageEvent<JobRequest>) => {
  const job = event.data
  const start = performance.now()
  try {
    const out = renderFilmPixels({
      pixels: new Uint8ClampedArray(job.pixels),
      width: job.width,
      height: job.height,
      recipe: job.recipe,
      lut: parseLut(job.lut, job.lutSize),
    })
    const reply: JobResponse = { id: job.id, ok: true, pixels: out.buffer as ArrayBuffer, ms: performance.now() - start }
    scope.postMessage(reply, [reply.pixels])
  } catch (error) {
    const reply: JobResponse = { id: job.id, ok: false, error: error instanceof Error ? error.message : String(error) }
    scope.postMessage(reply)
  }
}
