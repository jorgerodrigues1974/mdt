param(
    [switch]$FromBat
)

# --- 1. Autoelevacao ---
if (-not $FromBat -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Solicitando privilegios de Administrador..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -ErrorAction Stop
        exit
    } catch {
        Write-Host "ERRO: Nao foi possivel obter privilegios de Administrador." -ForegroundColor Red
        Read-Host "Pressione Enter para sair..."
        exit
    }
}

# --- 2. Configuracoes e Estado ---
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
$installersPath = Join-Path $scriptRoot "installers"
$port = 8070

# Detetar IP Local (Filtrando interfaces virtuais e preferindo fisicas)
$Global:LocalIP = try {
    $ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.InterfaceAlias -notlike "*Loopback*" -and
        $_.InterfaceAlias -notlike "*vEthernet*" -and
        $_.InterfaceAlias -notlike "*VMware*" -and
        $_.IPv4Address -notlike "169.254.*"
    } | Sort-Object InterfaceAlias
    if ($ips) { $ips[0].IPv4Address } else { "127.0.0.1" }
} catch { "127.0.0.1" }

# Deteção de Arquitetura do Sistema
$Global:OSArch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
Write-Host "[MDT INFO] Sistema detetado como: $Global:OSArch" -ForegroundColor Cyan

# Dicionário Sincronizado para múltiplas sessões simultâneas
$Global:ActiveSessions = [hashtable]::Synchronized(@{})

function Get-TargetStatus {
    param($Target)
    $Target = $Target.ToLower()
    if (-not $Global:ActiveSessions.ContainsKey($Target)) {
        $Global:ActiveSessions[$Target] = [hashtable]::Synchronized(@{
            is_running = $false
            current_app = ""
            completed_count = 0
            total_count = 0
            percent = 0
            finished = $false
            error = ""
            results = @()
            auto_shutdown = $false
            target_host = $Target
        })
    }
    return $Global:ActiveSessions[$Target]
}

# --- Segurança ---
$Global:MDTPassword = "1234" # Pode alterar esta password manualmente aqui
$Global:SessionToken = [guid]::NewGuid().ToString()

function Test-Auth {
    param($request)
    $authHeader = $request.Headers["Authorization"]
    return ($authHeader -eq "Bearer $Global:SessionToken")
}

