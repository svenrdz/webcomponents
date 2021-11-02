import dom, jsffi
import webcomponents

defineComponent("hello-world", HelloWorld):
  name: cstring

  constructor:
    this.name = "tata"

  attributeChangedCallback:
    if oldValue != newValue:
      this[property] = newValue

  connectedCallback:
    var
      shadow = this.attachShadow(smClosed)
      hwMsg = "Hello " & $this.name
    shadow.innerHTML = hwMsg
