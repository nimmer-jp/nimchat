import crown/core
import tiara/components

const chatClientScript = """
<script>
(function () {
  "use strict";

  const STORAGE_SETUP = "nimchat.setup.v1";
  const STORAGE_SESSIONS = "nimchat.sessions.v1";
  const STORAGE_ACTIVE_SESSION = "nimchat.active-session.v1";
  const STORAGE_KEYS = [STORAGE_SETUP, STORAGE_SESSIONS, STORAGE_ACTIVE_SESSION];

  const state = {
    setup: null,
    sessions: [],
    activeSessionId: "",
    sending: false
  };

  let setupView;
  let chatView;
  let setupForm;
  let setupError;
  let setupEndpointInput;
  let setupModelInput;
  let setupSkipIpInput;
  let setupIpAllowlistInput;
  let endpointBadge;
  let modelBadge;
  let ipBadge;
  let sessionList;
  let newSessionButton;
  let resetButton;
  let messageList;
  let composerForm;
  let composerInput;
  let composerStatus;
  let sendButton;

  function byId(id) {
    return document.getElementById(id);
  }

  function safeJsonParse(raw, fallback) {
    try {
      return JSON.parse(raw);
    } catch (_) {
      return fallback;
    }
  }

  function normalizeList(values) {
    if (!Array.isArray(values)) {
      return [];
    }
    return values
      .map(function (v) { return String(v || "").trim(); })
      .filter(function (v) { return v.length > 0; });
  }

  function loadSetup() {
    const raw = localStorage.getItem(STORAGE_SETUP);
    if (!raw) {
      return null;
    }
    const parsed = safeJsonParse(raw, null);
    if (!parsed || typeof parsed !== "object") {
      return null;
    }
    const endpoint = String(parsed.endpoint || "").trim();
    if (!endpoint) {
      return null;
    }
    return {
      endpoint: endpoint,
      model: String(parsed.model || "").trim(),
      skipIpRestriction: !!parsed.skipIpRestriction,
      ipAllowlist: normalizeList(parsed.ipAllowlist),
      lockedAt: String(parsed.lockedAt || "")
    };
  }

  function saveSetup(setup) {
    localStorage.setItem(STORAGE_SETUP, JSON.stringify(setup));
  }

  function loadSessions() {
    const raw = localStorage.getItem(STORAGE_SESSIONS);
    if (!raw) {
      return [];
    }
    const parsed = safeJsonParse(raw, []);
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed
      .filter(function (session) {
        return session && typeof session.id === "string" && Array.isArray(session.messages);
      })
      .map(function (session) {
        return {
          id: session.id,
          title: String(session.title || "新しい会話"),
          createdAt: String(session.createdAt || new Date().toISOString()),
          messages: session.messages
            .filter(function (msg) {
              return msg && (msg.role === "user" || msg.role === "assistant" || msg.role === "system");
            })
            .map(function (msg) {
              return {
                role: msg.role,
                content: String(msg.content || ""),
                createdAt: String(msg.createdAt || new Date().toISOString())
              };
            })
        };
      });
  }

  function persistSessions() {
    localStorage.setItem(STORAGE_SESSIONS, JSON.stringify(state.sessions));
    if (state.activeSessionId) {
      localStorage.setItem(STORAGE_ACTIVE_SESSION, state.activeSessionId);
    }
  }

  function newSessionId() {
    return "session-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2, 8);
  }

  var markdownOptionsApplied = false;

  function assistantMarkdownToSafeHtml(text) {
    var raw = String(text || "");
    if (!raw) {
      return "";
    }
    var parse =
      typeof marked !== "undefined" && typeof marked.parse === "function"
        ? marked.parse.bind(marked)
        : typeof marked === "function"
          ? marked
          : null;
    var purify = typeof DOMPurify !== "undefined" ? DOMPurify.sanitize : null;
    if (!parse || !purify) {
      return null;
    }
    if (!markdownOptionsApplied && typeof marked.setOptions === "function") {
      try {
        marked.setOptions({
          mangle: false,
          headerIds: false
        });
      } catch (_) {
      }
      markdownOptionsApplied = true;
    }
    var html = parse(raw);
    if (typeof html !== "string") {
      return null;
    }
    return purify(html, { USE_PROFILES: { html: true } });
  }

  function deriveSessionTitle(text) {
    const normalized = String(text || "").trim();
    if (!normalized) {
      return "新しい会話";
    }
    if (normalized.length <= 20) {
      return normalized;
    }
    return normalized.slice(0, 20) + "...";
  }

  function createSession(seedTitle) {
    return {
      id: newSessionId(),
      title: deriveSessionTitle(seedTitle || ""),
      createdAt: new Date().toISOString(),
      messages: []
    };
  }

  function ensureActiveSession() {
    if (state.sessions.length === 0) {
      const firstSession = createSession("");
      state.sessions = [firstSession];
      state.activeSessionId = firstSession.id;
      persistSessions();
      return;
    }

    const exists = state.sessions.some(function (session) {
      return session.id === state.activeSessionId;
    });
    if (!exists) {
      state.activeSessionId = state.sessions[0].id;
      persistSessions();
    }
  }

  function activeSession() {
    for (let i = 0; i < state.sessions.length; i += 1) {
      if (state.sessions[i].id === state.activeSessionId) {
        return state.sessions[i];
      }
    }
    return null;
  }

  function showSetupError(message) {
    setupError.textContent = message;
    setupError.classList.toggle("is-hidden", message.length === 0);
  }

  function renderSetupVisibility(showSetup) {
    setupView.classList.toggle("is-hidden", !showSetup);
    chatView.classList.toggle("is-hidden", showSetup);
  }

  function renderSessionList() {
    sessionList.innerHTML = "";
    state.sessions.forEach(function (session) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "session-item";
      if (session.id === state.activeSessionId) {
        button.classList.add("is-active");
      }
      const title = document.createElement("span");
      title.className = "session-title";
      title.textContent = session.title || "新しい会話";
      button.appendChild(title);
      button.addEventListener("click", function () {
        state.activeSessionId = session.id;
        persistSessions();
        renderSessionList();
        renderMessages();
      });
      sessionList.appendChild(button);
    });
  }

  function renderMessages() {
    messageList.innerHTML = "";
    const session = activeSession();
    if (!session || session.messages.length === 0) {
      const empty = document.createElement("p");
      empty.className = "message-empty";
      empty.textContent = "右下の入力欄からメッセージを送信すると、このセッションに会話が蓄積されます。";
      messageList.appendChild(empty);
      return;
    }

    session.messages.forEach(function (message) {
      const row = document.createElement("div");
      row.className = "message-row";
      if (message.role === "user") {
        row.classList.add("is-user");
      }

      const bubble = document.createElement("div");
      bubble.className = "message-bubble";
      if (message.role === "assistant") {
        bubble.classList.add("is-assistant");
      } else if (message.role === "system") {
        bubble.classList.add("is-system");
      } else {
        bubble.classList.add("is-user");
      }
      if (message.role === "assistant") {
        var safeHtml = assistantMarkdownToSafeHtml(message.content);
        if (safeHtml !== null) {
          bubble.classList.add("is-markdown");
          bubble.innerHTML = safeHtml;
        } else {
          bubble.textContent = message.content;
        }
      } else {
        bubble.textContent = message.content;
      }

      row.appendChild(bubble);
      messageList.appendChild(row);
    });

    messageList.scrollTop = messageList.scrollHeight;
  }

  function setComposerState(isSending, labelText) {
    state.sending = isSending;
    composerInput.disabled = isSending;
    sendButton.disabled = isSending;
    composerStatus.textContent = labelText;
  }

  async function sendMessage() {
    if (state.sending) {
      return;
    }

    const text = composerInput.value.trim();
    if (!text) {
      return;
    }

    const session = activeSession();
    if (!session) {
      return;
    }

    session.messages.push({
      role: "user",
      content: text,
      createdAt: new Date().toISOString()
    });
    if (session.title === "新しい会話") {
      session.title = deriveSessionTitle(text);
    }
    persistSessions();
    renderSessionList();
    renderMessages();

    const setup = state.setup;
    const history = session.messages
      .filter(function (item) { return item.role === "user" || item.role === "assistant"; })
      .slice(0, -1)
      .map(function (item) { return { role: item.role, content: item.content }; });

    composerInput.value = "";
    setComposerState(true, "ローカルLLMに問い合わせ中...");

    try {
      const body = new URLSearchParams({
        endpoint: setup.endpoint,
        model: setup.model || "",
        prompt: text,
        historyJson: JSON.stringify(history),
        ipRestrictionEnabled: String(!setup.skipIpRestriction && setup.ipAllowlist.length > 0),
        allowedIps: setup.ipAllowlist.join(","),
        clientIp: String(window.location.hostname || "").trim()
      });

      const response = await fetch("/api/chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"
        },
        body: body.toString()
      });

      const payload = await response.json().catch(function () {
        return { ok: false, error: "レスポンスのJSON解析に失敗しました。" };
      });

      if (!response.ok || !payload.ok) {
        throw new Error(String(payload.error || "チャット応答の取得に失敗しました。"));
      }

      session.messages.push({
        role: "assistant",
        content: String(payload.assistant || ""),
        createdAt: new Date().toISOString()
      });
      setComposerState(false, "応答を受信しました。");
    } catch (error) {
      session.messages.push({
        role: "system",
        content: "エラー: " + String(error && error.message ? error.message : "不明なエラー"),
        createdAt: new Date().toISOString()
      });
      setComposerState(false, "エラーが発生しました。");
    }

    persistSessions();
    renderSessionList();
    renderMessages();
    composerInput.focus();
  }

  function bindEvents() {
    setupSkipIpInput.addEventListener("change", function () {
      const disabled = setupSkipIpInput.checked;
      setupIpAllowlistInput.disabled = disabled;
      setupIpAllowlistInput.classList.toggle("is-disabled", disabled);
    });

    setupForm.addEventListener("submit", function (event) {
      event.preventDefault();
      showSetupError("");

      const endpoint = setupEndpointInput.value.trim();
      if (!endpoint) {
        showSetupError("接続先URLを入力してください。");
        return;
      }
      if (!(endpoint.startsWith("http://") || endpoint.startsWith("https://"))) {
        showSetupError("接続先URLは http:// か https:// で始めてください。");
        return;
      }

      const skipIp = setupSkipIpInput.checked;
      const allowlist = setupIpAllowlistInput.value
        .split(",")
        .map(function (value) { return value.trim(); })
        .filter(function (value) { return value.length > 0; });

      if (!skipIp && allowlist.length === 0) {
        showSetupError("IP制限を有効化する場合は、1件以上の許可IPを指定してください。");
        return;
      }

      state.setup = {
        endpoint: endpoint,
        model: setupModelInput.value.trim(),
        skipIpRestriction: skipIp,
        ipAllowlist: allowlist,
        lockedAt: new Date().toISOString()
      };
      saveSetup(state.setup);
      startChatMode();
    });

    newSessionButton.addEventListener("click", function () {
      const session = createSession("");
      state.sessions.unshift(session);
      state.activeSessionId = session.id;
      persistSessions();
      renderSessionList();
      renderMessages();
      composerInput.focus();
    });

    resetButton.addEventListener("click", function () {
      if (state.sending) {
        return;
      }
      const confirmed = window.confirm(
        "localStorage に保存された接続設定と会話履歴をすべて削除します。よろしいですか？"
      );
      if (!confirmed) {
        return;
      }
      resetLocalStorage();
    });

    composerForm.addEventListener("submit", function (event) {
      event.preventDefault();
      sendMessage();
    });

    composerInput.addEventListener("keydown", function (event) {
      if (event.key !== "Enter") {
        return;
      }
      if (!event.metaKey && !event.ctrlKey) {
        return;
      }
      if (state.sending) {
        return;
      }
      event.preventDefault();
      sendMessage();
    });
  }

  function resetLocalStorage() {
    STORAGE_KEYS.forEach(function (key) {
      try {
        localStorage.removeItem(key);
      } catch (_) {
      }
    });
    state.setup = null;
    state.sessions = [];
    state.activeSessionId = "";
    showSetupError("");
    setupForm.reset();
    setupSkipIpInput.checked = true;
    setupIpAllowlistInput.disabled = true;
    setupIpAllowlistInput.classList.add("is-disabled");
    renderSetupVisibility(true);
    setupEndpointInput.focus();
  }

  function renderSetupMeta() {
    endpointBadge.textContent = "Endpoint: " + state.setup.endpoint;
    modelBadge.textContent = state.setup.model.length > 0
      ? "Model: " + state.setup.model
      : "Model: (指定なし)";
    ipBadge.textContent = state.setup.skipIpRestriction || state.setup.ipAllowlist.length === 0
      ? "IP制限: スキップ"
      : "IP制限: " + state.setup.ipAllowlist.join(", ");
  }

  function startChatMode() {
    renderSetupVisibility(false);
    renderSetupMeta();
    state.sessions = loadSessions();
    state.activeSessionId = localStorage.getItem(STORAGE_ACTIVE_SESSION) || "";
    ensureActiveSession();
    renderSessionList();
    renderMessages();
    setComposerState(false, "準備完了");
  }

  function init() {
    setupView = byId("setup-view");
    chatView = byId("chat-view");
    setupForm = byId("setup-form");
    setupError = byId("setup-error");
    setupEndpointInput = byId("tiara-setup-endpoint");
    setupModelInput = byId("tiara-setup-model");
    setupSkipIpInput = byId("setup-skip-ip");
    setupIpAllowlistInput = byId("tiara-setup-ip-allowlist");
    endpointBadge = byId("endpoint-badge");
    modelBadge = byId("model-badge");
    ipBadge = byId("ip-badge");
    sessionList = byId("session-list");
    newSessionButton = byId("new-session-button");
    resetButton = byId("reset-storage-button");
    messageList = byId("message-list");
    composerForm = byId("composer-form");
    composerInput = byId("composer-input");
    composerStatus = byId("composer-status");
    sendButton = byId("send-button");

    if (!setupView || !chatView || !setupForm || !setupError ||
        !setupEndpointInput || !setupModelInput || !setupSkipIpInput || !setupIpAllowlistInput ||
        !endpointBadge || !modelBadge || !ipBadge ||
        !sessionList || !newSessionButton || !resetButton || !messageList ||
        !composerForm || !composerInput || !composerStatus || !sendButton) {
      console.error("nimchat init failed: required DOM nodes are missing.");
      return;
    }

    bindEvents();

    state.setup = loadSetup();
    if (!state.setup || !state.setup.lockedAt) {
      renderSetupVisibility(true);
      setupSkipIpInput.checked = true;
      setupIpAllowlistInput.disabled = true;
      setupIpAllowlistInput.classList.add("is-disabled");
      return;
    }

    startChatMode();
  }

  document.addEventListener("DOMContentLoaded", init);
})();
</script>
"""

