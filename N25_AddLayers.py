# N25_AddLayers.py - SELF-CONTAINED: no QML files and no C:/scripts needed on the computer you run it on.
# Run ONCE per project in QGIS (Plugins > Python Console > Show Editor > open > Run). Save the QGIS project first.
# Creates N25_Data.gpkg beside the project (if missing) with N25_Points, N25_Mapping, N25_Profile and N25_Track,
# adds them to the project in an 'N25' group, applies the built-in N25 symbology (categorised on Code for N25_Mapping)
# to the layers - including ones already in the project - and saves the project. It prints what happened for each layer.
import os, zlib, base64, tempfile
from qgis.core import (QgsProject, QgsVectorLayer, QgsFields, QgsField, QgsVectorFileWriter,
                       QgsCoordinateTransformContext, QgsWkbTypes, QgsEditFormConfig, QgsDefaultValue, Qgis)
from qgis.PyQt.QtCore import QVariant

STYLES = {
  "N25_Points": (
    "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"
  ),
  "N25_Mapping": (
    "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"
  ),
  "N25_Profile": (
    "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"
    "fp/mIflVZJkoVisbY/XJ5sPG/wANBoYS"
  ),
  "N25_Track": (
    "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"
    "kkezUrazlIgQyJ0EkFs4UKcILKb3x7fNqHE6SgQsQ5gKuQrrkBfSl+x7zPX2sJS667MEO6vFBu+hcpz11Dz9gaODsGQV5vhTspoR"
    "xzD0T058TFhABJ89i5KjCYN08wlsgRNfbSrEE8hgA3RPgyRwpvKD7+XL1kaEBUfurRQ7X/U5+ZJQTpQVS/OY5h2MGPNz6oInZGf6"
    "oBclibonkDsEdVo+fwVgfR+EcxYSlsQlH4Y8MoaUC+daW95X8zF9BQTFSSpGedEsE7QfQzDW1vaUOhc0qOobmCMciEFnLgvxYo1v"
    "wrXCVe4TFigBXCvK8qtoR0zkEwXMx4/SCAlGBGOC/0HxmIjYcllS3JnYiMIUcfWh/kcoxeuQfpHEcqyy+xpai3zKENqEWH4fL7/e"
    "LwrqBQG9PP1YxpiD1bItkMsIuVTM5AMBlbJEyNYizU1sZOUrTlyaf7zO5asD5CyJfOoiQT4C+dLux1Dbz+mEuLdxJp8rS6cs9Og4"
    "/ejf0rI+6FGzScbAtfru/Vy+H3GuyqUrBFhv0JlT/YCEld6aSO9BYPUBfVyFgjWWwZ40pAo/+UMCUGG45Rr5mAXI95HJH9kWnHwB"
    "oXhUAFZubTcpgzfkXrwDYHlzTtNcsENU3gS1qlhDqyBdPFgAHD6S2zMYpu+I3euET8mM8e+I5Y/sv6/h9OecWQ+RT1Gcx6aqZHil"
    "lzxoiMl9eX/ZWoSqjCjDba7GzUcww2+txlfqy3DbVdyhVeJ/mM79TJi0aKAo8meX4ecIZ0+WkMqjISVxrUc19RgPkHBk3euQ3b1+"
    "03g1gz/mxYWJ8as39Yp2rO24yrW1ZXulvVRXZf1IE4uFfJok11cBMUqVSudAGjJuWCzHYqIPI0omEjIRJr5fQgALgMz1S0IqMGtN"
    "P/byfrR9zXdkL+jI3qWjwjhfoDNt2Y/qSE368riV+i2ewlkwouCHXfXSzn20xObXIlfMeC32nOGubVE21aVSDQsrV81Sp53nozpp"
    "fLAEnOgjvFsyO6qfonCK4iIRyV6SMhf8lf35lq82C7op+hYyetOLsqER9GqsHoWSe+osOmN3kLPFbO7hIoBcypucpWDJZX4ShMXZ"
    "qy4bEwqxaFhaktUkzL4aJTK2VRtI6rqntba1nlpbNy8mzNYk9DR4bPNm1iQdigWNpBnlKiwNXmmcsimkdwaQrzb9i9PyO122yh6/"
    "BFJ2Ot90CDE6J7iw1BRb+mfpMwyhX4FSp7zH2m9LeAUJsk9hzUFcGVCzhLsqkl9S87CRvFgcITE5rrbIwYs6OR7+8Nvp2cnNyW9/"
    "Mcy/mrCmyTeu3hqJ8My+hNTq9Xrt008fruUxdRAbLoKxQVNiIONqJiYw3bwk1PNOTJAwqETxfYKNuwmRMKIaArwGyUxI8EGt9jkm"
    "UAGYRVNmIIzVm1jI8NmYuhI0Azl1t9DonczuFD1pTgbzNO2MAtV91VOmPoB8eWW9pkb0oHYSQhdInvsCWd+HcX+r5PM4C9RzeQdX"
    "s0/i4FMaXsUGlS+BCeOTLtdqsNAYwcyRPDlSnNeYImC3od+0axhpzvXmrTIkmdkYRxnwIEt0Xr9RtWBTgjMfEDSRAw+Cn9MJ9fHr"
    "tL+GUb+YyRNqFTe+qf3++/G8MeT5n1JUEiljlKndHCwbf8aBW5aIY8ipiLxogHVZ085rM/TS63E6FM6ApRCw4jOWYhUr/yqsOY+y"
    "FDN3a5rzjNGhenLwMrxhUYVCAX64Llrr8RbwvhBvCfcLcUv8V1mGnDWJyTmKhdokuGKQZs8q9MqL+iJkxfCJNHGCH7BSXo23alr4"
    "gq2aKz+2WUt5UWexItT5xpne11dbQlf5XolueZdu4qgC2P+UkrvCFx9r1cnvMR7WSPwARTc0Kl8LgYmngcUuyk/pdJYvWeZbKRVg"
    "baie2Tyu/QeGcLHe"
  )
}

