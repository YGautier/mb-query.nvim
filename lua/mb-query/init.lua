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

--- @return string?
local function get_buf_sql()
	if not is_buf_sql() then
		vim.notify("Not a SQL file.", vim.log.levels.ERROR)
		return nil
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

---@class MetabaseQueryColumn
--- @field display_name string

--- @class MetabaseQueryResult
--- @field rows any[][]
--- @field cols MetabaseQueryColumn[]

--- @param query_result MetabaseQueryResult
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
		display_metabase_query_result(vim.json.decode(out.stdout).data, max_nb_rows)
	end)
end

--- @return nil
function M.run_buf_query()
	local query = get_buf_sql()
	if query == nil then
		return nil
	end
	query_metabase(M.config.database, query, M.config.metabase_url, M.config.metabase_token, M.config.max_nb_rows)
end

return M
