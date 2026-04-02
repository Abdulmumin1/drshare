const state = {
  token: "",
  session: null,
};

const elements = {
  connectionIndicator: document.querySelector("#connection-indicator"),
  hostSummary: document.querySelector("#host-summary"),
  pairingSection: document.querySelector("#pairing-section"),
  tokenForm: document.querySelector("#token-form"),
  tokenInput: document.querySelector("#token-input"),
  textForm: document.querySelector("#text-form"),
  textInput: document.querySelector("#text-input"),
  fileForm: document.querySelector("#file-form"),
  fileInput: document.querySelector("#file-input"),
  fileHint: document.querySelector("#file-hint"),
  refreshButton: document.querySelector("#refresh-button"),
  feedback: document.querySelector("#feedback"),
  dropsList: document.querySelector("#drops-list"),
  emptyState: document.querySelector("#empty-state"),
  tabBtns: document.querySelectorAll(".tab-btn"),
  viewPanels: document.querySelectorAll(".view-panel"),
};

boot();

async function boot() {
  hydrateToken();
  bindEvents();
  registerServiceWorker();
  await loadSession();
  await loadDrops();
}

function registerServiceWorker() {
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('/sw.js').catch((error) => {
        console.error('ServiceWorker registration failed: ', error);
      });
    });
  }
}

function hydrateToken() {
  const params = new URLSearchParams(window.location.search);
  const queryToken = params.get("token");
  const savedToken = window.localStorage.getItem("drshare-token");
  state.token = queryToken || savedToken || "";
  elements.tokenInput.value = state.token;
}

function switchTab(targetId) {
  elements.tabBtns.forEach(btn => btn.classList.remove("active"));
  elements.viewPanels.forEach(panel => panel.classList.remove("active"));
  
  const targetBtn = Array.from(elements.tabBtns).find(btn => btn.dataset.target === targetId);
  if (targetBtn) targetBtn.classList.add("active");
  
  const targetPanel = document.getElementById(targetId);
  if (targetPanel) targetPanel.classList.add("active");
}

function bindEvents() {
  elements.tabBtns.forEach(btn => {
    btn.addEventListener("click", () => {
      switchTab(btn.dataset.target);
    });
  });

  elements.tokenForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    state.token = elements.tokenInput.value.trim();
    window.localStorage.setItem("drshare-token", state.token);
    await loadSession();
    await loadDrops();
  });

  elements.textForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const text = elements.textInput.value.trim();

    if (!text) {
      setFeedback("Text is empty.");
      return;
    }

    try {
      await api("/api/drops/text", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ text }),
      });

      elements.textInput.value = "";
      setFeedback("");
      await loadDrops();
      switchTab("view-drops");
    } catch (error) {
      setFeedback(error.message);
    }
  });

  elements.fileInput.addEventListener("change", () => {
    const file = elements.fileInput.files?.[0];
    const display = document.getElementById("file-name-display");
    if (display) {
      display.textContent = file ? file.name : "Click to select or drop a file";
    }
  });

  elements.fileForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const file = elements.fileInput.files?.[0];

    if (!file) {
      setFeedback("Choose a file first.");
      return;
    }

    try {
      await api("/api/drops/file", {
        method: "POST",
        headers: {
          "Content-Type": file.type || "application/octet-stream",
          "X-DrShare-Filename": encodeURIComponent(file.name),
        },
        body: file,
      }, false);

      elements.fileInput.value = "";
      setFeedback("");
      await loadDrops();
      switchTab("view-drops");
    } catch (error) {
      setFeedback(error.message);
    }
  });

  elements.refreshButton.addEventListener("click", async () => {
    await loadSession();
    await loadDrops();
  });
}

