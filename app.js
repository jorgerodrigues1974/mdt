let appCategories = [];
let apps = [];

// State
let selectedApps = new Set();
let currentCategory = 'all';
let searchQuery = '';
let authToken = sessionStorage.getItem('mdt_token') || null;
let installMode = 'local'; // 'local' ou 'remote'
let activeTarget = 'localhost'; 

async function mdtFetch(url, options = {}) {
    if (!options.headers) options.headers = {};
    if (authToken) {
        options.headers['Authorization'] = `Bearer ${authToken}`;
    }
    const response = await fetch(url, options);
    if (response.status === 401 && url !== '/api/login') {
        showLogin();
    }
    return response;
}

function showLogin() {
    document.getElementById('loginModal').style.display = 'flex';
}

// DOM Elements
const categoryNav = document.getElementById('categoryNav');
const appsGrid = document.getElementById('appsGrid');
const selectionBar = document.getElementById('selectionBar');
const selectedCountEl = document.getElementById('selectedCount');
const appSearch = document.getElementById('appSearch');
const generateBtn = document.getElementById('generateBtn');
const clearSelectionBtn = document.getElementById('clearSelection');
// Initialize
async function init() {
    if (!authToken) {
        showLogin();
    }

    try {
        const response = await fetch('apps.json');
        if (!response.ok) throw new Error('Não foi possível carregar apps.json');
        
        const data = await response.json();
        appCategories = data.categories || [];
        apps = data.apps || [];
    } catch (e) {
        console.error("Erro a carregar configurações:", e);
        appsGrid.innerHTML = `<div class="alert alert-info">Falha ao carregar as aplicações. Certifique-se de que o ficheiro apps.json existe.</div>`;
    }

    renderCategories();
    renderApps();
    setupEventListeners();
    checkConnection();
    initClock();
    // Intervado de verificação a cada 5 segundos
    setInterval(checkConnection, 5000);
}

async function checkConnection() {
    const dot = document.getElementById('serverStatusDot');
    const text = document.getElementById('serverStatusText');
    const warning = document.getElementById('serverOfflineWarning');
    const grid = document.getElementById('appsGrid');
    const installBtn = document.getElementById('generateBtn');

    try {
        const response = await mdtFetch('/api/status', { signal: AbortSignal.timeout(2000) });
        if (response.ok) {
            dot.className = 'status-dot online';
            text.textContent = 'Servidor Online';
            warning.style.display = 'none';
            grid.style.display = 'grid';
            installBtn.disabled = false;
            
            // Buscar info de rede
            fetchNetworkInfo();
        } else {
            throw new Error();
        }
    } catch (e) {
        dot.className = 'status-dot offline';
        text.textContent = 'Servidor Offline';
        warning.style.display = 'flex';
        grid.style.display = 'none';
        installBtn.disabled = true;
        document.getElementById('networkBadge').style.display = 'none';
        document.getElementById('smbBadge').style.display = 'none';
    }
}

async function fetchNetworkInfo() {
    try {
        const response = await mdtFetch('/api/network');
        const data = await response.json();
        
        if (data.ip) {
            window.serverIp = data.ip;
        }
    } catch (e) {}
}

function initClock() {
    function update() {
        const now = new Date();
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        document.getElementById('timeClock').textContent = `${hours}:${minutes}`;

        let greeting = 'Bom dia,';
        if (now.getHours() >= 13 && now.getHours() < 20) greeting = 'Boa tarde,';
        else if (now.getHours() >= 20 || now.getHours() < 6) greeting = 'Boa noite,';
        
        document.getElementById('timeGreeting').textContent = greeting;
    }
    update();
    setInterval(update, 60000); // Atualiza a cada minuto
}


function renderCategories() {
    categoryNav.innerHTML = `
        <div class="nav-item ${currentCategory === 'all' ? 'active' : ''}" data-category="all" style="--cat-color: var(--primary-color);">
            <span class="nav-icon">📦</span>
            <span class="nav-text">Todas</span>
        </div>
    `;

    appCategories.forEach(cat => {
        categoryNav.innerHTML += `
            <div class="nav-item ${currentCategory === cat.id ? 'active' : ''}" data-category="${cat.id}" style="--cat-color: ${cat.color};">
                <span class="nav-icon">${cat.icon}</span>
                <span class="nav-text">${cat.name}</span>
            </div>
        `;
    });
}

