# N25_AddLayers.py - run ONCE per project in QGIS (Plugins > Python Console > Show Editor > open > Run).
# Creates N25_Data.gpkg beside the project (if missing) with N25_Points, N25_Mapping and N25_Profile,
# adds them to the project in the project CRS, and saves the project. Existing layers are left alone.
import os
from qgis.core import (QgsProject, QgsVectorLayer, QgsFields, QgsField, QgsVectorFileWriter,
                       QgsCoordinateTransformContext, QgsWkbTypes)
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
LAYERS = [("N25_Points", POINTS), ("N25_Mapping", POINTS), ("N25_Profile", PROFILE)]

proj = QgsProject.instance()
if not proj.fileName():
    raise Exception("Save the project first, then run this script.")
gpkg = os.path.join(os.path.dirname(proj.fileName()), "N25_Data.gpkg")
crs = proj.crs()
existing = {l.name() for l in proj.mapLayers().values()}
first = not os.path.exists(gpkg)
added = []
for name, fields in LAYERS:
    if name in existing:
        continue
    mem = QgsVectorLayer("Point?crs=" + crs.authid(), name, "memory")
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
    proj.addMapLayer(lyr)
    added.append(name)
proj.write()
print("N25 layers added: %s. Project saved. Package it for QField as usual." % (", ".join(added) or "none (all already present)"))
