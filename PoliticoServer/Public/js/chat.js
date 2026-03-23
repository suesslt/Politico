// ---- Chat ----
var chatHistory = [];

function sendChatMessage() {
    var input = document.getElementById('chatInput');
    if (!input) { console.error('chatInput not found'); return; }
    var msg = input.value.trim();
    if (!msg) return;
    input.value = '';

    var container = document.getElementById('chatMessages');
    if (!container) { console.error('chatMessages not found'); return; }

    // Clear placeholder if first message
    if (chatHistory.length === 0) container.innerHTML = '';

    // Show user message
    var userDiv = document.createElement('div');
    userDiv.className = 'mb-3 text-end';
    userDiv.innerHTML = '<div class="d-inline-block bg-primary text-white rounded px-3 py-2" style="max-width:80%">' + escChat(msg) + '</div>';
    container.appendChild(userDiv);

    // Add assistant placeholder
    var assistantId = 'assistant-' + Date.now();
    var assistantDiv = document.createElement('div');
    assistantDiv.className = 'mb-3';
    assistantDiv.innerHTML = '<div class="d-inline-block bg-white border rounded px-3 py-2" style="max-width:80%">'
        + '<div id="' + assistantId + '-sources" class="mb-1"></div>'
        + '<span id="' + assistantId + '"><span class="spinner-border spinner-border-sm text-muted"></span></span>'
        + '</div>';
    container.appendChild(assistantDiv);
    container.scrollTop = container.scrollHeight;

    // Disable input while streaming
    var sendBtn = document.getElementById('chatSendBtn');
    if (sendBtn) sendBtn.disabled = true;

    chatHistory.push({ role: 'user', content: msg });

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/chat', true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    var fullResponse = '';
    var el = document.getElementById(assistantId);
    var started = false;
    var lastParsed = 0;
    var lastEventType = '';

    xhr.onprogress = function() {
        var newText = xhr.responseText.substring(lastParsed);
        lastParsed = xhr.responseText.length;
        var lines = newText.split('\n');

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (!line) { lastEventType = ''; continue; }

            if (line.indexOf('event: ') === 0) {
                lastEventType = line.substring(7);
                continue;
            }
            if (line.indexOf('data: ') === 0) {
                var payload = line.substring(6);

                if (lastEventType === 'sources') {
                    try {
                        var sources = JSON.parse(payload);
                        var srcEl = document.getElementById(assistantId + '-sources');
                        if (srcEl && sources.length > 0) {
                            var srcHtml = '<div class="small text-muted mb-2"><strong>Quellen:</strong> ';
                            for (var j = 0; j < sources.length; j++) {
                                srcHtml += '<span class="badge bg-light text-dark border me-1">' + escChat(sources[j].speaker) + ' (' + escChat(sources[j].date) + ')</span>';
                            }
                            srcHtml += '</div>';
                            srcEl.innerHTML = srcHtml;
                        }
                    } catch(e) { console.error('Sources parse error:', e); }
                    lastEventType = '';
                    continue;
                }

                if (payload === '[DONE]') continue;
                if (payload.indexOf('[ERROR]') === 0) {
                    if (el) el.innerHTML = '<span class="text-danger">' + escChat(payload) + '</span>';
                    continue;
                }

                if (el) {
                    if (!started) { el.textContent = ''; started = true; }
                    var token = payload.replace(/\\n/g, '\n');
                    fullResponse += token;
                    el.textContent = fullResponse;
                    container.scrollTop = container.scrollHeight;
                }
            }
        }
    };

    xhr.onloadend = function() {
        if (sendBtn) sendBtn.disabled = false;
        if (fullResponse) chatHistory.push({ role: 'assistant', content: fullResponse });
    };

    xhr.onerror = function() {
        if (el) el.innerHTML = '<span class="text-danger">Verbindungsfehler</span>';
        if (sendBtn) sendBtn.disabled = false;
    };

    xhr.send(JSON.stringify({ message: msg, history: chatHistory.slice(-10) }));
}

function escChat(s) {
    if (!s) return '';
    var d = document.createElement('div');
    d.textContent = s;
    return d.innerHTML;
}

// ---- Proposition Extraction ----
var propPolling = null;