S, D, I = QVariant.String, QVariant.Double, QVariant.Int
POINTS = [("Station",S),("Easting",D),("Northing",D),("Elevation",D),("Descriptor",S),("Comments",S),
 ("sLat",D),("sLng",D),("sHgt",D),("numSats",I),("BaseID",S),("Date",S),("Time",S),("AntHgt",D),
 ("LineID",S),("Stn",S),("Code",S),("Latitude",D),("Longitude",D),("RawHgt",D),("NVal",D),
 ("ObsFile",S),("Surveyor",S),("SolAge",D),("SolStatus",S),("PositionType",S),("GPSSerialNum",S),
 ("GPSModel",S),("GPS",S),("OmniStar",S),("HDatum",S),("Zone",S),("VDatum",S),("Source",S),
 ("Deleted",S),("PDOP",D),("Track",S),("Bin",I),("MarkID",I),("PointType",S),("PMTie",I),
 ("StringNo",I),("Warnings",S)]
PROFILE = [("Line",S),("Stn",D),("XTrack",D),("Easting",D),("Northing",D),("Elev",D),("Time",S),("Hdop",D)]
TRACK = [("Date",S),("Surveyor",S),("Note",S)]
LAYERS = [("N25_Points", POINTS, "Point"), ("N25_Mapping", POINTS, "Point"), ("N25_Profile", PROFILE, "Point"), ("N25_Track", TRACK, "LineString")]


def apply_style(lyr, name):
    """Write the embedded style to a temp file and load it. Returns a short status string."""
    data = STYLES.get(name)
    if data is None:
        return "no embedded style"
    path = os.path.join(tempfile.gettempdir(), name + "_n25.qml")
    with open(path, "wb") as f:
        f.write(zlib.decompress(base64.b64decode("".join(data))))
    msg, ok = lyr.loadNamedStyle(path)
    lyr.triggerRepaint()
    return "style applied" if ok else "STYLE FAILED: %s" % msg

print("QGIS version: %s" % Qgis.QGIS_VERSION)
proj = QgsProject.instance()
if not proj.fileName():
    raise Exception("Save the project first, then run this script.")