function renderApps() {
    const filteredApps = apps.filter(app => {
        const matchesCategory = currentCategory === 'all' || app.category === currentCategory;
        const matchesSearch = app.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
                             app.description.toLowerCase().includes(searchQuery.toLowerCase());
        return matchesCategory && matchesSearch;
    });

    appsGrid.innerHTML = '';
    
    if (filteredApps.length === 0) {
        appsGrid.innerHTML = '<div class="no-results">Nenhuma aplicação encontrada.</div>';
        return;
    }

    filteredApps.forEach(app => {
        const isSelected = selectedApps.has(app.id);
        const appCard = document.createElement('div');
        
        // Puxar metadados da categoria principal
        const catObj = appCategories.find(c => c.id === app.category) || { icon: '📦', color: '#60a5fa' };
        
        appCard.className = 'app-card';
        appCard.dataset.id = app.id;
        /* Inject variable to CSS to be able to color borders dynamically */
        appCard.style.setProperty('--cat-color', catObj.color);
        appCard.style.borderTop = `3px solid ${catObj.color}`;

        if (isSelected) appCard.classList.add('selected');

        // Gerar ícone visual real (se existir) centralizado no design Microsoft
        let iconHtml = '';
        if (app.iconUrl) {
            // Utilizamos onerror para recorrer ao inicial genérico caso falhe o download (ex: num site interno sem net)
            iconHtml = `<img src="${app.iconUrl}" alt="${app.name} icon" class="app-icon-img" onerror="this.style.display='none'; this.nextElementSibling.style.display='flex'">
                        <div class="app-icon-fallback" style="display: none;">${app.name.substring(0, 2).toUpperCase()}</div>`;
        }

        appCard.innerHTML = `
            <div class="app-header">
                <div class="app-identity">
                    <div class="icon-container">
                        ${iconHtml}
                    </div>
                    <div class="app-info">
                        <h3><span class="app-cat-icon">${catObj.icon}</span> ${app.name}</h3>
                    </div>
                </div>
                <div class="checkbox-circle"></div>
            </div>
            <p class="app-description">${app.description}</p>
        `;
        appCard.addEventListener('click', () => toggleAppSelection(app.id));
        appsGrid.appendChild(appCard);
    });
}

function toggleAppSelection(appId) {
    if (selectedApps.has(appId)) {
        selectedApps.delete(appId);
    } else {
        selectedApps.add(appId);
    }
    updateSelectionBar();
    renderApps();
}

function updateSelectionBar() {
    const count = selectedApps.size;
    selectedCountEl.textContent = count;
    
    if (count > 0) {
        selectionBar.classList.add('visible');
    } else {
        selectionBar.classList.remove('visible');
    }
}

