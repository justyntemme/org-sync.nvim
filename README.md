# org-sync.nvim

Sync git repository on load/save for orgfiles in nvim

# Install

## LazyVim configuration

```lua
return {
  "justyntemme/org-sync.nvim",
  -- The event trigger now lives here, in your personal config.
  -- event = "VeryLazy",
  -- event = { "BufReadPost ~/.org/**/*.org", "BufWritePost ~/.org/**/*.org" },
  event = { "BufReadPost *.org", "BufWritePost *.org" },
  -- The config function calls the `setup` function from your plugin.
  config = function()
    require("org-sync").setup({
      dir = "~/.org",
    })
  end,
}
```
