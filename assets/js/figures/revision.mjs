export function replacementRange(doc, from, expectedId) {
  if (!Number.isInteger(from) || from < 0 || from >= doc.content.size) return null
  const node = doc.nodeAt(from)
  if (node?.type.name !== 'codeBlock' || node.attrs.language !== 'leitor-figure') return null
  let reference
  try {reference = JSON.parse(node.textContent)} catch (_) {return null}
  if (reference.engine !== 'anatomy-program' || reference.artifact_id !== expectedId) return null
  return {from, to: from + node.nodeSize}
}
