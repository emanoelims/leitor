# Reading and learning implementation

## Boundaries

- Accounts: email magic-link registration, confirmation, sessions, and email changes. Password login is not exposed.
- Library: owned texts and lesson materials, document extraction, sentence positions. Anonymous reading is ephemeral; account history is private.
- Learning: vocabulary and expressions, known words, review scheduling, writing/practice attempts, and progress derived from actual activity.
- Study: invitation-only rooms, host-owned reading position, Presence, and temporary chat.
- Language: Anthropic through ReqLLM, structured sentence analysis and writing feedback. Model and credentials belong in runtime environment configuration. Provider failures remain explicit and recoverable.

## Delivery stages

1. Generate scoped resources; adopt native Ecto UUID v7 for all application schemas without rewriting existing identities.
2. Extract the application shell and reusable function components. Replace daisyUI with the prototype's warm neutral palette, Google Fonts stylesheet links, accessible controls, and a development component gallery.
3. Implement public reading/import and email-only authentication. Add owned history, vocabulary, expressions, and spaced review.
4. Implement dictation, shadowing, rewriting, writing feedback, lesson material import with persisted guides, measured progress, and private collaboration.
5. Test ownership boundaries, validation, magic links, streams, and provider failures. Review desktop/mobile layouts, keyboard operation, accessibility, request errors, and responsiveness using Tidewave.

## UI and state

Use function components with declared attributes and slots for presentation. LiveViews own server state. JS commands handle immediate DOM operations; hooks handle browser speech, microphone recording, theme preference, and keyboard shortcuts with lifecycle cleanup. Use live navigation within a session and regular navigation at authentication/session boundaries.

Stream persistent collections with stable IDs, reset after filtering, and reinsert changed records. Track counts/empty states separately. Keep the current sentence and bounded exercise state in assigns. Persist private mutations through scoped contexts; never trust a submitted user ID.

## Acceptance

Only reading is publicly accessible. Saving and all learning workspaces require authentication. Import errors and unsupported browser capabilities have visible recovery paths. Progress is based on recorded work, not fixture numbers. AI feedback is identified as such and validated before persistence. All changes pass precommit and the existing coverage floor; do not weaken checks to accommodate new code.
