import { json } from '@sveltejs/kit'
import pkg from '../../../package.json' with { type: 'json' }
import type { RequestHandler } from './$types'

/** Liveness check for the container health check, the reverse proxy and dev-kit deploy. */
export const GET: RequestHandler = () => json({ status: 'ok', version: pkg.version })
