import type { Config } from 'tailwindcss';

export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        cream: '#F7F2E8',
        ivory: '#FBF8F3',
        peach: '#FCEEE1',
        orange: '#F97316',
        'orange-deep': '#EA580C',
        espresso: '#2D221B',
        taupe: '#7A6A5E',
        mint: '#86EFAC',
        green: '#16A34A',
        lavender: '#A78BFA',
        coral: '#EF4444',
      },
      boxShadow: {
        clay: '0 12px 30px rgba(140, 109, 79, .12), -2px -2px 5px rgba(255,255,255,.9)',
        'clay-orange': '0 8px 20px rgba(249,115,22,.26), inset 0 1px 0 rgba(255,255,255,.5)',
        inset: 'inset 0 2px 6px rgba(140,109,79,.08), 0 1px 0 rgba(255,255,255,.8)',
      },
      borderRadius: { clay: '24px' },
      fontFamily: { sorani: ['Noto Sans Arabic', 'Tahoma', 'Arial', 'sans-serif'] },
    },
  },
  plugins: [],
} satisfies Config;
