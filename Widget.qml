import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Night sky for the Omarchy bar. Runs bin/night-sky --bar from this plugin's folder every
// few minutes. Pill: next sunrise/sunset, moon glyph and moon-free dark hours, plus a cloud
// or aurora glyph when the night calls for it. Left click opens the night panel: night, place,
// verdict, best interval and subject always on top; then Tonight (chart, clouds, twilight),
// Details, Week and Places tabs, most useful first. Right click refreshes.
BarWidget {
  id: root
  moduleName: "buschbrian.night-sky"

  property var night: null
  property var view: null
  property int dayOffset: 0
  property bool popupOpen: false
  property real nowMs: Date.now()
  property int tab: 0
  property string mode: String(setting("mode", "milky-way"))
  property string savedLocation: String(setting("savedLocation", ""))
  property var comparison: []
  property string locationMessage: ""
  property var places: []
  readonly property var modes: [
    { key: "milky-way", label: "Milky Way" }, { key: "meteors", label: "Meteors" },
    { key: "aurora", label: "Aurora" }, { key: "moonlit", label: "Moonlit" }
  ]

  // Normalised to null: a "set location" reply or an older cached reply has no panel or shoot.
  readonly property var panel: view && view.panel ? view.panel : null
  readonly property var line: panel && panel.timeline ? panel.timeline : null
  readonly property var shoot: panel && panel.shoot ? panel.shoot : null
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // One palette for the chart, the lanes and the event cards.
  readonly property var bandColors: ({ day: "#8fb4d9", golden: "#dba254", blue: "#507fc4", twilight: "#354568", dark: "#141e33" })
  readonly property color sunColor: "#f2b347"
  readonly property color moonColor: "#ece6d2"
  readonly property color coreColor: "#72d6db"
  readonly property real gutter: Style.space(52)

  // Design tokens: every glyph is one size in one column width; two text tones; theme spacing.
  readonly property real iconSize: Style.font.iconSmall
  readonly property real iconBox: Style.space(14)
  readonly property color muted: Qt.darker(fg, 1.5)
  readonly property real sectionGap: Style.spacing.xxl
  readonly property real itemGap: Style.spacing.sm
  readonly property var tabs: ["Tonight", "Details", "Week", "Places"]

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("bin/night-sky").toString().replace(/^file:\/\//, ""))
  readonly property real auroraKp: Number(setting("auroraKp", 6))
  readonly property var baseArgs: {
    var args = ["python3", script, "--bar", "--aurora-kp", String(auroraKp), "--mode", mode]
    if (savedLocation !== "") args.push("--saved-location", savedLocation)
    var tz = String(setting("timezone", "")).trim(), name = String(setting("locationName", "")).trim()
    if (tz !== "") args.push("--tz", tz)
    if (name !== "") args.push("--location-name", name)
    var lat = String(setting("latitude", "")).trim(), lon = String(setting("longitude", "")).trim()
    if (lat !== "" && lon !== "" && !isNaN(Number(lat)) && !isNaN(Number(lon))) args.push("--lat", lat, "--lon", lon)
    if (!setting("network", true)) args.push("--offline")
    var focal = Number(setting("focalLength", 0)), aperture = Number(setting("aperture", "")),
        pitch = Number(setting("pixelPitch", "")), crop = Number(setting("cropFactor", "1"))
    if (focal > 0) {
      args.push("--focal", String(focal), "--crop", String(crop > 0 ? crop : 1))
      if (aperture > 0) args.push("--aperture", String(aperture))
      if (pitch > 0) args.push("--pitch", String(pitch))
    }
    return args
  }
  onBaseArgsChanged: { dayOffset = 0; comparison = []; refresh() }

  visible: night !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function close() { popupOpen = false; dayOffset = 0; tab = 0 }
  function open() { view = night; popupOpen = true; placesProc.running = true }
  property bool rerun: false
  // A settings change while a run is in flight would otherwise be dropped.
  property var runArgs: []
  property var browseArgs: []
  property string wantedDate: ""
  function refresh() {
    if (skyProc.running) rerun = true
    else { runArgs = baseArgs.slice(); skyProc.running = true }
  }
  function browse() {
    if (browseProc.running || dayOffset === 0) return
    browseArgs = baseArgs.concat(["--date", wantedDate])
    browseProc.running = true
  }
  function ago(iso) {
    if (!iso) return "never checked"
    var m = Math.max(0, Math.floor((nowMs - new Date(iso).getTime()) / 60000))
    return m < 1 ? "just now" : m < 60 ? m + "m ago" : Math.floor(m / 60) + "h ago"
  }
  readonly property bool anyStale: panel !== null && panel.sources !== undefined
    && ["clouds", "haze", "kp"].some(function(k) { return panel.sources[k].stale })
  function sourcesLine() {
    if (!panel || !panel.sources) return ""
    return "Updated · " + ["clouds", "haze", "kp"].map(function(key) {
      var s = panel.sources[key], label = ({ clouds: "clouds", haze: "haze", kp: "Kp" })[key]
      return label + " " + (s.updated ? ago(s.updated) : "never") + (s.stale ? " (stale)" : "") + (!s.available ? " (no data tonight)" : "")
    }).join(" · ")
  }
  function duration(m) { return Math.floor(m / 60) + "h" + ("0" + m % 60).slice(-2) }
  function comparePlaces() {
    if (compareProc.running) return
    comparison = []
    compareArgs = baseArgs.concat(["--compare-locations", "--date", panel.date])
    compareProc.running = true
  }
  property var compareArgs: []
  property var placeArgs: []
  function savePlace() {
    if (placeProc.running) return
    locationMessage = ""
    placeArgs = ["python3", script, "--save-location", placeNameField.text, "--lat", placeLat.text,
                 "--lon", placeLon.text, "--tz", placeTz.text]
    placeProc.running = true
  }
  function removePlace(name) {
    if (placeProc.running) return
    locationMessage = ""
    if (savedLocation === name) savedLocation = ""
    placeArgs = ["python3", script, "--remove-location", name]
    placeProc.running = true
  }

  function viewDate() {
    var d = new Date(night.panel.date + "T12:00:00")
    d.setDate(d.getDate() + dayOffset)
    return Qt.formatDate(d, "yyyy-MM-dd")
  }

  function step(days) {
    if (!night || !night.panel) return
    panelScroll.contentY = 0
    dayOffset = Math.max(-30, Math.min(365, dayOffset + days))
    if (dayOffset === 0) { view = night; return }
    wantedDate = viewDate()
    comparison = []
    browse()
  }

  function title() {
    if (!panel) return ""
    var label = Qt.formatDate(new Date(panel.date + "T12:00:00"), "ddd d MMM")
    if (dayOffset === 0) return "Tonight · " + label
    return dayOffset === 1 ? "Tomorrow · " + label : label
  }

  function moonTimes() {
    var spans = line ? line.moon : []
    if (!spans.length) return "not up"
    var first = spans[0], last = spans[spans.length - 1]
    var start = first.a === 0 ? "up at dusk" : "rises " + first.start
    return last.b === 1 ? (first.a === 0 ? "up all night" : start) : start + ", sets " + last.end
  }

  function minutesBetween(a, b) {
    if (a === "--" || b === "--") return ""
    var m = (parseInt(b.slice(0, 2)) * 60 + parseInt(b.slice(3))) - (parseInt(a.slice(0, 2)) * 60 + parseInt(a.slice(3)))
    return " " + ((m + 1440) % 1440) + "m"
  }

  function kpColor(kp) {
    if (kp >= 7) return "#c24bd6"
    if (kp >= 6) return "#e0457b"
    if (kp >= 5) return "#e08a3a"
    if (kp >= 4) return "#d9c34a"
    return "#4caf7a"
  }

  function rgba(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  readonly property var levelColors: ({ "go": "#4caf7a", "marginal": "#e3b341", "no-go": "#e0574f" })
  readonly property var ratingColors: ({ good: "#4caf7a", marginal: "#e3b341", poor: "#e0574f", unavailable: "#808080", shown: "#808080" })
  readonly property var factorNames: ({ shoot_minutes: "Target window", moon_free_minutes: "Moon-free", cloud_cover_total: "Clouds", cloud_cover_max_hour: "Cloud peak",
    aerosol_optical_depth: "Haze", wind_gust: "Gusts", dew_point_spread: "Dew spread", gc_max_altitude: "Core", jet_stream: "Jet stream" })


  function goToDate(iso) {
    if (!night || !night.panel) return
    var base = new Date(night.panel.date + "T12:00:00"), target = new Date(iso + "T12:00:00")
    step(Math.round((target - base) / 86400000) - dayOffset)
    tab = 0
  }

  IpcHandler {
    target: "buschbrian.night-sky"
    function toggle(): void { if (root.popupOpen) root.close(); else root.open() }
    function step(days: int): void { root.step(days) }
    function showTab(index: int): void { root.tab = Math.max(0, Math.min(root.tabs.length - 1, index)); panelScroll.contentY = 0 }
    function selectMode(key: string): void { if (root.modes.some(function(m) { return m.key === key })) root.mode = key }
    function selectLocation(name: string): void { if (name === "" || root.places.some(function(p) { return p.name === name })) root.savedLocation = name }
    function compare(): void { if (root.panel) root.comparePlaces() }
  }

  Process {
    id: skyProc
    command: root.runArgs
    onExited: if (root.rerun) { root.rerun = false; root.refresh() }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (JSON.stringify(root.runArgs) !== JSON.stringify(root.baseArgs)) return
          root.night = JSON.parse(text)
          if (root.night.panel) root.places = root.night.panel.saved_locations
          if (root.dayOffset === 0) root.view = root.night
        } catch (e) { root.night = null }
      }
    }
  }

  Process {
    id: browseProc
    command: root.browseArgs
    onExited: if (root.dayOffset !== 0 && JSON.stringify(root.browseArgs) !== JSON.stringify(root.baseArgs.concat(["--date", root.wantedDate]))) root.browse()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.dayOffset === 0 || JSON.stringify(root.browseArgs) !== JSON.stringify(root.baseArgs.concat(["--date", root.wantedDate]))) return
        try { root.view = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Process {
    id: placesProc
    command: ["python3", root.script, "--list-locations"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.places = JSON.parse(text) } catch (e) {} }
    }
  }
  Process {
    id: placeProc
    command: root.placeArgs
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.error) root.locationMessage = result.error
          else {
            root.places = result.saved_locations
            root.locationMessage = "Saved locations updated."
            placeNameField.text = ""; placeLat.text = ""; placeLon.text = ""; placeTz.text = ""
            root.comparison = []
            root.refresh()
          }
        } catch (e) { root.locationMessage = "Could not save. Check the coordinates and time zone." }
      }
    }
  }
  Process {
    id: compareProc
    command: root.compareArgs
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (root.panel && JSON.stringify(root.compareArgs) === JSON.stringify(root.baseArgs.concat(["--compare-locations", "--date", root.panel.date])))
            root.comparison = JSON.parse(text).comparison
        } catch (e) { root.locationMessage = "Could not compare locations." }
      }
    }
  }

  Timer {
    interval: Math.max(5, Number(root.setting("refreshMinutes", 10))) * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 60 * 1000
    running: root.popupOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.night ? root.night.text : ""
    active: root.night !== null && root.night.class === "go"
    horizontalMargin: 6
    tooltipText: root.popupOpen ? "" : (root.night ? root.night.tooltip : "")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (root.popupOpen) root.close()
      else root.open()
    }
  }

  // KeyboardPanel, not PopupCard: an xdg-popup never receives keys, so the Places form could not be typed into.
  KeyboardPanel {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen && root.panel !== null
    focusTarget: panelFocus
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(560))

    FocusScope {
      id: panelFocus
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

    Flickable {
      id: panelScroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      QQC.ScrollBar.vertical: QQC.ScrollBar {
        policy: QQC.ScrollBar.AsNeeded
        visible: panelScroll.contentHeight > panelScroll.height + 2
        contentItem: Rectangle { implicitWidth: Style.space(3); radius: width / 2; color: root.fg; opacity: 0.5 }
      }

    Column {
      id: column
      width: panelScroll.width - Style.space(8)
      spacing: root.sectionGap

      // ================= Always visible: which night, where, and whether to go
      Column {
        width: parent.width
        spacing: root.itemGap

        Item {
          width: parent.width
          height: Math.max(nightNavigation.implicitHeight, placeControls.implicitHeight)

          Row {
            id: nightNavigation
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Button { iconText: "󰅁"; iconSize: root.iconSize; horizontalPadding: Style.spacing.xs; verticalPadding: Style.spacing.xxs; foreground: root.fg; tooltipText: "Previous night"; focusable: true; onClicked: root.step(-1) }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, column.width - placeControls.width - Style.space(110))
              elide: Text.ElideRight
              text: root.title()
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Button { iconText: "󰅂"; iconSize: root.iconSize; horizontalPadding: Style.spacing.xs; verticalPadding: Style.spacing.xxs; foreground: root.fg; tooltipText: "Next night"; focusable: true; onClicked: root.step(1) }
            TextChoice {
              anchors.verticalCenter: parent.verticalCenter
              bottomPadding: 0
              visible: root.dayOffset !== 0
              text: "tonight"
              ruled: false
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onActivated: root.step(-root.dayOffset)
            }
          }

          Row {
            id: placeControls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xxs
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "󰍎"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: root.iconSize
            }
            TextChoice {
              readonly property string name: root.panel && root.panel.location ? root.panel.location.name : ""
              anchors.verticalCenter: parent.verticalCenter
              bottomPadding: 0
              text: name.length > 20 ? name.slice(0, 19) + "…" : name
              ruled: false
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onActivated: { root.tab = 3; panelScroll.contentY = 0 }
            }
            Button {
              iconText: "󰑐"
              iconSize: root.iconSize
              horizontalPadding: Style.spacing.xs
              verticalPadding: Style.spacing.xxs
              foreground: root.fg
              tooltipText: "Refresh"
              focusable: true
              iconSpinning: skyProc.running || browseProc.running
              onClicked: { root.refresh(); if (root.dayOffset !== 0) root.browse() }
            }
          }
        }

        // The answer: shaded moon, verdict, best interval
        Row {
          width: parent.width
          spacing: Style.spacing.lg

          Canvas {
            id: moonCanvas
            width: Style.space(34)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            property real fraction: root.panel ? root.panel.moon.fraction : 0
            property bool waxing: root.panel ? root.panel.moon.waxing : true
            onFractionChanged: requestPaint()
            onWaxingChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var r = width / 2 - 1, cx = width / 2, cy = height / 2
              // Lit on the right while waxing as seen from the northern hemisphere; mirrored south.
              var side = (waxing ? 1 : -1) * (root.panel && root.panel.south ? -1 : 1), k = 1 - 2 * fraction
              var night = ctx.createRadialGradient(cx - r * 0.3, cy - r * 0.3, 0, cx, cy, r)
              night.addColorStop(0, root.rgba(root.fg, 0.16)); night.addColorStop(1, root.rgba(root.fg, 0.05))
              ctx.fillStyle = night
              ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
              // Lit limb from the top round to the bottom, back up along the terminator.
              var lit = ctx.createRadialGradient(cx + side * r * 0.35, cy - r * 0.35, 0, cx, cy, r)
              lit.addColorStop(0, "#fffaf0"); lit.addColorStop(0.6, root.moonColor); lit.addColorStop(1, "#a9a28c")
              ctx.fillStyle = lit
              ctx.beginPath()
              ctx.arc(cx, cy, r, -Math.PI / 2, Math.PI / 2, side < 0)
              for (var i = 0; i <= 32; i++) {
                var t = Math.PI / 2 - Math.PI * i / 32
                ctx.lineTo(cx + side * k * r * Math.cos(t), cy + r * Math.sin(t))
              }
              ctx.fill()
            }
          }

          Column {
            width: parent.width - moonCanvas.width - parent.spacing
            spacing: Style.spacing.xxs
            anchors.verticalCenter: parent.verticalCenter

            Row {
              spacing: Style.spacing.sm
              visible: root.shoot !== null
              Text {
                id: verdictText
                readonly property string headline: root.shoot ? root.shoot.headline : ""
                readonly property int split: headline.indexOf(" · ")
                textFormat: Text.StyledText
                text: root.shoot ? "<b><font color=\"" + root.levelColors[root.shoot.level] + "\">"
                      + (split < 0 ? headline : headline.slice(0, split)) + "</font></b>"
                      + (split < 0 ? "" : "&nbsp;&nbsp;" + headline.slice(split + 3)) : ""
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: if (root.bar) root.bar.showTooltip(verdictText, "Whole target window. The chart outlines the best interval.")
                  onExited: if (root.bar) root.bar.hideTooltip(verdictText)
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.shoot !== null && root.shoot.aurora === true
                text: "󰭄"
                color: root.kpColor(root.auroraKp)
                font.family: root.fontFamily
                font.pixelSize: root.iconSize
              }
            }

            Text {
              width: parent.width
              readonly property var best: root.panel ? root.panel.best_window : null
              text: best ? "Best " + best.headline + " · " + root.duration(best.minutes)
                      + (best.incomplete ? " · incomplete forecast" : "") + (best.stale ? " · stale forecast" : "")
                    : "No usable interval left in the forecast"
              color: best ? root.fg : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        Row {
          spacing: Style.spacing.lg
          Text {
            text: "Shooting"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            bottomPadding: Style.space(4)
          }
          Repeater {
            model: root.modes
            TextChoice {
              required property var modelData
              text: modelData.label
              selected: root.mode === modelData.key
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onActivated: root.mode = modelData.key
            }
          }
        }
      }

      // ---- Tabs over a hairline
      Item {
        width: parent.width
        height: tabRow.implicitHeight
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.rgba(root.fg, 0.12) }
        Row {
          id: tabRow
          spacing: Style.spacing.xxxl
          Repeater {
            model: root.tabs
            TextChoice {
              required property var modelData
              required property int index
              text: modelData
              selected: root.tab === index
              foreground: root.fg
              fontFamily: root.fontFamily
              onActivated: { root.tab = index; panelScroll.contentY = 0 }
            }
          }
        }
      }

      // ================= Tonight: when, at a glance
      Column {
        width: parent.width
        spacing: root.sectionGap
        visible: root.tab === 0 && root.line !== null

        Column {
          width: parent.width
          spacing: root.itemGap

          SkyTimeline {
            id: skyTimeline
            width: parent.width
            timeline: root.line
            bestWindow: root.panel ? root.panel.best_window : null
            nowMs: root.nowMs
            moonFraction: root.panel ? root.panel.moon.fraction : 0
            waxing: root.panel ? root.panel.moon.waxing : true
            south: root.panel ? root.panel.south : false
            foreground: root.fg
            fontFamily: root.fontFamily
            iconSize: root.iconSize
            sunColor: root.sunColor
            moonColor: root.moonColor
            coreColor: root.coreColor
            bandColors: root.bandColors
          }

          Lanes {
            width: parent.width
            timeline: root.line
            rows: ["clouds"]
            plotLeft: skyTimeline.plotLeft
            plotWidth: skyTimeline.plotWidth
            foreground: root.fg
            fontFamily: root.fontFamily
          }
        }

        // Evening and morning: one twilight gradient per row, times under their colour
        Column {
          width: parent.width
          spacing: root.itemGap

          Repeater {
            model: root.line ? [
              ["Evening", [
                ["#dba254", "Golden", root.line.events.evening.golden],
                ["#d9774f", "Sunset", root.line.events.evening.sunset],
                ["#507fc4", "Blue" + root.minutesBetween(root.line.events.evening.blue, root.line.events.evening.blue_end), root.line.events.evening.blue],
                ["#1c2742", "Dark", root.line.events.evening.dark]]],
              ["Morning", [
                ["#1c2742", "Dawn", root.line.events.morning.dawn],
                ["#507fc4", "Blue" + root.minutesBetween(root.line.events.morning.blue, root.line.events.morning.golden), root.line.events.morning.blue],
                ["#d9774f", "Sunrise", root.line.events.morning.sunrise],
                ["#dba254", "Golden to", root.line.events.morning.golden_end]]]
            ] : []

            Row {
              id: eventRow
              required property var modelData
              width: column.width

              Text {
                width: skyTimeline.plotLeft
                anchors.verticalCenter: parent.verticalCenter
                text: eventRow.modelData[0]
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Column {
                width: parent.width - skyTimeline.plotLeft
                spacing: Style.spacing.xxs

                Rectangle {
                  width: parent.width
                  height: Style.space(3)
                  radius: height / 2
                  gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.12; color: eventRow.modelData[1][0][0] }
                    GradientStop { position: 0.37; color: eventRow.modelData[1][1][0] }
                    GradientStop { position: 0.62; color: eventRow.modelData[1][2][0] }
                    GradientStop { position: 0.87; color: eventRow.modelData[1][3][0] }
                  }
                }

                Row {
                  width: parent.width
                  Repeater {
                    model: eventRow.modelData[1]
                    Text {
                      required property var modelData
                      width: parent.width / 4
                      textFormat: Text.StyledText
                      text: "<font color=\"" + root.muted + "\">" + modelData[1] + "</font>&nbsp;" + modelData[2]
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ================= Details: why, the other lanes, where to point, data
      Column {
        width: parent.width
        spacing: root.sectionGap
        visible: root.tab === 1

        // Conditions: every factor behind the verdict; advice-only ones have italic labels
        Column {
          width: parent.width
          spacing: root.itemGap
          visible: root.shoot !== null && root.shoot.factors.length > 0
          PanelSectionHeader { text: "Conditions"; foreground: root.fg; fontFamily: root.fontFamily }
          Grid {
            id: factorGrid
            width: parent.width
            columns: 3
            columnSpacing: Style.spacing.xxl
            rowSpacing: root.itemGap
            Repeater {
              model: root.shoot ? root.shoot.factors.slice().sort(function(a, b) { return (b.gates ? 1 : 0) - (a.gates ? 1 : 0) }) : []
              Row {
                id: factorCell
                required property var modelData
                width: (factorGrid.width - factorGrid.columnSpacing * 2) / 3
                spacing: Style.spacing.sm
                Text {
                  width: parent.width * 0.55
                  elide: Text.ElideRight
                  text: root.factorNames[factorCell.modelData.key] || factorCell.modelData.label
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.italic: !factorCell.modelData.gates
                }
                Text {
                  width: parent.width * 0.45 - parent.spacing
                  elide: Text.ElideRight
                  text: factorCell.modelData.value
                  color: factorCell.modelData.rating === "good" ? root.fg : root.ratingColors[factorCell.modelData.rating]
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: factorCell.modelData.rating === "poor"
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: root.itemGap
          visible: root.line !== null
          PanelSectionHeader { text: "Seeing and aurora"; foreground: root.fg; fontFamily: root.fontFamily }
          Lanes {
            width: parent.width
            timeline: root.line
            rows: ["seeing", "aurora"]
            plotLeft: skyTimeline.plotLeft
            plotWidth: skyTimeline.plotWidth
            auroraKp: root.auroraKp
            kpColor: root.kpColor
            foreground: root.fg
            fontFamily: root.fontFamily
          }
        }

        // Where to point, and what might spoil it
        Column {
          width: parent.width
          spacing: root.itemGap
          visible: root.line !== null
          PanelSectionHeader { text: "Where to point"; foreground: root.fg; fontFamily: root.fontFamily }

          Row {
            width: parent.width
            spacing: Style.spacing.lg

            Canvas {
              id: compassCanvas
              width: Style.space(48)
              height: width
              property var core: root.line ? root.line.core_best : null
              property var moonDir: root.line ? root.line.moon_dir : null
              onCoreChanged: requestPaint()
              onMoonDirChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2, r = width / 2 - 7
                var dial = ctx.createRadialGradient(cx, cy, 0, cx, cy, r)
                dial.addColorStop(0, root.rgba(root.fg, 0.02)); dial.addColorStop(1, root.rgba(root.fg, 0.1))
                ctx.fillStyle = dial
                ctx.beginPath(); ctx.arc(cx, cy, r, 0, 2 * Math.PI); ctx.fill()
                ctx.strokeStyle = root.rgba(root.fg, 0.3)
                ctx.lineWidth = 1
                ctx.stroke()
                ctx.fillStyle = root.rgba(root.fg, 0.6)
                ctx.font = Math.round(Style.font.caption * 0.8) + "px '" + root.fontFamily + "'"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                ctx.fillText("N", cx, 4)
                function arrow(az, color, len, w) {
                  var a = (az - 90) * Math.PI / 180
                  ctx.strokeStyle = color
                  ctx.lineWidth = w
                  ctx.lineCap = "round"
                  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(a) * len, cy + Math.sin(a) * len); ctx.stroke()
                  ctx.fillStyle = color
                  ctx.beginPath(); ctx.arc(cx + Math.cos(a) * len, cy + Math.sin(a) * len, w + 1, 0, 2 * Math.PI); ctx.fill()
                }
                if (moonDir) arrow(moonDir.az, root.moonColor, r - 2, 1.5)
                if (core) arrow(core.az, root.coreColor, r - 2, 2)
                ctx.fillStyle = root.fg
                ctx.beginPath(); ctx.arc(cx, cy, 2, 0, 2 * Math.PI); ctx.fill()
              }
            }

            Column {
              id: pointList
              width: parent.width - compassCanvas.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Repeater {
                model: root.line ? [
                  ["󰫢", root.coreColor, root.line.core_best
                    ? "Core best " + root.line.core_best.time + " · " + root.line.core_best.alt + "° " + root.line.core_best.dir + " (" + root.line.core_best.az + "°)"
                      + (root.line.core_best.moon_free ? "" : " · moonlit")
                    : "Milky Way core stays below the horizon in the dark"],
                  ["󰫢", root.coreColor, root.panel.core_times
                    ? "Core " + (root.panel.core_times.rise ? "rises " + root.panel.core_times.rise.time + " " + root.panel.core_times.rise.dir : "up all night")
                      + " · highest " + root.panel.core_times.transit.time + " " + root.panel.core_times.transit.alt + "° " + root.panel.core_times.transit.dir
                      + (root.panel.core_times.set ? " · sets " + root.panel.core_times.set.time + " " + root.panel.core_times.set.dir : "")
                    : "Core never rises here"],
                  ["󰽢", root.moonColor, root.line.moon_dir
                    ? "Moonrise " + root.line.moon_dir.time + " · " + root.line.moon_dir.dir + " (" + root.line.moon_dir.az + "°) · "
                      + root.panel.moon.phase + ", " + root.panel.moon.illumination_pct + "% lit"
                    : root.panel.moon.phase + ", " + root.panel.moon.illumination_pct + "% lit · moon " + root.moonTimes()]
                ].concat(root.panel.exposure ? [["󰄀", root.fg,
                    root.panel.exposure.focal + " mm" + (root.panel.exposure.aperture ? " f/" + root.panel.exposure.aperture : "") + ": "
                    + (root.panel.exposure.npf ? root.panel.exposure.npf + " s NPF (core) · " : "")
                    + root.panel.exposure.rule500 + " s 500 rule"]] : []).concat(root.panel.notes.map(function(n) {
                  return [n.indexOf("Aurora") === 0 ? "󰭄" : "󰖐", n.indexOf("Aurora") === 0 ? root.kpColor(root.auroraKp) : root.muted, n]
                })) : []

                Row {
                  id: pointRow
                  required property var modelData
                  spacing: Style.spacing.sm
                  Text {
                    id: pointGlyph
                    width: root.iconBox
                    text: pointRow.modelData[0]
                    color: pointRow.modelData[1]
                    font.family: root.fontFamily
                    font.pixelSize: root.iconSize
                  }
                  Text {
                    width: pointList.width - pointGlyph.width - pointRow.spacing
                    anchors.verticalCenter: pointGlyph.verticalCenter
                    wrapMode: Text.WordWrap
                    text: pointRow.modelData[2]
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: root.itemGap
          PanelSectionHeader { text: "Reading the chart"; foreground: root.fg; fontFamily: root.fontFamily }
          Text {
            width: parent.width
            text: "Hover or ← → on the chart to inspect · bold core: moon down, ≥10° · dashed: below horizon · Kp line: your threshold (Kp "
                  + root.auroraKp + "), faded bins forecast" + (root.mode === "aurora" ? ". Kp is a planning guide, not a visibility prediction." : "")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Text {
            width: parent.width
            text: root.sourcesLine()
            color: root.anyStale ? Color.urgent : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      // ================= Week & events
      Column {
        id: weekTab
        width: parent.width
        spacing: root.sectionGap
        visible: root.tab === 2

        Column {
          width: parent.width
          spacing: root.itemGap
          PanelSectionHeader { text: "Next seven nights"; foreground: root.fg; fontFamily: root.fontFamily }

          Row {
            id: weekRow
            width: parent.width
            Repeater {
              model: root.panel && root.panel.week ? root.panel.week : []
              Item {
                id: dayCard
                required property var modelData
                readonly property color tone: root.levelColors[modelData.level]
                width: weekRow.width / 7
                height: dayColumn.implicitHeight + Style.spacing.md * 2
                activeFocusOnTab: true
                Keys.onReturnPressed: root.goToDate(modelData.date)

                // Hover and focus wash, strongest at the top.
                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(5)
                  visible: dayArea.containsMouse || dayCard.activeFocus
                  gradient: Gradient {
                    GradientStop { position: 0; color: root.rgba(root.fg, 0.1) }
                    GradientStop { position: 1; color: root.rgba(root.fg, 0) }
                  }
                }

                Column {
                  id: dayColumn
                  anchors.centerIn: parent
                  spacing: Style.spacing.xxs
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: dayCard.modelData.day + " " + Qt.formatDate(new Date(dayCard.modelData.date + "T12:00:00"), "d"); color: dayCard.modelData.recommended ? Color.accent : root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: dayCard.modelData.glyph; color: root.moonColor; font.family: root.fontFamily; font.pixelSize: root.iconSize }
                  Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(26)
                    height: Style.space(3)
                    radius: height / 2
                    gradient: Gradient {
                      orientation: Gradient.Horizontal
                      GradientStop { position: 0; color: root.rgba(dayCard.tone, 0.35) }
                      GradientStop { position: 0.5; color: dayCard.tone }
                      GradientStop { position: 1; color: root.rgba(dayCard.tone, 0.35) }
                    }
                  }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.duration(dayCard.modelData.moon_free_minutes); color: root.fg; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: dayCard.modelData.cloud + (dayCard.modelData.incomplete ? "?" : ""); color: root.muted; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                }

                MouseArea {
                  id: dayArea
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  hoverEnabled: true
                  onEntered: if (root.bar) root.bar.showTooltip(dayCard, dayCard.modelData.headline + (dayCard.modelData.best_window ? "\nBest interval: " + dayCard.modelData.best_window.headline : "") + (dayCard.modelData.aurora ? " · aurora possible" : ""))
                  onExited: if (root.bar) root.bar.hideTooltip(dayCard)
                  onClicked: root.goToDate(dayCard.modelData.date)
                }
              }
            }
          }

          Text {
            width: parent.width
            text: root.panel && root.panel.week && root.panel.week.some(function(n) { return n.recommended })
                  ? "Accent: best night with a complete, fresh forecast · bar: verdict · moon-free hours · cloud · click to open"
                  : "No best night yet: that needs a usable interval with a complete, fresh forecast · click a night to open it"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          width: parent.width
          spacing: root.itemGap
          PanelSectionHeader { text: "Next 30 days"; foreground: root.fg; fontFamily: root.fontFamily }

          Repeater {
            model: root.panel && root.panel.events ? root.panel.events : []
            Row {
              id: eventLine
              required property var modelData
              width: weekTab.width
              spacing: Style.spacing.md
              Text {
                width: Style.space(62)
                text: eventLine.modelData.date
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: root.iconBox
                text: ({ moon: "󰽢", season: "󰖨", shower: "󰫢", festival: "󰋼", other: "󰋼" })[eventLine.modelData.kind] || "󰋼"
                color: eventLine.modelData.good ? root.levelColors.go : root.muted
                font.family: root.fontFamily
                font.pixelSize: root.iconSize
              }
              Column {
                width: eventLine.width - Style.space(62) - root.iconBox - eventLine.spacing * 2
                Text {
                  width: parent.width
                  text: eventLine.modelData.title
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: eventLine.modelData.good
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: eventLine.modelData.detail
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }
      }

      // ================= Places: pick, remove or compare, then add one
      Column {
        id: locationsTab
        width: parent.width
        visible: root.tab === 3
        spacing: root.sectionGap

        Column {
          width: parent.width
          spacing: root.itemGap

          Item {
            width: parent.width
            height: placesHeader.implicitHeight
            PanelSectionHeader { id: placesHeader; text: "Show the sky for"; foreground: root.fg; fontFamily: root.fontFamily }
            TextChoice {
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              bottomPadding: 0
              text: compareProc.running ? "comparing…" : "compare this night"
              ruled: false
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onActivated: root.comparePlaces()
            }
          }

          Repeater {
            model: [{ name: "", tz: "" }].concat(root.places)
            Item {
              id: placeRow
              required property var modelData
              readonly property bool isDefault: modelData.name === ""
              width: locationsTab.width
              height: placeChoice.implicitHeight

              TextChoice {
                id: placeChoice
                text: placeRow.isDefault ? "Default location" : placeRow.modelData.name
                selected: root.savedLocation === placeRow.modelData.name
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onActivated: root.savedLocation = placeRow.modelData.name
              }
              Text {
                x: placeChoice.width + Style.spacing.lg
                anchors.baseline: placeChoice.baseline
                text: placeRow.isDefault ? "widget settings or Omarchy weather" : placeRow.modelData.tz
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              TextChoice {
                anchors.right: parent.right
                anchors.baseline: placeChoice.baseline
                visible: !placeRow.isDefault
                enabled: !placeProc.running
                text: "remove"
                ruled: false
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onActivated: root.removePlace(placeRow.modelData.name)
              }
            }
          }

          Repeater {
            model: root.comparison
            Text {
              id: compareRow
              required property var modelData
              readonly property var best: modelData.best_window
              readonly property string level: best ? best.level : modelData.shoot.level
              width: locationsTab.width
              textFormat: Text.StyledText
              text: "<b><font color=\"" + root.levelColors[level] + "\">" + modelData.location.name + "</font></b>&nbsp;&nbsp;"
                    + (best ? best.headline + (best.incomplete ? " · incomplete forecast" : "") + (best.stale ? " · stale forecast" : "")
                       : modelData.shoot.headline + " · no usable interval")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        Column {
          width: parent.width
          spacing: root.itemGap
          PanelSectionHeader { text: "Add a location"; foreground: root.fg; fontFamily: root.fontFamily }
          TextField { id: placeNameField; width: parent.width; placeholderText: "Name"; foreground: root.fg; Keys.onEscapePressed: root.close() }
          Row {
            width: parent.width
            spacing: root.itemGap
            TextField { id: placeLat; width: (parent.width - parent.spacing) / 2; placeholderText: "Latitude · 38.29"; foreground: root.fg; Keys.onEscapePressed: root.close() }
            TextField { id: placeLon; width: (parent.width - parent.spacing) / 2; placeholderText: "Longitude · -111.26"; foreground: root.fg; Keys.onEscapePressed: root.close() }
          }
          TextField {
            id: placeTz
            width: parent.width
            placeholderText: "Time zone · America/Denver"
            foreground: root.fg
            Keys.onEscapePressed: root.close()
            Keys.onReturnPressed: if (saveButton.enabled) root.savePlace()
          }
          Item {
            width: parent.width
            height: saveButton.implicitHeight
            TextChoice {
              anchors.verticalCenter: parent.verticalCenter
              bottomPadding: 0
              text: "copy displayed location"
              ruled: false
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onActivated: {
                if (!root.panel || !root.panel.location) return
                var p = root.panel.location
                placeNameField.text = p.name; placeLat.text = String(p.lat); placeLon.text = String(p.lon); placeTz.text = p.tz
              }
            }
            Button {
              id: saveButton
              anchors.right: parent.right
              text: "Save"
              bordered: true
              foreground: root.fg
              fontSize: Style.font.caption
              horizontalPadding: Style.spacing.lg
              verticalPadding: Style.spacing.xs
              enabled: !placeProc.running && placeNameField.text.trim() !== "" && placeLat.text.trim() !== "" && placeLon.text.trim() !== ""
              focusable: true
              onClicked: root.savePlace()
            }
          }
          Text {
            width: parent.width
            text: root.locationMessage !== "" ? root.locationMessage
                  : "Times follow the place's time zone. Saving an existing name replaces it."
            color: root.locationMessage !== "" ? root.fg : root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
    }
    }
  }
}
