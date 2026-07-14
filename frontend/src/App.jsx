import React, { useState, useEffect, useCallback } from 'react';
import { BrowserRouter as Router, Routes, Route, NavLink } from 'react-router-dom';
import { ethers } from 'ethers';
import { createWeb3Modal, defaultConfig, useWeb3Modal, useWeb3ModalAccount, useWeb3ModalProvider } from '@web3modal/ethers/react';

// --- Basic Styles for Layout and Skeletons ---
const GlobalStyles = () => (
  <style>{`
    :root {
      --bg-color: #121212;
      --surface-color: #1e1e1e;
      --primary-color: #6200ee;
      --on-primary-color: #ffffff;
      --text-color: #e0e0e0;
      --skeleton-color: #333;
    }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
        'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
        sans-serif;
      background-color: var(--bg-color);
      color: var(--text-color);
    }
    .main-content {
      padding: 20px;
    }
    /* Navbar */
    .navbar {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 10px 20px;
      background-color: var(--surface-color);
      border-bottom: 1px solid #333;
    }
    .navbar-left { display: flex; align-items: center; gap: 20px; }
    .navbar-logo { font-weight: bold; font-size: 1.5rem; color: var(--primary-color); }
    .nav-link { color: var(--text-color); text-decoration: none; padding: 5px 10px; border-radius: 5px; transition: background-color 0.2s; }
    .nav-link:hover { background-color: #333; }
    .nav-link.active { background-color: var(--primary-color); color: var(--on-primary-color); }
    .navbar-right { display: flex; align-items: center; gap: 15px; }
    .balance-display { background-color: #2a2a2a; padding: 8px 12px; border-radius: 5px; font-weight: 500;}
    .connect-button {
      background-color: var(--primary-color);
      color: var(--on-primary-color);
      border: none;
      padding: 10px 15px;
      border-radius: 5px;
      cursor: pointer;
      font-weight: bold;
    }
    /* Dashboard */
    .dashboard-container { max-width: 1200px; margin: 0 auto; text-align: left; }
    .dashboard-container h2 { border-bottom: 1px solid #444; padding-bottom: 10px; margin-top: 40px; }
    .stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 20px; }
    .stat-card { background-color: var(--surface-color); padding: 20px; border-radius: 8px; }
    .stat-card h3 { margin: 0 0 10px; font-size: 1rem; color: #aaa; }
    .stat-card p { margin: 0; font-size: 1.5rem; font-weight: bold; }
    /* NFT Grid */
    .nft-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; }
    .nft-card { background-color: var(--surface-color); border-radius: 8px; overflow: hidden; }
    .nft-card img { width: 100%; height: 200px; object-fit: cover; background-color: #333; }
    .nft-card h4 { margin: 10px; text-align: center; }
    /* Skeletons */
    @keyframes pulse { 0% { opacity: 0.6; } 50% { opacity: 1; } 100% { opacity: 0.6; } }
    .skeleton { animation: pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite; background-color: var(--skeleton-color); }
    .skeleton-text { height: 1em; margin-bottom: 0.5em; border-radius: 4px; background-color: #444; }
    .skeleton-title { width: 60%; }
    .skeleton-value { width: 40%; height: 1.5em; }
    .skeleton-image { width: 100%; height: 200px; background-color: #444; }
    .skeleton-nft-title { width: 80%; margin: 10px auto; }
  `}</style>
);

// 1. Get projectId at https://cloud.walletconnect.com
const projectId = 'YOUR_WALLETCONNECT_PROJECT_ID';

// 2. Set up chains
const sepolia = {
  chainId: 11155111,
  name: 'Sepolia',
  currency: 'ETH',
  explorerUrl: 'https://sepolia.etherscan.io',
  rpcUrl: 'https://rpc.sepolia.org'
};

// 3. Create modal
const metadata = {
  name: 'EvoStaking Platform',
  description: 'Stake your NFTs and earn rewards.',
  url: 'https://web3modal.com', // origin must match your domain & subdomain
  icons: ['https://avatars.githubusercontent.com/u/37784886']
};

createWeb3Modal({
  ethersConfig: defaultConfig({ metadata }),
  chains: [sepolia],
  projectId,
  enableAnalytics: true
});

// --- Placeholder ABIs and Contract Addresses ---
const EVO_TOKEN_ABI = ["function balanceOf(address owner) view returns (uint256)"];
const STAKING_CONTRACT_ABI = ["function getStakedTokens(address owner) view returns (uint256[])"];
const NFT_COLLECTION_ABI = ["function walletOfOwner(address owner) view returns (uint256[])", "function tokenURI(uint256 tokenId) view returns (string)"];

