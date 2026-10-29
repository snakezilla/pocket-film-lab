import type { Recipe } from './engine/film'
import type { JobRequest, JobResponse } from './worker'

export class CancelledError extends Error {
  constructor() {
    super('Cancelled')
    this.name = 'CancelledError'
  }
}

export interface RenderResult {
  readonly image: ImageData
  readonly ms: number
}

/**
 * One background worker running one job at a time. cancel() terminates the
 * worker (a pixel loop cannot be interrupted any other way) and rejects the
 * pending job with CancelledError.
 */
export class Processor {
  private worker: Worker | null = null
  private nextId = 1
  private pending: { id: number; reject: (e: Error) => void } | null = null

  render(source: ImageData, recipe: Recipe, lut: ArrayBuffer, lutSize: number): Promise<RenderResult> {
    this.cancel()
    const worker = this.ensureWorker()
    const id = this.nextId++
    return new Promise<RenderResult>((resolve, reject) => {
      this.pending = { id, reject }
      worker.onmessage = (event: MessageEvent<JobResponse>) => {
        const msg = event.data
        if (msg.id !== id) return
        this.pending = null
        if (msg.ok) {
          const pixels = new Uint8ClampedArray(msg.pixels)
          resolve({ image: new ImageData(pixels, source.width, source.height), ms: msg.ms })
        } else {
          reject(new Error(`Processing failed: ${msg.error}`))
        }
      }
      worker.onerror = (event) => {
        this.pending = null
        this.dispose()
        reject(new Error(`Processing failed: ${event.message || 'the worker stopped (likely out of memory)'}`))
      }
      const request: JobRequest = {
        id,
        pixels: source.data.slice().buffer,
        width: source.width,
        height: source.height,
        recipe,
        lut: lut.slice(0),
        lutSize,
      }
      worker.postMessage(request, [request.pixels, request.lut])
    })
  }

  get busy(): boolean {
    return this.pending !== null
  }

  cancel(): void {
    if (!this.pending) return
    const { reject } = this.pending
    this.pending = null
    this.dispose()
    reject(new CancelledError())
  }

  dispose(): void {
    this.worker?.terminate()
    this.worker = null
  }

  private ensureWorker(): Worker {
    if (!this.worker) {
      this.worker = new Worker(new URL('./worker.ts', import.meta.url), { type: 'module' })
    }
    return this.worker
  }
}
