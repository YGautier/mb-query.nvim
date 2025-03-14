local M = {}

--- @return string?
local function get_env(var)
	return os.getenv(var)
end

M.config = {
	metabase_url = get_env("METABASE__URL"),
	metabase_token = get_env("METABASE__TOKEN"),
	database = 2,
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	if not M.config.metabase_url then
		vim.notify(
			"Warning: Metabase URL should be declared as the 'METABASE__URL' environment variable.",
			vim.log.levels.WARN
		)
	end

	if not M.config.metabase_token then
		vim.notify(
			"Warning: Metabase TOKEN should be declared as the 'METABASE__TOKEN' environment variable.",
			vim.log.levels.WARN
		)
	end
	vim.api.nvim_create_user_command("RunBufferQuery", M.run_buf_query, {})
end

--- @return boolean
local function is_buf_sql()
	local file_extension = vim.bo.filetype
	return file_extension == "sql"
end

--- @return string
local function get_buf_sql()
	if not is_buf_sql() then
		error("expected SQL file buffer")
	end
	return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

--- @param database integer
--- @param query string
--- @param url string
--- @param token string
--- @return string[]
local function make_curl_cmd(database, query, url, token)
	local payload = vim.json.encode({ database = database, native = { query = query }, type = "native" })
	return {
		"curl",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		string.format("X-API-KEY: %s", token),
		"-d",
		payload,
		string.format("%sapi/dataset", url),
	}
end

--- @param raw_data string?
--- @return integer[]
--- @return string[][]
local function cast_as_metabase_column_data(raw_data)
	if raw_data == nil then
		error("expected a string, received nil", 2)
	end
	local data = vim.json.decode(raw_data).data
	local cols = data.cols
	local rows = data.rows
	if cols == nil or rows == nil then
		error("missing fields data.rows and data.cols in the input data", 2)
	end

	local widths = {}
	local lines = {}

	-- Iterate over columns data
	local line = {}
	for col_idx, col_data in ipairs(cols) do
		local col_name = col_data.display_name
		if type(col_name) ~= "string" then
			error(
				string.format(
					"wrong type for field data.cols.%d.display_name, expected 'string', received '%s'",
					col_idx,
					type(col_name)
				),
				2
			)
		end
		widths[col_idx] = #col_name
		table.insert(line, col_name)
	end
	table.insert(lines, line)

	-- Iterate over columns data
	for _, row in ipairs(rows) do
		line = {}
		for col_idx, cell in ipairs(row) do
			local cell_str = tostring(cell)
			widths[col_idx] = math.max(widths[col_idx], #cell_str)
			table.insert(line, cell_str)
		end
		table.insert(lines, line)
	end

	return widths, lines
end

--- @param lines string[][]
--- @param widths integer[]
--- @return string[]
local function make_markdown_table(lines, widths)
	local total_width = 0
	local nb_columns = 0
	for _, width in ipairs(widths) do
		total_width = total_width + width
		nb_columns = nb_columns + 1
	end

	local md_table = {}
	local col_sep = " | "

	for row_idx, row in ipairs(lines) do
		local line = {}
		for col_idx, cell in ipairs(row) do
			table.insert(line, cell .. string.rep(" ", widths[col_idx] - #cell))
		end
		table.insert(md_table, table.concat(line, col_sep))
		if row_idx == 1 then
			-- First line: header
			table.insert(md_table, string.rep("-", total_width + #col_sep * (nb_columns - 1)))
		end
	end
	return md_table
end

--- @param lines string[][]
--- @param widths integer[]
--- @return nil
local function to_buffer(lines, widths)
	local md_table = make_markdown_table(lines, widths)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, md_table)

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
end

--- @param database integer
--- @param query string
--- @param url string
--- @param token string
--- @return nil
local function query_metabase(database, query, url, token)
	local curl_cmd = make_curl_cmd(database, query, url, token)

	vim.system(curl_cmd, {}, function(out)
		vim.schedule(function()
			local success, err = pcall(function()
				local widths, lines = cast_as_metabase_column_data(out.stdout)
				to_buffer(lines, widths)
			end)
			if not success then
				vim.notify(tostring(err), vim.log.levels.ERROR)
			end
		end)
	end)
end

--- @return nil
function M.run_buf_query()
	local success, err = pcall(function()
		local query = get_buf_sql()
		query_metabase(M.config.database, query, M.config.metabase_url, M.config.metabase_token)
	end)
	if not success then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

return M
