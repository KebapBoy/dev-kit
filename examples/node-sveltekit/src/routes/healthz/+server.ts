import pkg from '../../../package.json' with { type: 'json' }
import type { RequestHandler } from './$types'

/** Liveness check for the container health check, the reverse proxy and dev-kit deploy. */
export const GET: RequestHandler = () => Response.json({ status: 'ok', version: pkg.version })
