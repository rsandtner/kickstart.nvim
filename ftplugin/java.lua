local cache_vars = {}

local features = {
  debugger = true,
}

local function get_jdtls_paths()
  if cache_vars.paths then return cache_vars.paths end

  local path = {}

  path.data_dir = vim.fn.stdpath 'cache' .. '/nvim-jdtls'

  -- Use direct paths to Mason packages
  local mason_path = vim.fn.stdpath 'data' .. '/mason/packages'

  local jdtls_install = mason_path .. '/jdtls'
  path.java_agent = jdtls_install .. '/lombok.jar'
  path.launcher_jar = vim.fn.glob(jdtls_install .. '/plugins/org.eclipse.equinox.launcher_*.jar')

  if vim.fn.has 'mac' == 1 then
    path.platform_config = jdtls_install .. '/config_mac'
  elseif vim.fn.has 'unix' == 1 then
    path.platform_config = jdtls_install .. '/config_linux'
  elseif vim.fn.has 'win32' == 1 then
    path.platform_config = jdtls_install .. '/config_win'
  end

  path.bundles = {}

  ---
  -- Include java-test bundle if present
  ---
  local java_test_path = mason_path .. '/java-test'
  local java_test_bundle = vim.split(vim.fn.glob(java_test_path .. '/extension/server/*.jar'), '\n')

  if java_test_bundle[1] ~= '' then vim.list_extend(path.bundles, java_test_bundle) end

  ---
  -- Include java-debug-adapter bundle if present
  ---
  local java_debug_path = mason_path .. '/java-debug-adapter'
  local java_debug_bundle = vim.split(vim.fn.glob(java_debug_path .. '/extension/server/com.microsoft.java.debug.plugin-*.jar'), '\n')

  if java_debug_bundle[1] ~= '' then vim.list_extend(path.bundles, java_debug_bundle) end

  ---
  -- Useful if you're starting jdtls with a Java version that's
  -- different from the one the project uses.
  ---
  path.runtimes = {
    -- Note: the field `name` must be a valid `ExecutionEnvironment`,
    -- you can find the list here:
    -- https://github.com/eclipse/eclipse.jdt.ls/wiki/Running-the-JAVA-LS-server-from-the-command-line#initialize-request
    --
    -- Example with sdkman: https://sdkman.io
    -- {
    --   name = 'JavaSE-17',
    --   path = vim.fn.expand('~/.sdkman/candidates/java/17.0.6-tem'),
    -- },
    -- {
    --   name = 'JavaSE-21',
    --   path = vim.fn.expand('~/.sdkman/candidates/java/21.0.1-tem'),
    -- },
  }

  cache_vars.paths = path

  return path
end

local function enable_debugger(bufnr)
  -- Check if nvim-dap is available
  local dap_ok, _ = pcall(require, 'dap')
  if not dap_ok then
    vim.notify('nvim-dap is not installed. Debugger features will not be available.', vim.log.levels.WARN)
    return
  end

  require('jdtls').setup_dap { hotcodereplace = 'auto' }
  require('jdtls.dap').setup_dap_main_class_configs()

  vim.keymap.set('n', '<leader>dt', "<cmd>lua require('jdtls').test_nearest_method()<cr>", { buffer = bufnr, desc = 'Debug: Test Nearest Method' })
  vim.keymap.set('n', '<leader>dT', "<cmd>lua require('jdtls').test_class()<cr>", { buffer = bufnr, desc = 'Debug: Test Class' })
end

-- Check if jdtls is available
local status, jdtls = pcall(require, 'jdtls')
if not status then return end

local path = get_jdtls_paths()
local data_dir = path.data_dir .. '/' .. vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')

if cache_vars.capabilities == nil then
  jdtls.extendedClientCapabilities.resolveAdditionalTextEditsSupport = true

  local ok_cmp, cmp_lsp = pcall(require, 'cmp_nvim_lsp')
  local ok_blink, blink = pcall(require, 'blink.cmp')

  cache_vars.capabilities = vim.tbl_deep_extend(
    'force',
    vim.lsp.protocol.make_client_capabilities(),
    ok_blink and blink.get_lsp_capabilities() or {},
    ok_cmp and cmp_lsp.default_capabilities() or {}
  )