const EVO_TOKEN_ADDRESS = "0x0000000000000000000000000000000000000000";
const STAKING_CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000";
const NFT_COLLECTION_ADDRESS = "0x0000000000000000000000000000000000000000";

// --- Skeleton Components for Loading State ---
const StatCardSkeleton = () => (
  <div className="stat-card skeleton">
    <div className="skeleton-text skeleton-title"></div>
    <div className="skeleton-text skeleton-value"></div>
  </div>
);

const NftCardSkeleton = () => (
  <div className="nft-card skeleton">
    <div className="skeleton-image"></div>
    <div className="skeleton-text skeleton-nft-title"></div>
  </div>
);

// --- Dashboard Component ---
function Dashboard({ isLoading, dashboardData, nfts, isConnected }) {
  const statCards = [
    { title: 'Total Battles', value: dashboardData.totalBattles },
    { title: 'Win Rate', value: `${dashboardData.winRate}%` },
    { title: 'EVO Balance', value: dashboardData.evoBalance },
    { title: 'Staked NFTs', value: dashboardData.stakedTokens },
    { title: 'Active Rentals', value: dashboardData.activeRentals },
  ];

  if (!isConnected) {
    return <div style={{marginTop: '50px', fontSize: '1.2rem', textAlign: 'center' }}>Please connect your wallet to view the dashboard.</div>
  }

  return (
    <div className="dashboard-container">
      <h2>Dashboard</h2>
      <div className="stats-grid">
        {isLoading ? (
          Array(5).fill(0).map((_, index) => <StatCardSkeleton key={index} />)
        ) : (
          statCards.map(card => (
            <div key={card.title} className="stat-card">
              <h3>{card.title}</h3>
              <p>{card.value}</p>
            </div>
          ))
        )}
      </div>

      <h2>Your Collection</h2>
      <div className="nft-grid">
        {isLoading ? (
          Array(8).fill(0).map((_, index) => <NftCardSkeleton key={index} />)
        ) : (
          nfts.length > 0 ? nfts.map(nft => (
            <div key={nft.id} className="nft-card">
              <img src={nft.image} alt={nft.name} />
              <h4>{nft.name}</h4>
            </div>
          )) : <p>You don't own any NFTs from this collection yet.</p>
        )}
      </div>
    </div>
  );
}

// --- Navbar Component ---
function Navbar({ onConnect, address, isConnected, evoBalance }) {
  return (
    <nav className="navbar">
      <div className="navbar-left">
        <span className="navbar-logo">EVO</span>
        <NavLink to="/" className={({ isActive }) => isActive ? "nav-link active" : "nav-link"}>Dashboard</NavLink>
        <NavLink to="/arena" className={({ isActive }) => isActive ? "nav-link active" : "nav-link"}>Arena</NavLink>
        <NavLink to="/training" className={({ isActive }) => isActive ? "nav-link active" : "nav-link"}>Training</NavLink>
        <NavLink to="/evolution" className={({ isActive }) => isActive ? "nav-link active" : "nav-link"}>Evolution</NavLink>
        <NavLink to="/leaderboard" className={({ isActive }) => isActive ? "nav-link active" : "nav-link"}>Leaderboard</NavLink>
      </div>
      <div className="navbar-right">
        {isConnected && (
            <div className="balance-display">
                EVO: {evoBalance}
            </div>
        )}
        <button onClick={onConnect} className="connect-button">
          {isConnected ? `${address.substring(0, 6)}...${address.substring(address.length - 4)}` : 'Connect Wallet'}
        </button>
      </div>
    </nav>
  );
}

