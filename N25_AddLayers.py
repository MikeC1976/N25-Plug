# N25_AddLayers.py - run ONCE per project in QGIS (Plugins > Python Console > Show Editor > open > Run).
# Creates N25_Data.gpkg beside the project (if missing) with N25_Points, N25_Mapping, N25_Profile and the N25_Track line layer,
# adds them to the project in the project CRS (in their own top-level 'N25' group), and saves the project. Existing layers are left alone.
import os
from qgis.core import (QgsProject, QgsVectorLayer, QgsFields, QgsField, QgsVectorFileWriter,
                       QgsCoordinateTransformContext, QgsWkbTypes, QgsEditFormConfig, QgsDefaultValue)
from qgis.PyQt.QtCore import QVariant

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

STYLE_DIR = "C:/scripts"   # folder holding N25_Mapping.qml (the symbol style for N25_Mapping)
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
    if name == "N25_Mapping" and os.path.exists(STYLE_DIR + "/N25_Mapping.qml"):
        lyr.loadNamedStyle(STYLE_DIR + "/N25_Mapping.qml")   # symbols by feature Code
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
proj.write()
print("N25 layers added: %s. Project saved. Package it for QField as usual." % (", ".join(added) or "none (all already present)"))
