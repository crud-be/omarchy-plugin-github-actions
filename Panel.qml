import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "crud.github-actions"
  ipcTarget: "crud.github-actions"
  manageIpc: false

  // "list" | "settings" | "add" | "trigger"
  property string view: "list"
  property var expanded: ({})
  property var settingsExpanded: ({})
  property bool textFocus: false
  property string selectedRepo: ""
  property string selectedId: ""
  property var triggerRepo: null
  property var triggerWorkflow: null
  property var formValues: ({})
  property string branch: ""
  property string workflowQuery: ""
  property string repoQuery: ""

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color green: "#3fb950"
  readonly property color amber: "#d29922"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Settings: workflows per repo matching the search.
  readonly property var settingsGroups: {
    var query = workflowQuery.trim().toLowerCase()
    var result = []
    for (var i = 0; i < gh.repos.length; i++) {
      var repo = gh.repos[i]
      var repoMatch = query === "" || repo.name.toLowerCase().indexOf(query) >= 0
      var workflows = repo.workflows.filter(function(w) { return repoMatch || w.name.toLowerCase().indexOf(query) >= 0 })
      if (workflows.length > 0) result.push({ name: repo.name, workflows: workflows, total: repo.workflows.length })
    }
    return result
  }

  // Add view: accessible repositories matching the search, minus the added ones.
  readonly property var repoMatches: {
    var query = repoQuery.trim().toLowerCase()
    var added = gh.names()
    return gh.available.filter(function(name) {
      return added.indexOf(name) < 0 && (query === "" || name.toLowerCase().indexOf(query) >= 0)
    }).slice(0, 50)
  }
  readonly property bool typedRepoAddable: /^[\w.-]+\/[\w.-]+$/.test(repoQuery.trim())
    && gh.names().indexOf(repoQuery.trim()) < 0 && repoMatches.indexOf(repoQuery.trim()) < 0

  function openUrl(url) {
    if (!url) return
    close()
    Qt.callLater(function() { Qt.openUrlExternally(url) })
  }

  function setView(name) {
    view = name
    textFocus = false
    keyCatcher.forceActiveFocus()
    if (panelFlick) panelFlick.contentY = 0
    if (name === "add") {
      repoQuery = ""
      addField.text = ""
      gh.loadAvailable()
      addField.forceActiveFocus()
    }
  }

  function back() {
    if (view === "add") setView("settings")
    else if (view !== "list" && gh.authenticated) setView("list")
    else close()
  }

  function toggleIn(map, name) {
    var next = Object.assign({}, map)
    next[name] = !next[name]
    return next
  }

  function isExpanded(name) {
    return expanded[name] === undefined ? gh.visibleRepos.length === 1 : expanded[name]
  }

  function select(repo, workflow) {
    if (selectedId === workflow.id) {
      selectedId = ""
      return
    }
    selectedRepo = repo.name
    selectedId = workflow.id
    gh.loadRuns(repo.name, workflow.id)
  }

  function addTyped() {
    var name = typedRepoAddable ? repoQuery.trim() : (repoMatches.length > 0 ? repoMatches[0] : "")
    if (name && gh.addRepo(name)) {
      addField.text = ""
      repoQuery = ""
    }
  }

  function startTrigger(repo, workflow) {
    triggerRepo = repo
    triggerWorkflow = workflow
    formValues = {}
    refField.text = repo.defaultBranch
    branch = repo.defaultBranch
    setView("trigger")
    gh.loadInputs(repo.name, workflow, repo.defaultBranch)
  }

  function setValue(key, value) {
    var next = Object.assign({}, formValues)
    next[key] = value
    formValues = next
  }

  // Toggle one option of a choice input; at least one stays picked.
  function toggleChoice(key, option) {
    var picked = (formValues[key] || []).slice()
    var at = picked.indexOf(option)
    if (at < 0) picked.push(option)
    else if (picked.length > 1) picked.splice(at, 1)
    setValue(key, picked)
  }

  function runTrigger() {
    if (inputSets.length > 0) gh.dispatch(triggerRepo.name, triggerWorkflow, branch || triggerRepo.defaultBranch, inputSets)
  }

  function runState(run) {
    if (run.running) return { glyph: "", color: amber }
    if (run.conclusion === "success") return { glyph: "", color: green }
    if (run.conclusion === "failure" || run.conclusion === "timed_out" || run.conclusion === "startup_failure")
      return { glyph: "", color: urgent }
    return { glyph: "", color: dim }
  }

  // One set of inputs per combination of picked choice values.
  readonly property var inputSets: {
    var sets = [{}]
    for (var k = 0; k < gh.inputs.length; k++) {
      var key = gh.inputs[k].key
      var value = formValues[key]
      if (value === undefined) continue
      var options = Array.isArray(value) ? value : [value]
      var next = []
      for (var i = 0; i < sets.length; i++)
        for (var j = 0; j < options.length; j++) {
          var set = Object.assign({}, sets[i])
          set[key] = String(options[j])
          next.push(set)
        }
      sets = next
    }
    return sets
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    setView("list")
    gh.refresh()
  }

  GithubService {
    id: gh
    settings: root.settings
    panelOpen: root.opened
    onDispatched: {
      root.selectedRepo = root.triggerRepo.name
      root.selectedId = root.triggerWorkflow.id
      root.setView("list")
    }
    // Keep the selected workflow's runs as fresh as the list.
    onReposChanged: if (root.opened && root.selectedId !== "" && !loading) loadRuns(root.selectedRepo, root.selectedId)
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { gh.refresh(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: gh.runningCount > 0
    activeColor: root.amber
    tooltipText: gh.error !== "" ? gh.error
      : (gh.runningCount > 0 ? gh.runningCount + " workflow" + (gh.runningCount === 1 ? "" : "s") + " running" : "GitHub Actions")
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(440))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.textFocus
      onCloseRequested: root.back()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(value) {
        if (value === "r" || value === "R") gh.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        readonly property bool scrollable: contentHeight > height + 1

        // Thin, always-visible bar in its own gutter so it never covers row actions.
        ScrollBar.vertical: ScrollBar {
          id: scrollBar
          policy: panelFlick.scrollable ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          padding: 0
          contentItem: Rectangle {
            implicitWidth: Style.space(4)
            radius: Style.cornerRadius > 0 ? width / 2 : 0
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
              scrollBar.pressed ? 0.6 : (scrollBar.hovered ? 0.45 : 0.3))
          }
          background: Rectangle {
            implicitWidth: Style.space(4)
            radius: Style.cornerRadius > 0 ? width / 2 : 0
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          }
        }

        Column {
          id: column
          width: panelFlick.width - (panelFlick.scrollable ? Style.space(14) : 0)
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.view === "trigger" && root.triggerWorkflow ? root.triggerWorkflow.name : "GitHub Actions"
            meta: root.view === "settings" ? (gh.user !== "" ? "Signed in as " + gh.user : "Settings")
              : root.view === "add" ? "Add repository"
              : root.view === "trigger" && root.triggerRepo ? "Run workflow · " + root.triggerRepo.name
              : gh.loading && gh.repos.length === 0 ? "Loading"
              : gh.runningCount > 0 ? gh.runningCount + " running"
              : gh.repos.length + (gh.repos.length === 1 ? " repository" : " repositories")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              PanelActionButton {
                visible: gh.authenticated
                iconText: root.view === "list" ? "" : ""
                tooltipText: root.view === "list" ? "Settings" : "Back"
                foreground: hero.foreground
                fontFamily: hero.fontFamily
                onClicked: root.view === "list" ? root.setView("settings") : root.back()
              }
            }
          }

          Text {
            visible: gh.error !== ""
            width: parent.width
            text: gh.error
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Workflow list ----------
          Column {
            visible: root.view === "list" && gh.authenticated
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            EmptyState {
              visible: !gh.loading && gh.repos.length === 0
              text: "Add the repositories whose workflows you want to run."
              actionText: "Add repository"
              onAction: root.setView("add")
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: gh.visibleRepos

                Column {
                  id: repoGroup
                  required property var modelData
                  readonly property bool isOpen: root.isExpanded(modelData.name)
                  readonly property int running: modelData.workflows.filter(function(w) { return w.running }).length
                  width: parent.width
                  spacing: Style.space(2)

                  GroupHeader {
                    width: parent.width
                    open: repoGroup.isOpen
                    title: repoGroup.modelData.name
                    detail: repoGroup.modelData.error || (repoGroup.modelData.loading ? "Loading" : "")
                    detailColor: repoGroup.modelData.error ? root.urgent : root.dim
                    spinning: repoGroup.running > 0
                    onClicked: {
                      var next = Object.assign({}, root.expanded)
                      next[repoGroup.modelData.name] = !repoGroup.isOpen
                      root.expanded = next
                    }
                  }

                  Repeater {
                    model: repoGroup.isOpen ? repoGroup.modelData.workflows : []

                    Column {
                      id: workflowItem
                      required property var modelData
                      readonly property bool selected: root.selectedId === modelData.id
                      width: parent.width
                      spacing: Style.space(2)

                      WorkflowRow {
                        width: parent.width
                        repo: repoGroup.modelData
                        workflow: workflowItem.modelData
                        current: workflowItem.selected
                      }

                      RunList {
                        visible: workflowItem.selected
                        width: parent.width
                        workflow: workflowItem.modelData
                      }
                    }
                  }
                }
              }
            }
          }

          // ---------- Settings ----------
          Column {
            visible: root.view === "settings"
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            SectionHeader {
              text: "REPOSITORIES"
              actionIcon: ""
              actionTooltip: "Add repository"
              onAction: root.setView("add")
            }

            EmptyState {
              visible: gh.repos.length === 0
              text: "No repositories added yet."
              actionText: "Add repository"
              onAction: root.setView("add")
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: gh.repos

                RepoRow {
                  required property var modelData
                  width: parent.width
                  name: modelData.name
                  detail: modelData.error || ""
                  actionIcon: ""
                  actionTooltip: "Remove"
                  actionColor: root.urgent
                  onAction: gh.removeRepo(modelData.name)
                }
              }
            }

            PanelSeparator {
              visible: gh.repos.length > 0
              foreground: root.foreground
            }

            SectionHeader {
              visible: gh.repos.length > 0
              text: "SHOWN WORKFLOWS"
            }

            SearchField {
              id: workflowSearch
              visible: gh.repos.length > 0
              placeholderText: "Search workflows"
              onTextChanged: root.workflowQuery = text
            }

            Text {
              visible: gh.repos.length > 0 && root.settingsGroups.length === 0
              width: parent.width
              text: "No matching workflows"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              Repeater {
                model: root.settingsGroups

                Column {
                  id: settingsRepo
                  required property var modelData
                  // Searching opens every matching group.
                  readonly property bool isOpen: root.workflowQuery.trim() !== "" || root.settingsExpanded[modelData.name] === true
                  readonly property int shown: modelData.workflows.filter(function(w) { return gh.hidden.indexOf(w.id) < 0 }).length
                  width: parent.width
                  spacing: Style.space(2)

                  GroupHeader {
                    width: parent.width
                    open: settingsRepo.isOpen
                    title: settingsRepo.modelData.name
                    detail: root.workflowQuery.trim() !== "" ? "" : settingsRepo.shown + " of " + settingsRepo.modelData.total
                    onClicked: root.settingsExpanded = root.toggleIn(root.settingsExpanded, settingsRepo.modelData.name)
                  }

                  Repeater {
                    model: settingsRepo.isOpen ? settingsRepo.modelData.workflows : []

                    CursorSurface {
                      id: shownRow
                      required property var modelData
                      readonly property bool shown: gh.hidden.indexOf(modelData.id) < 0
                      width: parent.width
                      foreground: root.foreground
                      hasCursor: shownMouse.containsMouse
                      implicitHeight: shownContent.implicitHeight + Style.spacing.lg

                      MouseArea {
                        id: shownMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: gh.setHidden(shownRow.modelData.id, shownRow.shown)
                      }

                      RowLayout {
                        id: shownContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(28)
                        anchors.rightMargin: Style.space(8)
                        spacing: Style.space(8)

                        Text {
                          Layout.fillWidth: true
                          text: shownRow.modelData.name
                          textFormat: Text.PlainText
                          color: shownRow.shown ? root.foreground : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                        }

                        ToggleSwitch {
                          checked: shownRow.shown
                          interactive: false
                          foreground: root.foreground
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ---------- Add repository ----------
          Column {
            visible: root.view === "add"
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            SearchField {
              id: addField
              placeholderText: "Search or type owner/name"
              onTextChanged: root.repoQuery = text
              onAccepted: root.addTyped()
            }

            Text {
              visible: gh.availableLoading
              width: parent.width
              text: "Loading your repositories…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              width: parent.width
              spacing: Style.space(2)

              RepoRow {
                visible: root.typedRepoAddable
                width: parent.width
                name: root.repoQuery.trim()
                actionIcon: ""
                actionTooltip: "Add"
                onAction: root.addTyped()
                onClicked: root.addTyped()
              }

              Repeater {
                model: root.repoMatches

                RepoRow {
                  required property string modelData
                  width: parent.width
                  name: modelData
                  actionIcon: ""
                  actionTooltip: "Add"
                  onAction: gh.addRepo(modelData)
                  onClicked: gh.addRepo(modelData)
                }
              }
            }

            Button {
              width: parent.width
              text: "Done"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setView("list")
            }
          }

          // ---------- Trigger form ----------
          Column {
            visible: root.view === "trigger"
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            SectionHeader { text: "BRANCH" }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                text: "\uf418"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                Layout.preferredWidth: Style.space(14)
              }

              TextField {
                id: refField
                Layout.fillWidth: true
                foreground: root.foreground
                font.family: root.fontFamily
                verticalPadding: Style.spacing.sm
                onActiveFocusChanged: root.textFocus = activeFocus
                onTextChanged: root.branch = text.trim()
                onAccepted: if (root.triggerWorkflow) gh.loadInputs(root.triggerRepo.name, root.triggerWorkflow, text.trim())
                Keys.onEscapePressed: root.back()
              }
            }

            Text {
              visible: gh.inputsLoading
              text: "Loading inputs…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: gh.inputsLoading ? [] : gh.inputs

              Column {
                id: inputItem
                required property var modelData
                readonly property string kind: modelData.type
                readonly property bool isText: kind !== "boolean" && kind !== "choice"
                readonly property var value: root.formValues[modelData.key]
                readonly property string label: modelData.description + (modelData.required ? " *" : "")
                width: parent.width
                spacing: Style.space(6)

                Component.onCompleted: root.setValue(modelData.key, kind === "choice"
                  ? (modelData.default !== "" ? [String(modelData.default)] : modelData.options.slice(0, 1))
                  : modelData.default)

                // Choice: pick one or more; each picked value gets its own run.
                Item {
                  visible: inputItem.kind === "choice"
                  width: parent.width
                  implicitHeight: choiceLabel.implicitHeight

                  InputLabel {
                    id: choiceLabel
                    width: parent.width - choiceHint.implicitWidth - Style.space(8)
                    text: inputItem.label
                  }

                  Text {
                    id: choiceHint
                    visible: inputItem.modelData.options.length > 1
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    text: "pick one or more"
                    color: Qt.darker(root.foreground, 1.8)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Flow {
                  visible: inputItem.kind === "choice"
                  width: parent.width
                  spacing: Style.spacing.xs

                  Repeater {
                    model: inputItem.kind === "choice" ? inputItem.modelData.options : []

                    Button {
                      required property string modelData
                      text: modelData
                      fontSize: Style.font.caption
                      horizontalPadding: Style.spacing.xl
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      active: Array.isArray(inputItem.value) && inputItem.value.indexOf(modelData) >= 0
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      onClicked: root.toggleChoice(inputItem.modelData.key, modelData)
                    }
                  }
                }

                CursorSurface {
                  id: boolRow
                  visible: inputItem.kind === "boolean"
                  width: parent.width
                  foreground: root.foreground
                  hasCursor: boolMouse.containsMouse
                  implicitHeight: boolContent.implicitHeight + Style.spacing.lg

                  MouseArea {
                    id: boolMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setValue(inputItem.modelData.key, inputItem.value !== true)
                  }

                  RowLayout {
                    id: boolContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      text: inputItem.label
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WordWrap
                    }

                    ToggleSwitch {
                      checked: inputItem.value === true
                      interactive: false
                      foreground: root.foreground
                    }
                  }
                }

                InputLabel {
                  visible: inputItem.isText
                  text: inputItem.label
                }

                TextField {
                  visible: inputItem.isText
                  width: parent.width
                  text: inputItem.isText ? String(inputItem.modelData.default) : ""
                  foreground: root.foreground
                  font.family: root.fontFamily
                  verticalPadding: Style.spacing.sm
                  onActiveFocusChanged: root.textFocus = activeFocus
                  onTextChanged: if (inputItem.isText) root.setValue(inputItem.modelData.key, text)
                  onAccepted: root.runTrigger()
                  Keys.onEscapePressed: root.back()
                }
              }
            }

            Text {
              visible: gh.triggerError !== ""
              width: parent.width
              text: gh.triggerError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Button {
              width: parent.width
              text: gh.dispatching ? "Starting…"
                : "Run on " + (root.branch || (root.triggerRepo ? root.triggerRepo.defaultBranch : ""))
                  + (root.inputSets.length > 1 ? " · " + root.inputSets.length + " runs" : "")
              iconText: "\uf04b"
              bordered: true
              active: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !gh.inputsLoading && !gh.dispatching && gh.triggerError.indexOf("workflow_dispatch") < 0
              onClicked: root.runTrigger()
            }
          }

          Item {
            width: parent.width
            height: Style.space(2)
          }
        }
      }
    }
  }

  component InputLabel: Text {
    width: parent ? parent.width : 0
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  component Spinner: Text {
    id: spinner
    property bool spinning: true
    text: ""
    color: root.amber
    font.family: root.fontFamily
    font.pixelSize: Style.font.body

    RotationAnimator on rotation {
      running: spinner.visible && spinner.spinning
      from: 0
      to: 360
      duration: 1200
      loops: Animation.Infinite
      onRunningChanged: if (!running) spinner.rotation = 0
    }
  }

  component SearchField: TextField {
    width: parent ? parent.width : 0
    foreground: root.foreground
    font.family: root.fontFamily
    onActiveFocusChanged: root.textFocus = activeFocus
    Keys.onEscapePressed: {
      if (text !== "") text = ""
      else root.back()
    }
  }

  // Section label with an optional action on the trailing edge.
  component SectionHeader: Item {
    id: section
    property string text: ""
    property string actionIcon: ""
    property string actionTooltip: ""
    signal action()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(sectionLabel.implicitHeight, sectionAction.visible ? sectionAction.implicitHeight : 0)

    PanelSectionHeader {
      id: sectionLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: section.text
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    PanelActionButton {
      id: sectionAction
      visible: section.actionIcon !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: section.actionIcon
      tooltipText: section.actionTooltip
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: section.action()
    }
  }

  component EmptyState: Column {
    id: empty
    property string text: ""
    property string actionText: ""
    signal action()

    width: parent ? parent.width : 0
    spacing: Style.space(10)
    topPadding: Style.space(6)
    bottomPadding: Style.space(6)

    Text {
      width: parent.width
      text: empty.text
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Button {
      anchors.horizontalCenter: parent.horizontalCenter
      text: empty.actionText
      iconText: ""
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: empty.action()
    }
  }

  // Collapsible repository header: chevron, name, and a dim detail on the right.
  component GroupHeader: CursorSurface {
    id: group
    property bool open: false
    property string title: ""
    property string detail: ""
    property color detailColor: root.dim
    property bool spinning: false
    signal clicked()

    foreground: root.foreground
    hasCursor: groupMouse.containsMouse
    implicitHeight: groupRow.implicitHeight + Style.spacing.xl

    MouseArea {
      id: groupMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: group.clicked()
    }

    RowLayout {
      id: groupRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: group.open ? "" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: Style.space(14)
      }

      Text {
        Layout.fillWidth: true
        text: group.title
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideMiddle
      }

      Text {
        visible: group.detail !== ""
        text: group.detail
        textFormat: Text.PlainText
        color: group.detailColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Spinner { visible: group.spinning }
    }
  }

  // Repository row with a leading repo glyph and one trailing action.
  component RepoRow: CursorSurface {
    id: repoRow
    property string name: ""
    property string detail: ""
    property string actionIcon: ""
    property string actionTooltip: ""
    property color actionColor: root.foreground
    signal action()
    signal clicked()

    foreground: root.foreground
    hasCursor: repoMouse.containsMouse
    implicitHeight: repoContent.implicitHeight + Style.spacing.xl

    MouseArea {
      id: repoMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: repoRow.clicked()
    }

    RowLayout {
      id: repoContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        text: ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        Layout.preferredWidth: Style.space(14)
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: repoRow.name
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideMiddle
        }

        Text {
          visible: repoRow.detail !== ""
          Layout.fillWidth: true
          text: repoRow.detail
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: repoRow.actionIcon
        tooltipText: repoRow.actionTooltip
        foreground: root.foreground
        hoverColor: repoRow.actionColor
        fontFamily: root.fontFamily
        onClicked: repoRow.action()
      }
    }
  }

  // A workflow: its name and a run button. Click to show the last runs.
  component WorkflowRow: CursorSurface {
    id: row
    property var repo: null
    property var workflow: null

    foreground: root.foreground
    hasCursor: rowMouse.containsMouse
    implicitHeight: rowContent.implicitHeight + Style.spacing.xxl
    opacity: workflow.active ? 1.0 : 0.5

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.select(row.repo, row.workflow)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(28)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        Layout.fillWidth: true
        text: row.workflow.name
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Spinner { visible: row.workflow.running }

      PanelActionButton {
        visible: row.workflow.dispatchable
        iconText: ""
        tooltipText: "Run workflow"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.startTrigger(row.repo, row.workflow)
      }
    }
  }

  // The last three runs of the selected workflow.
  component RunList: Column {
    id: runList
    property var workflow: null
    readonly property var runs: workflow ? gh.runs[workflow.id] : undefined
    readonly property bool loading: runs === undefined

    spacing: Style.space(2)
    topPadding: Style.space(2)
    bottomPadding: Style.space(6)

    Text {
      visible: runList.loading || (runList.runs !== undefined && runList.runs.length === 0)
      leftPadding: Style.space(28)
      topPadding: Style.space(4)
      bottomPadding: Style.space(4)
      text: runList.loading ? "Loading runs…" : "No runs yet"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: runList.loading ? [] : runList.runs

      CursorSurface {
        id: runRow
        required property var modelData
        readonly property var runInfo: root.runState(modelData)
        width: parent.width
        foreground: root.foreground
        hasCursor: runMouse.containsMouse
        implicitHeight: runContent.implicitHeight + Style.spacing.xl

        MouseArea {
          id: runMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openUrl(runRow.modelData.url)
        }

        RowLayout {
          id: runContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(28)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          Spinner {
            visible: runRow.modelData.running
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: !runRow.modelData.running
            text: runRow.runInfo.glyph
            color: runRow.runInfo.color
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            text: runRow.modelData.title
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            // The branch gives way to the run title when space is short.
            Layout.maximumWidth: runContent.width * 0.35
            text: runRow.modelData.branch
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            text: runRow.modelData.age
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