// --- Main App Component ---
function App() {
  const { open } = useWeb3Modal();
  const { address, isConnected } = useWeb3ModalAccount();
  const { walletProvider } = useWeb3ModalProvider();
  
  const [isLoading, setIsLoading] = useState(false);
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  
  const [evoTokenContract, setEvoTokenContract] = useState(null);
  const [stakingContract, setStakingContract] = useState(null);
  const [nftCollectionContract, setNftCollectionContract] = useState(null);

  const [dashboardData, setDashboardData] = useState({
    totalBattles: 0, winRate: 0, evoBalance: '0.00', stakedTokens: 0, activeRentals: 0,
  });
  const [userNfts, setUserNfts] = useState([]);

  useEffect(() => {
    if (walletProvider) {
      const ethersProvider = new ethers.BrowserProvider(walletProvider);
      setProvider(ethersProvider);
      ethersProvider.getSigner().then(setSigner);
    } else {
      setProvider(null);
      setSigner(null);
    }
  }, [walletProvider]);

  useEffect(() => {
    if (provider) {
      setEvoTokenContract(new ethers.Contract(EVO_TOKEN_ADDRESS, EVO_TOKEN_ABI, provider));
      setStakingContract(new ethers.Contract(STAKING_CONTRACT_ADDRESS, STAKING_CONTRACT_ABI, provider));
      setNftCollectionContract(new ethers.Contract(NFT_COLLECTION_ADDRESS, NFT_COLLECTION_ABI, provider));
    }
  }, [provider]);

  const loadBlockchainData = useCallback(async () => {
    if (!isConnected || !evoTokenContract || !stakingContract || !nftCollectionContract || !address) {
      setDashboardData({ totalBattles: 0, winRate: 0, evoBalance: '0.00', stakedTokens: 0, activeRentals: 0 });
      setUserNfts([]);
      return;
    }

    setIsLoading(true);
    try {
      const [rawEvoBalance, stakedTokenIds, ownedTokenIds] = await Promise.all([
        evoTokenContract.balanceOf(address),
        stakingContract.getStakedTokens(address),
        nftCollectionContract.walletOfOwner(address),
      ]);
      
      const formattedEvoBalance = ethers.formatUnits(rawEvoBalance, 18);

      const nftPromises = ownedTokenIds.map(async (tokenId) => {
          try {
              const tokenURI = await nftCollectionContract.tokenURI(tokenId);
              const metadataUrl = tokenURI.startsWith('ipfs://') ? `https://gateway.pinata.cloud/ipfs/${tokenURI.split('ipfs://')[1]}` : tokenURI;
              const metadataResponse = await fetch(metadataUrl);
              const metadata = await metadataResponse.json();
              const imageUrl = metadata.image.startsWith('ipfs://') ? `https://gateway.pinata.cloud/ipfs/${metadata.image.split('ipfs://')[1]}` : metadata.image;
              return {
                  id: tokenId.toString(),
                  name: metadata.name || `NFT #${tokenId.toString()}`,
                  image: imageUrl,
              };
          } catch (e) {
              console.error(`Failed to fetch metadata for token ${tokenId}`, e);
              return null;
          }
      });

      const resolvedNfts = (await Promise.all(nftPromises)).filter(nft => nft !== null);

      setDashboardData(prevData => ({
        ...prevData, // Keep placeholder data for now
        evoBalance: parseFloat(formattedEvoBalance).toFixed(2),
        stakedTokens: stakedTokenIds.length,
      }));
      setUserNfts(resolvedNfts);

    } catch (error) {
      console.error("Error loading blockchain data:", error);
    } finally {
      setIsLoading(false);
    }
  }, [isConnected, evoTokenContract, stakingContract, nftCollectionContract, address]);

  useEffect(() => {
    if (isConnected && evoTokenContract) {
      loadBlockchainData();
      const intervalId = setInterval(() => loadBlockchainData(), 30000);
      return () => clearInterval(intervalId);
    } else {
        setIsLoading(false);
        setUserNfts([]);
        setDashboardData({ totalBattles: 0, winRate: 0, evoBalance: '0.00', stakedTokens: 0, activeRentals: 0 });
    }
  }, [isConnected, evoTokenContract, loadBlockchainData]);
  
  return (
    <Router>
      <GlobalStyles />
      <div className="app">
        <Navbar 
          onConnect={() => open()}
          isConnected={isConnected}
          address={address}
          evoBalance={dashboardData.evoBalance}
        />
        <main className="main-content">
          <Routes>
            <Route path="/" element={
              <Dashboard 
                isLoading={isLoading}
                dashboardData={dashboardData}
                nfts={userNfts}
                isConnected={isConnected}
              />
            } />
            <Route path="/arena" element={<div style={{marginTop: '50px'}}>Arena Page Coming Soon...</div>} />
            <Route path="/training" element={<div style={{marginTop: '50px'}}>Training Page Coming Soon...</div>} />
            <Route path="/evolution" element={<div style={{marginTop: '50px'}}>Evolution Page Coming Soon...</div>} />
            <Route path="/leaderboard" element={<div style={{marginTop: '50px'}}>Leaderboard Page Coming Soon...</div>} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
