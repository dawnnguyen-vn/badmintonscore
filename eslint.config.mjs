import js from "@eslint/js"
import pluginVue from "eslint-plugin-vue"
import prettier from "eslint-config-prettier"
import globals from "globals"

// Globals exposed by the aiot / quick-app runtime that `.ux` scripts use.
const quickAppGlobals = {
  ...globals.browser,
  $app: "readonly",
  App: "readonly",
  Page: "readonly",
  Card: "readonly",
  requirePlugin: "readonly"
}

// `.ux` files are Vue-style single-file components. Reuse eslint-plugin-vue's
// flat "essential" preset (error-prevention rules only — the opinionated Vue
// style rules don't fit a quick-app component), but retarget every entry that
// eslint-plugin-vue scopes to `**/*.vue` onto our `.ux` extension instead.
const vueForUx = pluginVue.configs["flat/essential"].map((config) => {
  if (config.files || config.rules) {
    return {...config, files: ["**/*.ux"]}
  }
  return config // plugin registration only — keep it global
})

export default [
  {
    ignores: [
      "node_modules/**",
      "dist/**",
      "build/**",
      "sign/**",
      "coverage/**",
      ".nyc_output/**",
      "tests/fixtures/**"
    ]
  },

  // Baseline JS recommendations everywhere (also lints the `<script>` block
  // that eslint-plugin-vue extracts from each `.ux` component).
  js.configs.recommended,

  // Vue-essential rules retargeted to `.ux`.
  ...vueForUx,

  // Component sources: quick-app runtime globals, modern ESM script blocks.
  {
    files: ["**/*.ux"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: quickAppGlobals
    },
    rules: {
      // Component filenames are single words (index.ux) by design here.
      "vue/multi-word-component-names": "off"
    }
  },

  // Root tooling config files are CommonJS running under Node.
  {
    files: ["**/*.js", "**/*.cjs"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "commonjs",
      globals: globals.node
    }
  },

  // Keep Prettier the sole authority on formatting: disable any stylistic
  // ESLint rules that would fight it. Must stay last.
  prettier
]
