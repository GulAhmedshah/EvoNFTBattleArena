/*
This file contains the content for multiple files required for the frontend setup.
Each file's content is separated by a header indicating its path.
*/

// --- FILE: .env.example ---
# -----------------------------------------------------------------------------
# Smart Contract Addresses
# -----------------------------------------------------------------------------
# The address of the deployed EvoNFT (ERC721) contract.
VITE_EVONFT_CONTRACT="0x..."

# The address of the deployed GameToken (ERC20) contract.
VITE_GAME_TOKEN_CONTRACT="0x..."

# The address of the deployed Staking contract.
VITE_STAKING_CONTRACT="0x..."


# -----------------------------------------------------------------------------
# Third-Party Services
# -----------------------------------------------------------------------------
# Your project ID from WalletConnect Cloud (https://cloud.walletconnect.com/)
VITE_WALLET_CONNECT_PROJECT_ID=""



// --- FILE: frontend/package.json ---
{
  "name": "evonft-staking-frontend",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "lint": "eslint . --ext js,jsx --report-unused-disable-directives --max-warnings 0",
    "preview": "vite preview"
  },
  "dependencies": {
    "@web3modal/ethers": "^4.1.1",
    "@web3modal/react": "^4.1.1",
    "ethers": "^6.11.1",
    "framer-motion": "^11.0.8",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-hot-toast": "^2.4.1",
    "react-router-dom": "^6.22.2"
  },
  "devDependencies": {
    "@types/react": "^18.2.56",
    "@types/react-dom": "^18.2.19",
    "@vitejs/plugin-react": "^4.2.1",
    "autoprefixer": "^10.4.17",
    "eslint": "^8.56.0",
    "eslint-plugin-react": "^7.33.2",
    "eslint-plugin-react-hooks": "^4.6.0",
    "eslint-plugin-react-refresh": "^0.4.5",
    "postcss": "^8.4.35",
    "tailwindcss": "^3.4.1",
    "vite": "^5.1.4"
  }
}



// --- FILE: frontend/vite.config.js ---
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
  },
})



// --- FILE: frontend/tailwind.config.js ---
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: '#6366f1',   // Indigo 500
        secondary: '#8b5cf6', // Violet 500
        accent: '#d946ef',    // Fuchsia 500
        dark: '#1a1a2e',
      },
      animation: {
        'pulse-slow': 'pulse 4s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'float': 'float 6s ease-in-out infinite',
        'glow': 'glow 2.5s ease-in-out infinite alternate',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-15px)' },
        },
        glow: {
          'from': {
            'text-shadow': '0 0 5px #fff, 0 0 10px #6366f1, 0 0 15px #6366f1',
          },
          'to': {
            'text-shadow': '0 0 10px #fff, 0 0 20px #8b5cf6, 0 0 30px #8b5cf6',
          }
        }
      },
    },
  },
  plugins: [],
}



// --- FILE: frontend/postcss.config.js ---
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}



// --- FILE: frontend/index.html ---
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>EvoNFT Staking</title>
  </head>
  <body class="bg-dark text-white">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>



// --- FILE: frontend/src/index.css ---
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  font-family: 'Inter', system-ui, Avenir, Helvetica, Arial, sans-serif;
  line-height: 1.5;
  font-weight: 400;

  color-scheme: dark;
  color: rgba(255, 255, 255, 0.87);
  background-color: #1a1a2e;

  font-synthesis: none;
  text-rendering: optimizeLegibility;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

body {
  margin: 0;
  min-width: 320px;
  min-height: 100vh;
  background-color: #1a1a2e; /* dark color */
  background-image:
    radial-gradient(at 10% 20%, #6366f11a 0px, transparent 50%),
    radial-gradient(at 85% 80%, #8b5cf61a 0px, transparent 50%),
    radial-gradient(at 40% 60%, #d946ef10 0px, transparent 50%);
}

/* Glassmorphism utility class */
@layer components {
  .glassmorphism {
    @apply bg-clip-padding backdrop-filter backdrop-blur-md bg-opacity-20 border border-gray-700;
    background-color: rgba(26, 26, 46, 0.25);
  }
}



// --- FILE: frontend/src/main.jsx ---
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)



// --- FILE: frontend/src/App.jsx (Placeholder) ---
import { Toaster, toast } from 'react-hot-toast';

function App() {
  return (
    <div className="min-h-screen flex flex-col items-center justify-center text-white p-4">
      <header className="absolute top-0 w-full p-6 flex justify-between items-center">
        <h1 className="text-2xl font-bold text-primary animate-glow">EvoNFT Staking</h1>
        <div>{/* TODO: Connect Button will go here */}</div>
      </header>

      <main className="flex flex-col items-center justify-center text-center">
        <div className="glassmorphism p-8 md:p-12 rounded-2xl shadow-2xl max-w-lg">
          <div className="animate-float mb-6">
            <img src="/favicon.svg" className="h-20 w-20 mx-auto" alt="EvoNFT Logo" />
          </div>
          <h2 className="text-3xl md:text-4xl font-bold mb-4">The Evolution of Staking is Here</h2>
          <p className="text-md text-gray-300 mb-8">
            Stake your EvoNFTs to earn rewards and participate in our growing ecosystem.
          </p>
          <button
            className="bg-primary hover:bg-secondary text-white font-bold py-3 px-6 rounded-lg transition-all duration-300 transform hover:scale-105 shadow-lg"
            onClick={() => toast.success('Frontend setup is complete!')}
          >
            Get Started
          </button>
        </div>
      </main>

      <Toaster
        position="bottom-right"
        toastOptions={{
          style: {
            background: '#1a1a2e',
            color: '#fff',
            border: '1px solid #6366f1',
          },
        }}
      />

      <footer className="absolute bottom-0 w-full p-4 text-center text-gray-500 text-sm">
        <p>EvoNFT Staking Platform &copy; 2024</p>
      </footer>
    </div>
  );
}

export default App;



// --- FILE: frontend/public/favicon.svg ---
<svg width="100" height="100" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg">
<defs>
<linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="100%">
<stop offset="0%" style="stop-color:#d946ef;stop-opacity:1" />
<stop offset="50%" style="stop-color:#8b5cf6;stop-opacity:1" />
<stop offset="100%" style="stop-color:#6366f1;stop-opacity:1" />
</linearGradient>
</defs>
<path d="M50 0L95.11 25V75L50 100L4.88 75V25L50 0Z" fill="url(#grad1)"/>
<path d="M50 10L87.55 30V70L50 90L12.45 70V30L50 10Z" fill="#1A1A2E"/>
<path d="M50 20L75.11 35V65L50 80L24.89 65V35L50 20Z" fill="url(#grad1)"/>
</svg>



// --- FILE: frontend/src/abis/.gitkeep ---
# This file is used to ensure the abis/ directory is tracked by git.
# Place your contract ABI JSON files in this directory.
# For example:
# - EvoNFT.json
# - GameToken.json
# - Staking.json
