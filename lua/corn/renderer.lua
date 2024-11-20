local utils = require 'corn.utils'
local config = require 'corn.config'

local M = {}

M.bufnr = nil
M.ns = nil
M.win = nil
M.state = true -- user controlled hiding toggle

M.cache = {}

M.update_cache = function()
  M.cache = utils.update_cached_diagnostic()
end

M.make_win_cfg = function(width, height, position, xoff, yoff)
  local cfg = {
    relative = "editor",


    width = width <= 0 and 1 or width,
    height = height <= 0 and 1 or height,
    focusable = false,
    style = 'minimal',

    border = config.opts.border_style,
  }


  cfg.anchor = "NE"

  local rline, _ = utils.get_cursor_relative_pos()
  local ui_config = vim.api.nvim_list_uis()[1]
  local win_y, _ = unpack(vim.api.nvim_win_get_position(0));

  if (win_y + rline) <= height then
    cfg.col = ui_config.width
    cfg.row = ui_config.height - height - 5 -- 2 for the border, then 3 for command line, statusline, buffer name
  else
    cfg.col = ui_config.width
    cfg.row = 0
  end

  return cfg
end

M.setup = function()
  M.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("undolevels", -1, { buf = M.bufnr })

  M.ns = vim.api.nvim_create_namespace('corn')
end

M.toggle = function(state)
  if state == nil then
    M.state = not M.state
  else
    if state == M.state then return end
    M.state = state
  end

  config.opts.on_toggle(M.state)
end

local assemble_lines = function(items, config)
  local item_lines = {}
  local max_item_lines_count = vim.api.nvim_win_get_height(0)
  local longest_line_len = 1
  local hl_segments = {}

  function insert_hl_segment(hl, lnum, col, end_col)
    table.insert(hl_segments, {
      hl_group = hl,
      lnum = lnum,
      col = col,
      end_col = end_col,
    })
  end

  -- assemble item lines
  for i, item in ipairs(items) do
    item = config.opts.item_preprocess_func(item)

    -- splitting messages by \n and adding each as a separate line
    local message_lines = vim.fn.split(item.message, '\n')
    for j, message_line in ipairs(message_lines) do
      local line = {}
      local line_lengh = 0

      function append_to_line(text, hl)
        insert_hl_segment(hl, #item_lines, line_lengh, line_lengh + #text)
        line[#line + 1] = text
        line_lengh = line_lengh + #text + 1
        -- line = line .. text
      end

      -- icon on first message_line, put and ' ' on the rest
      if j == 1 then
        append_to_line(utils.diag_severity_to_icon(item.severity), utils.diag_severity_to_hl_group(item.severity))
      else
        append_to_line('', utils.diag_severity_to_hl_group(item.severity))
      end
      -- message_line content
      append_to_line(message_line, utils.diag_severity_to_hl_group(item.severity))
      -- extra info on the last line only
      if j == #message_lines then
        append_to_line((item.code or '') .. '', 'Folded')
        append_to_line((item.source or ''), 'Comment')
        if config.opts.scope == 'line' then
          append_to_line(':' .. item.col, 'Comment')
        elseif config.opts.scope == 'file' then
          append_to_line(item.lnum + 1 .. ':' .. item.col, 'Comment')
        end
      end

      -- record the longest line length for later use
      local s_line = table.concat(line, ' ')
      if #s_line > longest_line_len then longest_line_len = #s_line end
      -- insert the entire line
      table.insert(item_lines, s_line)

      -- vertical truncation
      if #s_line == max_item_lines_count - 1 then
        line = {}
        -- local remaining_lines_count = item_lines_that_would_have_been_rendererd_if_there_was_enough_space_count - #item_lines
        append_to_line("... and more", "Folded")
        table.insert(item_lines, table.concat(line, ' '))
        goto break_assemble_item_lines
      end
    end
  end
  ::break_assemble_item_lines::

  return item_lines, hl_segments, longest_line_len
end

M.render_from_cache = function()
  return M.render(M.cache)
end

M.filter_diags = function(diags)
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local line = cursor_pos[1] - 1 -- Subtract 1 to convert to 0-based indexing
  local col = cursor_pos[2]

  local current_pos_diags = {}
  for _, diag in ipairs(diags) do
    local should_insert = false
    local in_line = diag.lnum <= line and line <= (diag.end_lnum or diag.lnum)
    if config.opts.scope == 'line' then
      should_insert = in_line
    elseif config.opts.scope == 'cursor' then
      if diag.end_col and diag.end_lnum then
        if diag.lnum == diag.end_lnum then
          should_insert = diag.lnum == line and diag.col <= col and col <= diag.end_col
        else
          should_insert = ((diag.lnum == line and diag.col <= col) -- On the first line, should be after the col
            or (diag.lnum < line and line < diag.end_lnum)         -- Between lines, we always show it
            or (diag.end_lnum == line and col <= diag.end_col)     -- On the last line, only before the end
          )
        end
      else
        should_insert = diag.lnum == line and (diag.col <= col and (diag.end_col or diag.col) >= col)
      end
    end

    if should_insert then
      table.insert(current_pos_diags, diag)
    end
  end

  return current_pos_diags
end

M.render = function(items)
  -- sorting
  local xoff = 0
  local yoff = 0
  local position = "NE"

  local current_buf = vim.api.nvim_get_current_buf()
  local local_diags = items[current_buf] or {}
  items = M.filter_diags(local_diags)

  -- calculate visibility
  if not (
      -- user didnt toggle off
        M.state
        -- there are items
        and #items > 0
        -- can fit in the width and height of the parent window
        -- and vim.api.nvim_win_get_width(0) >= longest_line_len + 2 -- because of the borders
        -- vim mode isnt blacklisted
        and vim.tbl_contains(config.opts.blacklisted_modes, vim.api.nvim_get_mode().mode) == false
      )
  then
    if M.win then
      vim.api.nvim_win_hide(M.win)
      M.win = nil
    end
    return
  end

  local item_lines, hl_segments, longest_line_len = assemble_lines(items, config)

  if not M.win then
    M.win = vim.api.nvim_open_win(M.bufnr, false, M.make_win_cfg(longest_line_len, #item_lines, position, xoff, yoff))
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, item_lines)
  elseif M.win then
    vim.api.nvim_win_set_config(M.win, M.make_win_cfg(longest_line_len, #item_lines, position, xoff, yoff))
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, item_lines)
  end

  -- apply highlights
  for i, hl_segment in ipairs(hl_segments) do
    vim.api.nvim_buf_add_highlight(M.bufnr, M.ns, hl_segment.hl_group, hl_segment.lnum, hl_segment.col,
      hl_segment.end_col)
  end
end

return M
