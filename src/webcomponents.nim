import jsffi, dom, macros, std/with
from strutils import join

when not defined(js):
  {.error: "webcomponents is only available for the JS target".}

type
  ShadowMode* = enum
    smClosed
    smOpen

# var console {.importc, used.}: JsObject
proc attachShadow*(this: Node, mode: JsObject): Node {.importcpp, nodecl.}

converter toJs*(mode: ShadowMode): JsObject =
  case mode
  of smClosed:
    js{"mode".cstring: "closed".cstring}
  of smOpen:
    js{"mode".cstring: "open".cstring}

proc addAttribute(typeSection: var NimNode, node: NimNode) =
  let attribute = newIdentDefs(node[0], node[1][0], newEmptyNode())
  var recList = typeSection[0][0][2][0][2]
  case recList.kind
  of nnkEmpty:
    recList = nnkRecList.newTree(attribute)
  of nnkRecList:
    recList.add(attribute)
  else:
    discard
  typeSection[0][0][2][0][2] = recList

proc makeConstructor(typ, body: NimNode): NimNode =
  result = quote do:
    {.emit: "constructor() {\nsuper();".}
    block:
      var this {.importc, inject.}: `typ`
      `body`
    {.emit: "}".}

proc makeConnectedCallback(cls, body: NimNode): NimNode =
  result = quote do:
    `cls`.prototype.connectedCallback = proc =
      var this {.importc, inject.}: `cls`.type
      `body`

proc makeAttributeChangedCallback(cls, body: NimNode): NimNode =
  result = quote do:
    `cls`.prototype.attributeChangedCallback = proc(
        property {.inject.}, oldValue {.inject.},
        newValue {.inject.}: cstring) =
      # var this {.importc, inject.}: `cls`.type
      var this {.importc, inject.}: JsObject
      `body`

macro defineComponent*(name: string, cls: untyped{nkIdent},
                body: untyped{nkStmtList}): untyped =
  let
    clsName = $cls
    typeName = ident("Component" & clsName)
  var typeSection = quote do:
    # this never exists in js code
    type `typeName` = ref object of Node
      prototype: JsObject
    # use `var` so `prototype` custom functions are exported to js
    var `cls` {.importc.}: `typeName`

  var
    constructorSection = newStmtList()
    observedAttributes: seq[string]
    bodySection = newStmtList()

  for child in body.children:
    case child.kind
    of nnkCall:
      case $child[0]
      of "constructor":
        constructorSection = `typeName`.makeConstructor(child[1])
      of "connectedCallback":
        bodySection.add `cls`.makeConnectedCallback(child[1])
      of "attributeChangedCallback":
        bodySection.add `cls`.makeAttributeChangedCallback(child[1])
      else:
        typeSection.addAttribute(child)
        observedAttributes.add($child[0])
    of nnkDiscardStmt:
      discard
    else:
      expectKind(child, nnkCall)

  let
    observedAttributesString = "[\"" & `observedAttributes`.join("\", \"") & "\"]"
    emitSection1 = quote do:
      {.emit: "class " & `clsName` & " extends HTMLElement {".}
    emitSection2 = quote do:
      {.emit: "static get observedAttributes() {\nreturn " &
          `observedAttributesString` & ";\n}\n}".}
    defineSection = quote do:
      {.emit: "customElements.define(\"" & `name` & "\", " & `clsName` & ");".}

  result = newStmtList()
  with result:
    add typeSection
    add emitSection1
    add constructorSection
    add emitSection2
    add bodySection
    add defineSection