# --- Auditoria ---
function Write-AuditLog {
    param($RequesterIP, $TargetHost, $Action, $Apps, $Status = "Sucesso")
    try {
        $auditDir = Join-Path $scriptRoot "auditoria"
        if (-not (Test-Path $auditDir)) { New-Item -ItemType Directory -Path $auditDir -Force }
        $logFile = Join-Path $auditDir "log_$(Get-Date -Format 'yyyy-MM-dd').txt"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        $appsString = if ($null -eq $Apps) { "N/A" } elseif ($Apps -is [array]) { $Apps -join ", " } else { $Apps }
        $entry = "[$timestamp] | ORIGEM: $RequesterIP | DESTINO: $TargetHost | ACAO: $Action | APPS: [$appsString] | STATUS: $Status"
        
        # Retry loop para evitar bloqueio de ficheiro em escritas simultâneas
        $retryCount = 0
        $success = $false
        while (-not $success -and $retryCount -lt 5) {
            try {
                Add-Content -Path $logFile -Value $entry -ErrorAction Stop
                $success = $true
            } catch {
                $retryCount++
                Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
            }
        }
    } catch {
        Write-Host "[!] Erro ao gravar auditoria: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$WingetActivationScript = {
    # Tentar localizar o winget ou ativá-lo
    $w = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $w) {
        # Procurar no caminho de aplicações do Windows
        $path = (Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller*_x64__*\winget.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
        if ($path) { 
            $env:Path += ";$(Split-Path $path)" 
            return "Ativado via Path"
        } else {
            # Tentar registo forçado
            Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction SilentlyContinue
            return "Tentativa de Registo Appx"
        }
    }
    return "Winget OK"
}

# --- 3. Funcao Executor (Background) ---
$ExcecutorBlock = {
    param($payload, $installersPath, $Status, $LocalIP)

    $Status["is_running"] = $true
    $Status["total_count"] = $payload.apps.Count
    $Status["completed_count"] = 0
    $Status["finished"] = $false
    $Status["error"] = ""

    $cred = $null
    if ($payload.mode -eq "remote" -and $payload.targetUser) {
        try {
            $securePass = ConvertTo-SecureString $payload.targetPass -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($payload.targetUser, $securePass)
        } catch {}
    }

    # A partilha Backend invisivel contem a raiz inteira
    $UNCShare = "\\$LocalIP\MDT-Backend$"

    foreach ($app in $payload.apps) {
        $Status["current_app"] = "Instalando $($app.name)..."
        
        # Calcular percentagem base
        $basePercent = [Math]::Round(($Status["completed_count"] / $Status["total_count"]) * 100)
        $Status["percent"] = $basePercent + 2

        try {
            if ($payload.mode -eq "remote") {
                # Ativar Winget no destino antes de começar (mesmo para local installers, pode ser útil)
                if ($cred) {
                    Invoke-Command -ComputerName $payload.targetHost -Credential $cred -ScriptBlock $WingetActivationScript -ErrorAction SilentlyContinue
                } else {
                    Invoke-Command -ComputerName $payload.targetHost -ScriptBlock $WingetActivationScript -ErrorAction SilentlyContinue
                }

                $RemoteCommand = {
                    param($UNCFile, $ArgsParams)
                    if (-not (Test-Path $UNCFile)) { throw "Ficheiro nao encontrado na rede: $UNCFile" }
                    
                    $extension = [System.IO.Path]::GetExtension($UNCFile).ToLower()
                    if ($extension -eq ".msi") {
                        $sanitizedArgs = $ArgsParams -replace "/S", "" -replace "/SILENT", "" -replace "/silent", "" -replace "/s", ""
                        $msiArgs = "/i `"$UNCFile`" /qn /norestart ALLUSERS=1 $($sanitizedArgs.Trim())"
                        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow -PassThru
                    } else {
                        $proc = Start-Process -FilePath $UNCFile -ArgumentList $ArgsParams -Wait -NoNewWindow -PassThru
                    }

                    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) { 
                        throw "Falha no PC de destino (Exit Code $($proc.ExitCode))" 
                    }
                    return "Instalacao concluida no destino com sucesso."
                }

                $UNCPath = "$UNCShare\installers\$($app.localFile)"
                if ($app.localFile -match "^[a-zA-Z]:" -or $app.localFile.StartsWith("\\")) {
                    $UNCPath = $app.localFile # Caminho absoluto ja fornecido
                }
                elseif ($app.localFile.StartsWith("installers\")) {
                    $UNCPath = "$UNCShare\$($app.localFile)"
                }

                if ($cred) {
                    Invoke-Command -ComputerName $payload.targetHost -Credential $cred -ScriptBlock $RemoteCommand -ArgumentList $UNCPath, $app.silentArgs -ErrorAction Stop
                } else {
                    Invoke-Command -ComputerName $payload.targetHost -ScriptBlock $RemoteCommand -ArgumentList $UNCPath, $app.silentArgs -ErrorAction Stop
                }
            } else {
                # Modo Local
                $fullPath = Join-Path $installersPath $app.localFile
                if (-not (Test-Path $fullPath)) {
                        $fullPath = "$scriptRoot\installers\$($app.localFile)"
                }
                
                if (Test-Path $fullPath) {
                    $workDir = Split-Path $fullPath
                    $extension = [System.IO.Path]::GetExtension($fullPath).ToLower()
                    
                    if ($extension -eq ".msi") {
                        $sanitizedArgs = $app.silentArgs -replace "/S", "" -replace "/SILENT", "" -replace "/silent", "" -replace "/s", ""
                        $msiArgs = "/i `"$fullPath`" $($sanitizedArgs.Trim()) /qn /norestart ALLUSERS=1"
                        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -NoNewWindow -PassThru
                    } else {
                        $proc = Start-Process -FilePath $fullPath -ArgumentList $app.silentArgs -WorkingDirectory $workDir -Wait -NoNewWindow -PassThru
                    }

                    $Status["current_app"] = "A verificar conclusão..."
                    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
                        throw "Erro na instalação local (Código: $($proc.ExitCode))."
                    }
                    Start-Sleep -Seconds 1
                } else {
                    throw "Instalador nao encontrado: $fullPath"
                }
            }
            $Status["percent"] = [Math]::Round((($Status["completed_count"] + 1) / $Status["total_count"]) * 100)
            Start-Sleep -Seconds 1
        } catch {
            $Status["error"] = "ERRO em $($app.name): $($_.Exception.Message)"
            Start-Sleep -Seconds 5
            $Status["error"] = $null
        }

        $Status["completed_count"]++
    }

    $Status["finished"] = $true
    $Status["is_running"] = $false
    $Status["current_app"] = "Concluido"

    # Auto-shutdown se solicitado
    if ($Status["auto_shutdown"]) {
        Write-Host "[MDT] Auto-shutdown ativado. Encerrando em 5 segundos..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Stop-Process -Id $PID -Force
    }
}

