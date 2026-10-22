# Goo jar tower theme mesh (JAR_THEME, not classic): the theme's props on the plot floor round jar 1, built round the
# goo_jar_foot anchor (models/_goo_jar.py COMPANIONS). Build: JAR_THEME=garden python iterate.py models/goo_jar_props.py --name goo_jar_props@garden
from models._goo_jar import *

ship("goo_jar_props", theme_props())
