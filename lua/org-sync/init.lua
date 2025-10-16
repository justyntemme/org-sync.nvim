-- This file returns the complete LazyVim plugin specification.
-- It is self-contained and manages its own triggers and configuration.
return {
	-- The event that will trigger the plugin to load.
	-- This is now encapsulated inside the plugin itself.
	event = { "BufReadPost ~/.org/**/*.org", "BufWritePost ~/.org/**/*.org" },

	-- The config function sets up the autocommands after the plugin is loaded.
	config = function()
		local orgHybridSync = vim.api.nvim_create_augroup("OrgHybridSync", { clear = true })
		local org_dir_pattern = "~/.org/**/*.org"

		--------------------------------
		-- 1. ASYNC PULL ON FILE OPEN --
		--------------------------------
		vim.api.nvim_create_autocmd("BufReadPost", {
			group = orgHybridSync,
			pattern = org_dir_pattern,
			desc = "Async Git pull for org files.",
			callback = function()
				local dir = vim.fn.expand("%:h")
				-- Safety check: Only run if we're inside a Git repository.
				if not vim.fn.isdirectory(dir .. "/.git") then
					return
				end

				vim.notify("Syncing with remote...", vim.log.levels.INFO, { title = "Org Sync" })
				-- Asynchronously run `git pull` in the background
				vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git pull", {
					on_exit = function(_, code)
						if code == 0 then
							-- On success, check if the open file was changed on disk by the pull
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
				local dir = vim.fn.expand("%:h")
				if not vim.fn.isdirectory(dir .. "/.git") then
					return
				end

				local filename = vim.fn.expand("%:t")
				local commit_message = "Auto-commit: update " .. filename

				vim.notify("Starting Git sync for " .. filename, vim.log.levels.INFO, { title = "Org Sync" })

				-- This is a sequential chain of background jobs.
				-- Each job starts the next one only upon successful completion.

				-- Job 1: `git add`
				vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git add " .. vim.fn.shellescape(filename), {
					on_exit = function(_, add_code)
						if add_code ~= 0 then
							return vim.notify("Git add failed", vim.log.levels.ERROR, { title = "Org Sync Error" })
						end

						-- Job 2: Check for changes to prevent empty commits
						vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git diff --staged --quiet", {
							on_exit = function(_, diff_code)
								if diff_code == 0 then
									return vim.notify(
										"No changes to commit.",
										vim.log.levels.WARN,
										{ title = "Org Sync" }
									)
								end

								-- Job 3: `git commit`
								vim.fn.jobstart(
									"cd "
										.. vim.fn.shellescape(dir)
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

											-- Job 4: `git push`
											vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git push", {
												on_exit = function(_, push_code)
													if push_code == 0 then
														-- SUCCESS PATH
														vim.notify(
															"Successfully synced " .. filename,
															vim.log.levels.INFO,
															{ title = "Org Sync" }
														)
													else
														-- FAILURE PATH: Open LazyGit
														vim.notify(
															"Git push failed! Opening LazyGit to resolve.",
															vim.log.levels.ERROR,
															{ title = "Org Sync Action Required" }
														)
														require("lazyvim.util").terminal.open("lazygit", {
															cwd = dir, -- Open lazygit in the file's directory
														})
													end
												end,
											})
										end,
									}
								)
							end,
						})
					end,
				})
			end,
		})
	end,
}
