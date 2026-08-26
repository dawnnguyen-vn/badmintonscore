module.exports = {
  extends: [
    "stylelint-config-standard",
    "stylelint-config-recess-order"
    // "stylelint-selector-bem-pattern"
  ],
  ignoreFiles: ["node_modules/**", "test/**", "dist/**", "build/**", "**/*.js"],
  // `.ux` single-file components keep their CSS inside a <style> block; parse
  // it with postcss-html so stylelint can reach the styles.
  overrides: [
    {
      files: ["**/*.ux"],
      customSyntax: "postcss-html"
    }
  ],
  rules: {
    "no-descending-specificity": null,
    "color-hex-length": "short",
    "at-rule-no-unknown": null,
    "block-no-empty": null,
    // This component set uses lowerCamelCase class names (e.g. .courtRow,
    // .scoreA) throughout; accept that convention instead of kebab-case.
    "selector-class-pattern": "^[a-z][a-zA-Z0-9]*$",
    "selector-pseudo-class-no-unknown": [
      true,
      {
        ignorePseudoClasses: ["blur"]
      }
    ],
    "property-no-unknown": [
      true,
      {
        ignoreProperties: [
          "placeholder-color",
          "gradient-start",
          "gradient-center",
          "gradient-end",
          "caret-color",
          "selected-color",
          "block-color"
        ]
      }
    ],
    "selector-type-no-unknown": [
      true,
      {
        ignoreTypes: ["selected-color", "block-color"]
      }
    ]
  }
}
