import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property var repos: []
  property var hidden: []
  property bool loading: false
  property bool authenticated: false
  property string user: ""
  property string error: ""

  // Trigger form state
  property bool inputsLoading: false
  property var inputs: []
  property string triggerError: ""
  property bool dispatching: false

  signal dispatched()

  readonly property string helperPath: String(Qt.resolvedUrl("github_actions.py")).replace(/^file:\/\//, "")
  readonly property int refreshIntervalMinutes: {
    var value = parseInt(String(settings.refreshIntervalMinutes || 5), 10)
    return Math.max(1, Math.min(60, isFinite(value) ? value : 5))
  }
  readonly property var visibleRepos: {
    var result = []
    for (var i = 0; i < repos.length; i++) {
      var workflows = repos[i].workflows.filter(function(w) { return hidden.indexOf(w.id) < 0 })
      if (workflows.length > 0) result.push(Object.assign({}, repos[i], { workflows: workflows }))
    }
    return result
  }
  readonly property int runningCount: {
    var count = 0
    for (var i = 0; i < visibleRepos.length; i++)
      count += visibleRepos[i].workflows.filter(function(w) { return w.run && w.run.running }).length
    return count
  }

  function refresh() {
    if (listProcess.running) return
    loading = true
    listProcess.run(["list"], "")
  }

  function setHidden(id, isHidden) {
    var next = hidden.filter(function(h) { return h !== id })
    if (isHidden) next.push(id)
    hidden = next
    hiddenProcess.run(["set-hidden"], JSON.stringify(next))
  }

  function loadInputs(repo, workflow, ref) {
    inputs = []
    triggerError = ""
    inputsLoading = true
    inputsProcess.run(["inputs", repo, workflow.path, ref], "")
  }

  function dispatch(repo, workflow, ref, values) {
    triggerError = ""
    dispatching = true
    dispatchProcess.run(["dispatch", repo, workflow.id], JSON.stringify({ ref: ref, inputs: values }))
  }

  Timer {
    // Poll faster while the panel is open and something is running.
    interval: root.panelOpen && root.runningCount > 0 ? 15000 : root.refreshIntervalMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: afterDispatch
    interval: 4000
    onTriggered: root.refresh()
  }

  Helper {
    id: listProcess
    onDone: function(result) {
      root.loading = false
      if (result.auth === false) {
        root.authenticated = false
        root.user = ""
      }
      if (!result.ok) {
        root.error = result.error || "Could not load GitHub Actions"
        return
      }
      root.authenticated = true
      root.error = ""
      root.user = result.user
      root.repos = result.repos
      root.hidden = result.hidden
    }
  }

  Helper { id: hiddenProcess }

  Helper {
    id: inputsProcess
    onDone: function(result) {
      root.inputsLoading = false
      if (result.ok) root.inputs = result.inputs
      else root.triggerError = result.error || "Could not read workflow inputs"
    }
  }

  Helper {
    id: dispatchProcess
    onDone: function(result) {
      root.dispatching = false
      if (!result.ok) {
        root.triggerError = result.error || "Could not trigger the workflow"
        return
      }
      root.dispatched()
      afterDispatch.restart()
    }
  }

  // Runs the helper with one line on stdin and emits its parsed JSON reply.
  component Helper: Process {
    id: helper
    property string input: ""
    property string output: ""
    signal done(var result)

    function run(args, stdinText) {
      input = stdinText
      output = ""
      command = ["python3", root.helperPath].concat(args)
      running = true
    }

    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: helper.output = String(text || "")
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(input + "\n")
      input = ""
    }
    onExited: {
      var result
      try { result = JSON.parse(output) } catch (e) { result = { ok: false, error: "Could not run the GitHub helper" } }
      done(result)
    }
  }
}
