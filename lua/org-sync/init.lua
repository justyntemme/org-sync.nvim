-- In your Git repo at: org-sync.nvim/lua/org-sync/init.lua

local M = {}

function M.setup(opts)
  opts = opts or {}
  -- We'll use the user's configured directory later, but we don't need the guard clause.
  local org_dir = opts.dir
  if not org_dir then return end
  local expanded_org_dir = vim.fn.expand(org_dir)

  vim.notify("✅ Org Sync loaded. Watching for changes.", vim.log.levels.INFO, { title = "Plugin Loaded" })

  local function find_git_root(start_path)
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

  ---------------------------------
  -- DEDICATED AUTOCMD FOR PULLING --
  ---------------------------------
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = orgHybridSync,
    pattern = "*.org",
    callback = function(args)
      local git_root = find_git_root(args.file)
      -- Silently exit if the .org file is not in a git repo.
      if not git_root then return end
      
      -- Only act on the configured directory.
      if not args.file:find(expanded_org_dir, 1, true) then return end

      vim.notify("Git: Pulling changes...", vim.log.levels.INFO, { title = "Org Sync" })
      vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git pull", {
        on_exit = function(_, code)
          if code == 0 then
            vim.cmd("checktime")
            vim.notify("Git: Repo is up to date.", vim.log.levels.INFO, { title = "Org Sync" })
          else
            vim.notify("Git: Pull failed!", vim.log.levels.ERROR, { title = "Org Sync Error" })
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
      local git_root = find_git_root(args.file)
      -- Silently exit if the .org file is not in a git repo.
      if not git_root then return end
      
      -- Only act on the configured directory.
      if not args.file:find(expanded_org_dir, 1, true) then return end

      local file_path = args.file
      local filename = vim.fn.fnamemodify(file_path, ":t")
      
      -- **FIX:** Calculate the path relative to the git root.
      -- This makes the `git add` command much more reliable.
      local relative_path = file_path:sub(#git_root + 2)
      
      local commit_message = "Auto-commit: update " .. filename

      vim.notify("Git: Save detected, starting sync for " .. filename, vim.log.levels.INFO, { title = "Org Sync" })
      vim.fn.jobstart(
        "cd " .. vim.fn.shellescape(git_root) .. " && git add " .. vim.fn.shellescape(relative_path),
        {
          on_exit = function(_, add_code)
            if add_code ~= 0 then return vim.notify("Git: Add failed", vim.log.levels.ERROR) end
            vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git diff --staged --quiet", {
              on_exit = function(_, diff_code)
                if diff_code == 0 then return vim.notify("Git: No changes to commit", vim.log.levels.WARN) end
                vim.fn.jobstart(
                  "cd " .. vim.fn.shellescape(git_root) .. " && git commit -m " .. vim.fn.shellescape(commit_message),
                  {
                    on_exit = function(_, commit_code)
                      if commit_code ~= 0 then return vim.notify("Git: Commit failed", vim.log.levels.ERROR) end
                      vim.fn.jobstart("cd " .. vim.fn.shellescape(git_root) .. " && git push", {
                        on_exit = function(_, push_code)
                          if push_code == 0 then
                            vim.notify("Git: Successfully synced " .. filename, vim.log.levels.INFO)
                          else
                            vim.notify("Git: Push failed! Opening LazyGit...", vim.log.levels.ERROR)
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