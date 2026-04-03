(function () {
  const STORAGE_KEY = "tempomeme-wallet-connected-v2";
  const LEGACY_KEYS = ["tempomeme-wallet-connected"];
  const PROVIDER_KEY = "tempomeme-wallet-provider-v1";
  const DISCOVERY_TIMEOUT_MS = 2800;
  const chooserState = { active: false };
  const eip6963Providers = new Map();
  let discoveryStarted = false;

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function readSessionFlag() {
    try {
      LEGACY_KEYS.forEach((key) => localStorage.removeItem(key));
    } catch (e) {}
    try {
      return localStorage.getItem(STORAGE_KEY) === "1";
    } catch (e) {
      return false;
    }
  }

  function writeSessionFlag(connected) {
    try {
      if (connected) localStorage.setItem(STORAGE_KEY, "1");
      else localStorage.removeItem(STORAGE_KEY);
    } catch (e) {}
  }

  function readPreferredWalletId() {
    try {
      return localStorage.getItem(PROVIDER_KEY) || "";
    } catch (e) {
      return "";
    }
  }

  function writePreferredWalletId(walletId) {
    try {
      if (walletId) localStorage.setItem(PROVIDER_KEY, walletId);
    } catch (e) {}
  }

  function formatAddress(address) {
    if (!address) return "";
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  }

  function normalizeError(error) {
    return (
      error?.reason ||
      error?.shortMessage ||
      error?.message ||
      "Unknown wallet error."
    );
  }

  function startDiscovery() {
    if (discoveryStarted) return;
    discoveryStarted = true;

    window.addEventListener("eip6963:announceProvider", (event) => {
      const detail = event?.detail;
      const info = detail?.info;
      const provider = detail?.provider;
      if (!provider) return;
      const key = info?.uuid || info?.rdns || info?.name || `provider-${eip6963Providers.size + 1}`;
      eip6963Providers.set(key, { info, provider });
    });

    try {
      window.dispatchEvent(new Event("eip6963:requestProvider"));
    } catch (e) {}
  }

  function getWalletMeta(provider, info = {}) {
    const rdns = (info.rdns || "").toLowerCase();
    const name = info.name || "";

    if (provider?.isRabby || rdns.includes("rabby")) {
      return { id: "rabby", name: "Rabby", icon: info.icon || "" };
    }
    if (provider?.isOkxWallet || provider?.isOKExWallet || rdns.includes("okx")) {
      return { id: "okx", name: "OKX Wallet", icon: info.icon || "" };
    }
    if (provider?.isCoinbaseWallet || rdns.includes("coinbase")) {
      return { id: "coinbase", name: "Coinbase Wallet", icon: info.icon || "" };
    }
    if (provider?.isBitKeep || provider?.isBitgetWallet || rdns.includes("bitget")) {
      return { id: "bitget", name: "Bitget Wallet", icon: info.icon || "" };
    }
    if (provider?.isTokenPocket || rdns.includes("tokenpocket")) {
      return { id: "tokenpocket", name: "TokenPocket", icon: info.icon || "" };
    }
    if (provider?.isImToken || rdns.includes("imtoken")) {
      return { id: "imtoken", name: "imToken", icon: info.icon || "" };
    }
    if (provider?.isTrust || provider?.isTrustWallet || rdns.includes("trust")) {
      return { id: "trust", name: "Trust Wallet", icon: info.icon || "" };
    }
    if (provider?.isBraveWallet || rdns.includes("brave")) {
      return { id: "brave", name: "Brave Wallet", icon: info.icon || "" };
    }
    if (provider?.isPhantom || rdns.includes("phantom")) {
      return { id: "phantom", name: "Phantom", icon: info.icon || "" };
    }
    if (provider?.isMetaMask || rdns.includes("metamask")) {
      return { id: "metamask", name: "MetaMask", icon: info.icon || "" };
    }
    return {
      id: rdns || name.toLowerCase().replace(/\s+/g, "-") || "injected",
      name: name || "Browser Wallet",
      icon: info.icon || ""
    };
  }

  function sortWallets(wallets) {
    const preferredOrder = {
      rabby: 1,
      metamask: 2,
      okx: 3,
      coinbase: 4,
      bitget: 5,
      trust: 6,
      tokenpocket: 7,
      imtoken: 8,
      brave: 9,
      phantom: 10,
      injected: 99
    };

    return [...wallets].sort((a, b) => {
      const orderA = preferredOrder[a.id] || 50;
      const orderB = preferredOrder[b.id] || 50;
      if (orderA !== orderB) return orderA - orderB;
      return a.name.localeCompare(b.name);
    });
  }

  function collectWallets() {
    const wallets = [];
    const seenProviders = new Set();

    function pushWallet(provider, info) {
      if (!provider || seenProviders.has(provider)) return;
      seenProviders.add(provider);
      const meta = getWalletMeta(provider, info);
      wallets.push({ ...meta, provider });
    }

    eip6963Providers.forEach(({ info, provider }) => pushWallet(provider, info));

    const injectedProviders = [];
    if (Array.isArray(window.ethereum?.providers)) {
      injectedProviders.push(...window.ethereum.providers);
    } else if (window.ethereum) {
      injectedProviders.push(window.ethereum);
    }

    injectedProviders.forEach((provider) => pushWallet(provider, {}));

    return sortWallets(wallets);
  }

  async function discoverWallets(timeoutMs = DISCOVERY_TIMEOUT_MS) {
    startDiscovery();

    let wallets = collectWallets();
    if (wallets.length) {
      const settleUntil = Date.now() + 220;
      while (Date.now() < settleUntil) {
        await sleep(60);
        wallets = collectWallets();
      }
      return wallets;
    }

    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      await sleep(120);
      wallets = collectWallets();
      if (wallets.length) return wallets;
    }

    return wallets;
  }

  async function waitForProvider(timeoutMs = DISCOVERY_TIMEOUT_MS) {
    const wallets = await discoverWallets(timeoutMs);
    return wallets[0]?.provider || null;
  }

  function ensureChooserStyles() {
    if (document.getElementById("tempomeme-wallet-chooser-style")) return;
    const style = document.createElement("style");
    style.id = "tempomeme-wallet-chooser-style";
    style.textContent = `
      .tm-wallet-overlay {
        position: fixed;
        inset: 0;
        z-index: 9999;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
        background: rgba(0,0,0,0.56);
        backdrop-filter: blur(10px);
      }
      .tm-wallet-modal {
        width: min(420px, 100%);
        border-radius: 22px;
        overflow: hidden;
        background: linear-gradient(180deg, rgba(24,26,24,0.98), rgba(12,13,12,0.98));
        border: 1px solid rgba(255,255,255,0.09);
        box-shadow: 0 28px 80px rgba(0,0,0,0.42);
      }
      .tm-wallet-head {
        padding: 18px 20px 12px;
        border-bottom: 1px solid rgba(255,255,255,0.06);
      }
      .tm-wallet-title {
        margin: 0;
        color: #f4f3ee;
        font: 800 22px/1.1 "Space Grotesk", "Manrope", sans-serif;
      }
      .tm-wallet-copy {
        margin: 10px 0 0;
        color: #9aa194;
        font: 500 14px/1.6 "Manrope", sans-serif;
      }
      .tm-wallet-list {
        display: grid;
        gap: 10px;
        padding: 16px 20px 20px;
      }
      .tm-wallet-option {
        width: 100%;
        min-height: 58px;
        padding: 0 16px;
        display: flex;
        align-items: center;
        gap: 12px;
        border-radius: 16px;
        border: 1px solid rgba(255,255,255,0.08);
        background: linear-gradient(180deg, rgba(31,34,31,0.96), rgba(18,19,18,0.98));
        color: #f4f3ee;
        cursor: pointer;
        transition: transform 160ms ease, border-color 160ms ease, box-shadow 160ms ease;
      }
      .tm-wallet-option:hover {
        transform: translateY(-2px);
        border-color: rgba(232,191,82,0.24);
        box-shadow: 0 16px 28px rgba(0,0,0,0.24);
      }
      .tm-wallet-badge {
        width: 36px;
        height: 36px;
        border-radius: 12px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        flex: 0 0 36px;
        overflow: hidden;
        background: rgba(232,191,82,0.12);
        border: 1px solid rgba(232,191,82,0.2);
        color: #e8bf52;
        font: 800 14px/1 "Manrope", sans-serif;
      }
      .tm-wallet-badge img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .tm-wallet-name {
        font: 800 15px/1.1 "Manrope", sans-serif;
      }
      .tm-wallet-meta {
        margin-top: 3px;
        color: #9aa194;
        font: 500 12px/1.4 "Manrope", sans-serif;
      }
      .tm-wallet-foot {
        padding: 0 20px 18px;
      }
      .tm-wallet-cancel {
        width: 100%;
        min-height: 46px;
        border-radius: 14px;
        border: 1px solid rgba(255,255,255,0.08);
        background: rgba(255,255,255,0.03);
        color: #d8ddd3;
        cursor: pointer;
        font: 700 14px/1 "Manrope", sans-serif;
      }
    `;
    document.head.appendChild(style);
  }

  function walletBadgeMarkup(wallet) {
    const icon = wallet.icon || "";
    if (icon && /^(data:image|https?:)/i.test(icon)) {
      return `<span class="tm-wallet-badge"><img src="${icon}" alt="${wallet.name}"></span>`;
    }
    return `<span class="tm-wallet-badge">${(wallet.name || "W").slice(0, 1).toUpperCase()}</span>`;
  }

  async function chooseWallet(wallets) {
    if (!wallets.length) return null;
    if (wallets.length === 1) return wallets[0];
    if (chooserState.active) return null;

    chooserState.active = true;
    ensureChooserStyles();

    return await new Promise((resolve) => {
      const overlay = document.createElement("div");
      overlay.className = "tm-wallet-overlay";
      overlay.innerHTML = `
        <div class="tm-wallet-modal" role="dialog" aria-modal="true" aria-label="Choose wallet">
          <div class="tm-wallet-head">
            <h3 class="tm-wallet-title">Choose a wallet</h3>
            <p class="tm-wallet-copy">Select one of the detected EVM wallets to connect to TempoBoard.</p>
          </div>
          <div class="tm-wallet-list">
            ${wallets.map((wallet) => `
              <button type="button" class="tm-wallet-option" data-wallet-id="${wallet.id}">
                ${walletBadgeMarkup(wallet)}
                <span>
                  <div class="tm-wallet-name">${wallet.name}</div>
                  <div class="tm-wallet-meta">Injected browser wallet</div>
                </span>
              </button>
            `).join("")}
          </div>
          <div class="tm-wallet-foot">
            <button type="button" class="tm-wallet-cancel">Cancel</button>
          </div>
        </div>
      `;

      function cleanup(selected) {
        chooserState.active = false;
        overlay.remove();
        resolve(selected || null);
      }

      overlay.addEventListener("click", (event) => {
        if (event.target === overlay) cleanup(null);
      });

      overlay.querySelector(".tm-wallet-cancel").addEventListener("click", () => cleanup(null));
      overlay.querySelectorAll(".tm-wallet-option").forEach((button) => {
        button.addEventListener("click", () => {
          const selectedId = button.getAttribute("data-wallet-id");
          cleanup(wallets.find((wallet) => wallet.id === selectedId) || null);
        });
      });

      document.body.appendChild(overlay);
    });
  }

  async function resolveWalletForConnect(wallets, requestAccess, walletId) {
    const preferredId = walletId || readPreferredWalletId();
    if (preferredId) {
      const preferred = wallets.find((wallet) => wallet.id === preferredId);
      if (preferred) return preferred;
    }

    if (wallets.length === 1) return wallets[0];

    if (!requestAccess) {
      for (const wallet of wallets) {
        try {
          const accounts = await wallet.provider.request({ method: "eth_accounts" });
          if (accounts && accounts.length) return wallet;
        } catch (e) {}
      }
      return null;
    }

    return null;
  }

  async function ensureChain(ethereum, chain) {
    const currentChainId = await ethereum.request({ method: "eth_chainId" });
    if (currentChainId === chain.chainId) return true;

    try {
      await ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: chain.chainId }]
      });
    } catch (switchErr) {
      if (switchErr?.code === 4902) {
        await ethereum.request({
          method: "wallet_addEthereumChain",
          params: [chain]
        });
      } else {
        throw switchErr;
      }
    }

    const nextChainId = await ethereum.request({ method: "eth_chainId" });
    return nextChainId === chain.chainId;
  }

  function createSession(config) {
    const state = {
      provider: null,
      signer: null,
      address: null,
      walletId: "",
      walletName: "",
      injectedProvider: null,
      boundProvider: null,
      boundHandlers: null
    };

    const onConnect = config.onConnect || (async () => {});
    const onDisconnect = config.onDisconnect || (() => {});
    const onError = config.onError || (() => {});
    const onWrongChain = config.onWrongChain || (() => {});

    function reset(options = {}) {
      const { forget = false, reason = "reset" } = options;
      state.provider = null;
      state.signer = null;
      state.address = null;
      state.injectedProvider = null;
      if (forget) writeSessionFlag(false);
      onDisconnect({ reason });
    }

    function unbindListeners() {
      const ethereum = state.boundProvider;
      const handlers = state.boundHandlers;
      if (!ethereum || !handlers) return;
      ethereum.removeListener?.("accountsChanged", handlers.accountsChanged);
      ethereum.removeListener?.("chainChanged", handlers.chainChanged);
      state.boundProvider = null;
      state.boundHandlers = null;
    }

    function bindListeners(wallet) {
      const ethereum = wallet?.provider;
      if (!ethereum) return;
      if (state.boundProvider === ethereum) return;

      unbindListeners();

      const handlers = {
        accountsChanged: async (accounts) => {
          if (accounts && accounts.length) {
            await api.connect(false, {
              silent: true,
              reason: "accountsChanged",
              walletId: state.walletId
            });
          } else {
            reset({ forget: true, reason: "accountsChanged" });
          }
        },
        chainChanged: async (chainId) => {
          if (chainId === config.chain.chainId) {
            await api.connect(false, {
              silent: true,
              reason: "chainChanged",
              walletId: state.walletId
            });
          } else {
            reset({ forget: false, reason: "wrongChain" });
            onWrongChain({ chainId });
          }
        }
      };

      ethereum.on?.("accountsChanged", handlers.accountsChanged);
      ethereum.on?.("chainChanged", handlers.chainChanged);
      state.boundProvider = ethereum;
      state.boundHandlers = handlers;
    }

    const api = {
      async init() {
        await discoverWallets();
        if (readSessionFlag()) {
          await api.connect(false, { silent: true, reason: "init" });
        }
      },

      async connect(requestAccess = true, options = {}) {
        const { silent = false, reason = requestAccess ? "manual" : "auto", walletId = "" } = options;
        const wallets = await discoverWallets();

        if (!wallets.length) {
          reset({ forget: !readSessionFlag(), reason: "missingProvider" });
          if (!silent) onError("No supported EVM wallet detected.");
          return false;
        }

        let wallet = await resolveWalletForConnect(wallets, requestAccess, walletId);
        if (!wallet && requestAccess) {
          wallet = await chooseWallet(wallets);
        }

        if (!wallet) {
          if (!requestAccess) reset({ forget: true, reason: "noAccounts" });
          return false;
        }

        bindListeners(wallet);

        try {
          const accounts = await wallet.provider.request({
            method: requestAccess ? "eth_requestAccounts" : "eth_accounts"
          });

          if (!accounts || !accounts.length) {
            if (!requestAccess) {
              reset({ forget: true, reason: "noAccounts" });
            }
            return false;
          }

          await ensureChain(wallet.provider, config.chain);

          state.injectedProvider = wallet.provider;
          state.walletId = wallet.id;
          state.walletName = wallet.name;
          state.provider = new ethers.BrowserProvider(wallet.provider);
          state.signer = await state.provider.getSigner();
          state.address = await state.signer.getAddress();
          writeSessionFlag(true);
          writePreferredWalletId(wallet.id);

          await onConnect({
            address: state.address,
            provider: state.provider,
            signer: state.signer,
            requestAccess,
            reason,
            walletId: wallet.id,
            walletName: wallet.name
          });

          return true;
        } catch (error) {
          if (error?.code === 4001) {
            if (!silent) onError("Wallet connection was canceled.", error);
            return false;
          }

          if (!silent) onError(normalizeError(error), error);
          return false;
        }
      },

      reset,

      get address() {
        return state.address;
      },

      get provider() {
        return state.provider;
      },

      get signer() {
        return state.signer;
      },

      get walletId() {
        return state.walletId;
      },

      get walletName() {
        return state.walletName;
      }
    };

    return api;
  }

  window.TempomemeWallet = {
    createSession,
    discoverWallets,
    formatAddress,
    waitForProvider,
    normalizeError
  };
})();
