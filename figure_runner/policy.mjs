import {parse} from 'acorn'

// This is a diagnostic boundary, not the isolation boundary. Container, CSP and
// iframe restrictions remain necessary even when a program passes analysis.
export function inspectSources(files) {
  const allowed=new Set(['./model.mjs','./geometry.mjs','/kit/iso-kit.mjs','/kit/lathe.mjs','/kit/tube.mjs','/kit/audit.mjs','/kit/facets.mjs','/leitor/occlusion.mjs','/leitor/mechanics.mjs'])
  for(const [name,source] of Object.entries(files)) {
    if(!['figure.mjs','geometry.mjs','model.mjs','checks.mjs'].includes(name)||typeof source!=='string'||Buffer.byteLength(source)>100_000)throw Error('Invalid source file')
    const tree=parse(source,{ecmaVersion:'latest',sourceType:'module'})
    const declared=new Set()
    function bindings(node) {
      if(!node||typeof node!=='object')return
      if(node.type==='VariableDeclarator'&&node.id.type==='Identifier')declared.add(node.id.name)
      if(['FunctionDeclaration','FunctionExpression','ArrowFunctionExpression'].includes(node.type))for(const param of node.params)if(param.type==='Identifier')declared.add(param.name)
      for(const value of Object.values(node))if(Array.isArray(value))value.forEach(bindings);else if(value&&typeof value==='object')bindings(value)
    }
    bindings(tree)
    function walk(node,parent=null,key=null) {
      if(!node||typeof node!=='object')return
      if(['ImportExpression','ExportAllDeclaration'].includes(node.type))throw Error('Dynamic imports and re-exports are unavailable')
      if(node.type==='ImportDeclaration'&&!allowed.has(node.source.value))throw Error('Only local modules and the bundled kit may be imported')
      if(node.type==='ExportNamedDeclaration'&&node.source)throw Error('Re-exports are unavailable')
      const ordinaryProperty=!(node.name==='cookie'||node.name==='constructor'||node.name==='__proto__')&&(
        parent?.type==='MemberExpression'&&key==='property'&&!parent.computed ||
        parent?.type==='Property'&&key==='key'&&!parent.computed&&!parent.shorthand)
      const localGeometryName=['top','parent'].includes(node.name)&&declared.has(node.name)
      if(node.type==='Identifier'&&!ordinaryProperty&&!localGeometryName&&['eval','Function','fetch','XMLHttpRequest','WebSocket','Worker','SharedWorker','EventSource','localStorage','sessionStorage','indexedDB','navigator','cookie','opener','top','parent','frames','globalThis','window','self','process','require','constructor','__proto__'].includes(node.name))throw Error(`Unavailable capability: ${node.name}`)
      for(const [childKey,value] of Object.entries(node))if(Array.isArray(value))value.forEach(child=>walk(child,node,childKey));else if(value&&typeof value==='object')walk(value,node,childKey)
    }
    walk(tree)
  }
  return true
}
