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

  // "list" | "settings" | "trigger"
  property string view: "list"
  property var expanded: ({})
  property bool textFocus: false
  property var triggerRepo: null
  property var triggerWorkflow: null
  property var formValues: ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color green: "#3fb950"
  readonly property color amber: "#d29922"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

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
  }

  function back() {
    if (view !== "list" && gh.authenticated) setView("list")
    else close()
  }

  function toggleRepo(name) {
    var next = Object.assign({}, expanded)
    next[name] = !next[name]
    expanded = next
  }

  function startTrigger(repo, workflow) {
    triggerRepo = repo
    triggerWorkflow = workflow
    formValues = {}
    refField.text = repo.defaultBranch
    setView("trigger")
    gh.loadInputs(repo.name, workflow, repo.defaultBranch)
  }

  function runTrigger() {
    var values = {}
    for (var key in formValues) values[key] = String(formValues[key])
    gh.dispatch(triggerRepo.name, triggerWorkflow, refField.text.trim() || triggerRepo.defaultBranch, values)
  }

  function runState(run) {
    if (!run) return { glyph: "", color: dim, label: "Never run" }
    if (run.running) return { glyph: "", color: amber, label: run.status.replace("_", " ") }
    if (run.conclusion === "success") return { glyph: "", color: green, label: "success" }
    if (run.conclusion === "failure" || run.conclusion === "timed_out" || run.conclusion === "startup_failure")
      return { glyph: "", color: urgent, label: run.conclusion.replace("_", " ") }
    return { glyph: "", color: dim, label: run.conclusion || run.status }
  }

  function repoState(repo) {
    var worst = null
    for (var i = 0; i < repo.workflows.length; i++) {
      var run = repo.workflows[i].run
      if (!run) continue
      if (run.running) return runState(run)
      if (!worst || runState(run).color === urgent) worst = run
    }
    return runState(worst)
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
    onDispatched: root.setView("list")
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
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(680))

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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: root.view === "trigger" && root.triggerWorkflow ? root.triggerWorkflow.name : "GitHub Actions"
            meta: root.view === "settings" ? "Settings"
              : root.view === "trigger" && root.triggerRepo ? "Run workflow · " + root.triggerRepo.name
              : gh.loading && gh.repos.length === 0 ? "Loading workflows"
              : (gh.runningCount > 0 ? gh.runningCount + " running · " : "") + gh.visibleRepos.length + " repositories"
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
                onClicked: root.view === "list" ? root.setView("settings") : root.setView("list")
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
            visible: root.view === "list"
            width: parent.width
            spacing: Style.space(4)

            Text {
              visible: gh.authenticated && !gh.loading && gh.visibleRepos.length === 0
              width: parent.width
              text: "No workflows found"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: gh.visibleRepos

              Column {
                id: repoGroup
                required property var modelData
                readonly property bool isOpen: root.expanded[modelData.name] === true
                width: parent.width
                spacing: Style.space(2)

                CursorSurface {
                  id: repoHeader
                  width: parent.width
                  foreground: root.foreground
                  hasCursor: repoMouse.containsMouse
                  implicitHeight: repoRow.implicitHeight + Style.spacing.rowPaddingX

                  MouseArea {
                    id: repoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleRepo(repoGroup.modelData.name)
                  }

                  RowLayout {
                    id: repoRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(8)

                    Text {
                      text: repoGroup.isOpen ? "" : ""
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      Layout.preferredWidth: Style.space(12)
                    }

                    Text {
                      Layout.fillWidth: true
                      text: repoGroup.modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideMiddle
                    }

                    StatusGlyph { info: root.repoState(repoGroup.modelData) }
                  }
                }

                Repeater {
                  model: repoGroup.isOpen ? repoGroup.modelData.workflows : []

                  WorkflowRow {
                    required property var modelData
                    width: parent.width
                    repo: repoGroup.modelData
                    workflow: modelData
                  }
                }
              }
            }
          }

          // ---------- Settings ----------
          Column {
            visible: root.view === "settings"
            width: parent.width
            spacing: Style.space(12)

            Text {
              width: parent.width
              text: "Signed in as " + gh.user + " via the gh CLI"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              visible: gh.repos.length > 0
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "SHOWN WORKFLOWS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: gh.repos

                Column {
                  id: settingsRepo
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(2)

                  Text {
                    text: settingsRepo.modelData.name
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    leftPadding: Style.space(10)
                    topPadding: Style.space(4)
                  }

                  Repeater {
                    model: settingsRepo.modelData.workflows

                    Toggle {
                      required property var modelData
                      width: parent.width
                      label: modelData.name
                      checked: gh.hidden.indexOf(modelData.id) < 0
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      titleSize: Style.font.body
                      onClicked: gh.setHidden(modelData.id, checked)
                    }
                  }
                }
              }
            }
          }

          // ---------- Trigger form ----------
          Column {
            visible: root.view === "trigger"
            width: parent.width
            spacing: Style.space(10)

            InputLabel { text: "Branch or tag" }

            TextField {
              id: refField
              width: parent.width
              foreground: root.foreground
              font.family: root.fontFamily
              onActiveFocusChanged: root.textFocus = activeFocus
              onAccepted: if (root.triggerWorkflow) gh.loadInputs(root.triggerRepo.name, root.triggerWorkflow, text.trim())
              Keys.onEscapePressed: root.back()
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
                property var value: modelData.default
                width: parent.width
                spacing: Style.space(4)

                Component.onCompleted: root.formValues[modelData.key] = value
                onValueChanged: root.formValues[modelData.key] = value

                InputLabel {
                  visible: inputItem.kind !== "boolean"
                  text: inputItem.modelData.description + (inputItem.modelData.required ? " *" : "")
                }

                Toggle {
                  visible: inputItem.kind === "boolean"
                  width: parent.width
                  label: inputItem.modelData.description + (inputItem.modelData.required ? " *" : "")
                  checked: inputItem.value === true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  titleSize: Style.font.body
                  onClicked: inputItem.value = !checked
                }

                Dropdown {
                  visible: inputItem.kind === "choice"
                  width: parent.width
                  showLabel: false
                  options: inputItem.modelData.options
                  value: String(inputItem.value)
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(v) { inputItem.value = v }
                }

                TextField {
                  visible: inputItem.isText
                  width: parent.width
                  text: inputItem.isText ? String(inputItem.modelData.default) : ""
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onActiveFocusChanged: root.textFocus = activeFocus
                  onTextChanged: if (inputItem.isText) inputItem.value = text
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

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              Button {
                Layout.fillWidth: true
                text: "Cancel"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setView("list")
              }

              Button {
                Layout.fillWidth: true
                text: gh.dispatching ? "Starting…" : "Run workflow"
                iconText: ""
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !gh.inputsLoading && !gh.dispatching && gh.triggerError.indexOf("workflow_dispatch") < 0
                onClicked: root.runTrigger()
              }
            }
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

  component StatusGlyph: Text {
    id: glyph
    property var info: null
    text: info ? info.glyph : ""
    color: info ? info.color : root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body

    RotationAnimator on rotation {
      running: glyph.info !== null && glyph.info.glyph === ""
      from: 0
      to: 360
      duration: 1200
      loops: Animation.Infinite
      onRunningChanged: if (!running) glyph.rotation = 0
    }
  }

  component WorkflowRow: CursorSurface {
    id: row
    property var repo: null
    property var workflow: null
    readonly property var info: root.runState(workflow.run)

    foreground: root.foreground
    hasCursor: rowMouse.containsMouse
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX
    opacity: workflow.active ? 1.0 : 0.5

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openUrl(row.workflow.run ? row.workflow.run.url : row.workflow.url)
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(30)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(9)

      StatusGlyph {
        info: row.info
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(1)
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: row.workflow.name
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: {
            var run = row.workflow.run
            if (!row.workflow.active) return "Disabled on GitHub"
            if (!run) return "Never run"
            return [row.info.label, run.branch, run.event, run.ago].filter(function(p) { return p }).join(" · ")
          }
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

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
}
