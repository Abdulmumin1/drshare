const state = {
  token: "",
  session: null,
  transferResetTimer: null,
};

const elements = {
  connectionIndicator: document.querySelector("#connection-indicator"),
  showInfoBtn: document.querySelector("#show-info-btn"),
  infoModal: document.querySelector("#info-modal"),
  closeInfoBtn: document.querySelector("#close-info-btn"),
  modalUrl: document.querySelector("#modal-url"),
  modalToken: document.querySelector("#modal-token"),
  modalRetention: document.querySelector("#modal-retention"),
  pairingSection: document.querySelector("#pairing-section"),
  tokenForm: document.querySelector("#token-form"),
  tokenInput: document.querySelector("#token-input"),
  textForm: document.querySelector("#text-form"),
  textInput: document.querySelector("#text-input"),
  fileForm: document.querySelector("#file-form"),
  fileInput: document.querySelector("#file-input"),
  fileSubmitButton: document.querySelector("#file-submit-button"),
  fileHint: document.querySelector("#file-hint"),
  transferPanel: document.querySelector("#transfer-panel"),
  transferTitle: document.querySelector("#transfer-title"),
  transferPercent: document.querySelector("#transfer-percent"),
  transferBarFill: document.querySelector("#transfer-bar-fill"),
  transferMeta: document.querySelector("#transfer-meta"),
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
      setFileUploadBusy(true);
      showTransfer({
        title: `uploading ${file.name}`,
        loaded: 0,
        total: file.size,
        detail: `starting upload · ${formatBytes(file.size)}`,
      });

      await requestWithProgress("/api/drops/file", {
        method: "POST",
        headers: {
          "Content-Type": file.type || "application/octet-stream",
          "X-DrShare-Filename": encodeURIComponent(file.name),
        },
        body: file,
        expectJson: true,
        onUploadProgress: (loaded, total) => {
          const effectiveTotal = total || file.size;
          showTransfer({
            title: `uploading ${file.name}`,
            loaded,
            total: effectiveTotal,
            detail: `uploaded ${formatBytes(loaded)} / ${formatBytes(effectiveTotal)}`,
          });
        },
      });

      elements.fileInput.value = "";
      const display = document.getElementById("file-name-display");
      if (display) {
        display.textContent = "Click to select or drop a file";
      }
      setFeedback("");
      showTransfer({
        title: `uploaded ${file.name}`,
        loaded: file.size,
        total: file.size,
        detail: `done · ${formatBytes(file.size)}`,
      });
      scheduleTransferReset();
      await loadDrops();
      switchTab("view-drops");
    } catch (error) {
      setFeedback(error.message);
      showTransfer({
        title: `upload failed`,
        loaded: 0,
        total: file.size,
        detail: error.message,
        isError: true,
      });
    } finally {
      setFileUploadBusy(false);
    }
  });

  elements.refreshButton.addEventListener("click", async () => {
    await loadSession();
    await loadDrops();
  });

  elements.showInfoBtn.addEventListener("click", () => {
    elements.infoModal.hidden = false;
  });

  elements.closeInfoBtn.addEventListener("click", () => {
    elements.infoModal.hidden = true;
  });

  elements.infoModal.addEventListener("click", (event) => {
    if (event.target === elements.infoModal) {
      elements.infoModal.hidden = true;
    }
  });
}

