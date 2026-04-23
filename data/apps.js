export const appCategories = [
  { id: 'browsers', name: 'Navegadores', icon: '🌐' },
  { id: 'utilities', name: 'Utilitários', icon: '🛠️' },
  { id: 'office', name: 'Documentos & PDF', icon: '📄' },
  { id: 'pro', name: 'Profissional & Design', icon: '📐' },
  { id: 'gov', name: 'Governo & Autenticação', icon: '⚖️' }
];

export const apps = [
  // Browsers
  {
    id: 'Google.Chrome',
    name: 'Google Chrome',
    category: 'browsers',
    description: 'Navegador rápido e seguro da Google.',
    type: 'winget'
  },
  {
    id: 'Mozilla.Firefox',
    name: 'Mozilla Firefox',
    category: 'browsers',
    description: 'Navegador focado em privacidade.',
    type: 'winget'
  },
  
  // Utilities
  {
    id: 'RARLab.WinRAR',
    name: 'WinRAR',
    category: 'utilities',
    description: 'Compressor e descompressor de arquivos.',
    type: 'winget'
  },
  {
    id: '7zip.7zip',
    name: '7-Zip',
    category: 'utilities',
    description: 'Alternativa open-source para compressão.',
    type: 'winget'
  },
  {
    id: 'VideoLAN.VLC',
    name: 'VLC Media Player',
    category: 'utilities',
    description: 'Reprodutor multimédia universal.',
    type: 'winget'
  },

  // Office / PDF
  {
    id: 'Adobe.Acrobat.Reader.64-bit',
    name: 'Adobe Reader (64-bit)',
    category: 'office',
    description: 'Leitor de PDF padrão da Adobe.',
    type: 'winget'
  },
  {
    id: 'geeksoftwareGmbH.PDF24Creator',
    name: 'PDF24 Creator',
    category: 'office',
    description: 'Conjunto de ferramentas PDF completo.',
    type: 'winget',
    overrideArgs: '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-'
  },

  // Professional / Design
  {
    id: 'Google.EarthPro',
    name: 'Google Earth Pro',
    category: 'pro',
    description: 'Exploração do mundo em 3D.',
    type: 'winget'
  },
  {
    id: 'Autodesk.DesignReview',
    name: 'Autodesk Design Review',
    category: 'pro',
    description: 'Visualizador de arquivos DWF e markups.',
    type: 'winget'
  },
  {
    id: 'Microsoft.PowerBI',
    name: 'Power BI Desktop',
    category: 'pro',
    description: 'Ferramenta de análise de negócios.',
    type: 'winget'
  },
  {
    id: 'autodesk.dwgtrueview',
    name: 'DWG TrueView',
    category: 'pro',
    description: 'Visualizador oficial da Autodesk para DWG.',
    type: 'local',
    localFile: 'dwgtrueview_setup.exe',
    silentArgs: '/quiet /norestart'
  },

  // Gov
  {
    id: 'ama.autenticacaogov',
    name: 'Autenticação.gov',
    category: 'gov',
    description: 'Aplicação para Cartão de Cidadão e Chave Móvel Digital.',
    type: 'local',
    localFile: 'autenticacaogov_setup.exe',
    silentArgs: '/S'
  },
  {
    id: 'ama.pluginautenticacao',
    name: 'Plugin Autenticação.gov',
    category: 'gov',
    description: 'Plugin de navegadores para autenticação GOV.',
    type: 'local',
    localFile: 'plugin_autenticacao_setup.exe',
    silentArgs: '/S'
  }
];
