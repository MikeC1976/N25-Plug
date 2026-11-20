# TS Survey Plugin for QField (formerly N25 / Nav25)

Seismic set-out plugin. Install in QField: Settings > Plugins > Install plugin from local file (or URL), then choose N25.zip.

## Position marker and bearing line (v3.0, line colour and arrow head v3.1)
N25 settings > "Position marker (drawn on the map)": choose a symbol (arrow, crosshair, dot + cone, 4WD, ute, truck, tractor, skid steer), colour, size (small to extra large) and an optional bearing line from the GNSS position along the direction of travel (500 m, 1, 2, 5, 10 or 20 km, solid or dashed, own colour, arrow head at the end). "QField default" leaves QField's own blue marker as it is. The marker and line are drawn over QField's own marker, which cannot be hidden from a plugin. Settings are remembered per project.

## Name change (v3.2)
The plugin is now called "TS Survey Plugin" (map button "TS"). Layer names (N25_Points, N25_Mapping, N25_Profile, N25_Track), N25_AddLayers.py, the N25.zip file name and the saved settings are unchanged, so existing projects and installs keep working.