async function loadSession() {
  try {
    state.session = await api("/api/session");
    elements.connectionIndicator.classList.add("connected");
    elements.pairingSection.hidden = true;
    const primaryUrl = state.session.urls[0] || window.location.origin;
    const shortUrl = primaryUrl.replace(/^https?:\/\//, '');
    const retentionText = typeof state.session.retention_seconds === "number"
      ? ` · clears after ${formatDuration(state.session.retention_seconds)}`
      : "";
    elements.hostSummary.textContent = `${shortUrl} · token ${state.session.token_hint}${retentionText}`;
    if (typeof state.session.max_upload_bytes === "number") {
      const retentionHint = typeof state.session.retention_seconds === "number"
        ? ` · auto clears after ${formatDuration(state.session.retention_seconds)}`
        : "";
      elements.fileHint.textContent = `Max size: ${formatBytes(state.session.max_upload_bytes)}${retentionHint}`;
    }
    setFeedback("");
  } catch (error) {
    elements.connectionIndicator.classList.remove("connected");
    elements.pairingSection.hidden = false;
    elements.hostSummary.textContent = "Not connected";
    elements.fileHint.textContent = "Max size: Unknown";
  }
}

async function loadDrops() {
  try {
    const response = await api("/api/drops");
    renderDrops(response.drops || []);
  } catch (error) {
    renderDrops([]);
    if (state.token) {
      setFeedback(error.message);
    }
  }
}

function renderDrops(drops) {
  elements.dropsList.innerHTML = "";
  elements.emptyState.hidden = drops.length > 0;

  for (const drop of drops) {
    const item = document.createElement("li");
    item.className = "drop";

    const createdAt = drop.created_at || drop.createdAt;
    const createdLabel = createdAt
      ? new Date(createdAt).toLocaleString()
      : "just now";

    item.innerHTML = `
      <div class="drop-header">
        <strong>${escapeHtml(labelFor(drop))}</strong>
        <span class="meta">${escapeHtml(createdLabel)}</span>
      </div>
    `;

    if ((drop.kind || "text") === "file") {
      const meta = document.createElement("p");
      meta.className = "meta";
      meta.textContent = `${drop.filename || "Untitled file"} · ${drop.mime || "application/octet-stream"} · ${formatBytes(drop.size || 0)}`;
      item.append(meta);

      const actions = document.createElement("div");
      actions.className = "drop-actions";

      if (drop.download_path || drop.downloadPath) {
        const downloadLink = document.createElement("a");
        downloadLink.className = "drop-link";
        downloadLink.textContent = "Download";
        downloadLink.href = withToken(drop.download_path || drop.downloadPath);
        downloadLink.download = drop.filename || "";
        actions.append(downloadLink);
      }

      item.append(actions);
    } else {
      const text = document.createElement("pre");
      text.textContent = drop.text || "";
      item.append(text);
    }

    elements.dropsList.append(item);
  }
}

async function api(path, options = {}, expectJson = true) {
  const headers = new Headers(options.headers || {});

  if (state.token) {
    headers.set("X-DrShare-Token", state.token);
  }

  const response = await fetch(path, {
    ...options,
    headers,
  });

  if (!response.ok) {
    let message = `Request failed with ${response.status}`;

    try {
      const payload = await response.json();
      message = payload.error || message;
    } catch (_) {
      // Leave the generic error when the response is not JSON.
    }

    throw new Error(message);
  }

  if (!expectJson) {
    return response;
  }

  return response.json();
}

function setFeedback(message) {
  elements.feedback.textContent = message;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function labelFor(drop) {
  const sender = drop.sender || "web";
  const kind = drop.kind || "text";
  return `${sender} ${kind}`;
}

function withToken(path) {
  const url = new URL(path, window.location.origin);

  if (state.token) {
    url.searchParams.set("token", state.token);
  }

  return url.toString();
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return "0 B";
  }

  const units = ["B", "KB", "MB", "GB"];
  let value = bytes;
  let index = 0;

  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }

  const digits = value >= 10 || index === 0 ? 0 : 1;
  return `${value.toFixed(digits)} ${units[index]}`;
}

function formatDuration(seconds) {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return "never";
  }

  if (seconds < 60) {
    return `${Math.floor(seconds)}s`;
  }

  if (seconds < 3600) {
    return `${Math.floor(seconds / 60)}m`;
  }

  if (seconds < 86400) {
    const hours = seconds / 3600;
    return Number.isInteger(hours) ? `${hours}h` : `${hours.toFixed(1)}h`;
  }

  const days = seconds / 86400;
  return Number.isInteger(days) ? `${days}d` : `${days.toFixed(1)}d`;
}