proc page*(req: Request): string =
  discard req

  let setupBadge = $Tiara.badge(
    "初回セットアップ",
    tone = "accent",
    variant = "solid"
  )
  let endpointInput = $Tiara.input(
    name = "setup_endpoint",
    label = "ローカルLLM接続先 URL",
    placeholder = "http://127.0.0.1:11434/v1/chat/completions",
    required = true,
    attrs = @[("autocomplete", "off")]
  )
  let modelInput = $Tiara.input(
    name = "setup_model",
    label = "モデル名 (任意)",
    placeholder = "例: qwen2.5-coder:7b",
    attrs = @[("autocomplete", "off")]
  )
  let ipAllowlistInput = $Tiara.textarea(
    name = "setup_ip_allowlist",
    label = "許可IPアドレス (カンマ区切り)",
    placeholder = "127.0.0.1, ::1, localhost",
    required = false,
    rows = 3,
    attrs = @[("class", "input")]
  )
  let setupSubmitButton = $Tiara.button(
    "設定を保存して開始",
    buttonType = "submit"
  )

  let liveBadge = $Tiara.badge(
    "Live",
    tone = "success",
    variant = "soft",
    size = "small"
  )
  let newSessionButton = $Tiara.button(
    "新規セッション",
    color = "secondary",
    outlined = true,
    attrs = @[("id", "new-session-button"), ("class", "sidebar-action")]
  )
  let resetStorageButton = $Tiara.button(
    "設定をリセット",
    color = "secondary",
    outlined = true,
    attrs = @[
      ("id", "reset-storage-button"),
      ("class", "sidebar-action sidebar-action-danger"),
      ("type", "button")
    ]
  )
  let sendButton = $Tiara.button(
    "送信",
    buttonType = "submit",
    attrs = @[("id", "send-button"), ("class", "send-action")]
  )

  return html"""
    <div class="nimchat-shell">
      <section id="setup-view" class="setup-view">
        <div class="setup-card">
          <div class="setup-badge">{setupBadge}</div>
          <h1 class="setup-title">nimchat</h1>
          <p class="setup-description">
            初回のみローカルLLM接続先を設定します。IP制限は任意で設定でき、スキップも可能です。
          </p>

          <form id="setup-form" class="setup-form">
            {endpointInput}
            {modelInput}
            {ipAllowlistInput}
            <p class="setup-help">例: <code>127.0.0.1, ::1, localhost</code>。スキップ時は未入力のままで問題ありません。</p>

            <label class="setup-skip-row">
              <input id="setup-skip-ip" type="checkbox" checked>
              <span>IP制限をスキップして開始する</span>
            </label>

            <p id="setup-error" class="setup-error is-hidden"></p>

            <div class="setup-actions">
              {setupSubmitButton}
            </div>
          </form>
        </div>
      </section>

      <section id="chat-view" class="chat-view is-hidden">
        <aside class="chat-sidebar">
          <div class="sidebar-header">
            <div class="sidebar-brand">
              <h2>nimchat</h2>
              {liveBadge}
            </div>
            <p id="endpoint-badge" class="sidebar-meta"></p>
            <p id="model-badge" class="sidebar-meta"></p>
            <p id="ip-badge" class="sidebar-meta"></p>
            {newSessionButton}
            {resetStorageButton}
          </div>
          <nav id="session-list" class="session-list"></nav>
        </aside>

        <main class="chat-main">
          <div id="message-list" class="message-list"></div>

          <form id="composer-form" class="composer-form">
            <textarea
              id="composer-input"
              class="composer-input"
              rows="3"
              placeholder="メッセージを入力..."
            ></textarea>
            <div class="composer-row">
              <span id="composer-status" class="composer-status">準備完了</span>
              {sendButton}
            </div>
          </form>
        </main>
      </section>
    </div>
  """ & chatClientScript
