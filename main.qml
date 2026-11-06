// Nav25 for QField
// A QField port of the Nav12 / Nav25 field-navigation rules (Terrex Spatial) for seismic set-out:
//   * 2D Stakeout guidance  - ATRACK / XTRACK to the next waypoint (bearings from consecutive waypoints),
//                             AutoSelect, AutoInc +/-1, Target Lock gates, From/To threshold
//   * Record a Point + QA   - Mark Position: Line Station / External Station / Feature, Check Pt, PM/Tie,
//                             3D / Elevation only / Position only, Instant / Current / Average (50 obs),
//                             MaxIntvl, MaxBend, DistTol and PTol/ZTol/QTol warnings, auto Mark ID
//   * No-Go / Warning zones - NG_ prefixed polygon layers = red No-Go, WZ_ prefixed = orange Warning;
//                             repeating alarm (Warning: fast first phase, then slower), as in Nav25
//   * On-target highlight  - whole screen goes green while inside both the inline (ATol) and crossline (XTol) gates
//
// Layers (see README):  preplot points (settings below), NG_* / WZ_* polygons, N25_Points (recorded points).
// The navigation/QA logic below the CORE marker is generated from nav25core.js (unit tested).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.qfield
import org.qgis
import org.qfield.core
import org.qfield.gui