end

-- The command that starts the language server
-- See: https://github.com/eclipse/eclipse.jdt.ls#running-from-the-command-line
local cmd = {
  'java',

  '-Declipse.application=org.eclipse.jdt.ls.core.id1',
  '-Dosgi.bundles.defaultStartLevel=4',
  '-Declipse.product=org.eclipse.jdt.ls.core.product',
  '-Dlog.protocol=true',
  '-Dlog.level=ALL',
  '-javaagent:' .. path.java_agent,
  '-Xms1g',
  '--add-modules=ALL-SYSTEM',
  '--add-opens',
  'java.base/java.util=ALL-UNNAMED',
  '--add-opens',
  'java.base/java.lang=ALL-UNNAMED',

  '-jar',
  path.launcher_jar,

  '-configuration',
  path.platform_config,

  '-data',
  data_dir,
}

local lsp_settings = {
  java = {
    eclipse = {
      downloadSources = true,
    },
    configuration = {
      updateBuildConfiguration = 'automatic',
      runtimes = path.runtimes,
    },
    maven = {
      downloadSources = true,
    },
    references = {
      includeDecompiledSources = true,
    },
    inlayHints = {
      parameterNames = {
        enabled = 'all', -- literals, all, none
      },
    },
    format = {
      enabled = true,
    },
    signatureHelp = {
      enabled = true,
    },
    contentProvider = {
      preferred = 'fernflower',
    },
    completion = {
      favoriteStaticMembers = {
        'org.hamcrest.MatcherAssert.assertThat',
        'org.hamcrest.Matchers.*',
        'org.hamcrest.CoreMatchers.*',
        'org.junit.jupiter.api.Assertions.*',
        'java.util.Objects.requireNonNull',
        'java.util.Objects.requireNonNullElse',
        'org.mockito.Mockito.*',
      },
    },
    sources = {
      organizeImports = {
        starThreshold = 9999,
        staticStarThreshold = 9999,
      },
    },
    codeGeneration = {
      toString = {
        template = '${object.className}{${member.name()}=${member.value}, ${otherMembers}}',
      },
      useBlocks = true,
    },
  },
}

local function on_attach(client, bufnr)
  -- Enable debugger if configured
  if features.debugger then enable_debugger(bufnr) end

  -- Java-specific keymaps (keeping your leader-based style)
  local opts = { buffer = bufnr }
  vim.keymap.set('n', '<leader>co', "<cmd>lua require('jdtls').organize_imports()<cr>", { buffer = bufnr, desc = 'Organize Imports' })
  vim.keymap.set('n', '<leader>crv', "<cmd>lua require('jdtls').extract_variable()<cr>", { buffer = bufnr, desc = 'Extract Variable' })
  vim.keymap.set('v', '<leader>crv', "<esc><cmd>lua require('jdtls').extract_variable(true)<cr>", { buffer = bufnr, desc = 'Extract Variable' })
  vim.keymap.set('n', '<leader>crc', "<cmd>lua require('jdtls').extract_constant()<cr>", { buffer = bufnr, desc = 'Extract Constant' })
  vim.keymap.set('v', '<leader>crc', "<esc><cmd>lua require('jdtls').extract_constant(true)<cr>", { buffer = bufnr, desc = 'Extract Constant' })
  vim.keymap.set('v', '<leader>crm', "<esc><cmd>lua require('jdtls').extract_method(true)<cr>", { buffer = bufnr, desc = 'Extract Method' })
end

-- This starts a new client & server,
-- or attaches to an existing client & server depending on the `root_dir`.
jdtls.start_or_attach {
  cmd = cmd,
  settings = lsp_settings,
  on_attach = on_attach,
  capabilities = cache_vars.capabilities,
  root_dir = vim.fn.getcwd(),
  flags = {
    allow_incremental_sync = true,
  },
  init_options = {
    bundles = path.bundles,
    extendedClientCapabilities = jdtls.extendedClientCapabilities,
  },
}
