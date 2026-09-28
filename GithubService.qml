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
  property bool refreshQueued: false

  // Repository picker
  property var available: []
  property bool availableLoading: false

  // Last runs of the selected workflow, keyed by workflow id
  property var runs: ({})

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
      if (workflows.length > 0 || repos[i].error || repos[i].loading) result.push(Object.assign({}, repos[i], { workflows: workflows }))
    }
    return result
  }
  readonly property int runningCount: {
    var count = 0
    for (var i = 0; i < visibleRepos.length; i++)
      count += visibleRepos[i].workflows.filter(function(w) { return w.running }).length
    return count
  }

  function refresh() {
    if (listProcess.running) {
      refreshQueued = true
      return
    }
    loading = true
    listProcess.run(["list"], "")
  }

  function names() {
    return repos.map(function(r) { return r.name })
  }

  function saveRepos(list) {
    reposProcess.run(["set-repos"], JSON.stringify(list))
  }

  function addRepo(name) {
    name = String(name || "").trim().replace(/^https:\/\/github\.com\//, "").replace(/\.git$|\/$/g, "")
    if (!/^[\w.-]+\/[\w.-]+$/.test(name) || names().indexOf(name) >= 0) return false
    repos = repos.concat([{ name: name, defaultBranch: "main", workflows: [], loading: true }])
    saveRepos(names())
    return true
  }

  function removeRepo(name) {
    repos = repos.filter(function(r) { return r.name !== name })
    saveRepos(names())
  }

  function loadAvailable() {
    if (availableProcess.running || available.length > 0) return
    availableLoading = true
    availableProcess.run(["repos"], "")
  }

  function loadRuns(repo, workflowId) {
    if (runsProcess.running) {
      runsProcess.pending = [repo, workflowId]
      return
    }
    runsProcess.workflowId = workflowId
    runsProcess.run(["runs", repo, workflowId], "")
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

  // Runs the workflow once per input set, one after another.
  function dispatch(repo, workflow, ref, inputSets) {
    afterDispatch.repo = repo
    afterDispatch.workflowId = workflow.id
    triggerError = ""
    dispatching = true
    dispatchProcess.queue = inputSets.slice(1)
    dispatchProcess.request = [repo, workflow.id, ref]
    dispatchProcess.run(["dispatch", repo, workflow.id], JSON.stringify({ ref: ref, inputs: inputSets[0] }))
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
    property string repo: ""
    property string workflowId: ""
    interval: 4000
    onTriggered: {
      root.refresh()
      root.loadRuns(repo, workflowId)
    }
  }

  Helper {
    id: listProcess
    onDone: function(result) {
      root.loading = false
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
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
    id: reposProcess
    onDone: root.refresh()
  }

  Helper {
    id: availableProcess
    onDone: function(result) {
      root.availableLoading = false
      if (result.ok) root.available = result.repos
    }
  }

  Helper {
    id: runsProcess
    property string workflowId: ""
    property var pending: null
    onDone: function(result) {
      var next = Object.assign({}, root.runs)
      next[workflowId] = result.ok ? result.runs : []
      root.runs = next
      if (pending) {
        var request = pending
        pending = null
        Qt.callLater(function() { root.loadRuns(request[0], request[1]) })
      }
    }
  }

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
    property var queue: []
    property var request: []
    onDone: function(result) {
      if (result.ok && queue.length > 0) {
        var values = queue[0]
        queue = queue.slice(1)
        Qt.callLater(function() {
          dispatchProcess.run(["dispatch", request[0], request[1]], JSON.stringify({ ref: request[2], inputs: values }))
        })
        return
      }
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
