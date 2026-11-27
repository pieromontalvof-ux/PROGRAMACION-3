export const API_BASE_URL = import.meta.env.VITE_API_URL || (import.meta.env.DEV ? 'http://127.0.0.1:5000/api' : '/api')
export const CORPORATE_EMAIL_DOMAIN = (import.meta.env.VITE_CORPORATE_EMAIL_DOMAIN || 'barbarian.pe').trim().toLowerCase().replace(/^@/, '') || 'barbarian.pe'
