import { defineConfig } from 'vitest/config'

export default defineConfig({
  base: './',
  build: { target: 'es2020' },
  worker: { format: 'es' },
  test: { include: ['tests/unit/**/*.test.ts'] },
})