function showPropButtons(running) {
    var startBtn = document.getElementById('btnStartProps');
    var stopBtn = document.getElementById('btnStopProps');
    if (startBtn) startBtn.style.display = running ? 'none' : '';
    if (stopBtn) stopBtn.style.display = running ? '' : 'none';
}

function pollPropositionStatus() {
    if (propPolling) return;
    updatePropositionStatus();
    propPolling = setInterval(updatePropositionStatus, 5000);
}

function updatePropositionStatus() {
    fetch('/propositions/status')
        .then(function(r) { return r.json(); })
        .then(function(data) {
            var el = document.getElementById('propStatus');
            if (!el) return;
            var running = (data.status === 'extracting' || data.status === 'stopping');
            showPropButtons(running);
            if (data.status === 'extracting') {
                el.innerHTML = '<span class="badge bg-warning text-dark me-1">Extrahiere...</span> ' + data.message;
            } else if (data.status === 'stopping') {
                el.innerHTML = '<span class="badge bg-warning text-dark me-1">Stoppe...</span> ' + data.message;
            } else if (data.status === 'completed') {
                el.innerHTML = '<span class="badge bg-success me-1">Fertig</span> ' + data.message;
                if (propPolling) { clearInterval(propPolling); propPolling = null; }
            } else if (data.status === 'stopped') {
                el.innerHTML = '<span class="badge bg-secondary me-1">Gestoppt</span> ' + data.message;
                if (propPolling) { clearInterval(propPolling); propPolling = null; }
            } else if (data.status === 'failed') {
                el.innerHTML = '<span class="badge bg-danger me-1">Fehler</span> ' + data.message;
                if (propPolling) { clearInterval(propPolling); propPolling = null; }
            } else {
                el.textContent = '';
                if (propPolling) { clearInterval(propPolling); propPolling = null; }
            }
        });
}

// ---- Embedding Generation ----
var embPolling = null;

function showEmbButtons(running) {
    var startBtn = document.getElementById('btnStartEmb');
    var stopBtn = document.getElementById('btnStopEmb');
    if (startBtn) startBtn.style.display = running ? 'none' : '';
    if (stopBtn) stopBtn.style.display = running ? '' : 'none';
}

function startEmbeddingGeneration() {
    showEmbButtons(true);
    fetch('/embeddings/generate', { method: 'POST' })
        .then(function() { pollEmbeddingStatus(); })
        .catch(function(err) { showEmbButtons(false); alert('Fehler: ' + err.message); });
}

function stopEmbeddingGeneration() {
    var btn = document.getElementById('btnStopEmb');
    if (btn) { btn.disabled = true; btn.textContent = 'Stoppe...'; }
    fetch('/embeddings/stop', { method: 'POST' });
}

function pollEmbeddingStatus() {
    if (embPolling) return;
    updateEmbeddingStatus();
    embPolling = setInterval(updateEmbeddingStatus, 5000);
}

function updateEmbeddingStatus() {
    fetch('/embeddings/status')
        .then(function(r) { return r.json(); })
        .then(function(data) {
            var el = document.getElementById('embStatus');
            if (!el) return;
            var running = (data.status === 'embedding' || data.status === 'stopping');
            showEmbButtons(running);
            var stopBtn = document.getElementById('btnStopEmb');
            if (stopBtn && running) { stopBtn.disabled = false; stopBtn.textContent = 'Stop'; }
            if (data.status === 'embedding') {
                el.innerHTML = '<span class="badge bg-warning text-dark me-1">Generiere...</span> ' + data.message;
            } else if (data.status === 'completed') {
                el.innerHTML = '<span class="badge bg-success me-1">Bereit</span> ' + data.message;
                if (embPolling) { clearInterval(embPolling); embPolling = null; }
            } else if (data.status === 'stopped') {
                el.innerHTML = '<span class="badge bg-secondary me-1">Gestoppt</span> ' + data.message;
                if (embPolling) { clearInterval(embPolling); embPolling = null; }
            } else if (data.status === 'failed') {
                el.innerHTML = '<span class="badge bg-danger me-1">Fehler</span> ' + data.message;
                if (embPolling) { clearInterval(embPolling); embPolling = null; }
            } else {
                el.textContent = '';
                if (embPolling) { clearInterval(embPolling); embPolling = null; }
            }
        });
}
