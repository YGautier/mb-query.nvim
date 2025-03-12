local M = {}

--- @return string?
local function get_env(var)
	return os.getenv(var)
end

M.config = {
	metabase_url = get_env("METABASE__URL"),
	metabase_token = get_env("METABASE__TOKEN"),
	database = 2,
	max_nb_rows = 30,
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

---@class MetabaseColumnData
--- @field col_name string
--- @field data string[]
local MetabaseColumnData = {}

--- @param col_name string
--- @return MetabaseColumnData
function MetabaseColumnData:new(col_name)
	local res = { col_name = col_name, data = {} }
	setmetatable(res, self)
	self.__index = self
	return res
end

--- @return integer
function MetabaseColumnData:get_display_width()
	local width = #self.col_name
	for _, value in ipairs(self.data) do
		width = math.max(width, #value)
	end
	return width
end

--- @param raw_data string?
--- @return MetabaseColumnData[]
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

	local res = {}
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
		table.insert(res, MetabaseColumnData:new(col_name))
	end

	for _, row in ipairs(rows) do
		for col_idx, cell in ipairs(row) do
			table.insert(res[col_idx].data, tostring(cell))
		end
	end

	return res
end

--- @param query_result MetabaseColumnData[]
--- @param max_nb_rows integer
--- @return nil
local function display_metabase_query_result(query_result, max_nb_rows)

end

--- @param database integer
--- @param query string
--- @param url string
--- @param token string
--- @param max_nb_rows integer
--- @return nil
local function query_metabase(database, query, url, token, max_nb_rows)
	local curl_cmd = make_curl_cmd(database, query, url, token)

	vim.system(curl_cmd, {}, function(out)
		local success, err = pcall(function()
			local data = cast_as_metabase_column_data(out.stdout)
			display_metabase_query_result(data, max_nb_rows)
		end)
		if not success then
			vim.notify(tostring(err), vim.log.levels.ERROR)
		end
	end)
end

--- @return nil
function M.run_buf_query()
	local success, err = pcall(function()
		local query = get_buf_sql()
		query_metabase(M.config.database, query, M.config.metabase_url, M.config.metabase_token, M.config.max_nb_rows)
	end)
	if not success then
		vim.notify(tostring(err), vim.log.levels.ERROR)
	end
end

return M