function setupEventListeners() {
    categoryNav.addEventListener('click', (e) => {
        const navItem = e.target.closest('.nav-item');
        if (navItem) {
            currentCategory = navItem.dataset.category;
            renderCategories();
            renderApps();
        }
    });

    document.getElementById('appSearch').addEventListener('input', (e) => {
        searchQuery = e.target.value.toLowerCase();
        renderApps();
    });

    document.getElementById('closeConnectionBtn').addEventListener('click', () => {
        // Limpar autenticação para segurança
        sessionStorage.removeItem('mdt_token');
        authToken = null;
        
        // Tentar fechar a janela. Se falhar (bloqueio do browser), recarrega para o login
        if (window.close()) {
            // Sucesso ao fechar
        } else {
            window.location.reload();
        }
    });

    clearSelectionBtn.addEventListener('click', () => {
        selectedApps.clear();
        updateSelectionBar();
        renderApps();
    });

    // Options Modal Logic
    const optionsModal = document.getElementById('optionsModal');
    let deployMode = 'local';

    function setDeployMode(mode) {
        deployMode = mode;
        document.getElementById('modeLocal').classList.toggle('active', mode === 'local');
        document.getElementById('modeRemote').classList.toggle('active', mode === 'remote');
        document.getElementById('remoteFields').style.display = mode === 'remote' ? 'block' : 'none';

        const btnLabels = {
            'local':        'Iniciar Instalação Direta',
            'remote':       'Empurrar Instalação via Rede'
        };
        document.getElementById('confirmDeployBtn').textContent = btnLabels[mode];
    }

    generateBtn.addEventListener('click', () => {
        if (selectedApps.size === 0) return;
        
        if (installMode === 'local') {
            executeDeployment('local');
        } else {
            // Abrir modal de credenciais para instalação remota
            document.getElementById('authHost').value = '';
            openCreds(() => {
                const host = document.getElementById('authHost').value;
                const user = document.getElementById('authUser').value;
                const pass = document.getElementById('authPass').value;

                if (!host || !user) {
                    alert('Por favor, preencha o Host e o Utilizador.');
                    return;
                }

                document.getElementById('credentialModal').style.display = 'none';
                executeDeployment('remote', host, user, pass);
            });
        }
    });

    // Toggle de Modo de Instalação (Barra Inferior)
    const installModeBtns = document.querySelectorAll('#installModeToggle .toggle-btn');
    installModeBtns.forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            installModeBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            installMode = btn.dataset.mode;
        });
    });

    // Start Real-Time Clock
    function updateClock() {
        const now = new Date();
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        document.getElementById('timeClock').innerText = `${hours}:${minutes}`;
        
        const hour = now.getHours();
        let greeting = 'Bom dia,';
        if (hour >= 13 && hour < 20) greeting = 'Boa tarde,';
        else if (hour >= 20 || hour < 6) greeting = 'Boa noite,';
        document.getElementById('timeGreeting').innerText = greeting;
    }
    setInterval(updateClock, 1000);
    updateClock();

    // Progress Actions
    // Botões antigos removidos do HTML: moreAppsBtn e shutdownBtn

    // document.getElementById('closeBtn').addEventListener('click', () => {
    //     window.close();
    //     document.getElementById('progressModal').style.display = 'none';
    // });

    // Botão de desligar removido do HTML

    // Login logic
    const loginBtn = document.getElementById('loginBtn');
    const loginPass = document.getElementById('loginPass');
    const loginError = document.getElementById('loginError');

    loginBtn.addEventListener('click', async () => {
        const pass = loginPass.value;
        if (!pass) return;

        try {
            const response = await fetch('/api/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ password: pass })
            });
            const data = await response.json();

            if (data.status === 'success') {
                authToken = data.token;
                sessionStorage.setItem('mdt_token', authToken);
                document.getElementById('loginModal').style.display = 'none';
                loginError.style.display = 'none';
                // Recarregar dados agora que estamos logados
                checkConnection();
            } else {
                loginError.style.display = 'block';
                loginPass.value = '';
            }
        } catch (e) {
            alert('Erro de ligação ao servidor.');
        }
    });

    loginPass.addEventListener('keypress', (e) => {
        if (e.key === 'Enter') loginBtn.click();
    });

    // Winget Upgrade Remote Action
    const upgradeCard = document.getElementById('upgradeCard');
    let upgradeMode = 'local'; // 'local' ou 'remote'

    // Gerir botões de modo (Local/Remoto)
    const modeBtns = document.querySelectorAll('#upgradeModeToggle .toggle-btn');
    modeBtns.forEach(btn => {
        btn.addEventListener('click', (e) => {
            e.stopPropagation();
            modeBtns.forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            upgradeMode = btn.dataset.mode;
        });
    });

    const upgradeBtn = document.getElementById('upgradeAllBtn');
    if (upgradeBtn) {
        upgradeBtn.addEventListener('click', () => {
            if (upgradeMode === 'local') {
                // Iniciar diretamente
                executeRemoteUpgrade('localhost', '', '', true);
            } else {
                // Abrir modal de credenciais
                openCreds(() => {
                    const host = document.getElementById('authHost').value;
                    const user = document.getElementById('authUser').value;
                    const pass = document.getElementById('authPass').value;

                    if (!host || !user) {
                        alert('Por favor, preencha o Host e o Utilizador.');
                        return;
                    }

                    document.getElementById('credentialModal').style.display = 'none';
                    executeRemoteUpgrade(host, user, pass, false);
                });
            }
        });
    }

    // Modal de Credenciais Logic
    document.getElementById('closeAuthModal').addEventListener('click', () => {
        document.getElementById('credentialModal').style.display = 'none';
    });

    const openCreds = (callback) => {
        document.getElementById('connectionStatus').style.display = 'none';
        document.getElementById('connectionStatus').innerHTML = '';
        document.getElementById('credentialModal').style.display = 'flex';
        document.getElementById('startAuthUpgradeBtn').onclick = callback;
    };

    document.getElementById('startAuthUpgradeBtn').addEventListener('click', () => {
        const host = document.getElementById('authHost').value;
        const user = document.getElementById('authUser').value;
        const pass = document.getElementById('authPass').value;

        if (!host || !user) {
            alert('Por favor, preencha o Host e o Utilizador.');
            return;
        }

        document.getElementById('credentialModal').style.display = 'none';
        executeRemoteUpgrade(host, user, pass, false);
    });

    // Botão Fechar Ligação (Progress Modal)
    document.getElementById('closeConnectionBtn').addEventListener('click', () => {
        document.getElementById('progressModal').style.display = 'none';
        selectedApps.clear();
        updateSelectionBar();
        renderApps();
        // Limpar campos de credenciais por segurança
        document.getElementById('authHost').value = '';
        document.getElementById('authUser').value = '';
        document.getElementById('authPass').value = '';
    });

    // Library Manager
    const libraryBtn = document.getElementById('libraryBtn');
    if (libraryBtn) {
        libraryBtn.addEventListener('click', openLibraryManager);
    }

    const closeLibraryBtn = document.getElementById('closeLibraryModal');
    if (closeLibraryBtn) {
        closeLibraryBtn.addEventListener('click', () => {
            document.getElementById('libraryModal').style.display = 'none';
        });
    }

    const refreshLibraryBtn = document.getElementById('refreshLibraryBtn');
    if (refreshLibraryBtn) {
        refreshLibraryBtn.addEventListener('click', openLibraryManager);
    }

    // Lógica de Teste de Ligação
    document.getElementById('testConnectionBtn').addEventListener('click', async () => {
        const host = document.getElementById('authHost').value;
        const user = document.getElementById('authUser').value;
        const pass = document.getElementById('authPass').value;
        const statusDiv = document.getElementById('connectionStatus');

        if (!host || !user) {
            alert('Por favor, preencha o Host e o Utilizador.');
            return;
        }

        statusDiv.style.display = 'block';
        statusDiv.style.color = 'var(--text-dim)';
        statusDiv.innerHTML = '⌛ A testar ligação...';
        
        try {
            const response = await mdtFetch('/api/test-connection', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ targetHost: host, targetUser: user, targetPass: pass })
            });
            const data = await response.json();

            if (data.status === 'success') {
                statusDiv.style.color = '#4ade80';
                statusDiv.innerHTML = '✅ ' + data.message;
            } else {
                statusDiv.style.color = '#ff6b6b';
                let msg = data.message;
                if (msg.includes('WS-Management')) {
                    msg = 'Erro de WinRM: O destino não está configurado para gestão remota. <br><b>Solução:</b> Execute o ficheiro <b>Ativar-Remoto.bat</b> (na pasta Acesso) no computador de destino.';
                }
                statusDiv.innerHTML = '❌ ' + msg;
            }
        } catch (e) {
            statusDiv.style.color = '#ff6b6b';
            statusDiv.innerHTML = '❌ Falha crítica de rede.';
        }
    });
}

