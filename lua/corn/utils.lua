local M = {}

require 'corn.types'
local config = require 'corn.config'


M.update_cached_diagnostic = function()
  local ok, diagnostics = pcall(vim.diagnostic.get, nil)

  if not ok then
    error('Failed to get diagnostic: ' .. diagnostics)
    return
  end

  if type(diagnostics) ~= "table" then
    error('Diagnostic is not a table ' .. diagnostics)
    return
  end

  local mapped_diags = {}
  for _, diag in pairs(diagnostics) do
    if not mapped_diags[diag.bufnr] then
      mapped_diags[diag.bufnr] = {}
    end
    table.insert(mapped_diags[diag.bufnr], diag)
  end

  ok, mapped_diags = pcall(function()
    for _, v in pairs(mapped_diags) do
      M.sort_diagnostics(v)
    end
    return mapped_diags
  end)

  if not ok then
    error('Failed to sort diagnostics ' .. mapped_diags)
    return
  end

  return mapped_diags
end

M.sort_diagnostics = function(items)
  if config.opts.sort_method == 'column' then
    table.sort(items, function(a, b) return a.col < b.col end)
  elseif config.opts.sort_method == 'column_reverse' then
    table.sort(items, function(a, b) return a.col > b.col end)
  elseif config.opts.sort_method == 'severity' then
    -- NOTE not needed since items already come ordered this way
    -- table.sort(items, function(a, b) return a.severity < b.severity end)
  elseif config.opts.sort_method == 'severity_reverse' then
    table.sort(items, function(a, b) return a.severity > b.severity end)
  elseif config.opts.sort_method == 'line_number' then
    table.sort(items, function(a, b) return a.lnum < b.lnum end)
  elseif config.opts.sort_method == 'line_number_reverse' then
    table.sort(items, function(a, b) return a.lnum > b.lnum end)
  end

  return items
end

-- M.get_diagnostic_items = function()
--   -- local lnum = vim.fn.line('.') - 1
--   --
--   -- local diagnostics = {}
--   -- if config.opts.scope == 'line' then
--   --   diagnostics = vim.diagnostic.get(0, { lnum = lnum })
--   -- elseif config.opts.scope == 'file' then
--   --   diagnostics = vim.diagnostic.get(0, {})
--   -- end
--   local diagnostics = vim.diagnostic.get(nil, {})
--
--   local items = {}
--
--   for _, diag in ipairs(diagnostics) do
--     -- skip blacklisted severities
--     if vim.tbl_contains(config.opts.blacklisted_severities, diag.severity) then
--       goto continue
--     end
--
--     ---@type Corn.Item
--     local item = {
--       -- non-optional keys
--       message = diag.message,
--       col = diag.col,
--       lnum = diag.lnum,
--       end_lnum = diag.end_lnum,
--       end_col = diag.end_col,
--
--       -- optional keys
--       severity = diag.severity or vim.diagnostic.severity.ERROR,
--       source = diag.source or '',
--       code = diag.code or '',
--     }
--
--     table.insert(items, item)
--
--     ::continue::
--   end
--
--   return items
-- end

M.diag_severity_to_hl_group = function(severity)
  local look_up = {
    [vim.diagnostic.severity.ERROR] = config.opts.highlights.error,
    [vim.diagnostic.severity.WARN] = config.opts.highlights.warn,
    [vim.diagnostic.severity.INFO] = config.opts.highlights.info,
    [vim.diagnostic.severity.HINT] = config.opts.highlights.hint,
  }

  return look_up[severity] or ''
end

M.diag_severity_to_icon = function(severity)
  local look_up = {
    [vim.diagnostic.severity.ERROR] = config.opts.icons.error,
    [vim.diagnostic.severity.WARN] = config.opts.icons.warn,
    [vim.diagnostic.severity.INFO] = config.opts.icons.info,
    [vim.diagnostic.severity.HINT] = config.opts.icons.hint,
  }

  return look_up[severity] or '-'
end

M.get_cursor_relative_pos = function()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor_pos[1]
  local cursor_col = cursor_pos[2]

  local cursor_relative_line = cursor_line - vim.fn.line('w0')
  local cursor_relative_col = cursor_col - vim.fn.col('w0')

  return cursor_relative_line, cursor_relative_col
end

return M
