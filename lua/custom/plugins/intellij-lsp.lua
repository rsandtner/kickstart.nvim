-- JetBrains' official IntelliJ LSP client (Java + Kotlin from one `intellij-server`).
-- Pre-alpha: https://github.com/JetBrains/intellij-lsp.nvim  (:help intellij-lsp)
--
-- First start downloads the server bundle and asks for region, EULA and usage statistics.
-- The server needs a license: 30-day trial, then IntelliJ IDEA Ultimate (:IntellijLspLicense).
-- Must load at startup (not on FileType), so opening nvim in a project root starts the import.
--
-- Run/debug (needs nvim-dap; the plugin configures it itself): cursor in a class with `main`,
-- <leader>rr run, <leader>rd debug, <leader>rl run the code lens on this line, <leader>b breakpoint.

vim.pack.add {
  'https://github.com/mfussenegger/nvim-dap',
  'https://github.com/JetBrains/intellij-lsp.nvim',
}

require('intellij-lsp').setup {
  -- default_sdk = '/Library/Java/JavaVirtualMachines/<jdk>/Contents/Home', -- only for projects without their own JDK
  -- jvm_args = { '-Xmx4g' },
  -- format_on_save = true,
}

-- Workaround: the server's launch classpath (intellij.java.resolveLaunch) also contains modules that
-- a dependency only uses with <scope>test</scope>, e.g. idp-sek/mail: service -> test-common (test),
-- so test-common's TestConfig ends up in the running app. Maven leaves them out. Until the server
-- fixes it, drop the output dirs of test-support modules (test-*, *-test, *-tests, *-test-*).
local function is_test_support_output(path)
  local module = path:match '([^/]+)/target/classes/?$' or path:match '([^/]+)/build/classes/[^/]+/main/?$'
  if not module then return false end
  return module:match '^tests?[-_]' or module:match '[-_]tests?$' or module:match '[-_]tests?[-_]'
end

require('dap').listeners.on_config['intellij-test-scope-fix'] = function(config)
  if config.type ~= 'intellij_jvm' or not config.classPaths then return config end
  config = vim.deepcopy(config)
  local kept, dropped = {}, {}
  for _, path in ipairs(config.classPaths) do
    table.insert(is_test_support_output(path) and dropped or kept, path)
  end
  if #dropped > 0 then
    config.classPaths = kept
    vim.notify('IntelliJ run: removed test-scoped classpath entries:\n  ' .. table.concat(dropped, '\n  '))
  end
  return config
end