async function openLibraryManager() {
    const modal = document.getElementById('libraryModal');
    const tbody = document.getElementById('libraryTableBody');
    const statusMsg = document.getElementById('libraryStatusMsg');
    
    modal.style.display = 'flex';
    tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; padding: 3rem;">Carregando biblioteca...</td></tr>';
    statusMsg.textContent = 'A analisar pasta installers...';

    try {
        const response = await mdtFetch('/api/library');
        const apps = await response.json();
        
        tbody.innerHTML = '';
        apps.forEach(app => {
            const trId = `lib-row-${app.id.replace(/\./g, '-')}`;
            const tr = document.createElement('tr');
            tr.id = trId;
            
            const statusClass = app.status === 'ok' ? 'status-ok' : 'status-missing';
            const statusText = app.status === 'ok' ? 'Existente' : 'Em Falta';

            tr.innerHTML = `
                <td>
                    <div style="font-weight:700; color: #fff;">${app.name}</div>
                    <div style="font-size:0.7rem; color:var(--text-muted);">${app.id}</div>
                </td>
                <td><code style="font-size:0.75rem; background: rgba(0,0,0,0.3); padding: 2px 4px; border-radius: 4px;">${app.localVersion}</code></td>
                <td id="latest-${trId}" style="font-size:0.75rem; color:var(--text-muted);">Consultando...</td>
                <td><span id="badge-${trId}" class="status-badge ${statusClass}">${statusText}</span></td>
                <td>
                    <button class="btn btn-secondary btn-sm sync-btn" data-id="${app.id}" data-file="${app.file}" data-rowid="${trId}" data-localver="${app.localVersion}">Sincronizar</button>
                </td>
            `;
            tbody.appendChild(tr);
            
            // Background check for winget version
            checkWingetVersion(app.id, trId, app.localVersion);
        });

        // Event delegation for sync buttons
        tbody.querySelectorAll('.sync-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                syncApp(btn.dataset.id, btn.dataset.file, btn.dataset.rowid);
            });
        });

        statusMsg.textContent = `${apps.length} aplicações mapeadas no sistema.`;
    } catch (e) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; color:var(--danger-color);">Erro ao carregar biblioteca.</td></tr>';
    }
}

