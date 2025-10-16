local M = {}

function M.setup(opts)
	opts = opts or {}
	-- We still check for the dir config to know if the plugin should be active.
	if not opts.dir then
		return
	end

	vim.notify("Org Sync loaded. Watching for changes.", vim.log.levels.INFO, { title = "Plugin Loaded" })

	local orgHybridSync = vim.api.nvim_create_augroup("OrgHybridSync", { clear = true })

	---------------------------------
	-- DEDICATED AUTOCMD FOR PULLING --
	---------------------------------
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = orgHybridSync,
		pattern = "*.org",
		callback = function(args)
			local dir = vim.fn.fnamemodify(args.file, ":h")

			vim.notify("Git: Pulling changes...", vim.log.levels.INFO, { title = "Org Sync" })
			vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git pull", {
				on_exit = function(_, code)
					if code == 0 then
						vim.cmd("checktime")
						vim.notify("Git: Repo is up to date.", vim.log.levels.INFO, { title = "Org Sync" })
					else
						-- On pull failure (like a merge conflict), open LazyGit.
						if
							vim.fn
								.system("cd " .. vim.fn.shellescape(dir) .. " && git rev-parse --is-inside-work-tree")
								:match("true")
						then
							vim.notify(
								"Git: Pull failed! Opening LazyGit to resolve.",
								vim.log.levels.ERROR,
								{ title = "Org Sync Error" }
							)
							require("lazyvim.util").terminal.open("lazygit", { cwd = dir })
						end
					end
				end,
			})
		end,
	})

	---------------------------------
	-- DEDICATED AUTOCMD FOR PUSHING --
	---------------------------------
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = orgHybridSync,
		pattern = "*.org",
		callback = function(args)
			local dir = vim.fn.fnamemodify(args.file, ":h")
			local filename = vim.fn.fnamemodify(args.file, ":t")
			local commit_message = "Auto-commit: update " .. filename

			vim.notify(
				"Git: Save detected, starting sync for " .. filename,
				vim.log.levels.INFO,
				{ title = "Org Sync" }
			)
			vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git add " .. vim.fn.shellescape(filename), {
				on_exit = function(_, add_code)
					if add_code ~= 0 then
						return vim.notify("Git: Add failed", vim.log.levels.ERROR)
					end
					vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git diff --staged --quiet", {
						on_exit = function(_, diff_code)
							if diff_code == 0 then
								return vim.notify("Git: No changes to commit", vim.log.levels.WARN)
							end
							vim.fn.jobstart(
								"cd "
									.. vim.fn.shellescape(dir)
									.. " && git commit -m "
									.. vim.fn.shellescape(commit_message),
								{
									on_exit = function(_, commit_code)
										if commit_code ~= 0 then
											return vim.notify("Git: Commit failed", vim.log.levels.ERROR)
										end
										vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git push", {
											on_exit = function(_, push_code)
												if push_code == 0 then
													vim.notify(
														"Git: Successfully synced " .. filename,
														vim.log.levels.INFO
													)
												else
													vim.notify(
														"Git: Push failed! Opening LazyGit...",
														vim.log.levels.ERROR
													)
													require("lazyvim.util").terminal.open("lazygit", { cwd = dir })
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
end

return M
