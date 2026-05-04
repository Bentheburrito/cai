// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
// import { hooks as colocatedHooks } from "phoenix-colocated/cai_newphx"
import topbar from "../vendor/topbar"


const setTheme = (theme) => {
  if (theme === "system") {
    localStorage.removeItem("phx:theme");
    document.documentElement.removeAttribute("data-theme");
  } else {
    localStorage.setItem("phx:theme", theme);
    document.documentElement.setAttribute("data-theme", theme);
  }
};
if (!document.documentElement.hasAttribute("data-theme")) {
  setTheme(localStorage.getItem("phx:theme") || "dark");
}
window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "dark"));

window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme));


const extractDateTime = element => {
  // The inner HTML should be a unix timestamp.
  const timestamp = parseInt(element.textContent);
  if (!timestamp) {
    console.error(`formatTimestamp: element's inner HTML is not an int: ${element.textContent}`);
    return;
  }

  // Multiply by 1000 to convert to MS and create a Date obj.
  const dateTimeObject = new Date(timestamp * 1000);
  if (!dateTimeObject) {
    console.error(`formatTimestamp: could not parse new Date(${timestamp * 1000})`);
    return;
  }

  return dateTimeObject;
}

const formatTimestamp = context => {
  const dateTimeObject = extractDateTime(context.el);
  if (!dateTimeObject) return;

  context.el.textContent = `${dateTimeObject.toLocaleDateString()} @ ${dateTimeObject.toLocaleTimeString()}`;
}

const hoverFormatTimestamp = context => {
  const dateTimeObject = extractDateTime(context.el);
  if (!dateTimeObject) return;

  context.el.textContent = dateTimeObject.toLocaleTimeString({}, { hour12: false });
  context.el.setAttribute("title", `${dateTimeObject.toLocaleDateString()} @ ${dateTimeObject.toLocaleTimeString()}`);
}

const Hooks = {
  // Format the given element when it is added or updated
  FormatTimestamp: {
    mounted () {
      formatTimestamp(this);
    },
    updated () {
      formatTimestamp(this);
    }
  },
  HoverFormatTimestamp: {
    mounted () {
      hoverFormatTimestamp(this);
    },
    updated () {
      hoverFormatTimestamp(this);
    }
  },
  BlurbPlayer: {
    mounted () {
      this.handleEvent("play-blurb", ({ track }) => {
        // Need to remove the . in extension names since it messes with querySelector
        track = track.replace(".", "");
        let audioElement = document.querySelector(`#blurb-source-${track}`);
        if (audioElement) audioElement.play();
      });
    }
  },
  BlurbSource: {
    mounted () {
      this.el.addEventListener("ended", _event => {
        this.pushEvent("blurb-ended", {});
      });
    }
  },
  BlurbVolumeControl: {
    mounted () {
      this.handleEvent("change-blurb-volume", ({ value }) => {
        let audioElements = document.querySelectorAll(`.blurb-source-audio`);
        for (let audio of audioElements) {
          audio.volume = value / 100;
        }
        console.log(`Set to ${value}`)
      });
    }
  },
  PinButton: {
    mounted () {
      let cookies = document.cookie;
      let pinned = cookies.split(';').find(cookie_pairs => cookie_pairs.trim().startsWith('pinned='))?.split('=')[1] || '';

      this.pushEvent("set-pinned", { pinned })
      this.handleEvent("set-pinned", ({ pinned: new_pinned }) => document.cookie = `pinned=${new_pinned};path=/;samesite=lax`);
    },
  }
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, { longPollFallbackMs: 2500, hooks: Hooks, params: { _csrf_token: csrfToken } })

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