async function checkWingetVersion(id, rowId, localVer) {
    try {
        const response = await mdtFetch('/api/library/check', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id })
        });
        const data = await response.json();
        const latest = data.latestVersion;
        
        const latestEl = document.getElementById(`latest-${rowId}`);
        const badgeEl = document.getElementById(`badge-${rowId}`);
        const syncBtn = document.querySelector(`#${rowId} .sync-btn`);
        
        if (!latestEl) return;

        latestEl.textContent = latest;
        latestEl.style.color = '#fff';
        
        if (latest !== 'N/A' && localVer !== 'N/A') {
            // Comparação simples de string. Funciona para 1.2.3 vs 1.2.4
            if (localVer !== latest && localVer !== 'Existente') {
                badgeEl.className = 'status-badge status-outdated';
                badgeEl.textContent = 'Actualização Disp.';
                if (syncBtn) {
                    syncBtn.classList.remove('btn-secondary');
                    syncBtn.style.background = 'var(--primary-color)';
                    syncBtn.style.color = 'white';
                }
            }
        }
    } catch (e) {
        const el = document.getElementById(`latest-${rowId}`);
        if(el) el.textContent = 'Erro';
    }
}

async function syncApp(id, filename, rowId) {
    const syncBtn = document.querySelector(`#${rowId} .sync-btn`);
    const originalText = syncBtn.textContent;
    
    syncBtn.disabled = true;
    syncBtn.innerHTML = '<span class="spinner"></span> Sincronizando...';
    
    try {
        const response = await mdtFetch('/api/library/sync', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id, file: filename })
        });
        const data = await response.json();
        
        if (data.status === 'success') {
            syncBtn.style.background = '#10b981';
            syncBtn.textContent = '✅ Sucesso';
            setTimeout(openLibraryManager, 2000);
        } else {
            alert('Falha na sincronização: ' + (data.message || 'Erro desconhecido.'));
            syncBtn.disabled = false;
            syncBtn.textContent = originalText;
        }
    } catch (e) {
        alert('Erro ao ligar ao servidor para sincronizar.');
        syncBtn.disabled = false;
        syncBtn.textContent = originalText;
    }
}

