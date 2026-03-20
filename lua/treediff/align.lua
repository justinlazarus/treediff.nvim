--- Anchor-based line alignment with filler padding.
--- Takes anchor pairs (lhs_line, rhs_line) from the Rust diff engine
--- and produces padded line arrays of equal length for side-by-side display.
local M = {}

--- Compute the longest increasing subsequence of rhs values.
--- Returns a set of indices (into the anchors array) to keep.
--- @param anchors table[]  sorted by lhs_line, each {lhs_line, rhs_line}
--- @return table  set of 1-indexed positions to keep
local function lis_indices(anchors)
  local n = #anchors
  if n == 0 then return {} end

  -- tails[i] = smallest rhs value ending an increasing subsequence of length i
  local tails = {}  -- values
  local tail_idx = {}  -- corresponding anchor indices
  local parent = {}  -- backtrack: parent[i] = index of previous element in LIS

  local len = 0
  for i = 1, n do
    local val = anchors[i][2]
    -- Binary search for the position to insert val
    local lo, hi = 1, len
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      if tails[mid] < val then
        lo = mid + 1
      else
        hi = mid - 1
      end
    end
    -- lo is the insertion position
    tails[lo] = val
    tail_idx[lo] = i
    parent[i] = lo > 1 and tail_idx[lo - 1] or nil
    if lo > len then
      len = lo
    end
  end

  -- Backtrack to find the actual LIS indices
  local keep = {}
  local k = tail_idx[len]
  while k do
    keep[k] = true
    k = parent[k]
  end
  return keep
end

--- Build padded line arrays from original lines and anchor pairs.
--- @param lhs_lines string[]  original LHS lines (1-indexed)
--- @param rhs_lines string[]  original RHS lines (1-indexed)
--- @param anchors table[]  array of {lhs_line, rhs_line} (0-indexed from Rust)
--- @return table  { lhs_padded = {...}, rhs_padded = {...} }
---   Each entry: { text = string, orig = number|nil }  (orig is 0-indexed file line, nil for fillers)
function M.build(lhs_lines, rhs_lines, anchors)
  if not anchors or #anchors == 0 then
    -- No anchors: pad shorter side entirely
    local lhs_padded = {}
    local rhs_padded = {}
    local max_len = math.max(#lhs_lines, #rhs_lines)
    for i = 1, max_len do
      lhs_padded[i] = { text = lhs_lines[i] or "", orig = lhs_lines[i] and (i - 1) or nil }
      rhs_padded[i] = { text = rhs_lines[i] or "", orig = rhs_lines[i] and (i - 1) or nil }
    end
    return { lhs_padded = lhs_padded, rhs_padded = rhs_padded }
  end

  -- Step 1: Sort anchors by lhs_line (they come sorted from BTreeSet but be safe)
  local sorted = {}
  for _, a in ipairs(anchors) do
    -- anchors from Rust are [lhs_line, rhs_line], 0-indexed
    sorted[#sorted + 1] = { a[1], a[2] }
  end
  table.sort(sorted, function(a, b) return a[1] < b[1] end)

  -- Step 2: Filter to enforce monotonicity on both sides (LIS on rhs values)
  local keep = lis_indices(sorted)
  local mono = {}
  for i = 1, #sorted do
    if keep[i] then
      mono[#mono + 1] = sorted[i]
    end
  end

  -- Step 3: Walk anchors and build padded arrays
  local lhs_padded = {}
  local rhs_padded = {}

  local function add_gap(l_start, l_end, r_start, r_end)
    -- l_start..l_end and r_start..r_end are 0-indexed inclusive ranges of lines to emit
    local l_count = l_end - l_start + 1
    local r_count = r_end - r_start + 1
    if l_count < 0 then l_count = 0 end
    if r_count < 0 then r_count = 0 end
    local max_count = math.max(l_count, r_count)

    for i = 0, max_count - 1 do
      local l_idx = l_start + i
      local r_idx = r_start + i
      if i < l_count then
        lhs_padded[#lhs_padded + 1] = { text = lhs_lines[l_idx + 1] or "", orig = l_idx }
      else
        lhs_padded[#lhs_padded + 1] = { text = "", orig = nil }
      end
      if i < r_count then
        rhs_padded[#rhs_padded + 1] = { text = rhs_lines[r_idx + 1] or "", orig = r_idx }
      else
        rhs_padded[#rhs_padded + 1] = { text = "", orig = nil }
      end
    end
  end

  -- Pre-first-anchor gap
  if #mono > 0 then
    local first_l = mono[1][1]  -- 0-indexed
    local first_r = mono[1][2]
    if first_l > 0 or first_r > 0 then
      add_gap(0, first_l - 1, 0, first_r - 1)
    end
  end

  -- Emit each anchor and gaps between consecutive anchors
  for i, anchor in ipairs(mono) do
    -- Emit the anchor line itself
    lhs_padded[#lhs_padded + 1] = { text = lhs_lines[anchor[1] + 1] or "", orig = anchor[1] }
    rhs_padded[#rhs_padded + 1] = { text = rhs_lines[anchor[2] + 1] or "", orig = anchor[2] }

    -- Gap between this anchor and the next
    if i < #mono then
      local next_anchor = mono[i + 1]
      local l_gap_start = anchor[1] + 1
      local l_gap_end = next_anchor[1] - 1
      local r_gap_start = anchor[2] + 1
      local r_gap_end = next_anchor[2] - 1
      add_gap(l_gap_start, l_gap_end, r_gap_start, r_gap_end)
    end
  end

  -- Post-last-anchor gap
  if #mono > 0 then
    local last_l = mono[#mono][1]
    local last_r = mono[#mono][2]
    local l_remaining = #lhs_lines - 1 - last_l
    local r_remaining = #rhs_lines - 1 - last_r
    if l_remaining > 0 or r_remaining > 0 then
      add_gap(last_l + 1, #lhs_lines - 1, last_r + 1, #rhs_lines - 1)
    end
  end

  return { lhs_padded = lhs_padded, rhs_padded = rhs_padded }
end

--- Build coordinate translation maps from a padded array.
--- @param padded table[]  array of { text, orig } entries
--- @return table  { buf_to_file = {[1-indexed_buf_row] = 0-indexed_file_line}, file_to_buf = {[0-indexed_file_line] = 1-indexed_buf_row} }
function M.build_maps(padded)
  local buf_to_file = {}
  local file_to_buf = {}
  for i, entry in ipairs(padded) do
    if entry.orig then
      buf_to_file[i] = entry.orig
      file_to_buf[entry.orig] = i
    end
  end
  return { buf_to_file = buf_to_file, file_to_buf = file_to_buf }
end

return M
