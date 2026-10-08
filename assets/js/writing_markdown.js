import {Extension, InputRule} from "@tiptap/core"
import Paragraph from "@tiptap/extension-paragraph"

// StarterKit recognizes bare URLs, but not Markdown links typed character by
// character. Keep the visible label and apply the existing safe link mark.
export const MarkdownLinks = Extension.create({
  name: "writingMarkdownLinks",
  addInputRules() {
    return [new InputRule({
      find: /\[([^\]\n]+)\]\(((?:https?:\/\/|mailto:|\/)[^\s)]+)\)$/,
      handler: ({state, range, match}) => {
        const [, label, href] = match
        const link = state.schema.marks.link
        state.tr.insertText(label, range.from, range.to)
          .addMark(range.from, range.from + label.length, link.create({href}))
          .removeStoredMark(link)
          .setMeta("preventAutolink", true)
      }
    })]
  }
})


// Explicit empty paragraphs survive both CommonMark rendering and editing.
// The default serializer encodes only consecutive empty paragraphs, so MDEx
// otherwise collapses the first intentional blank line in the preview.
export const WritingParagraph = Paragraph.extend({
  renderMarkdown(node, helpers) {
    return node.content?.length ? helpers.renderChildren(node.content) : "&nbsp;"
  }
})