$UpgradeBlock = {
    param($payload, $Status)

    $Status["is_running"] = $true
    $Status["finished"] = $false
    $Status["error"] = ""
    $Status["percent"] = 0
    $Status["results"] = @()
    $Status["current_app"] = "Consultando atualizacoes..."

    $cred = $null
    if (-not $payload.isLocal -and $payload.targetUser) {
        try {
            $securePass = ConvertTo-SecureString $payload.targetPass -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($payload.targetUser, $securePass)
        } catch {}
    }

    try {
        $RemoteScript = {
            param($isLocal)
            $w = Get-Command winget.exe -ErrorAction SilentlyContinue
            $exe = if ($w) { $w.Source } else { 
                (Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller*_x64__*\winget.exe" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
            }
            if (-not $exe) { $exe = "winget" }

            # Forçar locale en-US para garantir cabeçalhos previsíveis (Name, Id, Version)
            $raw = & $exe upgrade --accept-source-agreements --locale en-US | Out-String
            $lines = $raw -split "`r?`n" | Where-Object { $_.Trim() }
            
            # 1. Encontrar o separador (linha composta apenas por traços ou traços e espaços)
            $sIdx = -1
            for ($i=0; $i -lt $lines.Count; $i++) { 
                if ($lines[$i] -match "^-+$" -or $lines[$i] -match "^-+\s+-+") { $sIdx = $i; break } 
            }
            if ($sIdx -le 0) { return @() }

            $header = $lines[$sIdx - 1]
            
            # 2. Localizar a coluna "Id" (usando a posição da palavra no cabeçalho)
            $idStart = $header.IndexOf("Id")
            if ($idStart -lt 0) { $idStart = $header.IndexOf("ID") }
            if ($idStart -lt 0) { return @() }

            # Localizar "Version" para saber o limite lateral da coluna Id
            $vStart = $header.IndexOf("Version")

            $ids = @()
            for ($i=$sIdx+1; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line.Length -gt $idStart) {
                    # Substring do ID (até ao início da versão ou resto da linha)
                    $idPart = if ($vStart -gt $idStart) { 
                        $line.Substring($idStart, $vStart - $idStart).Trim() 
                    } else { 
                        $line.Substring($idStart).Trim() 
                    }
                    $id = ($idPart -split "\s+")[0]
                    if ($id -and $id -ne "---") { $ids += $id }
                }
            }
            return $ids
        }

        $appsToUpgrade = if ($payload.isLocal) {
            Invoke-Command -ScriptBlock $RemoteScript -ArgumentList $true
        } elseif ($cred) {
            Invoke-Command -ComputerName $payload.targetHost -Credential $cred -ScriptBlock $RemoteScript -ArgumentList $false -ErrorAction Stop
        } else {
            Invoke-Command -ComputerName $payload.targetHost -ScriptBlock $RemoteScript -ArgumentList $false -ErrorAction Stop
        }

        if ($null -eq $appsToUpgrade -or $appsToUpgrade.Count -eq 0) {
            $Status["current_app"] = "Nao foram encontradas atualizacoes pendentes."
            $Status["percent"] = 100
            Start-Sleep -Seconds 3
        } else {
            $Status["total_count"] = $appsToUpgrade.Count
            $Status["completed_count"] = 0
            $tempResults = New-Object System.Collections.Generic.List[PSObject]

            foreach ($appId in $appsToUpgrade) {
                $Status["current_app"] = "Atualizando: $appId ($($Status["completed_count"] + 1)/$($Status["total_count"]))..."
                $Status["percent"] = [Math]::Round(($Status["completed_count"] / $Status["total_count"]) * 100)

                $UpgradeCmd = { 
                    param($id)
                    $w = Get-Command winget.exe -ErrorAction SilentlyContinue
                    $exe = if ($w) { $w.Source } else { "winget" }
                    & $exe upgrade --id $id --silent --accept-package-agreements --accept-source-agreements --force --disable-interactivity
                }
                
                if ($payload.isLocal) {
                    Invoke-Command -ScriptBlock $UpgradeCmd -ArgumentList $appId
                } elseif ($cred) {
                    Invoke-Command -ComputerName $payload.targetHost -Credential $cred -ScriptBlock $UpgradeCmd -ArgumentList $appId
                } else {
                    Invoke-Command -ComputerName $payload.targetHost -ScriptBlock $UpgradeCmd -ArgumentList $appId
                }
                
                $tempResults.Add(@{ name = $appId; status = "OK" })
                $Status["results"] = $tempResults.ToArray()
                $Status["completed_count"]++
            }
            $Status["percent"] = 100
            $Status["current_app"] = "Sistema Atualizado com Sucesso!"
        }
    } catch {
        $Status["error"] = "Erro no Upgrade: $($_.Exception.Message)"
    } finally {
        $Status["finished"] = $true
        $Status["is_running"] = $false
    }
}