async function executeRemoteUpgrade(host, user, pass, isLocal) {
    const modal = document.getElementById('progressModal');
    const installingView = document.getElementById('installingView');
    const successView = document.getElementById('successView');
    
    modal.style.display = 'flex';
    installingView.style.display = 'block';
    successView.style.display = 'none';
    document.getElementById('upgradeReport').style.display = 'none';
    document.getElementById('upgradeList').innerHTML = '';
    
    const displayHost = isLocal ? 'este computador' : host;
    updateProgress(0, 'Iniciando ligação a ' + displayHost + '...');

    try {
        const response = await mdtFetch('/api/upgrade', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                targetHost: host,
                targetUser: user,
                targetPass: pass,
                isLocal: isLocal,
                autoShutdown: document.getElementById('autoShutdownCheck').checked
            })
        });

        const data = await response.json();
        if (data.status === 'started') {
            activeTarget = isLocal ? 'localhost' : host;
            statusInterval = setInterval(pollStatus, 1000);
        } else {
            alert('ERRO: ' + (data.message || 'Falha ao iniciar.'));
            modal.style.display = 'none';
        }
    } catch (e) {
        alert('Erro de conexão com o servidor MDT.');
        modal.style.display = 'none';
    }
}

let statusInterval = null;

async function executeDeployment(mode, targetHost = '', targetUser = '', targetPass = '') {
    const selectedList = apps.filter(app => selectedApps.has(app.id));

    let payload = {
        mode: mode,
        apps: selectedList,
        autoShutdown: document.getElementById('autoShutdownCheck').checked
    };

    if (mode === 'remote') {
        payload.targetHost = targetHost;
        payload.targetUser = targetUser;
        payload.targetPass = targetPass;
        
        if (!payload.targetHost) {
            alert('Por favor, indique o IP ou Nome do PC Alvo.');
            return;
        }
    }

    // Open Progress Modal
    const modal = document.getElementById('progressModal');
    const installingView = document.getElementById('installingView');
    const successView = document.getElementById('successView');
    
    modal.style.display = 'flex';
    installingView.style.display = 'block';
    successView.style.display = 'none';
    document.getElementById('upgradeReport').style.display = 'none';
    document.getElementById('upgradeList').innerHTML = '';
    updateProgress(0, mode === 'remote' ? 'Preparando envio para ' + payload.targetHost + '...' : 'Iniciando...');

    try {
        const response = await mdtFetch('/api/install', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });

        const data = await response.json();
        
        if (data.status === 'started') {
            activeTarget = mode === 'remote' ? targetHost : 'localhost';
            statusInterval = setInterval(pollStatus, 1000);
        } else if (data.status === 'busy') {
            alert('Já existe uma instalação em curso no servidor!');
            modal.style.display = 'none';
        } else if (data.error) {
            alert('ERRO: ' + data.error);
            modal.style.display = 'none';
        }
    } catch (error) {
        console.error(error);
        alert('ERRO DE CONEXÃO: Não foi possível comunicar com o servidor.');
        modal.style.display = 'none';
    }
}

async function pollStatus() {
    try {
        const response = await mdtFetch(`/api/status?target=${encodeURIComponent(activeTarget)}`);
        const status = await response.json();

        if (status.is_running || status.finished) {
            const percent = Math.round((status.completed_count / status.total_count) * 100);
            const displayText = status.error ? `⚠️ ${status.error}` : status.current_app;
            updateProgress(percent, displayText);

            if (status.finished) {
                clearInterval(statusInterval);
                if (status.error && status.error.startsWith('ERRO')) {
                    // Show error state
                    document.getElementById('currentAppName').style.color = '#ff6b6b';
                }
                showSuccess(status);
            }
        }
    } catch (error) {
        console.error('Erro ao obter status:', error);
    }
}

function updateProgress(percent, appName) {
    const bar = document.getElementById('progressBar');
    const percentEl = document.getElementById('progressPercent');
    const nameEl = document.getElementById('currentAppName');

    bar.style.width = `${percent}%`;
    percentEl.textContent = `${percent}%`;
    nameEl.textContent = appName;
}

function showSuccess(status = null) {
    document.getElementById('installingView').style.display = 'none';
    document.getElementById('successView').style.display = 'block';

    if (status && status.results && status.results.length > 0) {
        const report = document.getElementById('upgradeReport');
        const list = document.getElementById('upgradeList');
        const msg = document.getElementById('successMessage');
        
        report.style.display = 'block';
        msg.textContent = 'O processo de atualização foi concluído.';
        list.innerHTML = '';
        
        status.results.forEach(res => {
            const li = document.createElement('li');
            li.innerHTML = `<strong>${res.name}</strong> - <span style="color: var(--success)">Atualizado</span>`;
            list.appendChild(li);
        });
    }
}

init();
