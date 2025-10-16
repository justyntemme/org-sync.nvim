-- In your Git repo at: org-sync.nvim/lua/org-sync/init.lua

local M = {}

function M.setup(opts)
  opts = opts or {}
  -- We still check for the dir config to know if the plugin should be active.
  if not opts.dir then
    return
  end

  vim.notify("✅ Org Sync loaded. Watching for changes.", vim.log.levels.INFO, { title = "Plugin Loaded" })

  local orgHybridSync = vim.api.nvim_create_augroup("OrgHybridSync", { clear = true })

  ---------------------------------
  -- DEDICATED AUTOCMD FOR PULLING --
  ---------------------------------
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = orgHybridSync,
    pattern = "*.org",
    callback = function(args)
      -- SIMPLIFIED LOGIC: Get the file's directory.
      local dir = vim.fn.fnamemodify(args.file, ":h")

      vim.notify("Git: Pulling changes...", vim.log.levels.INFO, { title = "Org Sync" })
      -- Run git commands from the file's own directory.
      vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git pull", {
        on_exit = function(_, code)
          -- The command will fail silently if not in a git repo, which is fine.
          if code == 0 then
            vim.cmd("checktime")
            vim.notify("Git: Repo is up to date.", vim.log.levels.INFO, { title = "Org Sync" })
          else
            -- We only notify on failure if we are in a git repo.
            if vim.fn.isdirectory(dir .. "/.git") or vim.fn.system("cd " .. vim.fn.shellescape(dir) .. " && git rev-parse --is-inside-work-tree") == "true\n" then
              vim.notify("Git: Pull failed!", vim.log.levels.ERROR, { title = "Org Sync Error" })
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
      -- SIMPLIFIED LOGIC: Get the file's directory and name.
      local dir = vim.fn.fnamemodify(args.file, ":h")
      local filename = vim.fn.fnamemodify(args.file, ":t")
      local commit_message = "Auto-commit: update " .. filename

      vim.notify("Git: Save detected, starting sync for " .. filename, vim.log.levels.INFO, { title = "Org Sync" })
      -- Run git commands from the file's own directory, adding by filename.
      vim.fn.jobstart(
        "cd " .. vim.fn.shellescape(dir) .. " && git add " .. vim.fn.shellescape(filename),
        {
          on_exit = function(_, add_code)
            if add_code ~= 0 then return vim.notify("Git: Add failed", vim.log.levels.ERROR) end
            vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git diff --staged --quiet", {
              on_exit = function(_, diff_code)
                if diff_code == 0 then return vim.notify("Git: No changes to commit", vim.log.levels.WARN) end
                vim.fn.jobstart(
                  "cd " .. vim.fn.shellescape(dir) .. " && git commit -m " .. vim.fn.shellescape(commit_message),
                  {
                    on_exit = function(_, commit_code)
                      if commit_code ~= 0 then return vim.notify("Git: Commit failed", vim.log.levels.ERROR) end
                      vim.fn.jobstart("cd " .. vim.fn.shellescape(dir) .. " && git push", {
                        on_exit = function(_, push_code)
                          if push_code == 0 then
                            vim.notify("Git: Successfully synced " .. filename, vim.log.levels.INFO)
                          else
                            vim.notify("Git: Push failed! Opening LazyGit...", vim.log.levels.ERROR)
                            -- Open LazyGit in the file's directory.
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
        }
      )
    end,
  })
end

return M