async function loadSession() {
  try {
    state.session = await api("/api/session");
    elements.connectionIndicator.classList.add("connected");
    elements.showInfoBtn.hidden = false;
    elements.pairingSection.hidden = true;
    const primaryUrl = state.session.urls[0] || window.location.origin;
    elements.modalUrl.textContent = primaryUrl;
    elements.modalToken.textContent = state.session.token_hint;
    elements.modalRetention.textContent = typeof state.session.retention_seconds === "number"
      ? `auto clears after ${formatDuration(state.session.retention_seconds)}`
      : "never";

    if (typeof state.session.max_upload_bytes === "number") {
      const retentionHint = typeof state.session.retention_seconds === "number"
        ? ` · auto clears after ${formatDuration(state.session.retention_seconds)}`
        : "";
      elements.fileHint.textContent = `max size: ${formatBytes(state.session.max_upload_bytes)}${retentionHint}`;
    }
    setFeedback("");
  } catch (error) {
    elements.connectionIndicator.classList.remove("connected");
    elements.pairingSection.hidden = false;
    elements.showInfoBtn.hidden = true;
    elements.modalUrl.textContent = "";
    elements.modalToken.textContent = "";
    elements.modalRetention.textContent = "";
    elements.fileHint.textContent = "max size: unknown";
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
        const downloadButton = document.createElement("button");
        downloadButton.className = "drop-link";
        downloadButton.type = "button";
        downloadButton.textContent = "Download";
        downloadButton.addEventListener("click", () => {
          void downloadDrop(drop);
        });
        actions.append(downloadButton);
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

async function downloadDrop(drop) {
  const filename = drop.filename || "download";
  const path = drop.download_path || drop.downloadPath;
  const expectedSize = Number(drop.size) || 0;

  try {
    let completedBytes = expectedSize;

    showTransfer({
      title: `downloading ${filename}`,
      loaded: 0,
      total: expectedSize,
      detail: `starting download${expectedSize > 0 ? ` · ${formatBytes(expectedSize)}` : ""}`,
    });

    if ("showSaveFilePicker" in window) {
      completedBytes = await streamDownloadToFile(path, filename, expectedSize);
    } else {
      const blob = await requestWithProgress(path, {
        method: "GET",
        expectJson: false,
        responseType: "blob",
        onDownloadProgress: (loaded, total) => {
          const effectiveTotal = total || expectedSize || loaded;
          showTransfer({
            title: `downloading ${filename}`,
            loaded,
            total: effectiveTotal,
            detail: `downloaded ${formatBytes(loaded)} / ${formatBytes(effectiveTotal)}`,
          });
        },
      });

      triggerDownload(blob, filename);
      completedBytes = expectedSize || blob.size;
    }

    showTransfer({
      title: `downloaded ${filename}`,
      loaded: completedBytes,
      total: completedBytes,
      detail: `done · ${formatBytes(completedBytes)}`,
    });
    scheduleTransferReset();
    setFeedback("");
  } catch (error) {
    setFeedback(error.message);
    showTransfer({
      title: "download failed",
      loaded: 0,
      total: expectedSize,
      detail: error.message,
      isError: true,
    });
  }
}

function setFeedback(message) {
  elements.feedback.textContent = message;
}

function setFileUploadBusy(isBusy) {
  elements.fileInput.disabled = isBusy;
  elements.fileSubmitButton.disabled = isBusy;
  elements.fileSubmitButton.textContent = isBusy ? "Uploading…" : "Upload";
}

function showTransfer({ title, loaded, total, detail, isError = false }) {
  if (state.transferResetTimer) {
    window.clearTimeout(state.transferResetTimer);
    state.transferResetTimer = null;
  }

  const safeTotal = Number.isFinite(total) && total > 0 ? total : Math.max(loaded, 0);
  const progress = safeTotal > 0 ? Math.min(Math.max(loaded / safeTotal, 0), 1) : 0;

  elements.transferPanel.hidden = false;
  elements.transferTitle.textContent = title;
  elements.transferPercent.textContent = isError ? "error" : `${Math.round(progress * 100)}%`;
  elements.transferMeta.textContent = detail;
  elements.transferMeta.style.color = isError ? "var(--error)" : "";
  elements.transferPercent.style.color = isError ? "var(--error)" : "";
  elements.transferBarFill.style.width = `${progress * 100}%`;
  elements.transferBarFill.style.background = isError ? "var(--error)" : "var(--ink)";
}

function scheduleTransferReset() {
  if (state.transferResetTimer) {
    window.clearTimeout(state.transferResetTimer);
  }

  state.transferResetTimer = window.setTimeout(() => {
    elements.transferPanel.hidden = true;
    elements.transferBarFill.style.width = "0%";
    elements.transferMeta.style.color = "";
    elements.transferPercent.style.color = "";
    state.transferResetTimer = null;
  }, 1400);
}

function triggerDownload(blob, filename) {
  const objectURL = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = objectURL;
  anchor.download = filename;
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(objectURL), 1000);
}

async function streamDownloadToFile(path, filename, expectedSize) {
  const fileHandle = await window.showSaveFilePicker({
    suggestedName: filename,
  });

  const response = await fetch(withToken(path), {
    headers: state.token ? {
      "X-DrShare-Token": state.token,
    } : {},
  });

  if (!response.ok) {
    let message = `Request failed with ${response.status}`;

    try {
      const payload = await response.json();
      message = payload.error || message;
    } catch (_) {
      // Keep generic message.
    }

    throw new Error(message);
  }

  if (!response.body) {
    throw new Error("Streaming download is not available in this browser.");
  }

  const writable = await fileHandle.createWritable();
  const reader = response.body.getReader();
  const total = Number(response.headers.get("content-length")) || expectedSize;
  let loaded = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }

      loaded += value.byteLength;
      await writable.write(value);
      showTransfer({
        title: `downloading ${filename}`,
        loaded,
        total,
        detail: `downloaded ${formatBytes(loaded)} / ${formatBytes(total || loaded)}`,
      });
    }

    await writable.close();
    return loaded;
  } catch (error) {
    await writable.abort();
    throw error;
  }
}

function requestWithProgress(path, options = {}) {
  const {
    method = "GET",
    headers = {},
    body = null,
    expectJson = true,
    responseType = "text",
    onUploadProgress,
    onDownloadProgress,
  } = options;

  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open(method, path, true);
    xhr.responseType = responseType === "blob" ? "blob" : "text";

    if (state.token) {
      xhr.setRequestHeader("X-DrShare-Token", state.token);
    }

    for (const [header, value] of Object.entries(headers)) {
      xhr.setRequestHeader(header, value);
    }

    if (xhr.upload && typeof onUploadProgress === "function") {
      xhr.upload.onprogress = (event) => {
        onUploadProgress(event.loaded, event.lengthComputable ? event.total : 0);
      };
    }

    if (typeof onDownloadProgress === "function") {
      xhr.onprogress = (event) => {
        onDownloadProgress(event.loaded, event.lengthComputable ? event.total : 0);
      };
    }

    xhr.onerror = () => {
      reject(new Error("Network error."));
    };

    xhr.onload = async () => {
      if (xhr.status < 200 || xhr.status >= 300) {
        let message = `Request failed with ${xhr.status}`;

        try {
          const payloadText = xhr.responseType === "blob"
            ? await xhr.response.text()
            : xhr.responseText;
          const payload = JSON.parse(payloadText);
          message = payload.error || message;
        } catch (_) {
          // Keep the generic message when the body is not JSON.
        }

        reject(new Error(message));
        return;
      }

      if (responseType === "blob") {
        resolve(xhr.response);
        return;
      }

      if (!expectJson) {
        resolve(xhr.responseText);
        return;
      }

      try {
        resolve(JSON.parse(xhr.responseText));
      } catch (_) {
        reject(new Error("Invalid server response."));
      }
    };

    xhr.send(body);
  });
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
