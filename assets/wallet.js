(function () {
  const STORAGE_KEY = "tempomeme-wallet-connected-v2";
  const LEGACY_KEYS = ["tempomeme-wallet-connected"];

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

  async function waitForProvider(timeoutMs = 3200) {
    if (window.ethereum) return window.ethereum;

    return await new Promise((resolve) => {
      let settled = false;

      const finish = (value) => {
        if (settled) return;
        settled = true;
        clearInterval(pollId);
        clearTimeout(timeoutId);
        window.removeEventListener("ethereum#initialized", onInitialized);
        resolve(value || null);
      };

      const onInitialized = () => finish(window.ethereum || null);
      window.addEventListener("ethereum#initialized", onInitialized);

      const pollId = setInterval(() => {
        if (window.ethereum) finish(window.ethereum);
      }, 200);

      const timeoutId = setTimeout(() => finish(window.ethereum || null), timeoutMs);
    });
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
      listenersBound: false
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
      if (forget) writeSessionFlag(false);
      onDisconnect({ reason });
    }

    function bindListeners(ethereum) {
      if (!ethereum || state.listenersBound) return;
      state.listenersBound = true;

      ethereum.on?.("accountsChanged", async (accounts) => {
        if (accounts && accounts.length) {
          await api.connect(false, { silent: true, reason: "accountsChanged" });
        } else {
          reset({ forget: true, reason: "accountsChanged" });
        }
      });

      ethereum.on?.("chainChanged", async (chainId) => {
        if (chainId === config.chain.chainId) {
          await api.connect(false, { silent: true, reason: "chainChanged" });
        } else {
          reset({ forget: false, reason: "wrongChain" });
          onWrongChain({ chainId });
        }
      });
    }

    const api = {
      async init() {
        const ethereum = await waitForProvider();
        if (ethereum) bindListeners(ethereum);
        if (readSessionFlag()) {
          await api.connect(false, { silent: true, reason: "init" });
        }
      },

      async connect(requestAccess = true, options = {}) {
        const { silent = false, reason = requestAccess ? "manual" : "auto" } = options;
        const ethereum = await waitForProvider();

        if (!ethereum) {
          reset({ forget: !readSessionFlag(), reason: "missingProvider" });
          if (!silent) onError("No EVM wallet detected.");
          return false;
        }

        bindListeners(ethereum);

        try {
          const accounts = await ethereum.request({
            method: requestAccess ? "eth_requestAccounts" : "eth_accounts"
          });

          if (!accounts || !accounts.length) {
            if (!requestAccess) {
              reset({ forget: true, reason: "noAccounts" });
            }
            return false;
          }

          await ensureChain(ethereum, config.chain);

          state.provider = new ethers.BrowserProvider(ethereum);
          state.signer = await state.provider.getSigner();
          state.address = await state.signer.getAddress();
          writeSessionFlag(true);

          await onConnect({
            address: state.address,
            provider: state.provider,
            signer: state.signer,
            requestAccess,
            reason
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
      }
    };

    return api;
  }

  window.TempomemeWallet = {
    createSession,
    formatAddress,
    waitForProvider,
    normalizeError
  };
})();
