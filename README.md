# MDT Lite - Gerenciador de Instalação Automática

Este projeto permite selecionar e instalar diversas aplicações profissionais em série e de forma silenciosa.

## Como Usar

1. **Adicionar Instaladores Locais**:
   - Para aplicações que não estão no `winget` (como Autenticação.gov ou DWG TrueView), coloque os arquivos `.exe` na pasta `installers/`.
   - Certifique-se de que os nomes dos arquivos correspondem aos definidos em `data/apps.js`.

2. **Iniciar a Interface**:
   - Como este projeto usa módulos ES, ele precisa ser servido por um servidor (não abra o `index.html` diretamente).
   - Comando recomendado: `npx serve .` ou use a extensão "Live Server" no VS Code.

3. **Gerar e Rodar o Script**:
   - Selecione os aplicativos desejados na dashboard.
   - Clique em **"Gerar Script de Instalação"**.
   - Copie o código gerado.
   - Abra um terminal **PowerShell como Administrador**.
   - Cole o código e pressione Enter.

## Estrutura de Arquivos

- `index.html`, `style.css`, `app.js`: Interface e lógica da dashboard.
- `data/apps.js`: Lista de aplicações e seus IDs (Pode adicionar mais aqui!).
- `installers/`: Pasta para os instaladores offline.
