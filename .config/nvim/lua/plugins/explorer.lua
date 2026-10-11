return {
  {
    "nvim-tree/nvim-tree.lua",
    cmd = { "NvimTreeToggle", "NvimTreeOpen", "NvimTreeFocus", "NvimTreeFindFile" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    init = function() require("config.explorer").setup() end,
    config = function(_, opts)
      require("nvim-tree").setup(opts)
      require("config.explorer").setup_branches()
    end,
    opts = {
      on_attach = function(bufnr)
        local api = require("nvim-tree.api")
        api.map.on_attach.default(bufnr)
        -- Let the global Ctrl-k window/tab-bar mapping work in the tree too.
        vim.keymap.del("n", "<C-k>", { buffer = bufnr })
        local function opts(desc)
          return { buffer = bufnr, desc = desc, silent = true, nowait = true }
        end

        local function open_file(node)
          if #vim.api.nvim_tabpage_list_wins(0) == 1 then
            api.node.open.replace_tree_buffer(node)
          else
            api.node.open.edit(node)
          end
        end

        local previous_roots = {}
        local function is_root(node)
          local root = api.tree.get_nodes()
          return node and root and node.absolute_path == root.absolute_path
        end

        local function down()
          local root = api.tree.get_nodes()
          if not root then return end
          local child = previous_roots[root.absolute_path]
          if not child or vim.fn.isdirectory(child) ~= 1 then
            -- With no navigation history, descend into the first visible folder.
            child = nil
            for _, node in ipairs(root.nodes or {}) do
              if node.nodes and not node.hidden then
                child = node.absolute_path
                break
              end
            end
          end
          if child then
            api.tree.change_root(child)
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
          end
        end

        local function enter()
          local node = api.tree.get_node_under_cursor()
          if not node then
            return
          end
          if is_root(node) then
            down()
          elseif node.nodes then
            api.tree.change_root_to_node(node)
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
          else
            open_file(node)
          end
        end

        local function up(focus_root)
          local root = api.tree.get_nodes()
          local path = root and root.absolute_path
          local parent = path and vim.fs.dirname(path)
          if not parent or parent == path then
            return
          end

          previous_roots[parent] = path
          api.tree.change_root(parent)
          -- Keep the directory we left selected, with its children hidden.
          api.tree.find_file({ buf = path, focus = true })
          local node = api.tree.get_node_under_cursor()
          if node and node.nodes and (node.absolute_path == path or node.link_to == path) then
            api.node.collapse(node)
          end
          if focus_root then vim.api.nvim_win_set_cursor(0, { 1, 0 }) end
        end

        vim.keymap.set("n", "h", function()
          if is_root(api.tree.get_node_under_cursor()) then
            up(true)
          else
            api.node.navigate.parent_close()
          end
        end, opts("Close folder / go up a level on the root row"))
        vim.keymap.set("n", "l", function()
          local node = api.tree.get_node_under_cursor()
          if not node then
            return
          end
          if is_root(node) then
            down()
          elseif node.nodes then
            api.node.expand(node, {
              expand_until = function()
                return false
              end,
            })
          else
            open_file(node)
          end
        end, opts("Expand folder / open file / go down a level on the root row"))
        vim.keymap.set("n", "<CR>", function()
          local node = api.tree.get_node_under_cursor()
          if not node then return end
          if node.nodes then
            api.node.open.edit(node)
          else
            open_file(node)
          end
        end, opts("Toggle folder / open file"))
        vim.keymap.set("n", "H", up, opts("Go up and close previous root folder"))
        vim.keymap.set("n", "L", enter, opts("Enter folder as root / open file"))
        vim.keymap.set("n", "g.", api.filter.dotfiles.toggle, opts("Toggle hidden files"))
        vim.keymap.set("n", "gi", api.node.show_info_popup, opts("Show file info"))
      end,
      view = { side = "left", width = 26, signcolumn = "no" },
      -- Connected branches under a visible root, with no folder chevrons.
      renderer = {
        group_empty = false,
        root_folder_label = function(path)
          local name = vim.fs.basename(path)
          return "  " .. (name ~= "" and name or path)
        end,
        indent_width = 2,
        symlink_destination = false,
        highlight_git = "name",
        indent_markers = {
          enable = true,
          inline_arrows = false,
          icons = { corner = "└", edge = "│", item = "├", bottom = "─", none = " " },
        },
        icons = {
          show = { folder_arrow = false },
          web_devicons = { file = { enable = true, color = true } },
          git_placement = "after",
          diagnostics_placement = "after",
          modified_placement = "after",
          bookmarks_placement = "after", -- Keep badges out of a separate sign column.
          glyphs = {
            folder = {
              default = "",
              open = "",
              empty = "",
              empty_open = "",
            },
            -- Font-independent Git badges: no private-use Nerd Font glyphs.
            git = {
              unstaged = "~",
              staged = "+",
              unmerged = "!",
              renamed = ">",
              untracked = "?",
              deleted = "-",
              ignored = ".",
            },
          },
        },
      },
      diagnostics = {
        enable = true,
        show_on_dirs = true,
        show_on_open_dirs = false,
        icons = { hint = "󰌵", info = "", warning = "", error = "" },
      },
      modified = { enable = true, show_on_dirs = false },
      actions = { change_dir = { enable = false } }, -- Browsing shouldn't change Telescope's cwd.
      -- Opening/switching files must not move the root or expand their folders.
      update_focused_file = { enable = false, update_root = { enable = false } },
      sync_root_with_cwd = false,
      respect_buf_cwd = false,
      filters = { dotfiles = false },
    },
  },
}
