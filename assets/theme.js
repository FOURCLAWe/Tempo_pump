(function () {
  const STORAGE_KEY = "tempomeme-theme";
  const root = document.documentElement;

  function updateToggleButtons(theme) {
    document.querySelectorAll("[data-theme-toggle]").forEach((button) => {
      const icon = button.querySelector(".theme-toggle-icon");
      const label = button.querySelector(".theme-toggle-label");
      button.setAttribute("aria-pressed", "false");
      button.setAttribute("aria-label", "Dark mode only");
      if (icon) icon.textContent = "☾";
      if (label) label.textContent = "Dark Mode";
    });
  }

  function applyTheme() {
    root.dataset.theme = "dark";
    root.style.colorScheme = "dark";
    try {
      localStorage.setItem(STORAGE_KEY, "dark");
    } catch (e) {}
    updateToggleButtons("dark");
  }

  function initTheme() {
    applyTheme();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initTheme);
  } else {
    initTheme();
  }
})();
