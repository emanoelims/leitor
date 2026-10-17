// Shared by the opaque reader frame and isolated checker. Generated CSS may
// override these defaults; a custom background must set its foreground too.
export const baseFigureStyle = `
:root{--figure-text:#242321;--figure-muted:#6b655c;color-scheme:light}
html[data-theme=dark]{--figure-text:#e9e3d6;--figure-muted:#aaa394;color-scheme:dark}
html,body{margin:0;background:transparent;color:var(--figure-text);font-family:Arial,sans-serif}
*{box-sizing:border-box}svg{max-width:100%;height:auto}button,input,select,textarea{font:inherit}
#figure-root{width:100%;overflow:hidden}
.iso:where(:not([data-theme="light"])){
  --anatomy-paper:#242421;--anatomy-face:#33332d;--anatomy-top:#414139;
  --anatomy-shade-0:#242421;--anatomy-shade-1:#2b2b26;--anatomy-shade-2:#33332d;--anatomy-shade-3:#3b3b34;
  --anatomy-lit-top:#505047;--anatomy-lit-shade:#3b3b34;
}
`

// Reapply current host defaults after a stored artifact's original kit styles,
// then restore its authored CSS. This also updates old reviewed bundles without
// changing their executable bytes or overriding an author's explicit palette.
export const composeFigureStyle = (kitStyle, authoredStyle) => `${kitStyle}\n${baseFigureStyle}\n${authoredStyle}`