Item {
  id: plugin

  property var mainWindow: iface.mainWindow()
  property var positioning: iface.positioning()
  property var mapCanvas: iface.mapCanvas()

  // ---- layers ----
  property var preplotLayerNames: []
  property string stationField: ""             // blank = auto-detect (settings tab)
  property string preplotName: ""              // blank = use preplotLayerNames, or auto-detect when that is empty too
  property string stnUse: ""                    // station / line field actually in use for this load
  property string lineUse: ""
  property string preplotInfo: ""
  property string lineField: ""
  property bool stationHasLinePrefix: false
  property string noGoPrefix: "NG_"
  property string warnPrefix: "WZ_"
  // explicit extra zone layers (by project layer name) in addition to the prefixes
  property var noGoNames: []
  property var warnNames: []
  property string recordLayerName: "N25_Points"
  property string mappingLayerName: "N25_Mapping"   // Feature points (GATE, HAZARD, FENCE ...) go here, symbolised by Code

  // ---- Nav "Navigation tab" settings (names as in the Nav12 IN file) ----
  property real aTol: 1.0            // ATol  - along-track gate (m): Target Lock, AND recorded points within this of a preplot station are rounded onto it
  property real xTol: 5.0            // XTol  - crossline XTrack limit (m): Target Lock gate, red XTrack readout, AND points beyond it are NOT recorded
  property real fromToThreshold: 5.0 // FTol  - From/To threshold: metres past a waypoint before switching to the next
  property real stnInterval: 0       // Intvl - 0 = take the median spacing of the line
  property real maxIntvl: 0          // MaxIntvl (m) - 0 = 1.33 x station interval
  property real maxBend: 30          // MaxBend (deg)
  property real distTol: 10          // DistTol (%)
  property real antHt: 2.0           // AntHt (m) antenna phase centre above ground
  property int autoInc: 1            // AutoInc +1 / -1
  property real streamInterval: 10.0 // feature Stream interval (m)
  // ---- Nav "Quality tab" settings ----
  property real pTol: 0            // PTol - horizontal precision (m); 0 = off
  property real zTol: 0            // ZTol - vertical precision (m); 0 = off
  property real qTol: 0            // QTol - HDOP limit; 0 = off
  // ---- zone alarms (Nav25) ----
  // ---- Stakeless mode (Nav): auto-record each station as it is passed, plus a travelled-route profile ----
  property bool stakelessEnabled: true
  property real logInterval: 3.0     // LogInt - profile point every N metres while Stakeless is running
  property string profileLayerName: "N25_Profile"
  property bool alarmSound: true
  property bool voiceFeedback: true  // spoken "Point location stored" / "Point location not stored" for every point (START / REC / CHK)
  property int nogoAlarmMs: 800
  property int warnInitialMs: 1000
  property int warnInitialPhaseMs: 10000
  property int warnSustainedMs: 4000

  // ---- runtime state ----
  property var lines: ({})
  property var nogoZones: []
  property var warnZones: []
  property string curLine: ""
  property int dir: 1
  property bool follow: true
  property bool autoPickLine: false      // off: the line is only chosen with the LINE button
  property real lastCx: NaN
  property real lastCy: NaN
  property bool navView: true
  property bool streaming: false
  property var nav: null
  property var nogoHits: []
  property var warnHits: []
  property string zoneStat: "clear"
  property double zoneSince: 0
  property real hdop: 0
  property real hacc: -1
  property real vacc: -1
  property real elev: NaN
  property real posX: 0
  property real posY: 0
  property real heading: 0
  property real lastHX: 0
  property real lastHY: 0
  property real lastStreamX: 0
  property real lastStreamY: 0
  property bool haveFix: false
  property real posLat: NaN
  property real posLon: NaN
  property int nSats: 0
  property real pdopV: NaN
  property string qualDesc: ""
  property string surveyor: ""            // initials, e.g. PP  (goes in Surveyor and, with the day of year, ObsFile e.g. 263PP)
  property string hDatum: "GDA"
  property string vDatum: "AHD"
  property string sourceTag: "Nav25"
  property string baseId: ""              // BaseID column (base / correction source id)
  property string gpsSerial: ""           // GPSSerialNum column
  property string gpsModel: "UM980"       // GPSModel column
  property string gpsName: ""             // GPS column (free text, e.g. antenna / receiver id)
  property bool csvExport: true           // also append every point to <DOY><surveyor>_Combined.csv in the project folder
  property string csvStatus: ""
  property double lastUpdate: 0
  property var prev1: null           // last two recorded Line Stations on this line (for QA)
  property var prev2: null
  property int nextMarkId: 1
  property string lastComments: ""
  property string statusText: ""
  // Average (50 obs)
  property bool avgActive: false
  property int avgTarget: 50
  property var avg: null
  property var avgRec: null
  // Mark Position popup snapshot ("Instant")
  property var snap: null
  // Stakeless runtime
  property bool slRun: false
  property var slPrev: null
  property int slCount: 0
  property int slSkipped: 0
  property real slProfX: 0
  property real slProfY: 0
  property bool slProfValid: false

  function toast(msg) { mainWindow.displayToast(msg); }

  // ---- remembered settings (per QField project) ----
  property var store: null
  property string storeErr: ""
  function initStore() {
    try {
      var key = "Nav25";
      try { var bn = qgisProject.baseName; if (bn) key += "_" + bn; } catch (e0) {}
      var cat = key.replace(/[^A-Za-z0-9_]/g, "_");
      var tries = ['import QtQuick; import QtCore; Settings { category: "' + cat + '" }',
                   'import QtQuick 2.0; import Qt.labs.settings 1.0; Settings { category: "' + cat + '" }'];
      store = null; storeErr = "";
      for (var i = 0; i < tries.length && store === null; i++) {
        try { store = Qt.createQmlObject(tries[i], plugin, "nav25store" + i); } catch (e1) { storeErr += " [" + i + "] " + e1; store = null; }
      }
    } catch (e) { store = null; storeErr = String(e); }
  }
  readonly property var persistNums: ["aTol", "xTol", "fromToThreshold", "stnInterval", "maxIntvl", "maxBend", "distTol", "antHt", "autoInc", "logInterval", "pTol", "zTol", "qTol", "vOffset"]
  readonly property var persistStrs: ["surveyor", "preplotName", "stationField", "lineField", "recordLayerName", "mappingLayerName", "baseId", "gpsSerial", "gpsModel", "gpsName"]
  readonly property var persistBools: ["stakelessEnabled", "alarmSound", "voiceFeedback", "navView", "csvExport", "autoPickLine"]
  function saveSettings() {
    if (!store) return;
    try {
      var i;
      for (i = 0; i < persistNums.length; i++) store.setValue(persistNums[i], String(plugin[persistNums[i]]));
      for (i = 0; i < persistBools.length; i++) store.setValue(persistBools[i], plugin[persistBools[i]] ? "1" : "0");
      for (i = 0; i < persistStrs.length; i++) store.setValue(persistStrs[i], String(plugin[persistStrs[i]]));
      store.setValue("curLine", curLine); store.setValue("dir", String(dir));
      store.setValue("saved", "1");
      try { store.sync(); } catch (es) {}
    } catch (e) {}
  }
  function loadSettings() {
    if (!store) return;
    try {
      if (String(store.value("saved", "0")) !== "1") return;
      var i, v;
      for (i = 0; i < persistNums.length; i++) { v = parseFloat(store.value(persistNums[i], "")); if (!isNaN(v)) plugin[persistNums[i]] = v; }
      for (i = 0; i < persistStrs.length; i++) { v = store.value(persistStrs[i], undefined); if (v !== undefined && v !== null) plugin[persistStrs[i]] = String(v); }
      for (i = 0; i < persistBools.length; i++) { v = String(store.value(persistBools[i], "")); if (v === "1") plugin[persistBools[i]] = true; else if (v === "0") plugin[persistBools[i]] = false; }
    } catch (e) {}
  }
  function restoreLine() {
    if (!store) return;
    try {
      var id = String(store.value("curLine", ""));
      if (id !== "" && lines[id] && curLine === "") {
        var d = parseInt(store.value("dir", "1"));
        curLine = id; dir = d < 0 ? -1 : 1; nav = null; prev1 = null; prev2 = null; slPrev = null;
        if (haveFix) nav = locate2D(lines[id], posX, posY, dir, fromToThreshold);
      }
    } catch (e) {}
  }
  // degrees-minutes-seconds of a bearing (radians), e.g. 356° 00' 28"
  function dms(r) {
    var d = deg(r), D = Math.floor(d), m = (d - D) * 60, M = Math.floor(m), S = Math.round((m - M) * 60);
    if (S >= 60) { S = 0; M++; }
    if (M >= 60) { M = 0; D++; }
    if (D >= 360) D -= 360;
    return D + "\u00B0 " + ("0" + M).slice(-2) + "' " + ("0" + S).slice(-2) + '"';
  }
  // live station label like Nav25's "5080-0.2": nearest station + signed inline offset
  function liveStnLabel() {
    if (!nav || curLine === "" || !lines[curLine]) return "--";
    try { return snapStation(lines[curLine], nav.chain, aTol).label; } catch (e) { return "--"; }
  }
  function fmt(v, d) { return (v === undefined || v === null || isNaN(v)) ? "--" : Number(v).toFixed(d); }

  // ==================================================================== CORE (generated)
  // nav25core.js - pure logic for the Nav25 QField plugin (no QField dependencies).
  // Rules come from the Nav12/Nav25 user guide (Terrex Spatial). Coordinates are projected metres.
  // This file is inlined into main.qml by build.py and unit-tested with node (test/test_core.js).

  // ---------- WKT parsing ----------
  function parseWktNumbers(s) {
      var out = [], parts = s.split(",");
      for (var i = 0; i < parts.length; i++) {
          var n = parts[i].trim().split(/\s+/);
          if (n.length >= 2) out.push([parseFloat(n[0]), parseFloat(n[1])]);
      }
      return out;
  }
  function parseWkt(wkt) {
      var t = wkt.trim().toUpperCase();
      var body = wkt.substring(wkt.indexOf("("));
      body = body.replace(/\bZM?\b/gi, "");
      var res = {type: "", polys: [], lines: [], points: []};
      var i;
      if (t.indexOf("MULTIPOLYGON") === 0) {
          res.type = "polygon";
          var polys = body.slice(3, -3).split(")),((");
          for (i = 0; i < polys.length; i++) res.polys.push(polys[i].split("),(").map(parseWktNumbers));
      } else if (t.indexOf("POLYGON") === 0) {
          res.type = "polygon";
          res.polys.push(body.slice(2, -2).split("),(").map(parseWktNumbers));
      } else if (t.indexOf("MULTIPOINT") === 0) {
          res.type = "point";
          res.points = parseWktNumbers(body.replace(/[()]/g, ""));
      } else if (t.indexOf("POINT") === 0) {
          res.type = "point";
          res.points = parseWktNumbers(body.slice(1, -1));
      } else if (t.indexOf("MULTILINESTRING") === 0) {
          res.type = "line";
          res.lines = body.slice(2, -2).split("),(").map(parseWktNumbers);
      } else if (t.indexOf("LINESTRING") === 0) {
          res.type = "line";
          res.lines.push(parseWktNumbers(body.slice(1, -1)));
      }
      return res;
  }

  // ---------- zones (No-Go = red, Warning = orange) ----------
  function ringContains(ring, x, y) {
      var inside = false;
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          var xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
          if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) inside = !inside;
      }
      return inside;
  }
  function polyContains(rings, x, y) {
      if (!ringContains(rings[0], x, y)) return false;
      for (var k = 1; k < rings.length; k++) if (ringContains(rings[k], x, y)) return false;
      return true;
  }
  function bboxOf(rings) {
      var minx = 1e99, miny = 1e99, maxx = -1e99, maxy = -1e99, r = rings[0];
      for (var i = 0; i < r.length; i++) {
          if (r[i][0] < minx) minx = r[i][0];
          if (r[i][0] > maxx) maxx = r[i][0];
          if (r[i][1] < miny) miny = r[i][1];
          if (r[i][1] > maxy) maxy = r[i][1];
      }
      return [minx, miny, maxx, maxy];
  }
  function makeZone(name, parsed) {
      var z = {name: name, polys: parsed.polys, bbox: []};
      for (var i = 0; i < parsed.polys.length; i++) z.bbox.push(bboxOf(parsed.polys[i]));
      return z;
  }
  // returns the names of every zone containing (x,y)
  function zoneHits(zones, x, y) {
      var hits = [];
      for (var z = 0; z < zones.length; z++) {
          var Z = zones[z];
          for (var p = 0; p < Z.polys.length; p++) {
              var b = Z.bbox[p];
              if (x < b[0] || x > b[2] || y < b[1] || y > b[3]) continue;
              if (polyContains(Z.polys[p], x, y)) { hits.push(Z.name); break; }
          }
      }
      return hits;
  }
  // alarm state: "nogo" (red) beats "warn" (orange) beats "clear" (green)
  function zoneState(nogoHits, warnHits) {
      if (nogoHits.length > 0) return "nogo";
      if (warnHits.length > 0) return "warn";
      return "clear";
  }

  // ---------- preplot lines (2D Stakeout waypoints) ----------
  function buildLines(rows) {
      var lines = {}, i;
      for (i = 0; i < rows.length; i++) {
          var r = rows[i];
          if (!lines[r.line]) lines[r.line] = {id: r.line, pts: [], length: 0};
          lines[r.line].pts.push({stn: r.stn, x: r.x, y: r.y, chain: 0});
      }
      for (var id in lines) {
          var L = lines[id];
          L.pts.sort(function (a, b) { return a.stn - b.stn; });
          var c = 0;
          for (i = 0; i < L.pts.length; i++) {
              if (i > 0) c += Math.hypot(L.pts[i].x - L.pts[i - 1].x, L.pts[i].y - L.pts[i - 1].y);
              L.pts[i].chain = c;
          }
          L.length = c;
      }
      return lines;
  }
  // typical station interval of a line (median of consecutive spacing per station step)
  function lineInterval(L) {
      var d = [];
      for (var i = 1; i < L.pts.length; i++) {
          var ds = Math.abs(L.pts[i].stn - L.pts[i - 1].stn);
          if (ds > 0) d.push(Math.hypot(L.pts[i].x - L.pts[i - 1].x, L.pts[i].y - L.pts[i - 1].y) / ds);
      }
      if (d.length === 0) return 0;
      d.sort(function (a, b) { return a - b; });
      return d[Math.floor(d.length / 2)];
  }

  function bearing(x0, y0, x1, y1) { return Math.atan2(x1 - x0, y1 - y0); }
  function wrapPi(a) { while (a > Math.PI) a -= 2 * Math.PI; while (a < -Math.PI) a += 2 * Math.PI; return a; }
  function deg(r) { return (r * 180 / Math.PI + 360) % 360; }

  // 2D Stakeout guidance. Bearings are those of the segment between consecutive waypoints.
  // dir = +1 / -1 (AutoInc).  thr = From/To threshold: how far PAST a waypoint the display keeps
  // showing the distance back to it before it switches to the next waypoint.
  // atrack: + = target still ahead, - = target already passed (within thr).
  // xtrack: + = right of the direction of travel.
  function locate2D(L, px, py, dir, thr) {
      var pts = L.pts, best = null, i;
      if (pts.length < 2) return null;
      for (i = 0; i < pts.length - 1; i++) {
          var a = pts[i], b = pts[i + 1];
          var dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy;
          if (len2 === 0) continue;
          var t = ((px - a.x) * dx + (py - a.y) * dy) / len2;
          var tc = Math.max(0, Math.min(1, t));
          var fx = a.x + tc * dx, fy = a.y + tc * dy;
          var d = Math.hypot(px - fx, py - fy);
          if (best === null || d < best.dist) {
              var seglen = Math.sqrt(len2);
              var tAlong = (i === 0 && t < 0) ? t : (i === pts.length - 2 && t > 1 ? t : tc);
              best = {seg: i, dist: d, fx: fx, fy: fy, chain: a.chain + tAlong * seglen,
                      rawX: ((px - a.x) * dy - (py - a.y) * dx) / seglen, brg: Math.atan2(dx, dy), t: tAlong};
          }
      }
      if (best === null) return null;
      var sgn = dir >= 0 ? 1 : -1;
      var segA = pts[best.seg], segB = pts[best.seg + 1];
      var stn = segA.stn + best.t * (segB.stn - segA.stn);
      // waypoints in travel order, starting at the segment's near end
      var order = [];
      if (sgn > 0) { for (i = best.seg; i < pts.length; i++) order.push(i); }
      else { for (i = best.seg + 1; i >= 0; i--) order.push(i); }
      var target = order[order.length - 1], k, along;
      for (k = 0; k < order.length; k++) {
          along = (pts[order[k]].chain - best.chain) * sgn;
          if (along >= -thr) { target = order[k]; break; }
      }
      var tp = pts[target];
      var endPt = sgn > 0 ? pts[pts.length - 1] : pts[0];
      var tIdx = order.indexOf(target);
      var nextIdx = tIdx >= 0 && tIdx + 1 < order.length ? order[tIdx + 1] : -1;
      return {
          xtrack: best.rawX * sgn, chain: best.chain, stn: stn,
          foot: [best.fx, best.fy], travelBearing: best.brg + (sgn > 0 ? 0 : Math.PI),
          seg: best.seg, off: best.dist,
          fromStn: sgn > 0 ? segA.stn : segB.stn, toStn: sgn > 0 ? segB.stn : segA.stn,
          targetStn: tp.stn, targetX: tp.x, targetY: tp.y,
          atrack: (tp.chain - best.chain) * sgn,
          nextStn: nextIdx >= 0 ? pts[nextIdx].stn : null,
          toEnd: (endPt.chain - best.chain) * sgn
      };
  }
  // Target Lock: the target-locked display first appears when both ATrack and XTrack are within gates
  function targetLocked(nav, aTol, xTol) {
      return Math.abs(nav.atrack) <= aTol && Math.abs(nav.xtrack) <= xTol;
  }
  function nearestLines(lines, px, py, maxN) {
      var out = [];
      for (var id in lines) {
          var l = locate2D(lines[id], px, py, 1, 0);
          if (l) out.push({id: id, off: l.off});
      }
      out.sort(function (a, b) { return a.off - b.off; });
      return maxN ? out.slice(0, maxN) : out;
  }

  // ---------- Go Home / waypoint (WP) mode ----------
  function wpGuidance(px, py, tx, ty, travelBrg) {
      var brg = bearing(px, py, tx, ty);
      return {dist: Math.hypot(tx - px, ty - py), brg: brg, rel: wrapPi(brg - travelBrg)};
  }
  function findStation(lines, lineId, stn) {
      var L = lines[lineId];
      if (!L) return null;
      for (var i = 0; i < L.pts.length; i++) if (L.pts[i].stn === stn) return L.pts[i];
      return null;
  }

  // ---------- recording QA (Nav "warning message when recording a point") ----------
  // prev1/prev2: the last two recorded Line Stations on this line {x,y,stn} (prev2 may be null)
  // cand: {x,y,stn}; p: {stnInterval, maxIntvl, maxBend, distTol}
  // q: {hacc, vacc, hdop, pTol, zTol, qTol}
  function recordWarnings(prev1, prev2, cand, p, q) {
      var w = [];
      if (prev1) {
          var d = Math.hypot(cand.x - prev1.x, cand.y - prev1.y);
          var dStn = Math.abs(cand.stn - prev1.stn);
          if (p.maxIntvl > 0 && d > p.maxIntvl) w.push("Interval " + d.toFixed(1) + " m > MaxIntvl " + p.maxIntvl);
          if (p.stnInterval > 0 && dStn > 0 && p.distTol > 0) {
              var exp = p.stnInterval * dStn;
              var pct = Math.abs(d - exp) / exp * 100;
              if (pct > p.distTol) w.push("Distance error " + pct.toFixed(0) + "% (" + d.toFixed(1) + " m vs " + exp.toFixed(1) + " m)");
          }
          if (prev2 && p.maxBend > 0) {
              var b1 = bearing(prev2.x, prev2.y, prev1.x, prev1.y), b2 = bearing(prev1.x, prev1.y, cand.x, cand.y);
              var bend = Math.abs(wrapPi(b2 - b1)) * 180 / Math.PI;
              if (bend > p.maxBend) w.push("Bend " + bend.toFixed(0) + "° > MaxBend " + p.maxBend + "°");
          }
      }
      if (q) {
          if (q.pTol > 0 && q.hacc > 0 && q.hacc > q.pTol) w.push("Horiz precision " + q.hacc.toFixed(2) + " m > PTol " + q.pTol);
          if (q.zTol > 0 && q.vacc > 0 && q.vacc > q.zTol) w.push("Vert precision " + q.vacc.toFixed(2) + " m > ZTol " + q.zTol);
          if (q.qTol > 0 && q.hdop > 0 && q.hdop > q.qTol) w.push("HDOP " + q.hdop.toFixed(1) + " > QTol " + q.qTol);
      }
      return w;
  }

  // ---------- recorded-point helpers ----------
  // Nav combines Feature Code and String No into one label; consecutive identical labels with
  // a non-zero string number are joined by lines.
  function featureLabel(code, stringNo) {
      var s = parseInt(stringNo || 0);
      return String(code || "") + (s > 0 ? (s < 10 ? "0" + s : String(s)) : "");
  }
  function lineKey(descriptor) { return String(descriptor).replace(/^[A-Za-z]+/, ""); }
  function stationOf(raw, line, hasPrefix) {
      var v = Math.round(parseFloat(raw));
      if (!hasPrefix) return v;
      var s = String(v);
      return s.indexOf(line) === 0 && s.length > line.length ? parseInt(s.substring(line.length)) : v;
  }
  // running average of N observations (Nav "Average (50 obs)")
  function newAverager() { return {n: 0, x: 0, y: 0, z: 0, nz: 0}; }
  function addObs(a, x, y, z) {
      a.n++; a.x += x; a.y += y;
      if (z !== null && z !== undefined && !isNaN(z)) { a.z += z; a.nz++; }
  }
  function averageOf(a) { return {x: a.x / a.n, y: a.y / a.n, z: a.nz > 0 ? a.z / a.nz : NaN, n: a.n}; }

  // ---------- alarm timing (Nav25: Warning alarm has a fast initial phase, then a slower sustained one) ----------
  function alarmIntervalMs(state, msInState, c) {
      if (state === "nogo") return c.nogoMs;
      if (state === "warn") return msInState < c.warnInitialPhaseMs ? c.warnInitialMs : c.warnSustainedMs;
      return 0;
  }

  // ---------- station + offset (what a recorded Line Station always carries) ----------
  // chain = distance along the line at the recorded position (locate2D().chain).
  // The point is always tied to the NEAREST preplot station. offset = signed metres from that
  // station, + toward higher station numbers.  Offsets within aTol are rounded onto the station.
  function snapStation(L, chain, aTol) {
      var best = 0, bd = 1e99, i;
      for (i = 0; i < L.pts.length; i++) {
          var d = Math.abs(L.pts[i].chain - chain);
          if (d < bd) { bd = d; best = i; }
      }
      var off = chain - L.pts[best].chain;
      var snapped = Math.abs(off) <= aTol;
      if (snapped) off = 0;
      off = Math.round(off * 10) / 10;
      return {stn: L.pts[best].stn, offset: off, snapped: snapped, label: stationLabel(L.pts[best].stn, off)};
  }
  function stationLabel(stn, off) {
      if (!off) return String(stn);
      return String(stn) + (off > 0 ? "+" : "-") + Math.abs(off).toFixed(1);
  }
  // Crossline gate: a Line Station is only recorded when |XTrack| <= xTol
  function recordAllowed(nv, xTol) {
      if (!nv) return {ok: false, msg: "No line / position on line"};
      if (xTol > 0 && Math.abs(nv.xtrack) > xTol)
          return {ok: false, msg: "XTrack " + Math.abs(nv.xtrack).toFixed(1) + " m " + (nv.xtrack > 0 ? "R" : "L") + " is outside XTol " + xTol + " m"};
      return {ok: true, msg: ""};
  }

  // ---------- Stakeless: stations passed between two consecutive fixes ----------
  // cPrev/cNow: chain along the line at the previous / current fix; pPrev/pNow: {x,y} of the fixes.
  // Returns [{stn, x, y}] - each station whose chainage was crossed (in the direction of travel),
  // with the position interpolated along the travelled route between the two fixes.
  // Jumps longer than maxJump (m) are ignored (line change, GPS glitch).
  function stakelessCrossings(L, dir, cPrev, cNow, pPrev, pNow, maxJump) {
      var out = [], sgn = dir >= 0 ? 1 : -1;
      var a = sgn * cPrev, b = sgn * cNow;
      if (!(b > a) || (b - a) > maxJump) return out;
      for (var i = 0; i < L.pts.length; i++) {
          var cs = sgn * L.pts[i].chain;
          if (cs > a && cs <= b) {
              var t = (cs - a) / (b - a);
              out.push({stn: L.pts[i].stn, x: pPrev.x + t * (pNow.x - pPrev.x), y: pPrev.y + t * (pNow.y - pPrev.y)});
          }
      }
      if (sgn < 0) out.reverse();
      return out;
  }
  // ==================================================================== end CORE

  property real effInterval: stnInterval > 0 ? stnInterval : (curLine !== "" && lines[curLine] ? lineInterval(lines[curLine]) : 0)
  property real effMaxIntvl: maxIntvl > 0 ? maxIntvl : effInterval * 1.33

  // ------------------------------------------------------------------ loading
  function layerByName(name) {
    var l = qgisProject.mapLayersByName(name);
    return l.length > 0 ? l[0] : null;
  }
  function geomIn(layer, feature) {
    var g = feature.geometry;
    if (layer.crs.authid !== qgisProject.crs.authid)
      g = QfGeometryUtils.reprojectGeometry(g, layer.crs, qgisProject.crs);
    return g;
  }

  property bool loading: false
  property bool loadedOnce: false
  property bool pendingPicker: false
  property string recLabel: ""      // last stored point, shown as a banner (e.g. 1A1002)
  property bool recWarn: false
  property real autoPickDist: 50      // m - auto-select the nearest line when none is chosen and a fix is within this distance
  property var loadJobs: []
  property var loadJob: null
  property var loadIt: null
  property var loadRows: []
  property var loadNogo: []
  property var loadWarn: []
  property int loadCount: 0
  property int loadMaxId: 0

  function failLoad(e) {
    loadTimer.stop(); loading = false; loadIt = null;
    statusText = "LOAD ERROR: " + e;
    toast("Nav25: " + e);
  }

  function addJob(jobs, seen, kind, layer, extra) {
    if (!layer) return;
    var key = kind + "|" + layer.id;
    if (seen[key]) return;
    seen[key] = true;
    var j = {kind: kind, layer: layer};
    if (extra) j.field = extra;
    jobs.push(j);
  }

  // ---- auto-detect the preplot layer and its station / line fields (so the same plugin runs in any project) ----
  readonly property var stnCands: ["Stn", "Station", "Stn_No", "StnNo", "Station_No", "StationNo", "Sta", "STN", "Point", "PointID", "Point_ID", "SP", "ATTR_1"]
  readonly property var lineCands: ["Line_ID", "LineID", "Line", "Line_No", "LineNo", "Line_Name", "LineName", "LINE", "ATTR_2"]
  function firstField(layer, cands) {
    for (var i = 0; i < cands.length; i++) {
      var ix = -1;
      try { ix = layer.fields.indexFromName(cands[i]); } catch (e) { return ""; }
      if (ix >= 0) { try { return String(layer.fields.at(ix).name); } catch (e2) { return cands[i]; } }
    }
    // fuzzy pass: field names that start with a candidate, e.g. "Line Numbe" / "Point Numb" from truncated shapefile names
    try {
      var norm = function (t) { return String(t).toLowerCase().replace(/[^a-z0-9]/g, ""); };
      var nf = layer.fields.count();
      for (var c = 0; c < cands.length; c++) {
        var cn = norm(cands[c]);
        if (cn.length < 4) continue;
        for (var k = 0; k < nf; k++) {
          var fname = String(layer.fields.at(k).name), fn = norm(fname);
          if (fn.indexOf(cn) === 0 && fn.indexOf("part") < 0 && fn.indexOf("type") < 0) return fname;
        }
      }
    } catch (e3) {}
    return "";
  }
  function autoPreplot() {
    var best = "", bestScore = -1, bs = "", bl = "";
    try {
      var all = QfProjectUtils.mapLayers(qgisProject);
      for (var key in all) {
        var l = all[key];
        if (!l || l.name === undefined) continue;
        var nm = String(l.name);
        if (/^N25_/i.test(nm) || nm.indexOf(noGoPrefix) === 0 || nm.indexOf(warnPrefix) === 0 || nm.toUpperCase().indexOf("WARN") === 0) continue;
        var sf = "", lf = "";
        try {
          sf = stationField !== "" ? (l.fields.indexFromName(stationField) >= 0 ? stationField : "") : firstField(l, stnCands);
          lf = lineField !== "" ? (l.fields.indexFromName(lineField) >= 0 ? lineField : "") : firstField(l, lineCands);
        } catch (e) { continue; }
        if (sf === "" || lf === "") continue;
        var score = 1;
        if (/preplot|plot|rcv|receiver|node|station|src|source|point/i.test(nm)) score += 2;
        if (/preplot/i.test(nm)) score += 1;
        if (/src|source|shot/i.test(nm)) score += 0.5;
        if (score > bestScore) { bestScore = score; best = nm; bs = sf; bl = lf; }
      }
    } catch (e3) {}
    if (best === "") return [];
    if (stnUse === "") stnUse = bs;
    if (lineUse === "") lineUse = bl;
    return [best];
  }

  function startLoad() {
    if (loading) return;
    try {
      var jobs = [], seen = {}, i, layer, missing = [];
      stnUse = stationField; lineUse = lineField; preplotInfo = "";
      var pnames = preplotName !== "" ? [preplotName] : preplotLayerNames.slice();
      if (pnames.length === 0) pnames = autoPreplot();
      for (i = 0; i < pnames.length; i++) {
        layer = layerByName(pnames[i]);
        if (layer) addJob(jobs, seen, "preplot", layer); else missing.push(pnames[i]);
      }
      if (pnames.length > 0) {
        var pl0 = layerByName(pnames[0]);
        if (pl0 && stnUse === "") stnUse = firstField(pl0, stnCands);
        if (pl0 && lineUse === "") lineUse = firstField(pl0, lineCands);
      }
      if (pnames.length > 0 && missing.length === 0) preplotInfo = pnames.join(", ") + " (" + stnUse + " / " + lineUse + ")";
      for (i = 0; i < noGoNames.length; i++) addJob(jobs, seen, "nogo", layerByName(noGoNames[i]));
      for (i = 0; i < warnNames.length; i++) addJob(jobs, seen, "warn", layerByName(warnNames[i]));
      var all = QfProjectUtils.mapLayers(qgisProject);
      for (var key in all) {
        layer = all[key];
        if (!layer || layer.name === undefined) continue;
        if (layer.name.indexOf(noGoPrefix) === 0) addJob(jobs, seen, "nogo", layer);
        else if (layer.name.indexOf(warnPrefix) === 0 || layer.name.toUpperCase().indexOf("WARN") === 0) addJob(jobs, seen, "warn", layer);
      }
      var rl = layerByName(recordLayerName);
      if (rl) addJob(jobs, seen, "markid", rl);
      if (!rl) toast("N25: layer " + recordLayerName + " not found - run N25_AddLayers.py in QGIS once for this project");
      if (missing.length > 0) toast("Nav25: preplot layer(s) not found: " + missing.join(", "));
      if (pnames.length === 0) toast("Nav25: no preplot layer found - set its name in the settings tab");
      if (jobs.length === 0) { statusText = "No Nav25 layers found in this project"; return; }
      loadJobs = jobs; loadJob = null; loadIt = null;
      loadRows = []; loadNogo = []; loadWarn = []; loadCount = 0; loadMaxId = 0;
      loading = true; statusText = "Loading layers...";
      loadTimer.start();
    } catch (e) { failLoad(e); }
  }

  function processFeature(f) {
    var job = loadJob;
    if (job.kind === "markid") {
      var m = parseInt(f.attribute("MarkID"));
      if (!isNaN(m) && m > loadMaxId) loadMaxId = m;
      loadCount++;
      return;
    }
    var p = parseWkt(geomIn(job.layer, f).asWkt(job.kind === "preplot" ? 3 : 2));
    if (job.kind === "preplot") {
      if (p.points.length === 0) return;
      var ln = lineKey(f.attribute(lineUse));
      loadRows.push({line: ln, stn: stationOf(f.attribute(stnUse), ln, stationHasLinePrefix), x: p.points[0][0], y: p.points[0][1]});
    } else if (p.type === "polygon") {
      (job.kind === "nogo" ? loadNogo : loadWarn).push(makeZone(job.layer.name, p));
    }
    loadCount++;
  }

  function loadStep() {
    try {
      var t0 = Date.now();
      while (Date.now() - t0 < 40) {
        if (loadIt === null) {
          if (loadJobs.length === 0) { finishLoad(); return; }
          loadJob = loadJobs.shift();
          loadIt = QfLayerUtils.createFeatureIterator(loadJob.layer);
          statusText = "Loading " + loadJob.layer.name + "...  (" + loadCount + ")";
          continue;
        }
        if (!loadIt.hasNext()) { loadIt.close(); loadIt = null; continue; }
        processFeature(loadIt.next());
      }
    } catch (e) { failLoad(e); }
  }

  function finishLoad() {
    loadTimer.stop(); loading = false;
    lines = buildLines(loadRows);
    nogoZones = loadNogo; warnZones = loadWarn;
    nextMarkId = loadMaxId + 1;
    loadedOnce = true;
    var n = 0; for (var q in lines) n++;
    statusText = n + " lines, " + nogoZones.length + " No-Go, " + warnZones.length + " Warning zones"
               + (preplotInfo !== "" ? "  |  preplot: " + preplotInfo : "")
               + (layerByName(recordLayerName) ? "" : "  |  RECORD LAYER '" + recordLayerName + "' NOT IN PROJECT");
    restoreLine();
    toast("Nav25 ready: " + statusText + (curLine !== "" ? "  (line " + curLine + ")" : ""));
    if (pendingPicker) { pendingPicker = false; linePopup.openPicker(); }
  }

  Timer { id: loadTimer; interval: 5; repeat: true; running: false; onTriggered: plugin.loadStep() }

  // ------------------------------------------------------------------ alarms (Nav25 zone alarm)
  property var sndNogo: null
  property var sndWarn: null
  property bool soundOk: false

  function initSounds() {
    try {
      sndNogo = Qt.createQmlObject('import QtMultimedia\nSoundEffect { volume: 1.0 }', plugin, "n25NogoSnd");
      sndWarn = Qt.createQmlObject('import QtMultimedia\nSoundEffect { volume: 1.0 }', plugin, "n25WarnSnd");
      sndNogo.source = Qt.resolvedUrl("nogo.wav");
      sndWarn.source = Qt.resolvedUrl("warn.wav");
      soundOk = true;
    } catch (e) {
      soundOk = false;
      statusText = "Sound unavailable (" + e + ") - visual alarm only";
    }
  }
  // ------------------------------------------------------------------ voice feedback + GPS-corrections check
  property var sndStored: null
  property var sndNotStored: null
  property bool voiceOk: false
  function initVoice() {
    try {
      sndStored = Qt.createQmlObject('import QtMultimedia\nSoundEffect { volume: 1.0 }', plugin, "n25StoredSnd");
      sndNotStored = Qt.createQmlObject('import QtMultimedia\nSoundEffect { volume: 1.0 }', plugin, "n25NotStoredSnd");
      sndStored.source = Qt.resolvedUrl("stored.wav");
      sndNotStored.source = Qt.resolvedUrl("notstored.wav");
      voiceOk = true;
    } catch (e) { voiceOk = false; }
  }
  // ok = point stored (true) / not stored (false). quiet = automatic points (Stakeless / CHK stream): never talk over a clip that is still playing.
  function playVoice(ok, quiet) {
    if (!voiceFeedback || !voiceOk) return;
    try {
      var s = ok ? sndStored : sndNotStored, o = ok ? sndNotStored : sndStored;
      if (quiet && (sndStored.playing || sndNotStored.playing)) return;
      o.stop(); s.stop(); s.play();
    } catch (e) {}
  }
  // A point is only stored when the Quality-tab limits are met: horizontal precision <= PTol, vertical <= ZTol, HDOP <= QTol.
  // A limit of 0 means "off", so with PTol / ZTol / QTol all 0 every point is stored.
  function correctionsOk() { return !precisionBad(); }
  // per-value verdicts for the quality strip at the top of the panel (0 = tolerance off)
  function hBad() { return pTol > 0 && !(hacc > 0 && hacc <= pTol); }
  function vBad() { return zTol > 0 && !(vacc > 0 && vacc <= zTol); }
  function qBad() { return qTol > 0 && !(hdop > 0 && hdop <= qTol); }
  function correctionsMsg() {
    var w = [];
    if (pTol > 0 && !(hacc > 0 && hacc <= pTol)) w.push(hacc > 0 ? "H " + hacc.toFixed(2) + " m > PTol " + pTol : "H precision not reported");
    if (zTol > 0 && !(vacc > 0 && vacc <= zTol)) w.push(vacc > 0 ? "V " + vacc.toFixed(2) + " m > ZTol " + zTol : "V precision not reported");
    if (qTol > 0 && !(hdop > 0 && hdop <= qTol)) w.push(hdop > 0 ? "HDOP " + hdop.toFixed(1) + " > QTol " + qTol : "HDOP not reported");
    return "GPS quality out of tolerance (" + w.join(", ") + ")";
  }
  function readings() { return "H " + fmt(hacc > 0 ? hacc : NaN, 2) + " / V " + fmt(vacc > 0 ? vacc : NaN, 2) + " / HDOP " + fmt(hdop > 0 ? hdop : NaN, 1); }

  function playAlarm() {
    if (!alarmSound || !soundOk) return;
    try {
      if (zoneStat === "nogo") sndNogo.play();
      else if (zoneStat === "warn") sndWarn.play();
    } catch (e) {}
  }
  function setZoneState(s) {
    if (s === zoneStat) return;
    zoneStat = s;
    zoneSince = Date.now();
    if (s === "clear") { alarmTimer.stop(); return; }
    toast(s === "nogo" ? "NO-GO ZONE: " + nogoHits.join(", ") : "WARNING ZONE: " + warnHits.join(", "));
    playAlarm();
    alarmTimer.interval = alarmIntervalMs(s, 0, alarmCfg());
    alarmTimer.restart();
  }
  function alarmCfg() {
    return {nogoMs: nogoAlarmMs, warnInitialMs: warnInitialMs, warnInitialPhaseMs: warnInitialPhaseMs, warnSustainedMs: warnSustainedMs};
  }
  Timer {
    id: alarmTimer
    repeat: true; running: false
    onTriggered: {
      plugin.playAlarm();
      var iv = plugin.alarmIntervalMs(plugin.zoneStat, Date.now() - plugin.zoneSince, plugin.alarmCfg());
      if (iv > 0) interval = iv;
    }
  }

  // ------------------------------------------------------------------ navigation
  function firstPositive(info, names) {
    for (var i = 0; i < names.length; i++) {
      var v;
      try { v = info[names[i]]; } catch (e) { continue; }
      if (v !== undefined && v !== null && !isNaN(v) && Number(v) > 0) return Number(v);
    }
    return -1;
  }
  // diagnostic for the settings tab: every accuracy / DOP / quality value QField is giving this plugin
  function accDiag() {
    var out = [];
    try {
      var info = positioning.positionInformation;
      for (var k in info) { if (/acc|dop|qual|sats/i.test(k) && typeof info[k] !== "function") out.push(k + "=" + info[k]); }
    } catch (e) { return "n/a"; }
    return out.length > 0 ? out.join(", ") : "none";
  }
  function readAcc(info) {
    // QField / QGIS builds name these differently (hacc / horizontalAccuracy ...): take the first name that holds a real value
    hacc = firstPositive(info, ["hacc", "horizontalAccuracy", "horizontalAcc"]);
    vacc = firstPositive(info, ["vacc", "verticalAccuracy", "verticalAcc"]);
    elev = (info.elevation !== undefined && !isNaN(info.elevation) && info.elevationValid !== false) ? info.elevation : NaN;
  }

  property int dbgCalls: 0
  property real geoidShift: NaN
  property real vOffset: 0      // m, subtracted from the elevation: site calibration / geoid N when QField's own grid shift does not apply
  property string dbgExit: "never called"
  function posDiag() {
    var a = "?", lv = "?", la = "?";
    try { a = positioning.active; } catch (e) {}
    try { var i2 = positioning.positionInformation; lv = i2.latitudeValid; la = i2.latitude; } catch (e2) {}
    return "onPosition calls=" + dbgCalls + " last=" + dbgExit + "; active=" + a + ", latitudeValid=" + lv + ", latitude=" + la
         + ", elev(used)=" + elev + ", Z shift vs device=" + geoidShift + ", vOffset=" + vOffset + ", haveFix=" + haveFix + ", lines=" + Object.keys(lines).length + ", curLine='" + curLine + "'";
  }
  function onPosition() {
    dbgCalls++;
    if (!positioning.active) { dbgExit = "positioning.active is false"; return; }
    var now = Date.now();
    if (now - lastUpdate < 450) return;
    lastUpdate = now;
    var info = positioning.positionInformation;
    // some builds (e.g. Windows / external receivers) leave latitudeValid false while latitude / longitude are real numbers
    var llOk = false;
    try { llOk = isFinite(info.latitude) && isFinite(info.longitude) && !(info.latitude === 0 && info.longitude === 0); } catch (ell) {}
    if (!info.latitudeValid && !llOk) { haveFix = false; dbgExit = "no valid position (latitudeValid=" + info.latitudeValid + ")"; return; }
    haveFix = true; dbgExit = "ok";
    var pp = positioning.projectedPosition;
    var x = pp.x, y = pp.y;
    hdop = info.hdop;
    readAcc(info);
    // QField's vertical grid shift (geoid model) is applied to the projected position's Z, not to info.elevation:
    // take the elevation from there so the geoid correction reaches the recorded points
    geoidShift = NaN;
    try {
      var ppz = pp.z;
      if (isFinite(ppz)) { geoidShift = isNaN(elev) ? NaN : ppz - elev; elev = ppz; }
    } catch (ez) {}
    if (isFinite(elev) && vOffset !== 0) elev = elev - vOffset;
    try { posLat = info.latitude; posLon = info.longitude; } catch (e1) { posLat = NaN; posLon = NaN; }
    try { nSats = (info.satellitesUsed !== undefined && info.satellitesUsed > 0) ? info.satellitesUsed : 0; } catch (e2) { nSats = 0; }
    try { pdopV = (info.pdop !== undefined && !isNaN(info.pdop) && info.pdop > 0) ? info.pdop : NaN; } catch (e3) { pdopV = NaN; }
    try { qualDesc = info.qualityDescription ? String(info.qualityDescription) : ""; } catch (e4) { qualDesc = ""; }

    var moved = Math.hypot(x - lastHX, y - lastHY);
    if (info.directionValid && info.speedValid && info.speed > 0.5) heading = info.direction * Math.PI / 180;
    else if (moved > 1.0) heading = bearing(lastHX, lastHY, x, y);
    if (moved > 1.0) { lastHX = x; lastHY = y; }
    posX = x; posY = y;

    // No line chosen yet (e.g. first run on a new device - the last line is only remembered per device):
    // pick the nearest preplot line automatically when the position is within autoPickDist of it
    if (autoPickLine && curLine === "" && loadedOnce && !loading) {
      try {
        var nl = nearestLines(lines, x, y, 1);
        if (nl.length > 0 && nl[0].off <= autoPickDist) setLine(nl[0].id);
      } catch (eap) {}
    }

    // 2D Stakeout (AutoSelect: nearest segment / next waypoint chosen automatically)
    if (curLine !== "" && lines[curLine]) nav = locate2D(lines[curLine], x, y, dir, fromToThreshold);

    // zones
    nogoHits = zoneHits(nogoZones, x, y);
    warnHits = zoneHits(warnZones, x, y);
    setZoneState(zoneState(nogoHits, warnHits));

    // Stakeless
    if (slRun) stakelessTick(x, y);
    profileTick(x, y);

    // Average (50 obs)
    if (avgActive) {
      addObs(avg, x, y, isNaN(elev) ? null : elev - antHt);
      statusText = "Averaging " + avg.n + "/" + avgTarget + "  - hold still";
      if (avg.n >= avgTarget) finishAverage();
    }

    if (streaming && Math.hypot(x - lastStreamX, y - lastStreamY) >= streamInterval) streamPoint();

    if (follow) {
      // if the user has dragged the map away from where we last put it, stop following until FOLLOW is tapped
      try {
        var ms = mapCanvas.mapSettings, mupp = 0;
        try { mupp = ms.mapUnitsPerPoint; } catch (em1) { mupp = 0; }
        if (!(mupp > 0)) { try { mupp = ms.mapUnitsPerPixel; } catch (em2) { mupp = 0; } }
        if (!(mupp > 0)) mupp = 0.5;
        var cc = ms.center;
        if (isFinite(lastCx) && Math.hypot(cc.x - lastCx, cc.y - lastCy) > mupp * 12) {
          follow = false; toast("Map free - tap FOLLOW in the N25 panel to recentre");
        }
      } catch (ep) {}
    }
    if (follow) {
      mapCanvas.mapSettings.center = QfGeometryUtils.point(x, y);
      lastCx = x; lastCy = y;
      var tb = nav ? nav.travelBearing : null;
      if (navView && tb !== null) mapCanvas.mapSettings.rotation = -deg(tb);
      else if (!navView) mapCanvas.mapSettings.rotation = 0;
    }
  }

  function setLine(id) {
    curLine = id; dir = autoInc; nav = null; prev1 = null; prev2 = null; slPrev = null;
    if (haveFix && lines[id]) nav = locate2D(lines[id], posX, posY, dir, fromToThreshold);
    toast("Line " + id + (dir > 0 ? "  ▲ increasing" : "  ▼ decreasing"));
    saveSettings();
  }
  function toggleDir() {
    dir = -dir; slPrev = null;
    if (haveFix && curLine !== "" && lines[curLine]) nav = locate2D(lines[curLine], posX, posY, dir, fromToThreshold);
    saveSettings();
  }
  function startStop() {
    try {
      if (!positioning.active) {
        positioning.active = true; toast("GPS started");
        if (!loadedOnce && !loading) startLoad();
      } else {
        positioning.active = false; streaming = false; avgActive = false; slRun = false; slPrev = null; haveFix = false;
        setZoneState("clear"); toast("GPS stopped");
      }
    } catch (e) { statusText = "ERROR: " + e; toast("Nav25: " + e); }
  }

  // ------------------------------------------------------------------ recording (Mark Position)
  function setAttr(layer, feature, name, value) {
    if (value === null || value === undefined || (typeof value === "number" && isNaN(value))) return;
    var idx = layer.fields.indexFromName(name);
    if (idx >= 0) feature.setAttribute(idx, value);
  }
  // Stn: plain station name when within 1 m of it (e.g. 1001), otherwise name + signed inline offset (1001-3.2 / 1001+3.2).
  // If the layer's Stn field is still an integer field, the plain number is written (the Label field always holds the full text).
  function setStn(layer, f, stn, off) {
    if (stn === null || stn === undefined) return;
    var idx = layer.fields.indexFromName("Stn");
    if (idx < 0) return;
    var txt = (off !== null && off !== undefined && Math.abs(off) >= 1) ? stationLabel(stn, off) : String(stn);
    var isInt = false;
    try { var tn = String(layer.fields.at(idx).typeName).toLowerCase(); isInt = (tn.indexOf("int") >= 0 || tn.indexOf("real") >= 0 || tn.indexOf("double") >= 0); } catch (e) {}
    f.setAttribute(idx, isInt ? Number(stn) : txt);
  }
  function pointIn(layer, x, y) {
    var g = QfGeometryUtils.createGeometryFromWkt("Point (" + x + " " + y + ")");
    if (layer.crs.authid !== qgisProject.crs.authid) g = QfGeometryUtils.reprojectGeometry(g, qgisProject.crs, layer.crs);
    return g;
  }
  function qualityArgs() { return {hacc: hacc, vacc: vacc, hdop: hdop, pTol: pTol, zTol: zTol, qTol: qTol}; }

  // What a Line Station would be recorded as at (x,y): nearest preplot station + signed offset,
  // or refused if outside the crossline XTrack limit.
  function stationInfo(x, y, forceStn) {
    if (curLine === "" || !lines[curLine]) return {ok: false, msg: "Pick a line first"};
    var L = lines[curLine];
    var nv = locate2D(L, x, y, dir, fromToThreshold);
    var gate = recordAllowed(nv, xTol);
    if (!gate.ok) return {ok: false, msg: gate.msg};
    var sn = forceStn !== undefined ? {stn: forceStn, offset: 0, snapped: true, label: String(forceStn)} : snapStation(L, nv.chain, aTol);
    return {ok: true, nv: nv, sn: sn, msg: ""};
  }

  // ---- Combined-CSV export: one row per point, same 39 columns as Daily Processing's <name>_Combined.csv
  readonly property var csvHeader: ["Station","Easting","Northing","Elevation","Descriptor","Comments","sLat","sLng","sHgt","numSats","BaseID","Date","Time","AntHgt","LineID","Stn","Code","Latitude","Longitude","RawHgt","NVal","ObsFile","Surveyor","SolAge","SolStatus","PositionType","GPSSerialNum","GPSModel","GPS","OmniStar","HDatum","Zone","VDatum","Source","Deleted","PDOP","Track","Bin"]
  function csvCell(v) {
    var t = (v === null || v === undefined) ? "" : String(v);
    return /[",\n\r]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t;
  }
  function appendCsv(cols, obs) {
    try {
      var path = String(qgisProject.homePath) + "/" + obs + "_Combined.csv";
      var old = "";
      try { old = FileUtils.readFileContent(path); } catch (er) { old = ""; }
      if (old === undefined || old === null) old = "";
      old = String(old);
      var out = (old === "" ? csvHeader.join(",") + "\r\n" : (old.slice(-1) === "\n" ? old : old + "\r\n"));
      var line = [];
      for (var i = 0; i < cols.length; i++) line.push(csvCell(cols[i]));
      var ok = FileUtils.writeFileContent(path, out + line.join(",") + "\r\n");
      csvStatus = (ok === false) ? "CSV write failed" : ("CSV: " + obs + "_Combined.csv");
    } catch (e) { csvStatus = "CSV not available: " + e; }
  }
  // rec: {x,y,z,pointType,posMode,check,pm,code,stringNo,remarks,action,lineId,antHt,forceStn}
  function writeRecord(rec, quiet) {
    var tgtName = rec.pointType === "Feature" ? mappingLayerName : recordLayerName;
    var layer = layerByName(tgtName);
    if (!layer && tgtName !== recordLayerName) { layer = layerByName(recordLayerName); if (layer) tgtName = recordLayerName; }
    if (!layer) { toast("Layer '" + tgtName + "' not found - see README"); playVoice(false, quiet); return false; }
    var cOk = (rec.corrOk !== undefined) ? rec.corrOk : correctionsOk();
    if (!cOk) {
      statusText = "NOT RECORDED: " + correctionsMsg();
      if (!quiet) toast("NOT RECORDED: " + correctionsMsg());
      playVoice(false, quiet);
      return false;
    }
    var stn = null, off = null, warn = [], label = "";
    if (rec.pointType === "Line Station") {
      var si = stationInfo(rec.x, rec.y, rec.forceStn);
      if (!si.ok) {
        statusText = "NOT RECORDED: " + si.msg;
        if (!quiet) toast("NOT RECORDED: " + si.msg);
        playVoice(false, quiet);
        return false;
      }
      stn = si.sn.stn; off = si.sn.offset; label = si.sn.label;
      var fracStn = si.nv.stn;                         // fractional station, used for the interval / bend QA
      warn = recordWarnings(prev1, prev2, {x: rec.x, y: rec.y, stn: fracStn},
                            {stnInterval: effInterval, maxIntvl: effMaxIntvl, maxBend: maxBend, distTol: distTol}, qualityArgs());
      prev2 = prev1; prev1 = {x: rec.x, y: rec.y, stn: fracStn};
    } else {
      warn = recordWarnings(null, null, {x: rec.x, y: rec.y, stn: 0}, {}, qualityArgs());
      if (rec.pointType === "Feature") label = featureLabel(rec.code, rec.stringNo);
    }
    var f = QfFeatureUtils.createFeature(layer, pointIn(layer, rec.x, rec.y));
    // Attributes follow the Daily Processing "Combined" CSV (Station ... Bin), then a few Nav25 extras at the end.
    var lineStr = String(rec.lineId || "");
    var trk = lineStr.replace(/^[A-Za-z]/, "");
    var trkN = parseInt(trk);
    var isStn = rec.pointType === "Line Station" && stn !== null && stn !== undefined;
    var binN = isStn ? parseInt(stn) : NaN;
    var offSuffix = (isStn && off !== null && off !== undefined && Math.abs(off) >= 1) ? (off > 0 ? "+" : "-") + Math.abs(off).toFixed(1) : "";
    var stationVal = (isStn && !isNaN(binN) && !isNaN(trkN)) ? String(trkN * 10000 + binN) + offSuffix : null;
    var atFix = Math.hypot(rec.x - posX, rec.y - posY) < 0.5;   // lat/lon are the live fix; a few cm of movement since the position was taken does not matter
    var nowD = new Date();
    function p2(n) { return n < 10 ? "0" + n : String(n); }
    var dateStr = p2(nowD.getDate()) + "/" + p2(nowD.getMonth() + 1) + "/" + nowD.getFullYear();
    var timeStr = p2(nowD.getHours()) + ":" + p2(nowD.getMinutes()) + ":" + p2(nowD.getSeconds());
    var doy = Math.floor((Date.UTC(nowD.getFullYear(), nowD.getMonth(), nowD.getDate()) - Date.UTC(nowD.getFullYear(), 0, 0)) / 86400000);
    var zoneM = /EPSG:(?:283|78)(\d\d)$/.exec(String(layer.crs.authid));
    var ql = qualDesc.toLowerCase();
    var posType = ql === "" ? null : (ql.indexOf("rtk") >= 0 ? "RTK" : (ql.indexOf("dgps") >= 0 || ql.indexOf("differential") >= 0 ? "DGPS" : qualDesc));
    var lineOut = rec.check ? "CHK" : lineStr;
    var cmt = String(rec.remarks || "");
    if (rec.check && cmt.toUpperCase().indexOf("CHK") < 0) cmt = cmt !== "" ? "CHK " + cmt : "CHK";
    var nVal = isFinite(geoidShift) && geoidShift !== 0 ? -geoidShift : (vOffset !== 0 ? vOffset : NaN);   // geoid separation N (ellipsoid - AHD)
    var hOk = !(rec.posMode === "Position only" || isNaN(rec.z));
    var rawHgt = (hOk && isFinite(nVal)) ? Math.round((rec.z + nVal + rec.antHt) * 1000) / 1000 : null;
    setAttr(layer, f, "Station", stationVal);
    setAttr(layer, f, "Easting", rec.posMode === "Elevation only" ? null : Math.round(rec.x * 1000) / 1000);
    setAttr(layer, f, "Northing", rec.posMode === "Elevation only" ? null : Math.round(rec.y * 1000) / 1000);
    setAttr(layer, f, "Elevation", (rec.posMode === "Position only" || isNaN(rec.z)) ? null : Math.round(rec.z * 1000) / 1000);
    setAttr(layer, f, "Descriptor", lineOut !== "" ? lineOut : null);
    setAttr(layer, f, "Comments", cmt !== "" ? cmt : null);
    setAttr(layer, f, "sLat", hacc > 0 ? Math.round(hacc * 1000) / 1000 : null);
    setAttr(layer, f, "sLng", hacc > 0 ? Math.round(hacc * 1000) / 1000 : null);
    setAttr(layer, f, "sHgt", vacc > 0 ? Math.round(vacc * 1000) / 1000 : null);
    setAttr(layer, f, "numSats", nSats > 0 ? nSats : null);
    setAttr(layer, f, "Date", dateStr);
    setAttr(layer, f, "Time", timeStr);
    setAttr(layer, f, "AntHgt", rec.antHt);
    setAttr(layer, f, "LineID", lineOut !== "" ? lineOut : null);
    setStn(layer, f, stn, off);
    setAttr(layer, f, "Code", rec.code !== "" ? rec.code : null);
    setAttr(layer, f, "Latitude", atFix ? posLat : null);
    setAttr(layer, f, "Longitude", atFix ? posLon : null);
    setAttr(layer, f, "ObsFile", doy + surveyor);
    setAttr(layer, f, "Surveyor", surveyor !== "" ? surveyor : null);
    setAttr(layer, f, "SolStatus", qualDesc !== "" ? qualDesc : null);
    setAttr(layer, f, "PositionType", posType);
    setAttr(layer, f, "HDatum", hDatum);
    setAttr(layer, f, "Zone", zoneM ? zoneM[1] : null);
    setAttr(layer, f, "VDatum", vDatum);
    setAttr(layer, f, "Source", sourceTag);
    setAttr(layer, f, "Deleted", "0");
    setAttr(layer, f, "RawHgt", rawHgt);
    setAttr(layer, f, "NVal", isFinite(nVal) ? Math.round(nVal * 1000) / 1000 : null);
    setAttr(layer, f, "BaseID", baseId !== "" ? baseId : null);
    setAttr(layer, f, "SolAge", 0);
    setAttr(layer, f, "GPSSerialNum", gpsSerial !== "" ? gpsSerial : null);
    setAttr(layer, f, "GPSModel", gpsModel !== "" ? gpsModel : null);
    setAttr(layer, f, "GPS", gpsName !== "" ? gpsName : null);
    setAttr(layer, f, "PDOP", pdopV);
    setAttr(layer, f, "Track", isNaN(trkN) ? null : String(trkN));
    setAttr(layer, f, "Bin", isNaN(binN) ? null : binN);
    // Nav25 extras (after the Combined-CSV columns)
    setAttr(layer, f, "MarkID", nextMarkId);
    setAttr(layer, f, "PointType", rec.pointType);
    setAttr(layer, f, "PMTie", rec.pm ? 1 : 0);
    setAttr(layer, f, "StringNo", rec.stringNo > 0 ? rec.stringNo : null);
    setAttr(layer, f, "Warnings", warn.length > 0 ? warn.join("; ") : null);
    var werr = addFeatureTo(layer, f);
    if (werr !== "") {
      statusText = "ERROR: WRITE FAILED - " + werr;
      toast("WRITE FAILED - " + werr);
      playVoice(false, quiet);
      return false;
    }
    if (rec.pointType !== "Feature" && csvExport) {
      appendCsv([stationVal, rec.posMode === "Elevation only" ? "" : (Math.round(rec.x * 1000) / 1000).toFixed(3),
                 rec.posMode === "Elevation only" ? "" : (Math.round(rec.y * 1000) / 1000).toFixed(3),
                 hOk ? (Math.round(rec.z * 1000) / 1000).toFixed(3) : "", lineOut, cmt,
                 hacc > 0 ? hacc.toFixed(3) : "", hacc > 0 ? hacc.toFixed(3) : "", vacc > 0 ? vacc.toFixed(3) : "", nSats > 0 ? nSats : "",
                 baseId, dateStr, timeStr, Number(rec.antHt).toFixed(3), lineOut, (stn !== null && stn !== undefined) ? String(stn) : "",
                 rec.code, atFix && isFinite(posLat) ? posLat.toFixed(8) : "", atFix && isFinite(posLon) ? posLon.toFixed(8) : "",
                 rawHgt !== null ? rawHgt.toFixed(3) : "", isFinite(nVal) ? nVal.toFixed(3) : "", doy + surveyor, surveyor, 0, qualDesc, posType === null ? "" : posType,
                 gpsSerial, gpsModel, gpsName, "", hDatum, zoneM ? zoneM[1] : "", vDatum, sourceTag, 0, isNaN(pdopV) ? "" : pdopV,
                 isNaN(trkN) ? "" : String(trkN), isNaN(binN) ? "" : binN], doy + surveyor);
    }
    nextMarkId++;
    lastComments = rec.remarks;
    lastStreamX = rec.x; lastStreamY = rec.y;
    playVoice(true, quiet);
    // on-screen confirmation: line + station, e.g. 1A1002 (or 1A1002+1.5 when off the station), or the feature label
    recLabel = (rec.pointType === "Line Station" && label !== "") ? (String(rec.lineId || "") + label) : (label !== "" ? label : "#" + (nextMarkId - 1));
    recWarn = warn.length > 0;
    recBannerTimer.restart();
    if (!quiet) {
      var what = label !== "" ? "  L" + rec.lineId + " " + label : "";
      statusText = "Recorded #" + (nextMarkId - 1) + what + "  ->  " + tgtName + "   [" + readings() + "]";
      if (warn.length > 0) toast("RECORDED #" + (nextMarkId - 1) + what + " WITH WARNINGS: " + warn.join(" | "));
      else toast("Recorded #" + (nextMarkId - 1) + what + "  [" + readings() + "]");
    }
    return true;
  }

  // ------------------------------------------------------------------ Stakeless
  function slStart() {
    if (!positioning.active || !haveFix) { toast("Start the GPS and get a fix first"); return; }
    if (curLine === "" || !lines[curLine]) { toast("Pick a line first"); return; }
    if (!layerByName(recordLayerName)) { toast("Layer '" + recordLayerName + "' not found"); return; }
    slRun = true; slPrev = null; slCount = 0; slSkipped = 0;
    toast("STAKELESS ON - line " + curLine + ". Stations record as you pass them.");
  }
  function slStop(why) {
    slRun = false; slPrev = null;
    toast(why ? why : "STAKELESS OFF - " + slCount + " stations recorded, " + slSkipped + " refused (XTrack / corrections)");
  }
  // A limit > 0 needs a real reading within it; a reading QField does not supply (--) cannot be checked, so it counts as out of tolerance.
  function precisionBad() {
    return (pTol > 0 && !(hacc > 0 && hacc <= pTol)) || (zTol > 0 && !(vacc > 0 && vacc <= zTol)) || (qTol > 0 && !(hdop > 0 && hdop <= qTol));
  }
  function stakelessTick(x, y) {
    if (curLine === "" || !lines[curLine] || !nav) return;
    if (precisionBad()) { slStop("STAKELESS STOPPED - precision out of tolerance. Tap SL to resume."); playVoice(false, false); return; }
    var L = lines[curLine];
    var cur = {chain: nav.chain, x: x, y: y};
    if (slPrev) {
      var cr = stakelessCrossings(L, dir, slPrev.chain, cur.chain, slPrev, cur, Math.max(100, effInterval * 4));
      for (var i = 0; i < cr.length; i++) {
        var f = {pointType: "Line Station", posMode: "3D", check: false, pm: false, code: "", stringNo: 0,
                 remarks: lastComments, antHt: antHt};
        var rec = currentRec("Stakeless", cr[i].x, cr[i].y, groundZ(), f);
        rec.forceStn = cr[i].stn;
        if (writeRecord(rec, true)) { slCount++; } else { slSkipped++; }
      }
      if (cr.length > 0) statusText = "Stakeless: " + slCount + " recorded, " + slSkipped + " refused (XTrack > " + xTol + " m / corrections)";
    }
    slPrev = cur;
  }
  // Travelled-route profile: runs the whole time QField is open with a position (not only while START is on),
  // one point every logInterval metres (and at least one every 60 s, so a stationary receiver still leaves a trail).
  property real slProfT: 0
  function profileTick(x, y) {
    if (logInterval <= 0) return;
    var now = Date.now();
    if (!slProfValid || Math.hypot(x - slProfX, y - slProfY) >= logInterval || (now - slProfT) >= 60000) {
      writeProfile(x, y); slProfX = x; slProfY = y; slProfValid = true; slProfT = now;
    }
  }
  // QField's LayerUtils.addFeature does NOT start/commit editing (it returns false on a layer that is not
  // already editable), so wrap it: start editing if needed, add, then commit. Returns "" on success or an error text.
  function diagInfo(layer, f) {
    var d = [];
    try { d.push("editable=" + layer.isEditable()); } catch (e) { d.push("editable=?"); }
    try { d.push("ro=" + layer.readOnly); } catch (e) { d.push("ro=?"); }
    try { d.push("valid=" + layer.isValid); } catch (e) { d.push("valid=?"); }
    try { d.push("geom=" + layer.geometryType()); } catch (e) { d.push("geom=?"); }
    try { d.push("fields=" + layer.fields.count); } catch (e) { d.push("fields=?"); }
    try { d.push("fattr=" + f.attributes.length); } catch (e) { d.push("fattr=?"); }
    try { d.push("fgeom=" + (f.geometry && !f.geometry.isNull ? "ok" : "none")); } catch (e) { d.push("fgeom=?"); }
    try { d.push("crs=" + layer.crs.authid); } catch (e) { d.push("crs=?"); }
    return d.join(" ");
  }
  function addFeatureTo(layer, f) {
    var wasEditable = false;
    try { wasEditable = layer.isEditable(); } catch (e0) { wasEditable = false; }
    if (!wasEditable) {
      var started = false;
      try { started = layer.startEditing(); } catch (e1) { return "startEditing error: " + e1; }
      if (!started) return "could not start editing (layer read-only?)";
    }
    var ok = false;
    try { ok = QfLayerUtils.addFeature(layer, f); } catch (e2) {
      if (!wasEditable) { try { layer.rollBack(); } catch (e3) {} }
      return "addFeature error: " + e2;
    }
    if (ok === false) {
      if (!wasEditable) { try { layer.rollBack(); } catch (e4) {} }
      return "addFeature refused the point [" + diagInfo(layer, f) + "]";
    }
    if (!wasEditable) {
      var committed = false;
      try { committed = layer.commitChanges(); } catch (e5) { return "commit error: " + e5; }
      if (!committed) { try { layer.rollBack(); } catch (e6) {} return "commit failed (data provider rejected the point)"; }
    }
    return "";
  }
  function writeProfile(x, y) {
    var pl = layerByName(profileLayerName);
    if (!pl) return;
    var f = QfFeatureUtils.createFeature(pl, pointIn(pl, x, y));
    setAttr(pl, f, "Line", curLine);
    setAttr(pl, f, "Stn", nav ? Math.round(nav.stn * 10) / 10 : null);
    setAttr(pl, f, "XTrack", nav ? Math.round(nav.xtrack * 100) / 100 : null);
    setAttr(pl, f, "Easting", Math.round(x * 100) / 100);
    setAttr(pl, f, "Northing", Math.round(y * 100) / 100);
    setAttr(pl, f, "Elev", isNaN(groundZ()) ? null : Math.round(groundZ() * 100) / 100);
    setAttr(pl, f, "Time", new Date().toISOString());
    setAttr(pl, f, "Hdop", hdop);
    var perr = addFeatureTo(pl, f);
    if (perr !== "") statusText = "ERROR: profile write failed - " + perr;
  }

  function currentRec(mode, x, y, z, f) {
    return {x: x, y: y, z: z, pointType: f.pointType, posMode: f.posMode, check: f.check, pm: f.pm,
            code: f.code, stringNo: f.stringNo, remarks: f.remarks, action: mode, lineId: curLine, antHt: f.antHt};
  }
  function groundZ() { return isNaN(elev) ? NaN : elev - antHt; }

  // called by the Mark Position popup. f = form values
  function recordFromForm(f) {
    if (!haveFix) { toast("No GPS fix"); playVoice(false, false); return; }
    antHt = f.antHt;
    if (f.pointType === "Line Station") {
      var chk = stationInfo(posX, posY);
      if (!chk.ok) { toast("NOT RECORDED: " + chk.msg); playVoice(false, false); return; }
    }
    if (f.action === "Average (50 obs)") {
      avg = newAverager(); avgRec = f; avgActive = true;
      toast("Averaging 50 observations - hold still");
      return;
    }
    var x = posX, y = posY, z = groundZ();
    if (f.action === "Instant" && snap) { x = snap.x; y = snap.y; z = snap.z; }
    var rec = currentRec(f.action, x, y, z, f);
    if (f.action === "Instant" && snap) rec.corrOk = snap.corrOk;   // judge the corrections at the moment of the snapshot
    writeRecord(rec, false);
  }
  function finishAverage() {
    avgActive = false;
    var a = averageOf(avg);
    statusText = "Averaged " + a.n + " obs";
    writeRecord(currentRec("Average (50 obs)", a.x, a.y, a.z, avgRec), false);
  }
  function takeSnapshot() { snap = {x: posX, y: posY, z: groundZ(), corrOk: correctionsOk()}; }

  function streamPoint() {
    var f = {pointType: "Feature", posMode: "3D", check: false, pm: false, code: markPopup.lastCode,
             stringNo: markPopup.lastString, remarks: lastComments, antHt: antHt};
    writeRecord(currentRec("Stream", posX, posY, groundZ(), f), true);
  }

  Connections {
    target: plugin.positioning
    function onPositionInformationChanged() { plugin.onPosition(); }
  }

  // ------------------------------------------------------------------ UI
  readonly property color cBg: "#E6101820"
  readonly property color cOk: "#35D07F"
  readonly property color cBad: "#FF4B4B"
  readonly property color cWarn: "#FFC833"
  readonly property color cText: "#F2F5F7"
  readonly property color cDim: "#8FA1AE"
  // On target = inside BOTH the inline (ATol, along-track to the target station) and crossline (XTol) settings
  readonly property bool onTarget: positioning.active && haveFix && nav !== null && targetLocked(nav, aTol, xTol)
  readonly property color cZone: zoneStat === "nogo" ? cBad : (zoneStat === "warn" ? "#FF9A1F" : "#1E7B46")

  // Position of the N25 circle on screen, so REC and MARK can sit in a column directly under it
  property real launchX: -1
  property real launchY: -1
  function sideX(w) {
    var pw = mainWindow.contentItem.width;
    return Math.round(launchX >= 0 ? launchX + (launcher.width - w) / 2 : pw - w - 12);
  }
  function sideY(n, h) {
    var base = launchY >= 0 ? launchY + launcher.height : mainWindow.contentItem.height * 0.2;
    return Math.round(base + 10 + n * (h + 10));
  }
  Timer {
    id: launchTimer
    interval: 400; repeat: true; running: true
    onTriggered: {
      try {
        var p = launcher.mapToItem(mainWindow.contentItem, 0, 0);
        if (!isNaN(p.x) && !isNaN(p.y) && (Math.abs(p.x - plugin.launchX) > 0.5 || Math.abs(p.y - plugin.launchY) > 0.5)) { plugin.launchX = p.x; plugin.launchY = p.y; }
      } catch (e) {}
    }
  }

  Rectangle {
    id: launcher
    width: 48; height: 48; radius: 24
    color: panel.visible ? "#1B6EF3" : "#80000000"
    Text { anchors.centerIn: parent; text: "N25"; color: "white"; font.bold: true; font.pixelSize: 14 }
    MouseArea { anchors.fill: parent
      onClicked: {
        panel.visible = !panel.visible;
        if (panel.visible && !plugin.loadedOnce && !plugin.loading) plugin.startLoad();
      } }
  }

  // ---- Mini controls (shown when the big panel is closed): START/STOP Stakeless (rectangle) and REC (circle) ----
  Rectangle {
    id: miniStart
    parent: mainWindow.contentItem
    z: 101
    visible: !panel.visible && plugin.loadedOnce
    width: 120; height: 56; radius: 10
    x: Math.round((parent.width - width) / 2)
    y: (mainWindow.sceneTopMargin || 0) + 8
    color: plugin.slRun ? "#B3261E" : "#0F6E7A"
    border.color: "white"; border.width: 2
    Text { anchors.centerIn: parent; text: plugin.slRun ? "STOP" : "START"; color: "white"; font.bold: true; font.pixelSize: 18 }
    MouseArea { anchors.fill: parent
      onClicked: {
        try { if (plugin.slRun) plugin.slStop(""); else plugin.slStart(); }
        catch (e) { plugin.statusText = "ERROR: " + e; plugin.toast("Nav25: " + e); }
      } }
  }
  Rectangle {
    id: miniRec
    parent: mainWindow.contentItem
    z: 101
    visible: !panel.visible && plugin.loadedOnce
    width: 48; height: 48; radius: 24
    x: plugin.sideX(width)
    y: plugin.sideY(0, height)
    color: "#6B3FA0"
    border.color: "white"; border.width: 2
    Text { anchors.centerIn: parent; text: "REC"; color: "white"; font.bold: true; font.pixelSize: 13 }
    MouseArea { anchors.fill: parent
      onClicked: {
        try { markPopup.openRec(false); }   // same record form as the REC button in the N25 panel
        catch (e) { plugin.statusText = "ERROR: " + e; plugin.toast("Nav25: " + e); }
      } }
  }

  Rectangle {
    id: miniMark
    parent: mainWindow.contentItem
    z: 101
    visible: !panel.visible && plugin.loadedOnce
    width: 48; height: 48; radius: 24
    x: plugin.sideX(width)
    y: plugin.sideY(1, height)
    color: plugin.streaming ? "#B3261E" : "#C2610C"
    border.color: "white"; border.width: 2
    Text { anchors.centerIn: parent; text: plugin.streaming ? "STOP" : "MARK"; color: "white"; font.bold: true; font.pixelSize: 11 }
    MouseArea { anchors.fill: parent
      onClicked: { try { if (plugin.streaming) { plugin.streaming = false; plugin.toast("Stream stopped"); } else featPopup.openIt(); } catch (e) { plugin.statusText = "ERROR: " + e; plugin.toast("Nav25: " + e); } } }
  }

  // ---- stored-point banner: line + station of the point just recorded (e.g. 1A1002), fades after a few seconds ----
  Timer { id: recBannerTimer; interval: 6000; repeat: false; onTriggered: plugin.recLabel = "" }
  Rectangle {
    id: recBanner
    parent: mainWindow.contentItem
    z: 102
    visible: plugin.recLabel !== ""
    width: Math.min(parent.width - 24, recBannerText.implicitWidth + 40)
    height: 58; radius: 10
    x: Math.round((parent.width - width) / 2)
    y: panel.visible ? parent.height - height - (mainWindow.sceneBottomMargin || 0) - 130 : (mainWindow.sceneTopMargin || 0) + 72
    color: plugin.recWarn ? "#F0B26B00" : "#F0138A45"
    border.color: "white"; border.width: 2
    Text {
      id: recBannerText
      anchors.centerIn: parent
      text: "\u2713 " + plugin.recLabel
      color: "white"; font.pixelSize: 30; font.bold: true
    }
    MouseArea { anchors.fill: parent; onClicked: plugin.recLabel = "" }
  }

  // ---- Nav25-style info down the left side (panel closed): line, live station + offset, next station, azimuth, XTrack ----
  Rectangle {
    id: miniInfo
    parent: mainWindow.contentItem
    z: 101
    visible: !panel.visible && plugin.loadedOnce && plugin.positioning.active
    x: 6
    y: (mainWindow.sceneTopMargin || 0) + (compact ? 60 : 84)
    readonly property bool compact: mainWindow.contentItem.width < 700
    readonly property real k: compact ? 0.62 : 1.0
    width: Math.round(172 * k)
    height: infoCol.implicitHeight + 12
    radius: compact ? 6 : 8
    color: plugin.onTarget ? (compact ? "#B8138A45" : "#E0138A45") : (compact ? "#A0101820" : "#C8101820")
    MouseArea { anchors.fill: parent; onClicked: linePopup.openPicker() }
    Column {
      id: infoCol
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: miniInfo.compact ? 5 : 8 }
      spacing: miniInfo.compact ? 0 : 1
      Text { text: miniInfo.compact ? "LINE" : "LINE  (tap to change)"; color: plugin.cDim; font.pixelSize: Math.max(8, Math.round(10 * miniInfo.k)) }
      Text {
        text: plugin.curLine === "" ? "PICK LINE" : plugin.curLine
        color: plugin.curLine === "" ? plugin.cWarn : "#8FC7FF"
        font.pixelSize: Math.max(8, Math.round(26 * miniInfo.k)); font.bold: true
      }
      Text { text: "STATION"; color: plugin.cDim; font.pixelSize: Math.max(8, Math.round(10 * miniInfo.k)) }
      Text { text: plugin.liveStnLabel(); color: plugin.cOk; font.pixelSize: Math.max(8, Math.round(30 * miniInfo.k)); font.bold: true }
      Text { text: "TO NEXT STN " + (plugin.nav ? plugin.nav.targetStn : "--"); color: plugin.cDim; font.pixelSize: Math.max(8, Math.round(10 * miniInfo.k)) }
      Text { text: plugin.nav ? plugin.fmt(plugin.nav.atrack, 1) + " m" : "--"; color: plugin.cText; font.pixelSize: Math.max(8, Math.round(22 * miniInfo.k)); font.bold: true }
      Text {
        text: plugin.nav ? "AZ " + plugin.dms(plugin.bearing(plugin.posX, plugin.posY, plugin.nav.targetX, plugin.nav.targetY)) : ""
        color: plugin.cDim; font.pixelSize: Math.max(8, Math.round(12 * miniInfo.k))
        visible: !miniInfo.compact
        height: visible ? implicitHeight : 0
      }
      Text { text: "XTRACK"; color: plugin.cDim; font.pixelSize: Math.max(8, Math.round(10 * miniInfo.k)) }
      Text {
        property real xt: plugin.nav ? plugin.nav.xtrack : NaN
        text: isNaN(xt) ? "--" : (xt > 0 ? "R " : (xt < 0 ? "L " : "")) + Math.abs(xt).toFixed(1) + " m"
        color: isNaN(xt) ? plugin.cDim : (Math.abs(xt) > plugin.xTol ? plugin.cBad : plugin.cOk)
        font.pixelSize: Math.max(8, Math.round(24 * miniInfo.k)); font.bold: true
      }
      Text { text: plugin.dir > 0 ? "+ INCREASING" : "- DECREASING"; color: "#8FC7FF"; font.pixelSize: Math.max(8, Math.round(11 * miniInfo.k)); font.bold: true }
      Text { text: "N25 v2.7"; color: plugin.cDim; font.pixelSize: Math.max(8, Math.round(9 * miniInfo.k)) }
    }
  }

  // ---- H / V / HDOP on the map (panel closed): no background, white halo round the text, under the REC / MARK circles ----
  Column {
    id: miniQual
    parent: mainWindow.contentItem
    z: 101
    visible: !panel.visible && plugin.loadedOnce && plugin.positioning.active
    spacing: 0
    width: 96
    x: Math.max(4, Math.min(plugin.sideX(width), mainWindow.contentItem.width - width - 6))
    y: plugin.sideY(2, 48) + 2
    Repeater {
      model: [
        {t: "H", v: plugin.hacc > 0 ? plugin.hacc.toFixed(2) : "--", bad: plugin.hBad()},
        {t: "V", v: plugin.vacc > 0 ? plugin.vacc.toFixed(2) : "--", bad: plugin.vBad()},
        {t: "HDOP", v: plugin.hdop > 0 ? plugin.fmt(plugin.hdop, 1) : "--", bad: plugin.qBad()},
        {t: "PDOP", v: plugin.pdopV > 0 ? plugin.fmt(plugin.pdopV, 1) : "--", bad: false}
      ]
      delegate: Text {
        width: miniQual.width
        horizontalAlignment: Text.AlignHCenter
        text: plugin.haveFix ? (modelData.t + " " + modelData.v) : (index === 0 ? "NO FIX" : "")
        visible: plugin.haveFix || index === 0
        font.pixelSize: mainWindow.contentItem.width < 700 ? 12 : 15; font.bold: true
        style: Text.Outline; styleColor: "white"
        color: (!plugin.haveFix || modelData.bad) ? "#D62020" : "#0E8A43"
      }
    }
  }

  // ---- MARK: quick Feature record (code, string no, remarks) -> N25_Mapping ----
  Popup {
    id: featPopup
    parent: mainWindow.contentItem
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round(parent.height * 0.12)
    width: Math.min(parent.width - 24, 400)
    height: fcCol.implicitHeight + 28
    function openIt() {
      if (!plugin.haveFix) { plugin.toast("No GPS fix"); plugin.playVoice(false, false); return; }
      plugin.takeSnapshot();
      fcCode.editText = markPopup.lastCode;
      fcStr.text = markPopup.lastString > 0 ? markPopup.lastString : "";
      fcRem.text = "";
      open();
    }
    ColumnLayout {
      id: fcCol
      width: parent.width
      spacing: 6
      Text { text: "Mark feature  ->  " + plugin.mappingLayerName; font.bold: true; font.pixelSize: 17 }
      Text { text: "Feature code / string no. (0 or blank = single point)"; wrapMode: Text.Wrap; Layout.fillWidth: true; font.pixelSize: 12 }
      RowLayout { Layout.fillWidth: true
        ComboBox { id: fcCode; Layout.fillWidth: true; editable: true; model: markPopup.commonCodes
          onActivated: editText = currentText }
        TextField { id: fcStr; Layout.preferredWidth: 90; placeholderText: "String"; inputMethodHints: Qt.ImhDigitsOnly } }
      TextField { id: fcRem; Layout.fillWidth: true; placeholderText: "Remarks / comment"; maximumLength: 200 }
      RowLayout { Layout.fillWidth: true
        Button { Layout.fillWidth: true; text: "Cancel"; onClicked: featPopup.close() }
        Button { Layout.fillWidth: true; text: "Record"
          onClicked: {
            var code = fcCode.editText;
            var strNo = parseInt(fcStr.text || "0");
            markPopup.lastCode = code; markPopup.lastString = isNaN(strNo) ? 0 : strNo;
            plugin.recordFromForm({pointType: "Feature", posMode: "3D", check: false, pm: false, code: code, stringNo: markPopup.lastString,
                                   remarks: fcRem.text, action: "Instant", antHt: plugin.antHt});
            featPopup.close();
          } } }
      Button { Layout.fillWidth: true; text: "Start Stream (record every " + plugin.streamInterval + " m)"
        onClicked: {
          var code2 = fcCode.editText;
          var strNo2 = parseInt(fcStr.text || "0");
          markPopup.lastCode = code2; markPopup.lastString = isNaN(strNo2) ? 0 : strNo2;
          plugin.lastComments = fcRem.text;
          plugin.streamPoint();
          plugin.streaming = true;
          featPopup.close();
          plugin.toast("Streaming every " + plugin.streamInterval + " m. Tap the red MARK button to stop.");
        } }
    }
  }

  // Full-screen RED (no-go) / ORANGE (warning) highlight while inside a zone
  Rectangle {
    id: zoneFrame
    parent: mainWindow.contentItem
    anchors.fill: parent
    z: 100
    visible: positioning.active && (plugin.zoneStat === "nogo" || plugin.zoneStat === "warn")
    color: plugin.zoneStat === "nogo" ? "#40FF1F1F" : "#38FF9A1F"
    border.color: plugin.zoneStat === "nogo" ? "#FF1F1F" : "#FF9A1F"
    border.width: 18
  }

  // Full-screen green highlight while on target (touches pass straight through to the map)
  Rectangle {
    id: onTargetFrame
    parent: mainWindow.contentItem
    anchors.fill: parent
    z: 99
    visible: plugin.onTarget && plugin.zoneStat === "clear"
    color: "#2635D07F"
    border.color: "#35D07F"
    border.width: 14
  }

  Rectangle {
    id: panel
    parent: mainWindow.contentItem
    visible: false
    z: 100
    x: 4
    y: (mainWindow.sceneTopMargin || 0) + 92
    width: parent.width - 8
    height: col.implicitHeight + 12
    radius: 8
    color: plugin.onTarget ? "#F0138A45" : plugin.cBg

    Rectangle {
      z: 5
      anchors { top: parent.top; right: parent.right; margins: 4 }
      width: 30; height: 30; radius: 15
      color: "#40FFFFFF"
      Text { anchors.centerIn: parent; text: "✕"; color: "white"; font.pixelSize: 14 }
      MouseArea { anchors.fill: parent; onClicked: panel.visible = false }
    }

    ColumnLayout {
      id: col
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
      spacing: 4

      // GNSS quality strip: H / V accuracy and HDOP, each coloured against its own tolerance
      RowLayout {
        Layout.fillWidth: true
        Layout.rightMargin: 34
        spacing: 10
        Repeater {
          model: [
            {t: "H (m)", v: plugin.hacc > 0 ? plugin.hacc.toFixed(2) : "--", bad: plugin.hBad()},
            {t: "V (m)", v: plugin.vacc > 0 ? plugin.vacc.toFixed(2) : "--", bad: plugin.vBad()},
            {t: "HDOP", v: plugin.hdop > 0 ? plugin.fmt(plugin.hdop, 1) : "--", bad: plugin.qBad()},
            {t: "PDOP", v: plugin.pdopV > 0 ? plugin.fmt(plugin.pdopV, 1) : "--", bad: false}
          ]
          delegate: ColumnLayout {
            Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 0
            Text { text: modelData.t; color: plugin.cDim; font.pixelSize: 10 }
            Text {
              text: modelData.v; font.pixelSize: 20; font.bold: true
              color: !plugin.haveFix ? plugin.cBad : (modelData.bad ? plugin.cBad : plugin.cOk)
            }
          }
        }
      }

      // fix type (Fixed RTK / Float RTK / DGPS / ...), full width so it never runs off the screen
      Text {
        Layout.fillWidth: true
        Layout.rightMargin: 34
        elide: Text.ElideRight
        text: plugin.haveFix ? (plugin.qualDesc !== "" ? plugin.qualDesc : "FIX") : "NO FIX"
        font.pixelSize: 15; font.bold: true
        color: !plugin.haveFix ? plugin.cBad
             : (/fix/i.test(plugin.qualDesc) && !/float/i.test(plugin.qualDesc) ? plugin.cOk : plugin.cWarn)
      }

      // zone status bar (Nav25: green clear / orange warning / red no-go)
      Rectangle {
        id: zoneBar
        Layout.fillWidth: true
        Layout.rightMargin: 34
        height: 32; radius: 4
        color: plugin.cZone
        SequentialAnimation on opacity {
          running: plugin.zoneStat !== "clear"
          loops: Animation.Infinite
          NumberAnimation { to: 0.5; duration: 350 }
          NumberAnimation { to: 1.0; duration: 350 }
          onRunningChanged: if (!running) zoneBar.opacity = 1.0
        }
        Text {
          anchors.fill: parent; anchors.margins: 4
          verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight
          font.bold: true; font.pixelSize: 14; color: "white"
          text: plugin.zoneStat === "nogo" ? "⚠ NO-GO: " + plugin.nogoHits.join(", ")
              : (plugin.zoneStat === "warn" ? "⚠ WARNING: " + plugin.warnHits.join(", ") : "ZONES CLEAR")
        }
      }

      // readouts - stakeout
      RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
          model: [
            {t: "LINE", v: plugin.curLine === "" ? "--" : plugin.curLine},
            {t: "FROM → TO", v: plugin.nav ? (plugin.nav.fromStn + "→" + plugin.nav.toStn) : "--"},
            {t: "TARGET " + (plugin.nav ? plugin.nav.targetStn : "--"), v: plugin.nav ? plugin.fmt(plugin.nav.atrack, 1) : "--"},
            {t: "TO END", v: plugin.nav ? plugin.fmt(plugin.nav.toEnd, 0) : "--"}
          ]
          delegate: ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            Text { text: modelData.t; color: plugin.cDim; font.pixelSize: 11 }
            Text { text: modelData.v; color: plugin.cText; font.pixelSize: 22; font.bold: true }
          }
        }
      }

      // cross track + quality (stakeout)
      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Item {
          width: 54; height: 54
          visible: plugin.nav !== null
          Canvas {
            id: arrow
            anchors.fill: parent
            property real ang: plugin.nav
              ? plugin.wrapPi(plugin.bearing(plugin.posX, plugin.posY, plugin.nav.foot[0], plugin.nav.foot[1]) - plugin.nav.travelBearing)
              : 0
            property bool locked: plugin.nav && plugin.targetLocked(plugin.nav, plugin.aTol, plugin.xTol)
            onAngChanged: requestPaint()
            onLockedChanged: requestPaint()
            onPaint: {
              var c = getContext("2d"); c.reset();
              if (locked) {                       // Target Lock: solid ring
                c.strokeStyle = plugin.cOk; c.lineWidth = 6;
                c.beginPath(); c.arc(width / 2, height / 2, 20, 0, 2 * Math.PI); c.stroke();
                return;
              }
              c.translate(width / 2, height / 2); c.rotate(ang);
              c.fillStyle = plugin.cWarn;
              c.beginPath(); c.moveTo(0, -22); c.lineTo(14, 8); c.lineTo(0, 2); c.lineTo(-14, 8); c.closePath(); c.fill();
            }
          }
        }
        ColumnLayout {
          spacing: 0
          Text { text: "XTRACK"; color: plugin.cDim; font.pixelSize: 11 }
          Text {
            property real xt: plugin.nav ? plugin.nav.xtrack : NaN
            text: isNaN(xt) ? "--" : (xt > 0 ? "R " : (xt < 0 ? "L " : "")) + Math.abs(xt).toFixed(1) + " m"
            font.pixelSize: 38; font.bold: true
            color: isNaN(xt) ? plugin.cDim : (Math.abs(xt) > plugin.xTol ? plugin.cBad : plugin.cOk)
          }
        }
        Item { Layout.fillWidth: true }
        ColumnLayout {
          spacing: 0
          Text {
            text: plugin.haveFix ? "E " + plugin.fmt(plugin.posX, 1) + "  N " + plugin.fmt(plugin.posY, 1) : ""
            color: plugin.cDim; font.pixelSize: 11; Layout.alignment: Qt.AlignRight
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: plugin.statusText !== ""
        text: plugin.statusText
        wrapMode: Text.Wrap; font.pixelSize: 12
        color: plugin.statusText.indexOf("ERROR") >= 0 ? plugin.cBad : plugin.cDim
      }

      // buttons
      Repeater {
        model: [
          [
            {t: plugin.positioning.active ? "STOP" : "START", c: plugin.positioning.active ? "#B3261E" : "#1E7B46", a: "startstop"},
            {t: "LINE", c: "#2B3A47", a: "line"},
            {t: plugin.dir > 0 ? "DIR +" : "DIR \u2212", c: "#2B3A47", a: "dir"},
            {t: plugin.avgActive ? "AVG\u2026" : "REC", c: "#6B3FA0", a: "rec"},
            {t: plugin.streaming ? "STREAM \u25cf" : "CHK", c: plugin.streaming ? "#B3261E" : "#8A5A00", a: "chk"}
          ],
          [
            {t: plugin.slRun ? "SL STOP \u25cf" : "SL START", c: plugin.slRun ? "#B3261E" : "#0F6E7A", a: "sl", show: plugin.stakelessEnabled},
            {t: plugin.navView ? "NAV" : "MAP", c: "#2B3A47", a: "view", show: true},
            {t: plugin.follow ? "FOLLOW" : "FREE", c: plugin.follow ? "#1E7B46" : "#2B3A47", a: "follow", show: true},
            {t: "\u2699", c: "#2B3A47", a: "cfg", show: true}
          ]
        ]
        delegate: RowLayout {
          Layout.fillWidth: true
          spacing: 4
          Repeater {
            model: modelData
            delegate: Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 44
              visible: modelData.show === undefined ? true : modelData.show
              radius: 6
              color: modelData.c
              Text { anchors.centerIn: parent; text: modelData.t; color: "white"; font.bold: true; font.pixelSize: 12 }
              MouseArea {
                anchors.fill: parent
                onClicked: {
                  try {
                    switch (modelData.a) {
                    case "startstop": plugin.startStop(); break;
                    case "line": linePopup.openPicker(); break;
                    case "dir": plugin.toggleDir(); break;
                    case "rec": markPopup.openRec(false); break;
                    case "chk":
                      if (plugin.streaming) { plugin.streaming = false; plugin.toast("Stream stopped"); }
                      else markPopup.openRec(true);
                      break;
                    case "sl": if (plugin.slRun) plugin.slStop(""); else plugin.slStart(); break;
                    case "follow": plugin.follow = !plugin.follow; plugin.lastCx = NaN; if (plugin.follow && plugin.haveFix) { mapCanvas.mapSettings.center = QfGeometryUtils.point(plugin.posX, plugin.posY); plugin.lastCx = plugin.posX; plugin.lastCy = plugin.posY; } break;
                    case "view": plugin.navView = !plugin.navView; plugin.saveSettings(); break;
                    case "cfg": cfgPopup.open(); break;
                    }
                  } catch (e) { plugin.statusText = "ERROR: " + e; plugin.toast("Nav25: " + e); }
                }
              }
            }
          }
        }
      }
    }
  }

  // ---- LINE picker (Change Line) ----
  Popup {
    id: linePopup
    parent: mainWindow.contentItem
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - 40, 380)
    height: Math.min(parent.height - 80, 520)
    property var items: []
    function openPicker() {
      if (!plugin.loadedOnce) {
        plugin.pendingPicker = true;
        if (!plugin.loading) plugin.startLoad();
        plugin.toast(plugin.loading ? "Loading preplot... the line list opens when ready" : "Could not load layers");
        return;
      }
      var arr;
      if (plugin.haveFix) arr = plugin.nearestLines(plugin.lines, plugin.posX, plugin.posY, 0);
      else { arr = []; for (var id in plugin.lines) arr.push({id: id, off: NaN}); }
      items = arr; open();
    }
    ColumnLayout {
      anchors.fill: parent
      Text { text: "Change line" + (plugin.haveFix ? " (nearest first)" : ""); font.bold: true; font.pixelSize: 16 }
      ListView {
        Layout.fillWidth: true; Layout.fillHeight: true
        clip: true
        model: linePopup.items
        delegate: ItemDelegate {
          width: ListView.view.width
          text: "Line " + modelData.id + (isNaN(modelData.off) ? "" : "   —   " + modelData.off.toFixed(0) + " m away")
          onClicked: { plugin.setLine(modelData.id); linePopup.close(); }
        }
      }
    }
  }

  // ---- MARK POSITION (Record a Point) ----
  Popup {
    id: markPopup
    parent: mainWindow.contentItem
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - 24, 400)
    height: Math.min(parent.height - 60, 560)
    property string lastCode: ""
    property int lastString: 0
    property bool streamMode: false
    readonly property var commonCodes: ["FENCE", "GATE", "TRACK", "CREEK", "DRAIN", "POWERLINE", "PIPELINE", "HAZARD", "CHECK", "DAM", "BORE", "WELL", "TANK", "MUSTER", "GRID", "ENTRY", "CROSSING", "ROAD"]
    function openRec(chk) {
      if (!plugin.haveFix) { plugin.toast("No GPS fix"); plugin.playVoice(false, false); return; }
      plugin.takeSnapshot();
      streamMode = false;
      mpId.text = "Mark ID " + plugin.nextMarkId;
      mpLine.text = plugin.curLine;
      mpAnt.text = plugin.antHt;
      mpRem.text = "";   // a fresh comment / reason for every record
      mpType.currentIndex = 0; mpMode.currentIndex = 0; mpAct.currentIndex = 0;
      mpChk.checked = chk; mpPm.checked = false;
      open();
    }
    function form() {
      return {pointType: mpType.currentText, posMode: mpMode.currentText, check: mpChk.checked, pm: mpPm.checked,
              code: "", stringNo: 0, remarks: mpRem.text,
              action: mpAct.currentText, antHt: parseFloat(mpAnt.text) || plugin.antHt};
    }
    ScrollView {
      id: mpScroll
      anchors.fill: parent
      contentWidth: availableWidth
      clip: true
      ColumnLayout {
        width: mpScroll.availableWidth
        spacing: 4
        Text { id: mpId; font.bold: true; font.pixelSize: 17 }
        Rectangle {
          Layout.fillWidth: true; height: 40; radius: 4
          property var si: plugin.stationInfo(plugin.posX, plugin.posY)
          color: mpType.currentText !== "Line Station" ? "#555" : (si.ok ? "#1E7B46" : "#B3261E")
          Text {
            anchors.fill: parent; anchors.margins: 4; verticalAlignment: Text.AlignVCenter; wrapMode: Text.Wrap
            color: "white"; font.bold: true; font.pixelSize: 13
            text: mpType.currentText !== "Line Station" ? "Not tied to a preplot station"
                  : (parent.si.ok ? "Will record as L" + plugin.curLine + " stn " + parent.si.sn.label + "   (XTrack " + parent.si.nv.xtrack.toFixed(1) + " m)"
                                  : "WILL NOT RECORD: " + parent.si.msg)
          }
        }
        RowLayout { Layout.fillWidth: true
          TextField { id: mpLine; Layout.fillWidth: true; placeholderText: "Line ID"; onEditingFinished: if (text !== plugin.curLine && plugin.lines[text]) plugin.setLine(text) }
          TextField { id: mpAnt; Layout.preferredWidth: 110; placeholderText: "Ant Ht"; inputMethodHints: Qt.ImhFormattedNumbersOnly } }
        Text { text: "Comment / reason (e.g. why recorded off the station)"; font.pixelSize: 13; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap }
        TextField { id: mpRem; Layout.fillWidth: true; placeholderText: "Reason for offset / comment"; maximumLength: 200 }
        Text { text: "Point type" }
        ComboBox { id: mpType; Layout.fillWidth: true; model: ["Line Station", "External Station"] }
        Text { text: "Record" }
        ComboBox { id: mpMode; Layout.fillWidth: true; model: ["3D", "Position only", "Elevation only"] }
        RowLayout { Layout.fillWidth: true
          CheckBox { id: mpChk; text: "Check Pt" }
          CheckBox { id: mpPm; text: "PM / Tie" } }
        Text { text: "Action" }
        ComboBox { id: mpAct; Layout.fillWidth: true; model: ["Instant", "Use current position", "Average (50 obs)"] }
        RowLayout { Layout.fillWidth: true
          Button { Layout.fillWidth: true; text: "Cancel"; onClicked: markPopup.close() }
          Button { Layout.fillWidth: true; text: "Write"
            onClicked: {
              plugin.recordFromForm(markPopup.form()); markPopup.close();
            } }
        }
      }
    }
  }

  // ---- settings ----
  function configure() { cfgPopup.open(); }

  Popup {
    id: cfgPopup
    parent: mainWindow.contentItem
    modal: true
    x: Math.round((parent.width - width) / 2)
    y: Math.round((parent.height - height) / 2)
    width: Math.min(parent.width - 24, 400)
    height: Math.min(parent.height - 60, 600)
    onAboutToShow: {
      sA.text = plugin.aTol; sX.text = plugin.xTol; sF.text = plugin.fromToThreshold;
      sI.text = plugin.stnInterval; sM.text = plugin.maxIntvl; sB.text = plugin.maxBend; sD.text = plugin.distTol;
      sAnt.text = plugin.antHt; sInc.text = plugin.autoInc; sL.text = plugin.logInterval; sSl.checked = plugin.stakelessEnabled; sAuto.checked = plugin.autoPickLine;
      sP.text = plugin.pTol; sZ.text = plugin.zTol; sQ.text = plugin.qTol; sSnd.checked = plugin.alarmSound; sSv.text = plugin.surveyor;
      sVoice.checked = plugin.voiceFeedback;
      sPre.text = plugin.preplotName; sStnF.text = plugin.stationField; sLnF.text = plugin.lineField;
      sRecL.text = plugin.recordLayerName; sMapL.text = plugin.mappingLayerName;
      sVO.text = plugin.vOffset; sKnown.text = "";
      sBase.text = plugin.baseId; sGSn.text = plugin.gpsSerial; sGMod.text = plugin.gpsModel; sGNm.text = plugin.gpsName; sCsv.checked = plugin.csvExport;
    }
    ScrollView {
      id: cfgScroll
      anchors.fill: parent
      contentWidth: availableWidth
      clip: true
      GridLayout {
        width: cfgScroll.availableWidth
        columns: 2
        Text { text: "Nav25 settings"; font.bold: true; font.pixelSize: 16; Layout.columnSpan: 2 }
        Text { Layout.columnSpan: 2; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11
          color: plugin.store ? "#1E7B46" : "#B3261E"
          text: plugin.store ? "Settings are remembered between sessions." : "Settings can NOT be remembered on this QField: " + plugin.storeErr }
        Text { text: "ATol - snap to stn / lock (m)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sA; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "XTol - max crossline XTrack (m)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sX; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "From/To threshold (m)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sF; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "Stn interval (0 = auto)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sI; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "MaxIntvl (m, 0 = auto)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sM; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "MaxBend (deg)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sB; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "DistTol (%)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sD; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "Antenna Ht (m)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sAnt; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "Height offset (m)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sVO; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "Known AHD here (m)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sKnown; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; placeholderText: "e.g. 6.3"; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Button { Layout.columnSpan: 2; Layout.fillWidth: true; text: "Calibrate offset from here"
          onClicked: {
            var kh = parseFloat(sKnown.text), ah = parseFloat(sAnt.text);
            if (isNaN(ah)) ah = plugin.antHt;
            if (isNaN(kh)) { plugin.toast("Enter the known AHD first"); return; }
            if (!plugin.haveFix || isNaN(plugin.elev)) { plugin.toast("No GPS fix / elevation"); return; }
            var raw = plugin.elev + plugin.vOffset;                  // elevation before any offset
            plugin.vOffset = Math.round((raw - ah - kh) * 1000) / 1000;
            plugin.antHt = ah;
            sVO.text = plugin.vOffset;
            plugin.saveSettings();
            plugin.toast("Height offset set to " + plugin.vOffset + " m (antenna " + ah + " m, known " + kh + " m)");
          } }
        Text { text: "AutoInc (+1 / -1)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sInc; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "Profile every (m), 0 = off"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sL; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        CheckBox { id: sSl; text: "Stakeless mode (SL button)"; Layout.columnSpan: 2 }
        CheckBox { id: sAuto; text: "Auto-pick nearest line (off = LINE button only)"; Layout.columnSpan: 2 }
        Text { text: "PTol horiz (m, 0 = off)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sP; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "ZTol vert (m, 0 = off)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sZ; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "QTol HDOP (0 = off)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sQ; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; inputMethodHints: Qt.ImhFormattedNumbersOnly }
        Text { text: "Surveyor initials (ObsFile / Surveyor)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sSv; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120; maximumLength: 8 }
        Text { text: "Preplot layer (blank = auto)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sPre; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "Station field (blank = auto)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sStnF; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "Line field (blank = auto)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sLnF; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "Point record layer"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sRecL; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "Feature (mapping) layer"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sMapL; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        CheckBox { id: sSnd; text: "Alarm sound"; Layout.columnSpan: 2 }
        Text { text: "BaseID (CSV)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sBase; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "GPS serial no. (CSV)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sGSn; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "GPS model (CSV)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sGMod; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        Text { text: "GPS (CSV, free text)"; Layout.fillWidth: true; Layout.preferredWidth: 60; wrapMode: Text.Wrap } TextField { id: sGNm; Layout.fillWidth: true; Layout.preferredWidth: 40; Layout.minimumWidth: 120 }
        CheckBox { id: sCsv; text: "Write Combined CSV"; Layout.columnSpan: 2 }
        CheckBox { id: sVoice; text: "Voice: say Point location stored / not stored"; Layout.columnSpan: 2 }
        Text { Layout.columnSpan: 2; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11
          color: (plugin.voiceOk && plugin.sndStored && plugin.sndStored.status !== 3) ? "#1E7B46" : "#B3261E"
          text: ((plugin.voiceOk && plugin.sndStored && plugin.sndStored.status !== 3) ? "Voice files loaded." : "Voice files NOT found - stored.wav and notstored.wav must sit next to this plugin file.")
                + "  A point is NOT stored (and the voice says so) when H precision, V precision or HDOP exceed PTol / ZTol / QTol above (0 = off)."
                + "  Right now: " + plugin.readings() + (plugin.correctionsOk() ? " - within limits." : " - OUT of limits (or not reported).")
                + "  QField gives: " + plugin.accDiag()
                + "  | " + plugin.posDiag()
                + "  " + plugin.csvStatus + "  [N25 v2.7 build]" }
        Button { text: "Reload layers"; Layout.fillWidth: true
          onClicked: { plugin.loadedOnce = false; plugin.startLoad(); } }
        Button { text: "Apply"; Layout.fillWidth: true
          onClicked: {
            function num(t, d) { var v = parseFloat(t); return isNaN(v) ? d : v; }
            plugin.aTol = num(sA.text, 1); plugin.xTol = num(sX.text, 5); plugin.fromToThreshold = num(sF.text, 5);
            plugin.stnInterval = num(sI.text, 0); plugin.maxIntvl = num(sM.text, 0); plugin.maxBend = num(sB.text, 30);
            plugin.distTol = num(sD.text, 10); plugin.antHt = num(sAnt.text, 2); plugin.vOffset = num(sVO.text, 0); plugin.autoInc = parseInt(sInc.text) < 0 ? -1 : 1;
            plugin.logInterval = num(sL.text, 3); plugin.stakelessEnabled = sSl.checked; plugin.autoPickLine = sAuto.checked; plugin.pTol = num(sP.text, 0.1); plugin.zTol = num(sZ.text, 0.1);
            plugin.qTol = num(sQ.text, 3); plugin.alarmSound = sSnd.checked; plugin.surveyor = sSv.text.trim();
            plugin.voiceFeedback = sVoice.checked;
            plugin.baseId = sBase.text.trim(); plugin.gpsSerial = sGSn.text.trim(); plugin.gpsModel = sGMod.text.trim(); plugin.gpsName = sGNm.text.trim(); plugin.csvExport = sCsv.checked;
            var layersChanged = (plugin.preplotName !== sPre.text.trim() || plugin.stationField !== sStnF.text.trim() || plugin.lineField !== sLnF.text.trim());
            plugin.preplotName = sPre.text.trim(); plugin.stationField = sStnF.text.trim(); plugin.lineField = sLnF.text.trim();
            plugin.recordLayerName = sRecL.text.trim() !== "" ? sRecL.text.trim() : "N25_Points";
            plugin.mappingLayerName = sMapL.text.trim() !== "" ? sMapL.text.trim() : "N25_Mapping";
            plugin.saveSettings();
            if (layersChanged) { plugin.loadedOnce = false; plugin.startLoad(); }
            cfgPopup.close();
          } }
      }
    }
  }

  Component.onCompleted: {
    initStore();
    loadSettings();
    initSounds();
    initVoice();
    iface.addItemToPluginsToolbar(launcher);
  }
}
