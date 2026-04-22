# Histórico de Versões - MDT Lite 📝

Todas as alterações significativas serão registadas neste documento para manter um histórico transparente e profissional.

## [v1.2.1] - 2026-04-22 (Atual)
### Corrigido
- **Design Review**: Corrigido o nome do ficheiro para a versão Portuguesa (`pt-BR`).
- **DWG TrueView 2027**: Verificada a integridade da pasta e do ficheiro `Setup.exe`.

## [v1.2.0] - 2026-04-22
### Adicionado
- **Categorias**: Introduzidas as categorias "Segurança" 🛡️ e "Periféricos & Scanners" 🖨️.
- **Segurança**: Adicionado Check Point Endpoint Antivirus.
- **Periféricos**: Adicionados Scanners Epson (DS-520, DS-530, DS-570W, DS-580W) e HP Click.
- **Produtividade**: Adicionadas versões legadas e atual de GstarCAD (2017, 2018, 2026).
- **Utilitários**: Adicionado Chamador BU.

## [v1.1.1] - 2026-04-22
### Alterado
- **Interface**: Opção "Todas" movida para o final da barra de categorias a pedido do utilizador.

## [v1.1.0] - 2026-04-22
### Adicionado
- **Suporte Winget**: O motor de instalação (`Start-MDT.ps1`) agora suporta nativamente o `winget` para instalações locais e remotas.
- **ArcGIS Survey123 Connect**: Migrado para modo Winget (ID `9PMST5C0DLST`), permitindo instalação direta sem abrir a Loja Microsoft.

## [v1.0.2] - 2026-04-22
### Adicionado
- Nova aplicação: **ArcGIS Survey123 Connect** adicionada à dashboard.
- Atualização do roadmap (`plano.md`) e histórico de versões.

## [v1.0.1] - 2026-04-22
### Adicionado
- Criado ficheiro `plano.md` para gestão de roadmap.
- Criado ficheiro `versions.md` para controlo de histórico.
- Configuração de ambiente Git com `.gitignore` profissional.
- Sincronização inicial com repositório remoto.

## [v1.0.0] - 2026-04-20
### Base Inicial
- Dashboard funcional em HTML5/CSS3/JS.
- sistema de autenticação via modal.
- Gestor de biblioteca para instaladores locais.
- Suporte a instalações remotas via PowerShell WinRM.
