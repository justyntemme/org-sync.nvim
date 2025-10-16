-- In your Git repo at: org-sync.nvim/lua/org-sync/init.lua

-- This is now a standard Lua module. It exports a `setup` function.
local M = {}

-- The config function from your main nvim config will call this function.
function M.setup()
  -- For debugging, we'll know this function ran if we see this notification.
  vim.notify("✅ Org Sync Plugin setup() was called!", vim.log.levels.INFO, { title = "Plugin Loaded" })

  --- Finds the root of a Git repository by searching upwards from a starting path.
  local function find_git_root(start_path)
    -- ... (the rest of the logic is identical, just pasted inside the setup function) ...
    local dir = vim.fn.fnamemodify(start_path, ":h")
    while dir ~= "/" and dir ~= "" do
      if vim.fn.isdirectory(dir .. "/.git") then
        return dir
      end
      local parent = vim.fn.fnamemodify(dir, ":h")
      if parent == dir then break end
      dir = parent
    end
    return nil
  end

  local orgHybridSync = vim.api.nvim_create_augroup("OrgHybridSync", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = orgHybridSync,
    pattern = "~/.org/**/*.org",
    desc = "Async Git pull for org files.",
    callback = function(args)
      local git_root = find_git_root(args.file)
      if not git_root then return end
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

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = orgHybridSync,
    pattern = "~/.org/**/*.org",
    desc = "Async Git Sync with LazyGit on push failure.",
    callback = function(args)
      local git_root = find_git_root(args.file)
      if not git_root then return end
      local file_path = args.file
      local filename = vim.fn.fnamemodify(file_path, ":t")
      local commit_message = "Auto-commit: update " .. filename
      vim.notify("Starting Git sync for " .. filename, vim.log.levels.INFO, { title = "Org Sync" })
      vim.fn.jobstart(
        "cd " .. vim.fn.shellescape(git_root) .. " && git add " .. vim.fn.shellescape(file_path),
        {
          on_exit = function(_, add_code)
            if add_code ~= 0 then return vim.notify("Git add failed", vim.log.levels.ERROR) end
            vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git diff --staged --quiet", {
              on_exit = function(_, diff_code)
                if diff_code == 0 then return vim.notify("No changes to commit", vim.log.levels.WARN) end
                vim.fn.jobstart(
                  "cd " .. vim.fn.shellescape(git_root) .. " && git commit -m " .. vim.fn.shellescape(commit_message),
                  {
                    on_exit = function(_, commit_code)
                      if commit_code ~= 0 then return vim.notify("Git commit failed", vim.log.levels.ERROR) end
                      vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git push", {
                        on_exit = function(_, push_code)
                          if push_code == 0 then
                            vim.notify("Successfully synced " .. filename, vim.log.levels.INFO)
                          else
                            vim.notify("Git push failed! Opening LazyGit...", vim.log.levels.ERROR)
                            require("lazyvim.util").terminal.open("lazygit", { cwd = git_root })
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