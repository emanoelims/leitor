# Anatomy drawing kit

Source: https://github.com/wheresryan22/anatomy
Commit: e9488296a44211c42701ff71705b7901470ec78f
License: MIT, Copyright (c) 2026 Ryan. See LICENSE in this directory.

Except facets.mjs, the .mjs files and iso.css are unmodified upstream files. Leitor's declarative
engines and lifecycle live in assets/js/figures/. The program author uses the
kit in a separate compiler/browser container. Generated programs never execute
in Node or the Phoenix page's realm; reviewed bundles run in opaque-origin
sandboxed iframes with a restrictive Content Security Policy.

facets.mjs comes from Anatomy Community, commit
aeea92c80b0d14567de50ea67debf67068663180,
figures/nader0913/pin-tumbler-lock/src/engine.mjs. Original figure author: Nader
(@nader0913). Only the iso-kit import path was adapted. See COMMUNITY-LICENSE
for the retained MIT notice covering Ryan and the Anatomy figure contributors.

The development regression fixture `test/fixtures/figures/lock-program.json`
also adapts the same community figure's `model.mjs`, `draw.mjs` and the scene
construction from `build.mjs`, retaining the MIT notice in generated bundles.
Leitor supplies user-controlled state transitions, interface, theme integration,
camera fitting and the isolated execution pipeline. This fixture is a reviewed
demonstration, not a preset selected by the production generation path.
