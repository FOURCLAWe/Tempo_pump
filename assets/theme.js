(function () {
  const STORAGE_KEY = "tempomeme-theme";
  const root = document.documentElement;

  function getSavedTheme() {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved === "light" || saved === "dark") return saved;
    } catch (e) {}
    return "dark";
  }

  function getNextTheme(theme) {
    return theme === "light" ? "dark" : "light";
  }

  function updateToggleButtons(theme) {
    const nextTheme = getNextTheme(theme);
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      const icon = button.querySelector(".theme-toggle-icon");
      const label = button.querySelector(".theme-toggle-label");
      button.setAttribute("aria-pressed", theme === "light" ? "true" : "false");
      button.setAttribute("aria-label", `Switch to ${nextTheme} mode`);
      if (icon) icon.textContent = nextTheme === "light" ? "☀" : "☾";
      if (label) label.textContent = nextTheme === "light" ? "Light Mode" : "Dark Mode";
    });
  }

  function applyTheme(theme) {
    root.dataset.theme = theme;
    root.style.colorScheme = theme;
    try {
      localStorage.setItem(STORAGE_KEY, theme);
    } catch (e) {}
    updateToggleButtons(theme);
  }

  function bindToggles() {
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      if (button.dataset.themeBound === "true") return;
      button.dataset.themeBound = "true";
      button.addEventListener("click", () => {
        applyTheme(getNextTheme(root.dataset.theme || getSavedTheme()));
      });
    });
  }

  function initTheme() {
    applyTheme(root.dataset.theme || getSavedTheme());
    bindToggles();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initTheme);
  } else {
    initTheme();
  }
})();
