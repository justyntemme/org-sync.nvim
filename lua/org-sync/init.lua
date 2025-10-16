-- This file returns the complete LazyVim plugin specification.
return {
	event = { "BufReadPost ~/.org/**/*.org", "BufWritePost ~/.org/**/*.org" },

	config = function()
		--- Finds the root of a Git repository by searching upwards from a starting path.
		-- @param start_path string The file or directory path to start searching from.
		-- @return string|nil The path to the Git repository root, or nil if not found.
		local function find_git_root(start_path)
			local dir = vim.fn.fnamemodify(start_path, ":h")
			while dir ~= "/" and dir ~= "" do
				if vim.fn.isdirectory(dir .. "/.git") then
					return dir
				end
				local parent = vim.fn.fnamemodify(dir, ":h")
				if parent == dir then -- Reached the root of the filesystem
					break
				end
				dir = parent
			end
			return nil
		end

		local orgHybridSync = vim.api.nvim_create_augroup("OrgHybridSync", { clear = true })
		local org_dir_pattern = "~/.org/**/*.org"

		--------------------------------
		-- 1. ASYNC PULL ON FILE OPEN --
		--------------------------------
		vim.api.nvim_create_autocmd("BufReadPost", {
			group = orgHybridSync,
			pattern = org_dir_pattern,
			desc = "Async Git pull for org files.",
			callback = function(args)
				-- Use the robust function to find the repo root
				local git_root = find_git_root(args.file)
				if not git_root then
					return -- Not in a git repo, do nothing
				end

				vim.notify("Syncing with remote...", vim.log.levels.INFO, { title = "Org Sync" })
				vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git pull", {
					on_exit = function(_, code)
						if code == 0 then
							vim.cmd("checktime")
							vim.notify("Repo is up to date.", vim.log.levels.INFO, { title = "Org Sync" })
						else
							vim.notify("Git pull failed!", vim.log.levels.ERROR, { title = "Org Sync Error" })
						end
					end,
				})
			end,
		})

		----------------------------------------------------------
		-- 2. ASYNC COMMIT/PUSH ON FILE SAVE WITH LAZYGIT FALLBACK --
		----------------------------------------------------------
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = orgHybridSync,
			pattern = org_dir_pattern,
			desc = "Async Git Sync with LazyGit on push failure.",
			callback = function(args)
				-- Use the robust function to find the repo root
				local git_root = find_git_root(args.file)
				if not git_root then
					return -- Not in a git repo, do nothing
				end

				local file_path = args.file
				local filename = vim.fn.fnamemodify(file_path, ":t")
				local commit_message = "Auto-commit: update " .. filename

				vim.notify("Starting Git sync for " .. filename, vim.log.levels.INFO, { title = "Org Sync" })

				-- Chain of commands, all running from the determined git_root
				vim.fn.jobstart(
					"cd " .. vim.fn.shellescape(git_root) .. " && git add " .. vim.fn.shellescape(file_path),
					{
						on_exit = function(_, add_code)
							if add_code ~= 0 then
								return vim.notify("Git add failed", vim.log.levels.ERROR, { title = "Org Sync Error" })
							end
							vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git diff --staged --quiet", {
								on_exit = function(_, diff_code)
									if diff_code == 0 then
										return vim.notify(
											"No changes to commit.",
											vim.log.levels.WARN,
											{ title = "Org Sync" }
										)
									end
									vim.fn.jobstart(
										"cd "
											.. vim.fn.shellescape(git_root)
											.. " && git commit -m "
											.. vim.fn.shellescape(commit_message),
										{
											on_exit = function(_, commit_code)
												if commit_code ~= 0 then
													return vim.notify(
														"Git commit failed.",
														vim.log.levels.ERROR,
														{ title = "Org Sync Error" }
													)
												end
												vim.fn.jobstart(
													"cd " .. vim.fn.shellescape(git_root) .. " && git push",
													{
														on_exit = function(_, push_code)
															if push_code == 0 then
																vim.notify(
																	"Successfully synced " .. filename,
																	vim.log.levels.INFO,
																	{ title = "Org Sync" }
																)
															else
																vim.notify(
																	"Git push failed! Opening LazyGit to resolve.",
																	vim.log.levels.ERROR,
																	{ title = "Org Sync Action Required" }
																)
																require("lazyvim.util").terminal.open(
																	"lazygit",
																	{ cwd = git_root }
																)
															end
														end,
													}
												)
											end,
										}
									)
								end,
							})
						end,
					}
				)
			end,
		})
	end,
}
