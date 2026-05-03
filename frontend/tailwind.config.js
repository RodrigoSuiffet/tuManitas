/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class'],
  content: [
    './index.html',
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: '#1A3C5E',
          light: '#2B5F8C',
          bg: '#E8F0F8',
        },
        secondary: {
          DEFAULT: '#E8720C',
          light: '#F5A56B',
        },
        success: {
          DEFAULT: '#2E7D32',
        },
        warning: {
          DEFAULT: '#E65100',
        },
        danger: {
          DEFAULT: '#C62828',
        },
        neutral: {
          900: '#1C2B3A',
          700: '#546E7A',
          100: '#F5F7FA',
          50: '#FFFFFF',
          border: '#CFD8DC',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      borderRadius: {
        card: '12px',
      },
      boxShadow: {
        card: '0 2px 8px rgba(26, 60, 94, 0.08)',
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
}