# --- 4. Configurar Rede e Iniciar Listener ---
$IsNetworkClient = $scriptRoot.StartsWith("\\")

if (-not $IsNetworkClient) {
    # Abrir Porta no Firewall
    # APENAS CONFIGURAR REDE, FIREWALL E SMB SE ESTIVER A CORRER NO SERVIDOR FISICO
    # Se estiver a correr por UNC (\\Servidor\...) no Cliente, saltamos esta parte porque os clientes não mapeiam partilhas.
    if (-not $scriptRoot.StartsWith("\\")) {
        try {
            $ruleName = "MDT Lite Server"
            if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
                New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow -Profile Domain,Private -RemoteAddress LocalSubnet -ErrorAction SilentlyContinue
            } else {
                Set-NetFirewallRule -DisplayName $ruleName -Profile Any -ErrorAction SilentlyContinue
            }
        } catch {}
        try {
            $AdminGroup = "Administrators" # Local fallback
            $UserGroup = "Everyone"        # Local fallback
            try {
                # Obter nomes localizados via SID para evitar erros em Windows PT-PT/PT-BR
                $AdminGroup = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")).Translate([System.Security.Principal.NTAccount]).Value
                $UserGroup = (New-Object System.Security.Principal.SecurityIdentifier("S-1-1-0")).Translate([System.Security.Principal.NTAccount]).Value

                # SID para Domain Admins (S-1-5-21-*-512)
                $domainAdmins = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-0-0-0-512")).Translate([System.Security.Principal.NTAccount]).Value
                if ($domainAdmins) { $AdminGroup = $domainAdmins }
                
                # SID para Domain Users (S-1-5-21-*-513)
                $domainUsers = (New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-0-0-0-513")).Translate([System.Security.Principal.NTAccount]).Value
                if ($domainUsers) { $UserGroup = $domainUsers }
            } catch {
                # Fallback manual se a tradução de SID de domínio falhar
                if ($null -eq $AdminGroup) { $AdminGroup = "Administradores" }
                if ($null -eq $UserGroup) { $UserGroup = "Todos" }
            }

            # OBRIGAR à limpeza das partilhas antigas ou desconfiguradas!
            Remove-SmbShare -Name "MDT" -Force -ErrorAction SilentlyContinue
            Remove-SmbShare -Name "MDT-Lite" -Force -ErrorAction SilentlyContinue
            
            $backendName = "MDT-Backend$"
            $shareBackend = Get-SmbShare -Name $backendName -ErrorAction SilentlyContinue
            if (-not $shareBackend) {
                New-SmbShare -Name $backendName -Path $scriptRoot -ReadAccess $AdminGroup -ErrorAction Stop
                Write-Host "[SEC] Partilha oculta criada -> $backendName (Acesso: $AdminGroup)" -ForegroundColor Green
            }

            # 2. Partilha Publica (Isolada apenas com Iniciar-Cliente.vbs)
            $publicName = "MDT"
            $acessoPath = Join-Path $scriptRoot "Acesso"
            # Remover se já existir para garantir permissões novas
            Remove-SmbShare -Name $publicName -Force -ErrorAction SilentlyContinue
            # Adicionar permissão para utilizadores do domínio E administradores
            New-SmbShare -Name $publicName -Path $acessoPath -ReadAccess @($UserGroup, $AdminGroup) -ErrorAction SilentlyContinue
            Write-Host "[SEC] Partilha publica 'MDT' ativada para $UserGroup e $AdminGroup -> \\$($Global:LocalIP)\MDT" -ForegroundColor Green

            # --- CRITICO: Permissoes NTFS na pasta Base ---
            $acl = Get-Acl $scriptRoot
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $AdminGroup,
                "ReadAndExecute",
                "ContainerInherit, ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($rule)
            Set-Acl -Path $scriptRoot -AclObject $acl
            
            # Permissões NTFS específicas para a pasta Acesso (Domain Users)
            try {
                $acessoAcl = Get-Acl $acessoPath
                $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule($UserGroup, "ReadAndExecute", "ContainerInherit, ObjectInherit", "None", "Allow")
                $acessoAcl.AddAccessRule($userRule)
                Set-Acl -Path $acessoPath -AclObject $acessoAcl
            } catch {}
            
            Write-Host "[SEC] Permissoes NTFS aplicadas para: $AdminGroup (Root) e $UserGroup (Acesso)" -ForegroundColor Green

        } catch {
            Write-Host "[!] AVISO SMB: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[MDT CLIENTE] A correr a partir da rede ($scriptRoot). Ignorando firewall e partilha." -ForegroundColor Cyan
}

# ============================================================
# INICIALIZAR O SERVIDOR HTTP
# ============================================================
# $port = Get-Random -Minimum 10000 -Maximum 50000 # Mantendo a porta fixa em 8070 conforme solicitado

# Tentativa de matar processos zombies presos na porta 8070 (apenas outros PIDs para nao se matar a ele proprio)
try {
    $connections = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($conn in $connections) {
        if ($conn.OwningProcess -ne 4 -and $conn.OwningProcess -ne $PID) {
            Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
} catch {}

$isBusy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue

if ($isBusy) {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host " ATENCAO: A porta 8070 ja esta ocupada! " -ForegroundColor Yellow
    Write-Host " O servidor parece ja estar ativo em pano de fundo. " -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "A abrir o navegador em 3 segundos..." -ForegroundColor White
    Start-Sleep -Seconds 3
    Start-Process "http://localhost:$port/"
    exit
}

$listener = New-Object System.Net.HttpListener

# Registar prefixo de rede
try {
    $listener.Prefixes.Add("http://*:$port/")
} catch {
    Write-Host "AVISO: Nao foi possivel registar o prefixo [*]. Tentando prefixos especificos..." -ForegroundColor Yellow
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Prefixes.Add("http://127.0.0.1:$port/")
    if ($Global:LocalIP -ne "127.0.0.1") {
        try { $listener.Prefixes.Add("http://$($Global:LocalIP):$port/") } catch {}
    }
}

try {
    $listener.Start()

    # Banner
    Clear-Host
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "        MDT LITE - SERVIDOR DE INSTALACAO" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  O servidor esta ATIVO e PRONTO." -ForegroundColor Green
    Write-Host ""
    Write-Host "  >> URL LOCAL:   " -NoNewline
    Write-Host "http://localhost:$port/" -ForegroundColor White -BackgroundColor DarkCyan
    Write-Host "  >> URL REDE:    " -NoNewline
    Write-Host "http://$($Global:LocalIP):$port/" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "  >> URL NOME:    " -NoNewline
    Write-Host "http://$($env:COMPUTERNAME):$port/" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host ""
    Write-Host "  [SEGURANCA] Autenticacao ATIVA - Acesso protegido por sessao" -ForegroundColor Yellow
    Write-Host "  [SEGURANCA] Password do painel: " -NoNewline -ForegroundColor Yellow
    Write-Host $Global:MDTPassword -ForegroundColor White
    Write-Host ""
    Write-Host "  A janela vai minimizar em 3 segundos..." -ForegroundColor Gray
    Write-Host "===================================================" -ForegroundColor Cyan

    # Abrir navegador
    Start-Process "http://localhost:$port/"

    # Pausa para o utilizador ler o banner
    Start-Sleep -Seconds 3

    while ($listener.IsListening) {
        $context = $null
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            $path = $request.Url.AbsolutePath

            # ============================================================
            # Endpoints da API
            # ============================================================

            # API: LOGIN (Público)
            if ($path -eq "/api/login" -and $request.HttpMethod -eq "POST") {
                $reader = New-Object System.IO.StreamReader($request.InputStream)
                $body = $reader.ReadToEnd()
                $payload = $body | ConvertFrom-Json
                
                if ($payload.password -eq $Global:MDTPassword) {
                    $resData = @{ status = "success"; token = $Global:SessionToken } | ConvertTo-Json
                } else {
                    $resData = @{ status = "error"; message = "Password incorreta" } | ConvertTo-Json
                    $response.StatusCode = 401
                }
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                $response.ContentType = "application/json"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
                $response.OutputStream.Close()
            }
            # API: Descobrir IP do Cliente (Público para o app.js saber onde se ligar)
            elseif ($path -eq "/api/whoami" -and $request.HttpMethod -eq "GET") {
                $clientIP = $request.RemoteEndPoint.Address.ToString()
                $resData = @{ ip = $clientIP } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                $response.ContentType = "application/json"
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            }
            # API: Protegida por Token
            elseif ($path.StartsWith("/api/")) {
                if (-not (Test-Auth -request $request)) {
                    $resData = @{ status = "error"; message = "Não autorizado" } | ConvertTo-Json
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                    $response.StatusCode = 401
                    $response.ContentType = "application/json"
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    $response.OutputStream.Close()
                } else {
                    # --- Endpoints Protegidos ---
                    
                    if ($path -eq "/api/shutdown" -and $request.HttpMethod -eq "POST") {
                        $resData = @{ status = "shutting_down" } | ConvertTo-Json
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        $response.OutputStream.Close()
                        
                        Write-Host "[MDT LITE] Encerramento solicitado via interface." -ForegroundColor Yellow
                        Start-Sleep -Seconds 2
                        Stop-Process -Id $PID -Force
                    }
                    elseif ($path -eq "/api/test-connection" -and $request.HttpMethod -eq "POST") {
                        $reader = New-Object System.IO.StreamReader($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $payload = $body | ConvertFrom-Json

                        $hostName = $payload.targetHost
                        $user = $payload.targetUser
                        $pass = $payload.targetPass

                        $secPass = ConvertTo-SecureString $pass -AsPlainText -Force
                        $cred = New-Object System.Management.Automation.PSCredential($user, $secPass)

                        try {
                            # Testar WSMan e uma pequena execução remota
                            $test = Test-WSMan -ComputerName $hostName -ErrorAction Stop
                            $remoteTest = Invoke-Command -ComputerName $hostName -Credential $cred -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop
                            $resData = @{ status = "success"; message = "Ligação estabelecida com sucesso para $remoteTest" } | ConvertTo-Json
                        } catch {
                            $resData = @{ status = "error"; message = $_.Exception.Message } | ConvertTo-Json
                        }
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/network" -and $request.HttpMethod -eq "GET") {
                        $resData = @{ ip = $Global:LocalIP; port = $port; hostname = $env:COMPUTERNAME } | ConvertTo-Json
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/install" -and $request.HttpMethod -eq "POST") {
                        $reader = New-Object System.IO.StreamReader($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $payload = $body | ConvertFrom-Json

                        if ($null -eq $payload.mode) {
                            $payload = @{ mode = "local"; apps = $payload }
                        }

                        $target = if ($payload.mode -eq "remote") { $payload.targetHost } else { "localhost" }
                        $TargetStatus = Get-TargetStatus -Target $target

                        if ($TargetStatus["is_running"]) {
                            $resData = @{ status = "busy"; message = "Ja existe uma instalacao em curso para este destino ($target)." } | ConvertTo-Json
                        } else {
                            $TargetStatus["auto_shutdown"] = [bool]$payload.autoShutdown

                            $newRunspace = [runspacefactory]::CreateRunspace()
                            $newRunspace.Open()
                            $newRunspace.SessionStateProxy.SetVariable("Status", $TargetStatus)
                            $newRunspace.SessionStateProxy.SetVariable("WingetActivationScript", $WingetActivationScript)

                            try {
                                # Auditoria Inicial
                                $clientIP = $request.RemoteEndPoint.Address.ToString()
                                $appNames = if ($payload.apps) { $payload.apps | ForEach-Object { $_.name } } else { "N/A" }
                                Write-AuditLog -RequesterIP $clientIP -TargetHost $target -Action "Instalação" -Apps $appNames
                            } catch {
                                Write-Host "[!] Falha na auditoria: $($_.Exception.Message)" -ForegroundColor Yellow
                            }

                            $ps = [powershell]::Create().AddScript($ExcecutorBlock).AddArgument($payload).AddArgument($installersPath).AddArgument($TargetStatus).AddArgument($Global:LocalIP)
                            $ps.Runspace = $newRunspace
                            $ps.BeginInvoke()

                            $resData = @{ status = "started"; target = $target } | ConvertTo-Json
                        }
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/upgrade" -and $request.HttpMethod -eq "POST") {
                        $reader = New-Object System.IO.StreamReader($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $payload = $body | ConvertFrom-Json

                        $target = if (-not $payload.isLocal) { $payload.targetHost } else { "localhost" }
                        $TargetStatus = Get-TargetStatus -Target $target

                        if ($TargetStatus["is_running"]) {
                            $resData = @{ status = "busy"; message = "Operacao em curso para este PC ($target)." } | ConvertTo-Json
                        } else {
                            $TargetStatus["auto_shutdown"] = [bool]$payload.autoShutdown

                            $newRunspace = [runspacefactory]::CreateRunspace()
                            $newRunspace.Open()
                            $newRunspace.SessionStateProxy.SetVariable("Status", $TargetStatus)
                            $newRunspace.SessionStateProxy.SetVariable("WingetActivationScript", $WingetActivationScript)

                            try {
                                # Auditoria Inicial
                                $clientIP = $request.RemoteEndPoint.Address.ToString()
                                Write-AuditLog -RequesterIP $clientIP -TargetHost $target -Action "Upgrade Winget" -Apps "Todas"
                            } catch {
                                Write-Host "[!] Falha na auditoria (Upgrade): $($_.Exception.Message)" -ForegroundColor Yellow
                            }

                            $ps = [powershell]::Create().AddScript($UpgradeBlock).AddArgument($payload).AddArgument($TargetStatus)
                            $ps.Runspace = $newRunspace
                            $ps.BeginInvoke()

                            $resData = @{ status = "started"; target = $target } | ConvertTo-Json
                        }
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/status" -and $request.HttpMethod -eq "GET") {
                        $target = $request.QueryString["target"]
                        if ($null -eq $target) { $target = "localhost" }
                        $TargetStatus = Get-TargetStatus -Target $target
                        $resData = $TargetStatus | ConvertTo-Json
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/library" -and $request.HttpMethod -eq "GET") {
                        $appsData = Get-Content -Path (Join-Path $scriptRoot "apps.json") -Raw | ConvertFrom-Json
                        $results = New-Object System.Collections.Generic.List[PSObject]
                        foreach ($app in $appsData.apps) {
                            if ($app.type -ne "local") { continue }
                            $localPath = Join-Path $installersPath $app.localFile
                            $localVer = "N/A"; $status = "missing"
                            if (Test-Path $localPath) {
                                try {
                                    $localVer = (Get-Item $localPath).VersionInfo.ProductVersion
                                    if (-not $localVer) { $localVer = "Existente" }
                                } catch { $localVer = "Erro" }
                                $status = "ok"
                            }
                            $results.Add(@{ id = $app.id; name = $app.name; localVersion = $localVer; status = $status; file = $app.localFile })
                        }
                        $resData = $results | ConvertTo-Json
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/library/check" -and $request.HttpMethod -eq "POST") {
                        $reader = New-Object System.IO.StreamReader($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $payload = $body | ConvertFrom-Json
                        $id = $payload.id
                        
                        $w = Get-Command winget.exe -ErrorAction SilentlyContinue
                        $exe = if ($w) { $w.Source } else { "winget" }
                        $raw = & $exe show $id --locale en-US --accept-source-agreements --disable-interactivity | Out-String
                        $vMatch = [regex]::Match($raw, "Version:\s*(\S+)")
                        $ver = if ($vMatch.Success) { $vMatch.Groups[1].Value } else { "N/A" }
                        
                        $resData = @{ id = $id; latestVersion = $ver } | ConvertTo-Json
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                    elseif ($path -eq "/api/library/sync" -and $request.HttpMethod -eq "POST") {
                        $reader = New-Object System.IO.StreamReader($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $payload = $body | ConvertFrom-Json
                        $id = $payload.id
                        $targetFile = $payload.file
                        
                        $tempPath = Join-Path $scriptRoot "temp_sync"
                        if (-not (Test-Path $tempPath)) { New-Item -ItemType Directory -Path $tempPath }
                        Remove-Item (Join-Path $tempPath "*") -Force -ErrorAction SilentlyContinue
                        $w = Get-Command winget.exe -ErrorAction SilentlyContinue
                        $exe = if ($w) { $w.Source } else { "winget" }
                        & $exe download --id $id -d $tempPath --accept-source-agreements --accept-package-agreements --locale en-US --architecture x64 --disable-interactivity
                        $downloadedFile = Get-ChildItem $tempPath | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        if ($downloadedFile) {
                            $destPath = Join-Path $installersPath $targetFile
                            Move-Item $downloadedFile.FullName $destPath -Force
                            $resData = @{ status = "success" } | ConvertTo-Json
                        } else {
                            $resData = @{ status = "error"; message = "Nao foi possivel descarregar o instalador." } | ConvertTo-Json
                        }
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($resData)
                        $response.ContentType = "application/json"
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                }
            }
            # Servir Arquivos Estaticos
            else {
                $filePath = if ($path -eq "/") { "index.html" } else { $path.Substring(1).Replace("/", "\") }
                $fullFilePath = Join-Path $scriptRoot $filePath

                if (Test-Path $fullFilePath -PathType Leaf) {
                    $extension = [System.IO.Path]::GetExtension($fullFilePath)
                    $contentType = switch ($extension) {
                        ".html" { "text/html" }
                        ".css"  { "text/css" }
                        ".js"   { "application/javascript" }
                        ".exe"  { "application/vnd.microsoft.portable-executable" }
                        ".msi"  { "application/x-msi" }
                        default { "application/octet-stream" }
                    }

                    $buffer = [System.IO.File]::ReadAllBytes($fullFilePath)
                    $response.Headers.Add("Access-Control-Allow-Origin", "*")
                    $response.ContentType = $contentType
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                } else {
                    $response.StatusCode = 404
                }
            }
        } catch {
            if ($path -notmatch "\.(css|js|png|jpg|ico)$") {
                Write-Host "[!] Aviso de Ligação ($path): $($_.Exception.Message)" -ForegroundColor Gray
            }
            try {
                if ($null -ne $response -and $response.OutputStream.CanWrite) {
                    $errData = @{ status = "error"; message = $_.Exception.Message } | ConvertTo-Json
                    $errBuffer = [System.Text.Encoding]::UTF8.GetBytes($errData)
                    $response.StatusCode = 500
                    $response.ContentType = "application/json"
                    $response.OutputStream.Write($errBuffer, 0, $errBuffer.Length)
                }
            } catch {}
        } finally {
            if ($null -ne $response) {
                try { $response.OutputStream.Close() } catch {}
                try { $response.Close() } catch {}
            }
        }
    }
} catch {
    Write-Host ""
    Write-Host "ERRO CRITICO AO INICIAR O SERVIDOR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor White
    Write-Host ""
    Write-Host "DICA: Certifique-se de que esta a correr como Administrador." -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair..."
}
finally {
    if ($null -ne $listener) {
        try { $listener.Stop() } catch {}
        try { $listener.Close() } catch {}
    }
}