gpkg = os.path.join(os.path.dirname(proj.fileName()), "N25_Data.gpkg")
crs = proj.crs()
existing = {l.name() for l in proj.mapLayers().values()}
first = not os.path.exists(gpkg)
added = []
root = proj.layerTreeRoot()
grp = root.findGroup("N25") or root.insertGroup(0, "N25")
for name, fields, geom in LAYERS:
    if name in existing:
        for l in proj.mapLayers().values():
            if l.name() == name:
                print("%s: already in project, %s" % (name, apply_style(l, name)))
        continue
    mem = QgsVectorLayer(geom + "?crs=" + crs.authid(), name, "memory")
    mem.dataProvider().addAttributes([QgsField(n, t) for n, t in fields])
    mem.updateFields()
    opts = QgsVectorFileWriter.SaveVectorOptions()
    opts.driverName = "GPKG"
    opts.layerName = name
    opts.actionOnExistingFile = (QgsVectorFileWriter.CreateOrOverwriteFile if first
                                 else QgsVectorFileWriter.CreateOrOverwriteLayer)
    res = QgsVectorFileWriter.writeAsVectorFormatV3(mem, gpkg, QgsCoordinateTransformContext(), opts)
    if res[0] != QgsVectorFileWriter.NoError:
        raise Exception("Could not write %s: %s" % (name, res[1]))
    first = False
    lyr = QgsVectorLayer(gpkg + "|layername=" + name, name, "ogr")
    if not lyr.isValid():
        raise Exception("Layer %s did not load" % name)
    print("%s: created, %s" % (name, apply_style(lyr, name)))
    proj.addMapLayer(lyr, False)
    grp.addLayer(lyr)
    added.append(name)

# N25_Track: let QField's own tracking record it (one line per session, runs in the background on QField 3.5+,
# starts automatically when the project opens, one vertex every 3 m, no attribute form)
trk = None
for l in proj.mapLayers().values():
    if l.name() == "N25_Track":
        trk = l
if trk is not None and trk.isValid():
    trk.setCustomProperty("QFieldSync/tracking_session_active", True)
    trk.setCustomProperty("QFieldSync/tracking_time_requirement_active", False)
    trk.setCustomProperty("QFieldSync/tracking_time_requirement_interval_seconds", 30)
    trk.setCustomProperty("QFieldSync/tracking_distance_requirement_active", True)
    trk.setCustomProperty("QFieldSync/tracking_distance_requirement_minimum_meters", 3)
    trk.setCustomProperty("QFieldSync/tracking_sensor_data_requirement_active", False)
    trk.setCustomProperty("QFieldSync/tracking_all_requirements_active", False)
    trk.setCustomProperty("QFieldSync/tracking_erroneous_distance_safeguard_active", False)
    trk.setCustomProperty("QFieldSync/tracking_measurement_type", 0)
    cfg = trk.editFormConfig()
    try:
        cfg.setSuppress(QgsEditFormConfig.FeatureFormSuppression.SuppressOn)
    except AttributeError:
        cfg.setSuppress(QgsEditFormConfig.SuppressOn)
    trk.setEditFormConfig(cfg)
    ix = trk.fields().indexFromName("Date")
    if ix >= 0:
        trk.setDefaultValueDefinition(ix, QgsDefaultValue("format_date(now(),'yyyy-MM-dd')"))
# QFieldSync: all four N25 layers share N25_Data.gpkg, so they MUST have the same action on BOTH tabs
# (QFieldCloud Packaging = cloud_action, Cable Packaging = action). Offline editing, as the N25 plugin needs
# (a plain "copy" makes QField refuse the writes). Set here, after the layers are in the project (added 11/11/2026).
for l in proj.mapLayers().values():
    if l.name() in ("N25_Points", "N25_Mapping", "N25_Profile", "N25_Track"):
        l.setCustomProperty("QFieldSync/action", "offline")
        l.setCustomProperty("QFieldSync/cloud_action", "offline")
proj.write()
print("N25 layers added: %s. Project saved. Package it for QField as usual." % (", ".join(added) or "none (all already present)"))
